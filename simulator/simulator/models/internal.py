from typing import List, Dict, Optional
from pydantic import BaseModel

# Moved to infra layer - re-export for backwards compatibility
from simulator.infra.request_context import RequestContext
from simulator.infra.network import Message, NetworkMessage


class ShardInfo(BaseModel):
    shard_id: str
    leader_node_id: str
    replica_node_ids: List[str]


class NodeInfo(BaseModel):
    node_id: str
    address: str  # e.g., IP address or hostname
    availability_zone: str
    is_up: bool = True


class RoutingTable(BaseModel):
    version: int
    shard_to_leader: Dict[str, str]  # Shard ID to Leader Node ID
    shard_to_replicas: Dict[str, List[str]]  # Shard ID to all Replica Node IDs
    node_to_shards: Dict[str, List[str]]  # Node ID to Shard IDs it hosts


class WALEntry(BaseModel):
    entry_id: str
    key: str
    value: Optional[str] = None  # For Put/Delete
    metadata: Optional[List[str]] = None  # For Put/AppendMetadata
    operation_type: str  # e.g., 'PUT', 'DELETE', 'APPEND_METADATA'
    timestamp: float
    ttl: Optional[float] = None # Added ttl to WALEntry


class KVEntry(BaseModel):
    value: str
    metadata: List[str]
    ttl: Optional[float] = None  # Unix timestamp for expiration
    last_modified: float


class NodeStatusMessage(BaseModel):
    node_info: NodeInfo
    status: str  # 'REGISTER', 'UNREGISTER', 'HEARTBEAT'


class ShardRoleUpdateMessage(BaseModel):
    node_id: str
    is_leader_for_shards: List[str]
    is_replica_for_shards: List[str]