import simpy
import random
from typing import Dict, List, Optional

from simulator.models.internal import NodeInfo, ShardInfo, RoutingTable, NetworkMessage, NodeStatusMessage, WALEntry, KVEntry, ShardRoleUpdateMessage, RequestContext
from simulator.models.api import PutRequest, PutResponse, GetRequest, GetResponse, ReadConsistency
from simulator.infra.network import Network
from simulator.infra.machine import Machine
from simulator.infra.base_service import BaseService
from simulator.infra.logger import ContextLogger
from simulator.components.controller import Controller
from simulator.models.metrics import MetricsCollector, ErrorCategory

import logging
logger = logging.getLogger(__name__)


class DataNode(BaseService):
    """Data node that stores and replicates key-value data.

    Refactored to use BaseService for common crash/recover patterns.
    """
    # BaseService provides: id, env, network, machine, is_crashed, _listen_process

    controller: Controller
    az: str
    address: str
    node_info: Optional[NodeInfo] = None
    is_leader_for_shards: List[str] = []
    is_replica_for_shards: List[str] = []
    kv_store: Dict[str, KVEntry] = {}
    wal: List[WALEntry] = []
    replication_factor: int = 3
    metrics: 'MetricsCollector'
    _wal_process: Optional[simpy.Process] = None
    is_disk_failed: bool = False
    disk_failure_mode: str = "none"  # "none", "read_only", "corrupt_writes", "full_failure"
    _context_logger: Optional[ContextLogger] = None

    class Config:
        arbitrary_types_allowed = True

    def __init__(self, env: simpy.Environment, network: Network, controller: Controller, machine: Machine, az: str, address: str, metrics: 'MetricsCollector', **data):
        # Initialize BaseService (handles id, env, network, machine, callbacks, listen process)
        super().__init__(
            env=env,
            network=network,
            machine=machine,
            controller=controller,
            az=az,
            address=address,
            metrics=metrics,
            **data
        )

        # Initialize DataNode-specific fields
        self.node_info = NodeInfo(node_id=self.id, address=self.address, availability_zone=self.az, is_up=True)

        # Register with controller and start WAL process
        self.env.process(self._register_with_controller())
        self._wal_process = self.env.process(self._apply_wal_entries())

        # Create context logger
        self._context_logger = ContextLogger(f"DataNode {self.id}", self.machine, self.env)

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] DataNode {self.id} initialized in AZ {self.az}.")

    def _on_machine_fail(self, machine_id: str):
        """Override to add DataNode-specific behavior on machine failure."""
        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] DataNode {self.id}: Underlying machine {machine_id} failed. DataNode going down.")
        assert self.node_info is not None
        self.node_info.is_up = False

        # Call base class crash()
        super()._on_machine_fail(machine_id)

        # Notify controller about unregistration
        unregister_msg = NodeStatusMessage(node_info=self.node_info, status='UNREGISTER')
        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.controller.id,
                payload=unregister_msg,
                timestamp=self.machine.get_current_time(self.env.now)
            )
        )

    def _on_machine_recover(self, machine_id: str):
        """Override to add DataNode-specific behavior on machine recovery."""
        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] DataNode {self.id}: Underlying machine {machine_id} recovered. DataNode coming up.")
        assert self.node_info is not None
        self.node_info.is_up = True

        # Call base class recover()
        super()._on_machine_recover(machine_id)

        # Notify controller about registration
        register_msg = NodeStatusMessage(node_info=self.node_info, status='REGISTER')
        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.controller.id,
                payload=register_msg,
                timestamp=self.machine.get_current_time(self.env.now)
            )
        )

    def crash(self):
        """Override base class crash to also handle WAL process."""
        super().crash()
        # Also interrupt WAL process
        if self._wal_process and self._wal_process.is_alive:
            self._wal_process.interrupt()

    def recover(self):
        """Override base class recover to also restart WAL process."""
        super().recover()
        # Also restart WAL process
        if not self._wal_process or not self._wal_process.is_alive:
            self._wal_process = self.env.process(self._apply_wal_entries())

    def fail_disk(self, mode: str = "full_failure"):
        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] DataNode {self.id}: Disk failing with mode '{mode}'.")
        self.is_disk_failed = True
        self.disk_failure_mode = mode

    def recover_disk(self):
        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] DataNode {self.id}: Disk recovering.")
        self.is_disk_failed = False
        self.disk_failure_mode = "none"

    def _register_with_controller(self):
        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] DataNode {self.id}: Registering with Controller.")
        assert self.node_info is not None
        register_msg = NodeStatusMessage(node_info=self.node_info, status='REGISTER')
        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.controller.id,
                payload=register_msg,
                timestamp=self.machine.get_current_time(self.env.now)
            )
        )
        yield self.env.timeout(0) # Allow message to be processed

    def _handle_message(self, msg: NetworkMessage):
        """Handle received messages. Called by BaseService._listen_for_messages()."""
        # Use context logger
        if self._context_logger:
            log_prefix = self._context_logger._get_prefix(msg.request_context)
        else:
            # Fallback if logger not initialized
            log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] DataNode {self.id}"

        assert self.node_info is not None
        if not self.node_info.is_up:
            logger.info(f"{log_prefix} is down, dropping message from {msg.sender_id}: {msg.payload.__class__.__name__}")
            return

        logger.info(f"{log_prefix} received message from {msg.sender_id}: {msg.payload.__class__.__name__}")

        if isinstance(msg.payload, PutRequest):
            self.env.process(self._handle_put_request(msg.payload, msg.sender_id, msg.request_context))
        elif isinstance(msg.payload, GetRequest):
            self.env.process(self._handle_get_request(msg.payload, msg.sender_id, msg.request_context))
        elif isinstance(msg.payload, WALEntry):
            self.env.process(self._handle_wal_entry(msg.payload, msg.sender_id, msg.request_context))
        elif isinstance(msg.payload, ShardRoleUpdateMessage):
            self.update_shard_roles(msg.payload.is_leader_for_shards, msg.payload.is_replica_for_shards)
        # Add handlers for other message types (Delete, AppendMetadata, List, etc.)

    def _apply_wal_entries(self):
        # Asynchronously apply WAL entries to KV store
        while True:
            if self.is_crashed:
                yield self.env.timeout(1) # Wait if crashed
                continue
            try:
                assert self.node_info is not None
                if not self.node_info.is_up:
                    yield self.env.timeout(1) # If down, wait before checking again
                    continue

                if self.is_disk_failed:
                    if self.disk_failure_mode in ["read_only", "full_failure"]:
                        logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] DataNode {self.id}: Disk is in {self.disk_failure_mode} mode. Cannot apply WAL entry.")
                        self.metrics.increment_failure_reason(ErrorCategory.STORAGE_ERROR, f"Disk {self.disk_failure_mode}")
                        yield self.env.timeout(0.01) # Simulate a small delay for failed operation
                        continue
                    elif self.disk_failure_mode == "corrupt_writes":
                        if self.wal:
                            entry = self.wal.pop(0) # Still pop, but don't apply
                            logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] DataNode {self.id}: Disk is in corrupt_writes mode. WAL entry {entry.entry_id} for key {entry.key} corrupted.")
                            self.metrics.increment_failure_reason(ErrorCategory.STORAGE_ERROR, "Corrupt writes")
                            yield self.env.timeout(random.uniform(0.005, 0.015)) # Simulate disk write latency
                            continue

                if self.wal:
                    entry = self.wal.pop(0) # Process oldest entry first
                    logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] DataNode {self.id}: Applying WAL entry {entry.entry_id} for key {entry.key}.")
                    # Simulate disk write latency
                    yield self.env.timeout(random.uniform(0.005, 0.015)) # 5-15ms for disk write
                    if entry.operation_type == 'PUT':
                        self.kv_store[entry.key] = KVEntry(
                            value=entry.value, metadata=entry.metadata or [], ttl=entry.ttl, last_modified=self.machine.get_current_time(self.env.now)
                        )
                    elif entry.operation_type == 'DELETE':
                        if entry.key in self.kv_store:
                            del self.kv_store[entry.key]
                    # TODO: Handle APPEND_METADATA
                else:
                    yield self.env.timeout(0.01) # Check again after a short delay
            except simpy.Interrupt:
                logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] DataNode {self.id} _apply_wal_entries interrupted.")
                continue

    def _handle_put_request(self, request: PutRequest, client_id: str, request_context: Optional[RequestContext]):
        log_prefix = self._context_logger._get_prefix(request_context) if self._context_logger else f"[{self.machine.get_current_time(self.env.now):.4f}] DataNode {self.id}"

        if self.is_disk_failed and self.disk_failure_mode in ["read_only", "full_failure"]:
            logger.warning(f"{log_prefix}: Disk is in {self.disk_failure_mode} mode. Cannot process Put for key {request.key}.")
            self.metrics.increment_failure_reason(ErrorCategory.STORAGE_ERROR, f"Disk {self.disk_failure_mode}")
            response = PutResponse(request_id=request.request_id, timestamp=self.machine.get_current_time(self.env.now), key=request.key, success=False, message="Disk failure")
            self.network.send_message(
                NetworkMessage(
                    sender_id=self.id,
                    receiver_id=client_id,
                    payload=response,
                    timestamp=self.machine.get_current_time(self.env.now),
                    request_context=request_context
                )
            )
            return

        # This DataNode is the leader for the shard
        shard_id = self.controller.get_shard_for_key(request.key)
        logger.info(f"{log_prefix}: Handling Put for key {request.key}. Shard ID: {shard_id}. Is leader for shards: {self.is_leader_for_shards}")
        if shard_id not in self.is_leader_for_shards:
            self.metrics.increment_wrong_leader_requests()
            # This should not happen if routing is correct, but for robustness
            logger.info(f"{log_prefix}: Received Put for {request.key} but not leader for {shard_id}. Redirecting.")
            # In a real system, this would involve redirecting the client or returning an error.
            # For simulation, we'll just fail the request for now.
            routing_table = self.controller.get_routing_table()
            leader_node = routing_table.shard_to_leader.get(shard_id)
            response = PutResponse(request_id=request.request_id, timestamp=self.machine.get_current_time(self.env.now), key=request.key, success=False, message="Not leader for shard", redirect_to=leader_node)
            self.metrics.increment_failure_reason(ErrorCategory.CONSISTENCY_ERROR, "Not leader for shard")
            self.network.send_message(
                NetworkMessage(
                    sender_id=self.id,
                    receiver_id=client_id,
                    payload=response,
                    timestamp=self.machine.get_current_time(self.env.now),
                    request_context=request_context
                )
            )
            return
        else:
            self.metrics.increment_correct_leader_requests()

        logger.info(f"{log_prefix}: Handling Put for key {request.key}.")
        wal_entry = WALEntry(
            entry_id=f"wal-{self.id}-{self.machine.get_current_time(self.env.now)}",
            key=request.key,
            value=request.value,
            metadata=request.metadata,
            operation_type='PUT',
            timestamp=self.machine.get_current_time(self.env.now)
        )
        self.wal.append(wal_entry)

        # Simulate WAL write latency
        yield self.env.timeout(random.uniform(0.001, 0.003)) # 1-3ms for WAL write

        # Forward WAL entry to followers and wait for quorum
        current_routing = self.controller.get_routing_table()
        replica_ids = current_routing.shard_to_replicas.get(shard_id, [])
        
        acks_received = 0
        # Include self in quorum for simplicity, as leader also writes to its WAL
        # In a real system, leader would apply to its state machine after quorum
        # For simulation, we count its own WAL write as one ack.
        acks_needed = (self.replication_factor // 2) + 1 # W > N/2

        # Send WAL entry to replicas
        for replica_id in replica_ids:
            if replica_id != self.id: # Don't send to self
                self.network.send_message(
                    NetworkMessage(
                        sender_id=self.id,
                        receiver_id=replica_id,
                        payload=wal_entry,
                        timestamp=self.machine.get_current_time(self.env.now),
                        request_context=request_context
                    )
                )
        
        # Wait for acknowledgements (simplified: assume followers will eventually ack)
        # For a more robust simulation, we'd need a mechanism for followers to send back ACKs
        # and the leader to wait for them. For now, we'll simulate the delay.
        yield self.env.timeout(random.uniform(0.01, 0.03)) # Simulate network + follower WAL write latency
        acks_received = acks_needed # Assume quorum is reached for now

        if acks_received >= acks_needed:
            logger.info(f"{log_prefix}: Quorum reached for Put {request.key}. Acknowledging client.")
            response = PutResponse(request_id=request.request_id, timestamp=self.machine.get_current_time(self.env.now), key=request.key)
            self.network.send_message(
                NetworkMessage(
                    sender_id=self.id,
                    receiver_id=client_id,
                    payload=response,
                    timestamp=self.machine.get_current_time(self.env.now),
                    request_context=request_context
                )
            )
        else:
            logger.info(f"{log_prefix}: Quorum NOT reached for Put {request.key}. Returning error.")
            self.metrics.increment_failure_reason(ErrorCategory.CONSISTENCY_ERROR, "Quorum not reached")
            response = PutResponse(request_id=request.request_id, timestamp=self.machine.get_current_time(self.env.now), key=request.key, success=False, message="Quorum not reached")
            self.network.send_message(
                NetworkMessage(
                    sender_id=self.id,
                    receiver_id=client_id,
                    payload=response,
                    timestamp=self.machine.get_current_time(self.env.now),
                    request_context=request_context
                )
            )

    def _handle_get_request(self, request: GetRequest, client_id: str, request_context: Optional[RequestContext]):
        log_prefix = self._context_logger._get_prefix(request_context) if self._context_logger else f"[{self.machine.get_current_time(self.env.now):.4f}] DataNode {self.id}"

        if self.is_disk_failed and self.disk_failure_mode in ["full_failure", "corrupt_writes"]:
            logger.warning(f"{log_prefix}: Disk is in {self.disk_failure_mode} mode. Cannot process Get for key {request.key}.")
            self.metrics.increment_failure_reason(ErrorCategory.STORAGE_ERROR, f"Disk {self.disk_failure_mode}")
            response = GetResponse(request_id=request.request_id, timestamp=self.machine.get_current_time(self.env.now), key=request.key, success=False, message="Disk failure")
            self.network.send_message(
                NetworkMessage(
                    sender_id=self.id,
                    receiver_id=client_id,
                    payload=response,
                    timestamp=self.machine.get_current_time(self.env.now),
                    request_context=request_context
                )
            )
            return

        logger.info(f"{log_prefix}: Handling Get for key {request.key} with consistency {request.consistency.name}.")
        shard_id = self.controller.get_shard_for_key(request.key)

        if request.consistency == ReadConsistency.LINEARIZABLE:
            if shard_id not in self.is_leader_for_shards:
                self.metrics.increment_wrong_leader_requests()
                logger.info(f"{log_prefix}: Received Linearizable Get for {request.key} but not leader for {shard_id}. Redirecting.")
                routing_table = self.controller.get_routing_table()
                leader_node = routing_table.shard_to_leader.get(shard_id)
                response = GetResponse(request_id=request.request_id, timestamp=self.machine.get_current_time(self.env.now), key=request.key, success=False, message="Not leader for shard", redirect_to=leader_node)
                self.metrics.increment_failure_reason(ErrorCategory.CONSISTENCY_ERROR, "Not leader for shard")
                self.network.send_message(
                    NetworkMessage(
                        sender_id=self.id,
                        receiver_id=client_id,
                        payload=response,
                        timestamp=self.machine.get_current_time(self.env.now),
                        request_context=request_context
                    )
                )
                return
            else:
                self.metrics.increment_correct_leader_requests()
            
            # For linearizable reads, ensure all committed WAL entries are applied
            # In a real system, this would involve waiting for WAL application or a read lease.
            # For simulation, we'll just add a small delay.
            yield self.env.timeout(random.uniform(0.002, 0.005)) # Simulate waiting for consistency

        # Simulate read latency
        yield self.env.timeout(random.uniform(0.001, 0.002)) # 1-2ms for read from KV store

        kv_entry = self.kv_store.get(request.key)
        if kv_entry:
            response = GetResponse(request_id=request.request_id, timestamp=self.machine.get_current_time(self.env.now), key=request.key, value=kv_entry.value, metadata=kv_entry.metadata)
        else:
            self.metrics.increment_failure_reason(ErrorCategory.APPLICATION_ERROR, "Key not found")
            response = GetResponse(request_id=request.request_id, timestamp=self.machine.get_current_time(self.env.now), key=request.key, success=False, message="Key not found")
        
        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=client_id,
                payload=response,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=request_context
                )
            )

    def _handle_wal_entry(self, wal_entry: WALEntry, sender_id: str, request_context: Optional[RequestContext]):
        log_prefix = self._context_logger._get_prefix(request_context) if self._context_logger else f"[{self.machine.get_current_time(self.env.now):.4f}] DataNode {self.id}"
        # This DataNode is a replica, received WAL entry from leader
        logger.info(f"{log_prefix}: Received WAL entry {wal_entry.entry_id} for key {wal_entry.key} from {sender_id}.")
        self.wal.append(wal_entry)
        # In a real system, this would also send an ACK back to the leader.
        # For now, we just append and let _apply_wal_entries handle it.
        yield self.env.timeout(0) # Allow other processes to run

    def update_shard_roles(self, is_leader_for: List[str], is_replica_for: List[str]):
        self.is_leader_for_shards = is_leader_for
        self.is_replica_for_shards = is_replica_for
        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] DataNode {self.id}: Updated shard roles. Leader for: {self.is_leader_for_shards}, Replica for: {self.is_replica_for_shards}")

DataNode.model_rebuild()

