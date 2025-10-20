import argparse
import logging
import random
import simpy
import sys
import uuid
import statistics
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Optional

from simulator.components.mgs import MGS
from simulator.components.mds import MDS
from simulator.components.oss import OSS
from simulator.components.lustre_client import LustreClient
from simulator.infra.availability_zone import AvailabilityZone
from simulator.infra.machine import Machine
from simulator.infra.network import Network

# Configure logging
log_file_path = Path("simulator_log.log")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler(log_file_path),
    ],
)
logger = logging.getLogger(__name__)


class LustreSimulation:
    """Lustre file system simulation."""

    def __init__(self, args):
        self.args = args
        self.env = simpy.Environment()
        self.network = Network(self.env)

        self.availability_zones: Dict[str, AvailabilityZone] = {}
        self.machines: Dict[str, Machine] = {}
        self.mgs: Optional[MGS] = None
        self.mds_servers: Dict[str, MDS] = {}
        self.oss_servers: Dict[str, OSS] = {}
        self.clients: Dict[str, LustreClient] = {}

        self._setup_infrastructure(args.num_azs, args.machines_per_az)
        self._setup_mgs()
        self._setup_mds_servers(args.num_mds)
        self._setup_oss_servers(args.num_oss, args.osts_per_oss)
        self._setup_clients(args.num_clients)

    def _setup_infrastructure(self, num_azs: int, machines_per_az: int):
        """Set up availability zones and machines."""
        for i in range(num_azs):
            az_id = f"az-{i+1}"
            az = AvailabilityZone(id=az_id)
            self.availability_zones[az_id] = az

            for j in range(machines_per_az):
                machine_id = f"machine-{az_id}-{j+1}"
                machine = Machine(id=machine_id, az=az_id)
                self.machines[machine_id] = machine
                az.add_machine(machine)

    def _setup_mgs(self):
        """Set up the Management Server."""
        # MGS typically runs on its own machine
        machine_id = list(self.machines.keys())[0]
        machine = self.machines[machine_id]

        self.mgs = MGS(
            env=self.env,
            network=self.network
        )
        logger.info(f"[{self.env.now:.4f}] MGS initialized")

    def _setup_mds_servers(self, num_mds: int):
        """Set up Metadata Servers."""
        if not self.mgs:
            raise RuntimeError("MGS must be initialized before MDS servers")

        machine_ids = list(self.machines.keys())

        for i in range(num_mds):
            mds_id = f"mds_{i}"
            machine_id = machine_ids[i % len(machine_ids)]
            machine = self.machines[machine_id]

            mds = MDS(
                id=mds_id,
                env=self.env,
                network=self.network,
                mgs=self.mgs,
                machine=machine,
                az=machine.az,
                address=f"mds_{i}_addr",
                mdt_index=i
            )
            self.mds_servers[mds_id] = mds

    def _setup_oss_servers(self, num_oss: int, osts_per_oss: int):
        """Set up Object Storage Servers."""
        if not self.mgs:
            raise RuntimeError("MGS must be initialized before OSS servers")

        machine_ids = list(self.machines.keys())

        for i in range(num_oss):
            oss_id = f"oss_{i}"
            machine_id = machine_ids[i % len(machine_ids)]
            machine = self.machines[machine_id]

            oss = OSS(
                id=oss_id,
                env=self.env,
                network=self.network,
                mgs=self.mgs,
                machine=machine,
                az=machine.az,
                address=f"oss_{i}_addr",
                num_osts=osts_per_oss
            )
            self.oss_servers[oss_id] = oss

    def _setup_clients(self, num_clients: int):
        """Set up Lustre clients."""
        machine_ids = list(self.machines.keys())
        mds_ids = list(self.mds_servers.keys())

        for i in range(num_clients):
            client_id = f"client_{i}"
            machine_id = machine_ids[i % len(machine_ids)]
            machine = self.machines[machine_id]

            # Round-robin assign clients to MDS servers
            mds_id = mds_ids[i % len(mds_ids)] if mds_ids else "mds_0"

            client = LustreClient(
                id=client_id,
                env=self.env,
                network=self.network,
                machine=machine,
                mds_id=mds_id
            )
            self.clients[client_id] = client

    def run_scenario(self, duration: int = 100):
        """Run the simulation scenario."""
        logger.info(f"\n{'='*30}\nStarting Lustre Simulation for {duration} seconds\n{'='*30}")

        self.env.process(self._client_workload())
        self.env.process(self._failure_scenario())

        if self.args.enable_machine_failures:
            self.env.process(self._machine_failure_scenario())

        self.env.run(until=duration)
        logger.info(f"\n{'='*30}\nSimulation Finished at {self.env.now:.4f}\n{'='*30}")
        self._report_metrics()

    def _client_workload(self):
        """Generate client file system operations."""
        client_ids = list(self.clients.keys())
        oss_ids = list(self.oss_servers.keys())

        if not client_ids or not oss_ids:
            logger.warning("No clients or OSS servers available for workload")
            return

        file_count = 0

        while True:
            yield self.env.timeout(random.uniform(0.5, 1.5))

            client_id = random.choice(client_ids)
            client = self.clients[client_id]

            operation = random.choice(['create', 'write', 'read', 'stat', 'mkdir', 'list'])

            if operation == 'create':
                file_path = f"/testfile_{file_count}"
                stripe_count = random.choice([1, 2, 4])
                logger.info(f"[{self.env.now:.4f}] Client {client_id}: Creating file {file_path} "
                           f"with stripe_count={stripe_count}")
                client.create_file(file_path, stripe_count=stripe_count)
                file_count += 1

            elif operation == 'write' and file_count > 0:
                fid = f"0x200000000:0x{random.randint(1, file_count)}:0x0"
                data = f"data_{uuid.uuid4()}"
                oss_id = random.choice(oss_ids)
                logger.info(f"[{self.env.now:.4f}] Client {client_id}: Writing {len(data)} bytes to FID {fid}")
                client.write_file(fid, offset=0, data=data, oss_id=oss_id)

            elif operation == 'read' and file_count > 0:
                fid = f"0x200000000:0x{random.randint(1, file_count)}:0x0"
                oss_id = random.choice(oss_ids)
                logger.info(f"[{self.env.now:.4f}] Client {client_id}: Reading from FID {fid}")
                client.read_file(fid, offset=0, size=100, oss_id=oss_id)

            elif operation == 'stat' and file_count > 0:
                file_path = f"/testfile_{random.randint(0, file_count-1)}"
                logger.info(f"[{self.env.now:.4f}] Client {client_id}: Stat {file_path}")
                client.stat_file(file_path)

            elif operation == 'mkdir':
                dir_path = f"/testdir_{uuid.uuid4().hex[:8]}"
                logger.info(f"[{self.env.now:.4f}] Client {client_id}: Creating directory {dir_path}")
                client.mkdir(dir_path)

            elif operation == 'list':
                logger.info(f"[{self.env.now:.4f}] Client {client_id}: Listing directory /")
                client.list_dir("/")

    def _failure_scenario(self):
        """Simulate basic failures."""
        machine_ids = list(self.machines.keys())

        while True:
            yield self.env.timeout(random.uniform(20, 40))

            if random.random() < 0.3:  # 30% chance of failure
                machine_id = random.choice(machine_ids)
                machine = self.machines[machine_id]

                if machine.is_up:
                    logger.info(f"[{self.env.now:.4f}] Initiating machine failure for {machine_id}")
                    machine.fail()

                    # Recover after some time
                    yield self.env.timeout(random.uniform(5, 15))
                    logger.info(f"[{self.env.now:.4f}] Initiating machine recovery for {machine_id}")
                    machine.recover()

    def _machine_failure_scenario(self):
        """Simulate targeted machine failures."""
        while True:
            yield self.env.timeout(random.uniform(
                self.args.machine_failure_interval * 0.8,
                self.args.machine_failure_interval * 1.2
            ))

            # Randomly fail MDS, OSS, or client machines
            target_type = random.choice(['mds', 'oss', 'client'])

            if target_type == 'mds' and self.mds_servers:
                mds_id = random.choice(list(self.mds_servers.keys()))
                mds = self.mds_servers[mds_id]
                if not mds.is_crashed:
                    logger.info(f"[{self.env.now:.4f}] Crashing MDS {mds_id}")
                    mds.machine.fail()

                    yield self.env.timeout(random.uniform(10, 20))
                    logger.info(f"[{self.env.now:.4f}] Recovering MDS {mds_id}")
                    mds.machine.recover()

            elif target_type == 'oss' and self.oss_servers:
                oss_id = random.choice(list(self.oss_servers.keys()))
                oss = self.oss_servers[oss_id]
                if not oss.is_crashed:
                    logger.info(f"[{self.env.now:.4f}] Crashing OSS {oss_id}")
                    oss.machine.fail()

                    yield self.env.timeout(random.uniform(10, 20))
                    logger.info(f"[{self.env.now:.4f}] Recovering OSS {oss_id}")
                    oss.machine.recover()

            elif target_type == 'client' and self.clients:
                client_id = random.choice(list(self.clients.keys()))
                client = self.clients[client_id]
                if not client.is_crashed:
                    logger.info(f"[{self.env.now:.4f}] Crashing client {client_id}")
                    client.crash()

                    yield self.env.timeout(random.uniform(5, 10))
                    logger.info(f"[{self.env.now:.4f}] Recovering client {client_id}")
                    client.recover()

    def _report_metrics(self):
        """Report simulation metrics."""
        print("\n--- Lustre Simulation Metrics ---")

        total_requests = 0
        successful_requests = 0
        total_latency = 0.0
        latencies = []

        for client_id, client in self.clients.items():
            for req_id, success in client.request_results.items():
                total_requests += 1
                if success:
                    successful_requests += 1
                    latency = client.request_latencies.get(req_id)
                    if latency is not None:
                        total_latency += latency
                        latencies.append(latency)

        if total_requests > 0:
            success_rate = (successful_requests / total_requests) * 100
            avg_latency = total_latency / successful_requests if successful_requests > 0 else 0
            print(f"Total Requests: {total_requests}")
            print(f"Successful Requests: {successful_requests}")
            print(f"Success Rate: {success_rate:.2f}%")
            print(f"Average Request Latency: {avg_latency:.4f}s")

            if latencies:
                latencies.sort()
                if len(latencies) > 0:
                    p50_index = int(len(latencies) * 0.50)
                    p95_index = int(len(latencies) * 0.95)
                    p99_index = int(len(latencies) * 0.99)

                    p50_latency = latencies[p50_index - 1] if p50_index > 0 else latencies[0]
                    p95_latency = latencies[p95_index - 1] if p95_index > 0 else latencies[0]
                    p99_latency = latencies[p99_index - 1] if p99_index > 0 else latencies[0]

                    print(f"P50 Latency: {p50_latency:.4f}s")
                    print(f"P95 Latency: {p95_latency:.4f}s")
                    print(f"P99 Latency: {p99_latency:.4f}s")
        else:
            print("No requests processed.")

        # OST statistics
        print("\n--- OST Statistics ---")
        for oss_id, oss in self.oss_servers.items():
            for ost_index, ost_info in oss.osts.items():
                utilization = (ost_info.used_bytes / ost_info.capacity_bytes) * 100
                print(f"  {ost_info.ost_id}: {ost_info.used_bytes}/{ost_info.capacity_bytes} bytes "
                      f"({utilization:.2f}% utilization)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Run Lustre File System Simulation",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )

    # General Configuration
    general_group = parser.add_argument_group("General Simulation Configuration")
    general_group.add_argument("--num_azs", type=int, default=3, help="Number of availability zones")
    general_group.add_argument("--machines_per_az", type=int, default=3, help="Number of machines per AZ")
    general_group.add_argument("--num_mds", type=int, default=2, help="Number of MDS servers")
    general_group.add_argument("--num_oss", type=int, default=4, help="Number of OSS servers")
    general_group.add_argument("--osts_per_oss", type=int, default=2, help="Number of OSTs per OSS")
    general_group.add_argument("--num_clients", type=int, default=3, help="Number of clients")
    general_group.add_argument("--duration", type=int, default=60, help="Simulation duration in seconds")

    # Failure Injection
    failure_group = parser.add_argument_group("Failure Injection")
    failure_group.add_argument("--enable_machine_failures", action="store_true",
                              help="Enable targeted machine failure scenarios")
    failure_group.add_argument("--machine_failure_interval", type=float, default=30,
                              help="Average interval between machine failures in seconds")

    args = parser.parse_args()

    print("\n--- Lustre Simulation Configuration ---")
    print(f"  Availability Zones: {args.num_azs}")
    print(f"  Machines per AZ: {args.machines_per_az}")
    print(f"  MDS Servers: {args.num_mds}")
    print(f"  OSS Servers: {args.num_oss}")
    print(f"  OSTs per OSS: {args.osts_per_oss}")
    print(f"  Clients: {args.num_clients}")
    print(f"  Duration: {args.duration}s")
    print(f"  Machine Failures Enabled: {args.enable_machine_failures}")
    print("---------------------------------------\n")

    sim = LustreSimulation(args)
    sim.run_scenario(duration=args.duration)
