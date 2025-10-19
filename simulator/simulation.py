import argparse
import logging
import random
import simpy
import sys
import time
import uuid
import statistics
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple, cast, Union

from simulator.components.client_library import ClientLibrary
from simulator.components.controller import Controller
from simulator.components.data_node import DataNode
from simulator.components.gateway_node import GatewayNode
from simulator.components.snapshot_service import SnapshotService
from simulator.infra.availability_zone import AvailabilityZone
from simulator.infra.load_balancer import LoadBalancer
from simulator.infra.machine import Machine
from simulator.infra.network import Network
from simulator.models.api import PutRequest, GetRequest, SnapshotRequest
from simulator.models.base import ReadConsistency
from simulator.models.internal import NetworkMessage
from simulator.models.metrics import MetricsCollector # Import MetricsCollector

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


class HeliosSimulation:
    def __init__(self, args):
        self.args = args
        self.env = simpy.Environment()
        self.network = Network(self.env)
        self.load_balancer = LoadBalancer()
        self.controller = Controller(env=self.env, network=self.network)

        self.availability_zones: Dict[str, AvailabilityZone] = {}
        self.machines: Dict[str, Machine] = {}
        self.data_nodes: Dict[str, DataNode] = {}
        self.gateway_nodes: Dict[str, GatewayNode] = {}
        self.client_libraries: Dict[str, ClientLibrary] = {}
        self.snapshot_service = SnapshotService(env=self.env, network=self.network, controller=self.controller)

        self.metrics = MetricsCollector()

        self._setup_infrastructure(args.num_azs, args.machines_per_az)
        self._setup_gateway_nodes(args.num_gateways)
        self._setup_client_libraries(args.num_clients)

    def _setup_infrastructure(self, num_azs: int, machines_per_az: int):
        for i in range(num_azs):
            az_id = f"az-{i+1}"
            az = AvailabilityZone(id=az_id)
            self.availability_zones[az_id] = az
            for j in range(machines_per_az):
                machine_id = f"machine-{az_id}-{j+1}"
                machine = Machine(id=machine_id, az=az_id)
                self.machines[machine_id] = machine
                az.add_machine(machine)

                # Create DataNode on this machine
                data_node_id = f"data_node-{machine_id}"
                data_node = DataNode(
                    env=self.env,
                    network=self.network,
                    controller=self.controller,
                    machine=machine, # Pass the machine instance
                    az=az_id,
                    address=machine_id, # Using machine_id as address for simplicity
                    id=data_node_id,
                    metrics=self.metrics
                )
                self.data_nodes[data_node_id] = data_node

    def _setup_gateway_nodes(self, num_gateways: int):
        # Distribute gateway nodes across AZs and machines
        machine_ids = list(self.machines.keys())
        for i in range(num_gateways):
            machine_id = random.choice(machine_ids)
            machine = self.machines[machine_id]
            gateway_id = f"gateway-{i+1}"
            gateway = GatewayNode(
                env=self.env,
                network=self.network,
                controller=self.controller,
                load_balancer=self.load_balancer,
                machine=machine, # Pass the machine instance
                az=machine.az,
                address=gateway_id, # Using gateway_id as address for simplicity
                id=gateway_id,
                metrics=self.metrics
            )
            self.gateway_nodes[gateway_id] = gateway

    def _setup_client_libraries(self, num_clients: int):
        machine_ids = list(self.machines.keys())
        for i in range(num_clients):
            client_id = f"client-{i+1}"
            # Assign client to a random machine
            machine = self.machines[random.choice(machine_ids)]
            client = ClientLibrary(
                env=self.env,
                network=self.network,
                load_balancer=self.load_balancer,
                machine=machine, # Pass the machine instance
                id=client_id
            )
            self.client_libraries[client_id] = client

    def run_scenario(self, duration: int = 100):
        logger.info(f"\n{{'='*30}}\nStarting Helios Simulation for {duration} seconds\n{{'='*30}}")
        self.env.process(self._client_workload())
        self.env.process(self._failure_scenario())
        self.env.process(self._snapshot_scenario())
        if self.args.enable_machine_reboots:
            self.env.process(self._machine_reboot_scenario())
        if self.args.enable_network_outages:
            self.env.process(self._network_outage_scenario())
        if self.args.enable_client_crashes:
            self.env.process(self._client_crash_scenario())
        if self.args.enable_process_crashes:
            self.env.process(self._process_crash_scenario())
        if self.args.enable_disk_failures:
            self.env.process(self._disk_failure_scenario())
        if self.args.enable_clock_skew:
            self.env.process(self._clock_skew_scenario())
        if self.args.enable_high_latency:
            self.env.process(self._high_latency_scenario())
        if self.args.enable_packet_loss:
            self.env.process(self._packet_loss_scenario())
        self.env.run(until=duration)
        logger.info(f"\n{{'='*30}}\nSimulation Finished at {self.env.now:.4f}\n{{'='*30}}")
        self._report_metrics()

    def _client_workload(self):
        client_ids = list(self.client_libraries.keys())
        keys = [f"key_{i}" for i in range(20)] # Some keys to operate on
        request_count = 0

        effective_total_requests = None
        if self.args.requests_per_client is not None:
            effective_total_requests = self.args.requests_per_client * len(client_ids)

        while True:
            if effective_total_requests is not None and request_count >= effective_total_requests:
                logger.info(f"[{self.env.now:.4f}] Reached effective_total_requests limit ({effective_total_requests}). Stopping client workload.")
                break

            client_id = random.choice(client_ids)
            client = self.client_libraries[client_id]
            key = random.choice(keys)

            if random.random() < 0.7: # 70% Puts, 30% Gets
                value = f"value_{{{uuid.uuid4()}}}"
                logger.info("[{:.4f}] Client {}: Initiating PUT for {}".format(self.env.now, client_id, key))
                client.put(key, value)
            else:
                consistency = random.choice([ReadConsistency.LINEARIZABLE, ReadConsistency.STALE])
                logger.info("[{:.4f}] Client {}: Initiating GET for {} ({})".format(self.env.now, client_id, key, consistency.name))
                client.get(key, consistency)

            request_count += 1
            # Calculate the aggregate request interval based on the number of clients
            # If each client generates a request every `request_interval_per_client` seconds,
            # then `num_clients` clients generate `num_clients` requests in `request_interval_per_client` seconds.
            # So, one request is generated every `request_interval_per_client / num_clients` seconds.
            if len(client_ids) > 0:
                # Introduce some randomness around the calculated interval
                base_interval = self.args.request_interval_per_client / len(client_ids)
                yield self.env.timeout(random.uniform(base_interval * 0.8, base_interval * 1.2))
            else:
                yield self.env.timeout(self.args.request_interval_per_client) # Fallback if no clients


    def _failure_scenario(self):
        # Simulate machine failures and recoveries
        machine_ids = list(self.machines.keys())
        az_ids = list(self.availability_zones.keys())

        while True:
            # Determine next failure event time based on whether AZ failures are enabled
            if self.args.enable_az_failures:
                yield self.env.timeout(random.uniform(self.args.az_failure_interval * 0.8, self.args.az_failure_interval * 1.2))
            else:
                yield self.env.timeout(random.uniform(5, 15)) # Original interval for machine failures

            if self.args.enable_az_failures and random.random() < self.args.az_failure_chance_in_failure_scenario: # Chance of AZ failure
                az_id = random.choice(az_ids)
                az = self.availability_zones[az_id]
                if az.is_up:
                    logger.info("[{:.4f}] Initiating AZ failure for {}".format(self.env.now, az_id))
                    az.fail()
                    # Simulate recovery after some time
                    yield self.env.timeout(random.uniform(self.args.az_failure_duration * 0.8, self.args.az_failure_duration * 1.2))
                    logger.info("[{:.4f}] Initiating AZ recovery for {}".format(self.env.now, az_id))
                    az.recover()
                else:
                    logger.info("[{:.4f}] AZ {} already down, skipping failure.".format(self.env.now, az_id))
            else:
                # Existing machine failure logic
                machine_id = random.choice(machine_ids)
                machine = self.machines[machine_id]
                if machine.is_up:
                    logger.info("[{:.4f}] Initiating machine failure for {}".format(self.env.now, machine_id))
                    machine.fail()
                    # Simulate recovery after some time
                    yield self.env.timeout(random.uniform(5, 10))
                    logger.info("[{:.4f}] Initiating machine recovery for {}".format(self.env.now, machine_id))
                    machine.recover()
                else:
                    logger.info("[{:.4f}] Machine {} already down, skipping failure.".format(self.env.now, machine_id))

    def _snapshot_scenario(self):
        while True:
            yield self.env.timeout(random.uniform(20, 40)) # Take snapshot every 20-40 seconds
            snapshot_id = f"snapshot-{uuid.uuid4()}"
            logger.info("[{:.4f}] Initiating Snapshot {}".format(self.env.now, snapshot_id))
            snapshot_request = SnapshotRequest(
                client_id="simulation",
                request_id=snapshot_id,
                timestamp=self.env.now,
                snapshot_id=snapshot_id
            )
            self.network.send_message(
                NetworkMessage(
                    sender_id="simulation",
                    receiver_id=self.snapshot_service.id,
                    payload=snapshot_request,
                    timestamp=self.env.now
                )
            )

    def _machine_reboot_scenario(self):
        while True:
            yield self.env.timeout(random.uniform(self.args.machine_reboot_interval * 0.8, self.args.machine_reboot_interval * 1.2))

            available_machines = [m for m in self.machines.values() if m.is_up]
            if not available_machines:
                logger.info(f"[{self.env.now:.4f}] No machines available for reboot, skipping.")
                continue

            machine = random.choice(available_machines)
            logger.info(f"[{self.env.now:.4f}] Initiating machine reboot for {machine.id}")
            machine.fail()

            reboot_duration = random.uniform(self.args.machine_reboot_duration * 0.8, self.args.machine_reboot_duration * 1.2)
            yield self.env.timeout(reboot_duration)

            logger.info(f"[{self.env.now:.4f}] Machine {machine.id} recovering from reboot.")
            machine.recover()

    def _network_outage_scenario(self):
        while True:
            yield self.env.timeout(random.uniform(self.args.network_outage_interval * 0.8, self.args.network_outage_interval * 1.2))

            if random.random() < self.args.az_network_outage_chance:
                # AZ-wide network outage
                az_ids = list(self.availability_zones.keys())
                if not az_ids:
                    logger.info(f"[{self.env.now:.4f}] No AZs available for network outage, skipping.")
                    continue
                az_id = random.choice(az_ids)
                logger.info(f"[{self.env.now:.4f}] Initiating AZ network outage for {az_id}")
                self.network.fail_az_network(az_id)

                outage_duration = random.uniform(self.args.network_outage_duration * 0.8, self.args.network_outage_duration * 1.2)
                yield self.env.timeout(outage_duration)

                logger.info(f"[{self.env.now:.4f}] AZ network for {az_id} recovering.")
                self.network.recover_az_network(az_id)
            else:
                # Link failure between two random nodes
                node_ids = list(self.network.nodes.keys())
                if len(node_ids) < 2:
                    logger.info(f"[{self.env.now:.4f}] Not enough nodes for link failure, skipping.")
                    continue
                sender_id, receiver_id = random.sample(node_ids, 2)
                logger.info(f"[{self.env.now:.4f}] Initiating link failure between {sender_id} and {receiver_id}")
                self.network.fail_link(sender_id, receiver_id)

                outage_duration = random.uniform(self.args.network_outage_duration * 0.8, self.args.network_outage_duration * 1.2)
                yield self.env.timeout(outage_duration)

                logger.info(f"[{self.env.now:.4f}] Link between {sender_id} and {receiver_id} recovering.")
                self.network.recover_link(sender_id, receiver_id)

    def _client_crash_scenario(self):
        while True:
            yield self.env.timeout(random.uniform(self.args.client_crash_interval * 0.8, self.args.client_crash_interval * 1.2))

            available_clients = [c for c in self.client_libraries.values() if not c.is_crashed]
            if not available_clients:
                logger.info(f"[{self.env.now:.4f}] No clients available for crash, skipping.")
                continue

            client = random.choice(available_clients)
            logger.info(f"[{self.env.now:.4f}] Initiating client crash for {client.id}")
            client.crash()

            crash_duration = random.uniform(self.args.client_crash_duration * 0.8, self.args.client_crash_duration * 1.2)
            yield self.env.timeout(crash_duration)

            logger.info(f"[{self.env.now:.4f}] Client {client.id} recovering from crash.")
            client.recover()

    def _process_crash_scenario(self):
        while True:
            yield self.env.timeout(random.uniform(self.args.process_crash_interval * 0.8, self.args.process_crash_interval * 1.2))

            target_type = self.args.process_crash_target_type
            if target_type == "random":
                target_type = random.choice(["data_node", "gateway_node"])

            process: Union[DataNode, GatewayNode]
            if target_type == "data_node":
                available_data_nodes = [n for n in self.data_nodes.values() if not n.is_crashed and n.node_info and n.node_info.is_up]
                if not available_data_nodes:
                    logger.info(f"[{self.env.now:.4f}] No available DataNodes for process crash, skipping.")
                    continue
                process = random.choice(available_data_nodes)
            elif target_type == "gateway_node":
                available_gateway_nodes = [n for n in self.gateway_nodes.values() if not n.is_crashed and n.is_up]
                if not available_gateway_nodes:
                    logger.info(f"[{self.env.now:.4f}] No available GatewayNodes for process crash, skipping.")
                    continue
                process = random.choice(available_gateway_nodes)
            else:
                logger.warning(f"[{self.env.now:.4f}] Unknown process crash target type: {target_type}")
                continue

            logger.info(f"[{self.env.now:.4f}] Initiating process crash for {process.id} (Type: {target_type}).")
            process.crash()

            crash_duration = random.uniform(self.args.process_crash_duration * 0.8, self.args.process_crash_duration * 1.2)
            yield self.env.timeout(crash_duration)

            logger.info(f"[{self.env.now:.4f}] Process {process.id} (Type: {target_type}) recovering from crash.")
            process.recover()

    def _disk_failure_scenario(self):
        while True:
            yield self.env.timeout(random.uniform(self.args.disk_failure_interval * 0.8, self.args.disk_failure_interval * 1.2))

            available_data_nodes = [n for n in self.data_nodes.values() if not n.is_disk_failed]
            if not available_data_nodes:
                logger.info(f"[{self.env.now:.4f}] No available DataNodes for disk failure, skipping.")
                continue

            data_node = random.choice(available_data_nodes)
            
            # Determine failure mode
            failure_mode = self.args.disk_failure_mode
            if failure_mode == "random": # Add 'random' as a choice in argparse later if needed
                failure_mode = random.choice(["read_only", "corrupt_writes", "full_failure"])

            logger.info(f"[{self.env.now:.4f}] Initiating disk failure for DataNode {data_node.id} with mode: {failure_mode}.")
            data_node.fail_disk(failure_mode)

            failure_duration = random.uniform(self.args.disk_failure_duration * 0.8, self.args.disk_failure_duration * 1.2)
            yield self.env.timeout(failure_duration)

            logger.info(f"[{self.env.now:.4f}] DataNode {data_node.id} disk recovering.")
            data_node.recover_disk()

    def _clock_skew_scenario(self):
        while True:
            yield self.env.timeout(random.uniform(self.args.clock_skew_interval * 0.8, self.args.clock_skew_interval * 1.2))

            available_machines = list(self.machines.values())
            if not available_machines:
                logger.info(f"[{self.env.now:.4f}] No machines available for clock skew, skipping.")
                continue

            machine = random.choice(available_machines)
            skew_amount = random.uniform(-self.args.max_clock_skew, self.args.max_clock_skew)

            logger.info(f"[{self.env.now:.4f}] Introducing clock skew of {skew_amount:.4f}s to machine {machine.id}.")
            machine.introduce_skew(skew_amount)

            skew_duration = random.uniform(self.args.clock_skew_interval * 0.2, self.args.clock_skew_interval * 0.5) # Skew for a fraction of the interval
            yield self.env.timeout(skew_duration)

            logger.info(f"[{self.env.now:.4f}] Removing clock skew from machine {machine.id}.")
            machine.remove_skew()

    def _high_latency_scenario(self):
        # Store original network conditions
        original_latency_mean = self.network.latency_mean
        original_latency_std = self.network.latency_std

        while True:
            yield self.env.timeout(random.uniform(self.args.high_latency_interval * 0.8, self.args.high_latency_interval * 1.2))

            # Introduce high latency
            new_latency_mean = original_latency_mean + self.args.high_latency_mean_increase
            new_latency_std = original_latency_std + self.args.high_latency_std_increase
            self.network.set_network_conditions(latency_mean=new_latency_mean, latency_std=new_latency_std)
            logger.info(f"[{self.env.now:.4f}] Introducing high latency: mean={new_latency_mean:.4f}s, std={new_latency_std:.4f}s.")

            latency_duration = random.uniform(self.args.high_latency_duration * 0.8, self.args.high_latency_duration * 1.2)
            yield self.env.timeout(latency_duration)

            # Restore original latency
            self.network.set_network_conditions(latency_mean=original_latency_mean, latency_std=original_latency_std)
            logger.info(f"[{self.env.now:.4f}] Restoring normal latency: mean={original_latency_mean:.4f}s, std={original_latency_std:.4f}s.")

    def _packet_loss_scenario(self):
        # Store original network conditions
        original_drop_rate = self.network.drop_rate

        while True:
            yield self.env.timeout(random.uniform(self.args.packet_loss_interval * 0.8, self.args.packet_loss_interval * 1.2))

            # Introduce packet loss
            self.network.set_network_conditions(drop_rate=self.args.packet_loss_rate)
            logger.info(f"[{self.env.now:.4f}] Introducing packet loss: rate={self.args.packet_loss_rate:.2f}.")

            packet_loss_duration = random.uniform(self.args.packet_loss_duration * 0.8, self.args.packet_loss_duration * 1.2)
            yield self.env.timeout(packet_loss_duration)

            # Restore original drop rate
            self.network.set_network_conditions(drop_rate=original_drop_rate)
            logger.info(f"[{self.env.now:.4f}] Restoring normal packet drop rate: rate={original_drop_rate:.2f}.")

    def _report_metrics(self):
        print("\n--- Simulation Metrics ---")
        total_requests = 0
        successful_requests = 0
        total_latency = 0.0
        latencies = []

        for client_id, client_lib in self.client_libraries.items():
            for req_id, success in client_lib.request_results.items():
                total_requests += 1
                if success:
                    successful_requests += 1
                    latency = client_lib.request_latencies.get(req_id)
                    if latency is not None:
                        total_latency += latency
                        latencies.append(latency)
        
        if total_requests > 0:
            success_rate = (successful_requests / total_requests) * 100
            avg_latency = total_latency / successful_requests if successful_requests > 0 else 0
            print(f"Total Requests: {total_requests}")
            print(f"Successful Requests: {successful_requests}")
            print(f"Success Rate: {success_rate:.2f}%")
            print(f"Average Successful Request Latency: {avg_latency:.4f}s")
            
            if latencies:
                latencies.sort()
                # Calculate P99 latency correctly
                if len(latencies) > 0:
                    p99_index = int(len(latencies) * 0.99)
                    p99_latency = latencies[p99_index - 1] if p99_index > 0 else latencies[0]
                    print(f"P99 Latency: {p99_latency:.4f}s")
        else:
            print("No requests processed.")

        print(f"Total Redirects: {self.metrics.total_redirects}")
        print(f"Leader Requests (Correct Node): {self.metrics.leader_requests_correct_node}")
        print(f"Leader Requests (Wrong Node): {self.metrics.leader_requests_wrong_node}")

        if any(self.metrics.failure_reasons.values()):
            print("\n--- Failure Reasons ---")
            for category in self.metrics.failure_reasons:
                if self.metrics.failure_reasons[category]:
                    print(f"  {category.value}:")
                    for reason, count in self.metrics.failure_reasons[category].items():
                        print(f"    - {reason}: {count}")

        # Collect all_total_request_times for _analyze_request_timings
        all_total_request_times = []
        for client_id, client_lib in self.client_libraries.items():
            for req_id, latency in client_lib.request_latencies.items():
                # Only consider successful requests for overall latency calculation
                if client_lib.request_results.get(req_id) == True:
                    all_total_request_times.append(latency)

        self._analyze_request_timings(all_total_request_times)

    def _analyze_request_timings(self, all_total_request_times: List[float]):
        print("\n--- Request Timing Analysis ---")
        # This will store durations for each step across all requests
        step_durations: Dict[str, List[float]] = {
            "client_to_gateway": [],
            "gateway_processing": [],
            "gateway_to_datanode": [],
            "datanode_processing": [],
            "datanode_to_gateway": [],
            "gateway_to_client": [],
        }

        for req_id, events in self.network.request_timings.items():
            # Sort events by timestamp
            events.sort(key=lambda x: x[0])

            # Extract key event timestamps
            client_sent_ts = None
            gateway_received_req_ts = None
            gateway_forwarded_req_ts = None
            datanode_received_req_ts = None
            datanode_sent_resp_ts = None
            gateway_received_resp_ts = None
            client_received_resp_ts = None

            for ts, event_type, node_id in events:
                if event_type == "sent" and node_id.startswith("client") and client_sent_ts is None:
                    client_sent_ts = ts
                elif event_type == "received" and node_id.startswith("gateway") and gateway_received_req_ts is None:
                    gateway_received_req_ts = ts
                elif event_type == "sent" and node_id.startswith("gateway") and gateway_forwarded_req_ts is None:
                    gateway_forwarded_req_ts = ts
                elif event_type == "received" and node_id.startswith("data_node") and datanode_received_req_ts is None:
                    datanode_received_req_ts = ts
                elif event_type == "sent" and node_id.startswith("data_node") and datanode_sent_resp_ts is None:
                    datanode_sent_resp_ts = ts
                elif event_type == "received" and node_id.startswith("gateway") and datanode_sent_resp_ts is not None and gateway_received_resp_ts is None: # This is a response
                    gateway_received_resp_ts = ts
                elif event_type == "received" and node_id.startswith("client") and client_received_resp_ts is None:
                    client_received_resp_ts = ts
            
            # Calculate durations for available steps
            if client_sent_ts and gateway_received_req_ts:
                step_durations["client_to_gateway"].append(gateway_received_req_ts - client_sent_ts)
            if gateway_received_req_ts and gateway_forwarded_req_ts:
                step_durations["gateway_processing"].append(gateway_forwarded_req_ts - gateway_received_req_ts)
            if gateway_forwarded_req_ts and datanode_received_req_ts:
                step_durations["gateway_to_datanode"].append(datanode_received_req_ts - gateway_forwarded_req_ts)
            if datanode_received_req_ts and datanode_sent_resp_ts:
                step_durations["datanode_processing"].append(datanode_sent_resp_ts - datanode_received_req_ts)
            if datanode_sent_resp_ts and gateway_received_resp_ts:
                step_durations["datanode_to_gateway"].append(gateway_received_resp_ts - datanode_sent_resp_ts)
            if gateway_received_resp_ts and client_received_resp_ts:
                step_durations["gateway_to_client"].append(client_received_resp_ts - gateway_received_resp_ts)
        
        # Aggregate and print results
        if any(step_durations.values()):
            print("\nStep Durations (s) - Avg (Min/Max/Variance) and Percentage of Total Request Time:")
            
            avg_total_request_time = sum(all_total_request_times) / len(all_total_request_times) if all_total_request_times else 0.0

            for step, durations in step_durations.items():
                if durations:
                    avg_duration = sum(durations) / len(durations)
                    min_duration = min(durations)
                    max_duration = max(durations)
                    # Calculate variance, handle case with single data point
                    variance = statistics.variance(durations) if len(durations) > 1 else 0.0
                    percentage = (avg_duration / avg_total_request_time) * 100 if avg_total_request_time > 0 else 0
                    print(f"  {step:<20}: Avg={avg_duration:.4f}s (Min={min_duration:.4f}s / Max={max_duration:.4f}s / Var={variance:.4f}s^2) ({percentage:.2f}%)")
                else:
                    print(f"  {step:<20}: No data")
        else:
            print("No timing data collected for analysis.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run Helios Distributed KV Store Simulation.",
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    # General Simulation Configuration
    general_config_group = parser.add_argument_group("General Simulation Configuration")
    general_config_group.add_argument("--num_azs", type=int, default=3, help="Number of availability zones.")
    general_config_group.add_argument("--machines_per_az", type=int, default=3, help="Number of machines per availability zone.")
    general_config_group.add_argument("--num_gateways", type=int, default=3, help="Number of gateway nodes.")
    general_config_group.add_argument("--num_clients", type=int, default=2, help="Number of client libraries.")
    general_config_group.add_argument("--duration", type=int, default=60, help="Duration of the simulation in seconds.")
    general_config_group.add_argument("--request_interval_per_client", type=float, default=0.3, help="Average interval between requests generated by a single client (in seconds).")
    general_config_group.add_argument("--requests_per_client", type=int, default=None,
                                      help="Number of requests each client should generate (default: unlimited until time runs out).")

    # Failure Injection - Machine Reboot
    machine_reboot_group = parser.add_argument_group("Failure Injection - Machine Reboot")
    machine_reboot_group.add_argument("--enable_machine_reboots", action="store_true", help="Enable machine reboot failures.")
    machine_reboot_group.add_argument("--machine_reboot_interval", type=float, default=300,
                                      help="Average interval between machine reboots in seconds.")
    machine_reboot_group.add_argument("--machine_reboot_duration", type=float, default=30,
                                      help="Average duration a machine stays down during a reboot in seconds.")

    # Failure Injection - Network Outage
    network_outage_group = parser.add_argument_group("Failure Injection - Network Outage")
    network_outage_group.add_argument("--enable_network_outages", action="store_true", help="Enable network outage failures.")
    network_outage_group.add_argument("--network_outage_interval", type=float, default=120,
                                      help="Average interval between network outage events in seconds.")
    network_outage_group.add_argument("--network_outage_duration", type=float, default=15,
                                      help="Average duration of a network outage in seconds.")
    network_outage_group.add_argument("--az_network_outage_chance", type=float, default=0.3,
                                      help="Probability (0.0-1.0) that a network outage is AZ-wide.")

    # Failure Injection - Availability Zone Failure
    az_failure_group = parser.add_argument_group("Failure Injection - Availability Zone Failure")
    az_failure_group.add_argument("--enable_az_failures", action="store_true", help="Enable Availability Zone failures.")
    az_failure_group.add_argument("--az_failure_interval", type=float, default=60,
                                  help="Average interval between AZ failure events in seconds.")
    az_failure_group.add_argument("--az_failure_duration", type=float, default=30,
                                  help="Average duration an AZ stays down during a failure in seconds.")
    az_failure_group.add_argument("--az_failure_chance_in_failure_scenario", type=float, default=0.3,
                                  help="Probability (0.0-1.0) that a failure in _failure_scenario is an AZ failure.")

    # Failure Injection - Client Crash
    client_crash_group = parser.add_argument_group("Failure Injection - Client Crash")
    client_crash_group.add_argument("--enable_client_crashes", action="store_true", help="Enable client crash failures.")
    client_crash_group.add_argument("--client_crash_interval", type=float, default=90,
                                    help="Average interval between client crash events in seconds.")
    client_crash_group.add_argument("--client_crash_duration", type=float, default=10,
                                    help="Average duration a client stays crashed in seconds.")

    # Failure Injection - Process Crash
    process_crash_group = parser.add_argument_group("Failure Injection - Process Crash")
    process_crash_group.add_argument("--enable_process_crashes", action="store_true", help="Enable process crash failures.")
    process_crash_group.add_argument("--process_crash_interval", type=float, default=180,
                                     help="Average interval between process crash events in seconds.")
    process_crash_group.add_argument("--process_crash_duration", type=float, default=10,
                                     help="Average duration a process stays crashed/restarting in seconds.")
    process_crash_group.add_argument("--process_crash_target_type", type=str, default="random",
                                     choices=["data_node", "gateway_node", "random"],
                                     help="Type of process to crash: 'data_node', 'gateway_node', or 'random'.")

    # Failure Injection - Disk Failure
    disk_failure_group = parser.add_argument_group("Failure Injection - Disk Failure")
    disk_failure_group.add_argument("--enable_disk_failures", action="store_true", help="Enable disk failure injection.")
    disk_failure_group.add_argument("--disk_failure_interval", type=float, default=240,
                                    help="Average interval between disk failure events in seconds.")
    disk_failure_group.add_argument("--disk_failure_duration", type=float, default=20,
                                    help="Average duration a disk stays failed in seconds.")
    disk_failure_group.add_argument("--disk_failure_mode", type=str, default="full_failure",
                                    choices=["read_only", "corrupt_writes", "full_failure"],
                                    help="Mode of disk failure: 'read_only', 'corrupt_writes', or 'full_failure'.")

    # Failure Injection - Clock Skew
    clock_skew_group = parser.add_argument_group("Failure Injection - Clock Skew")
    clock_skew_group.add_argument("--enable_clock_skew", action="store_true", help="Enable clock skew injection.")
    clock_skew_group.add_argument("--clock_skew_interval", type=float, default=60,
                                  help="Average interval at which clock skew is introduced/adjusted in seconds.")
    clock_skew_group.add_argument("--max_clock_skew", type=float, default=0.1,
                                  help="Maximum absolute clock skew in seconds.")

    # Failure Injection - High Latency
    high_latency_group = parser.add_argument_group("Failure Injection - High Latency")
    high_latency_group.add_argument("--enable_high_latency", action="store_true", help="Enable high network latency injection.")
    high_latency_group.add_argument("--high_latency_interval", type=float, default=90,
                                    help="Average interval at which high latency is introduced/removed in seconds.")
    high_latency_group.add_argument("--high_latency_duration", type=float, default=15,
                                    help="Average duration high latency is active in seconds.")
    high_latency_group.add_argument("--high_latency_mean_increase", type=float, default=0.1,
                                    help="Amount to increase mean latency by during high latency events.")
    high_latency_group.add_argument("--high_latency_std_increase", type=float, default=0.05,
                                    help="Amount to increase standard deviation of latency by during high latency events.")

    # Failure Injection - Packet Loss
    packet_loss_group = parser.add_argument_group("Failure Injection - Packet Loss")
    packet_loss_group.add_argument("--enable_packet_loss", action="store_true", help="Enable network packet loss injection.")
    packet_loss_group.add_argument("--packet_loss_interval", type=float, default=100,
                                   help="Average interval at which packet loss is introduced/removed in seconds.")
    packet_loss_group.add_argument("--packet_loss_duration", type=float, default=10,
                                   help="Average duration packet loss is active in seconds.")
    packet_loss_group.add_argument("--packet_loss_rate", type=float, default=0.1,
                                   help="Rate of packet loss (0.0 to 1.0) during packet loss events.")

    args = parser.parse_args()

    sim = HeliosSimulation(args)
    def print_config(args):
        print("\n--- Simulation Configuration ---")

        print("\nGeneral Simulation Configuration:")
        print(f"  Number of Availability Zones: {args.num_azs}")
        print(f"  Machines per AZ: {args.machines_per_az}")
        print(f"  Number of Gateway Nodes: {args.num_gateways}")
        print(f"  Number of Client Libraries: {args.num_clients}")
        print(f"  Simulation Duration (seconds): {args.duration}")
        print(f"  Request Interval per Client (seconds): {args.request_interval_per_client}")
        print(f"  Requests Per Client: {args.requests_per_client if args.requests_per_client is not None else 'Unlimited'}")

        print("\nFailure Injection - Machine Reboot:")
        print(f"  Enable Machine Reboots: {args.enable_machine_reboots}")
        print(f"  Machine Reboot Interval (seconds): {args.machine_reboot_interval}")
        print(f"  Machine Reboot Duration (seconds): {args.machine_reboot_duration}")

        print("\nFailure Injection - Network Outage:")
        print(f"  Enable Network Outages: {args.enable_network_outages}")
        print(f"  Network Outage Interval (seconds): {args.network_outage_interval}")
        print(f"  Network Outage Duration (seconds): {args.network_outage_duration}")
        print(f"  AZ Network Outage Chance: {args.az_network_outage_chance}")

        print("\nFailure Injection - Availability Zone Failure:")
        print(f"  Enable AZ Failures: {args.enable_az_failures}")
        print(f"  AZ Failure Interval (seconds): {args.az_failure_interval}")
        print(f"  AZ Failure Duration (seconds): {args.az_failure_duration}")
        print(f"  AZ Failure Chance in Failure Scenario: {args.az_failure_chance_in_failure_scenario}")

        print("\nFailure Injection - Client Crash:")
        print(f"  Enable Client Crashes: {args.enable_client_crashes}")
        print(f"  Client Crash Interval (seconds): {args.client_crash_interval}")
        print(f"  Client Crash Duration (seconds): {args.client_crash_duration}")

        print("\nFailure Injection - Process Crash:")
        print(f"  Enable Process Crashes: {args.enable_process_crashes}")
        print(f"  Process Crash Interval (seconds): {args.process_crash_interval}")
        print(f"  Process Crash Duration (seconds): {args.process_crash_duration}")
        print(f"  Process Crash Target Type: {args.process_crash_target_type}")

        print("\nFailure Injection - Disk Failure:")
        print(f"  Enable Disk Failures: {args.enable_disk_failures}")
        print(f"  Disk Failure Interval (seconds): {args.disk_failure_interval}")
        print(f"  Disk Failure Duration (seconds): {args.disk_failure_duration}")
        print(f"  Disk Failure Mode: {args.disk_failure_mode}")

        print("\nFailure Injection - Clock Skew:")
        print(f"  Enable Clock Skew: {args.enable_clock_skew}")
        print(f"  Clock Skew Interval (seconds): {args.clock_skew_interval}")
        print(f"  Max Clock Skew (seconds): {args.max_clock_skew}")

        print("\nFailure Injection - High Latency:")
        print(f"  Enable High Latency: {args.enable_high_latency}")
        print(f"  High Latency Interval (seconds): {args.high_latency_interval}")
        print(f"  High Latency Duration (seconds): {args.high_latency_duration}")
        print(f"  High Latency Mean Increase (seconds): {args.high_latency_mean_increase}")
        print(f"  High Latency Std Increase (seconds): {args.high_latency_std_increase}")

        print("\nFailure Injection - Packet Loss:")
        print(f"  Enable Packet Loss: {args.enable_packet_loss}")
        print(f"  Packet Loss Interval (seconds): {args.packet_loss_interval}")
        print(f"  Packet Loss Duration (seconds): {args.packet_loss_duration}")
        print(f"  Packet Loss Rate: {args.packet_loss_rate}")
        print("------------------------------")

    print_config(args)
    sim.run_scenario(duration=args.duration)
