import simpy
import random
from typing import Dict, List, Optional
from pydantic import BaseModel

from simulator.models.internal import NodeInfo, ShardInfo, RoutingTable, NetworkMessage, NodeStatusMessage, ShardRoleUpdateMessage, RequestContext
from simulator.infra.network import Network

import logging
logger = logging.getLogger(__name__)


class Controller(BaseModel):
    id: str = "controller"
    env: simpy.Environment
    network: Network
    data_nodes: Dict[str, NodeInfo] = {}
    shards: Dict[str, ShardInfo] = {}
    routing_table: RoutingTable = RoutingTable(version=0, shard_to_leader={}, shard_to_replicas={}, node_to_shards={})
    replication_factor: int = 3
    num_shards: int = 10

    class Config:
        arbitrary_types_allowed = True

    def __init__(self, env: simpy.Environment, network: Network, **data):
        super().__init__(env=env, network=network, **data)
        self.network.register_node(self.id)
        self.env.process(self._run())
        self.env.process(self._listen_for_messages())
        logger.info(f"[{self.env.now:.4f}] Controller initialized.")

    def _run(self):
        while True:
            yield self.env.timeout(1)  # Periodically update routing table
            self._update_routing_table()

    def _get_log_prefix(self, request_context: Optional[RequestContext]) -> str:
        if request_context and request_context.request_id:
            return f"[{self.env.now:.4f}] [ReqID: {request_context.request_id}] Controller"
        return f"[{self.env.now:.4f}] Controller"

    def _listen_for_messages(self):
        while True:
            msg: NetworkMessage = yield self.network.get_inbox(self.id).get()
            log_prefix = self._get_log_prefix(msg.request_context)
            logger.info(f"{log_prefix} received message from {msg.sender_id}: {msg.payload.__class__.__name__}")
            if isinstance(msg.payload, NodeStatusMessage):
                if msg.payload.status == 'REGISTER':
                    self._register_data_node(msg.payload.node_info, msg.request_context)
                elif msg.payload.status == 'UNREGISTER':
                    self._unregister_data_node(msg.payload.node_info.node_id, msg.request_context)
                elif msg.payload.status == 'HEARTBEAT':
                    # For now, just acknowledge heartbeat. Later, can use for failure detection.
                    pass

    def _register_data_node(self, node_info: NodeInfo, request_context: Optional[RequestContext]):
        self.data_nodes[node_info.node_id] = node_info
        log_prefix = self._get_log_prefix(request_context)
        logger.info(f"{log_prefix}: Registered Data Node {node_info.node_id}.")
        self._rebalance_shards()
        self._update_routing_table()

    def _unregister_data_node(self, node_id: str, request_context: Optional[RequestContext]):
        if node_id in self.data_nodes:
            del self.data_nodes[node_id]
            log_prefix = self._get_log_prefix(request_context)
            logger.info(f"{log_prefix}: Unregistered Data Node {node_id}.")
            self._rebalance_shards()
            self._update_routing_table()

    def _rebalance_shards(self):
        active_nodes = [node.node_id for node in self.data_nodes.values() if node.is_up]
        if not active_nodes:
            self.shards = {}
            return

        if not self.shards:
            for i in range(self.num_shards):
                shard_id = f"shard_{i}"
                self.shards[shard_id] = ShardInfo(shard_id=shard_id, leader_node_id="", replica_node_ids=[])

        for i, shard_id in enumerate(self.shards.keys()):
            leader_index = i % len(active_nodes)
            leader_id = active_nodes[leader_index]
            
            replicas = []
            for j in range(1, self.replication_factor):
                replica_index = (i + j) % len(active_nodes)
                replicas.append(active_nodes[replica_index])
            
            self.shards[shard_id].leader_node_id = leader_id
            self.shards[shard_id].replica_node_ids = replicas

        logger.info(f"[{self.env.now:.4f}] Controller: Shards rebalanced. Current shard distribution: {self.shards}")

    def _update_routing_table(self):
        new_shard_to_leader = {s_id: s_info.leader_node_id for s_id, s_info in self.shards.items()}
        new_shard_to_replicas = {s_id: s_info.replica_node_ids for s_id, s_info in self.shards.items()}
        
        new_node_to_shards: Dict[str, List[str]] = {node_id: [] for node_id in self.data_nodes.keys()}
        for shard_id, shard_info in self.shards.items():
            if shard_info.leader_node_id:
                new_node_to_shards[shard_info.leader_node_id].append(shard_id)
            for replica_id in shard_info.replica_node_ids:
                new_node_to_shards[replica_id].append(shard_id)

        self.routing_table = RoutingTable(
            version=self.routing_table.version + 1,
            shard_to_leader=new_shard_to_leader,
            shard_to_replicas=new_shard_to_replicas,
            node_to_shards=new_node_to_shards
        )
        logger.info(f"[{self.env.now:.4f}] Controller: Routing table updated to version {self.routing_table.version}.")
        self._distribute_routing_table()

    def _distribute_routing_table(self):
        logger.info(f"[{self.env.now:.4f}] Controller: Distributing routing table v{self.routing_table.version}.")
        # Send ShardRoleUpdateMessage to each DataNode
        for node_id, node_info in self.data_nodes.items():
            is_leader_for = [shard_id for shard_id, s_info in self.shards.items() if s_info.leader_node_id == node_id]
            is_replica_for = [shard_id for shard_id, s_info in self.shards.items() if node_id in s_info.replica_node_ids and s_info.leader_node_id != node_id]
            
            update_msg = ShardRoleUpdateMessage(
                node_id=node_id,
                is_leader_for_shards=is_leader_for,
                is_replica_for_shards=is_replica_for
            )
            self.network.send_message(
                NetworkMessage(
                    sender_id=self.id,
                    receiver_id=node_id,
                    payload=update_msg,
                    timestamp=self.env.now
                )
            )

    def get_routing_table(self) -> RoutingTable:
        return self.routing_table

    def get_shard_for_key(self, key: str) -> str:
        return f"shard_{hash(key) % self.num_shards}"
