import simpy
import random
from typing import Dict, List, Optional
from pydantic import BaseModel

from simulator.models.internal import NetworkMessage, RequestContext
from simulator.models.api import SnapshotRequest, SnapshotResponse
from simulator.infra.network import Network
from simulator.components.controller import Controller

import logging
logger = logging.getLogger(__name__)


class SnapshotService(BaseModel):
    id: str = "snapshot_service"
    env: simpy.Environment
    network: Network
    controller: Controller

    class Config:
        arbitrary_types_allowed = True

    def __init__(self, env: simpy.Environment, network: Network, controller: Controller, **data):
        super().__init__(env=env, network=network, controller=controller, **data)
        self.network.register_node(self.id)
        self.env.process(self._listen_for_messages())
        logger.info(f"[{self.env.now:.4f}] SnapshotService initialized.")

    def _get_log_prefix(self, request_context: Optional[RequestContext]) -> str:
        if request_context and request_context.request_id:
            return f"[{self.env.now:.4f}] [ReqID: {request_context.request_id}] SnapshotService {self.id}"
        return f"[{self.env.now:.4f}] SnapshotService {self.id}"

    def _listen_for_messages(self):
        while True:
            msg: NetworkMessage = yield self.network.get_inbox(self.id).get()
            log_prefix = self._get_log_prefix(msg.request_context)
            logger.info(f"{log_prefix} received message from {msg.sender_id}: {msg.payload.__class__.__name__}")
            if isinstance(msg.payload, SnapshotRequest):
                self.env.process(self._handle_snapshot_request(msg.payload, msg.sender_id))

    def _handle_snapshot_request(self, request: SnapshotRequest, client_id: str):
        logger.info(f"[{self.env.now:.4f}] SnapshotService: Initiating snapshot {request.snapshot_id}.")

        # Simulate marker propagation to all shard leaders
        routing_table = self.controller.get_routing_table()
        leader_nodes = set(routing_table.shard_to_leader.values())

        # Simulate sending markers and waiting for local snapshot completion
        snapshot_delays = []
        for leader_id in leader_nodes:
            # Simulate delay for marker propagation and local snapshotting
            delay = random.uniform(0.1, 0.5) # 100-500ms for local snapshot
            snapshot_delays.append(delay)
            logger.info(f"[{self.env.now:.4f}] SnapshotService: Sending marker to {leader_id}. Local snapshot estimated {delay:.4f}s.")

        if snapshot_delays:
            yield self.env.timeout(max(snapshot_delays)) # Wait for the longest local snapshot
        else:
            yield self.env.timeout(0.1) # Minimum delay if no leaders

        # Simulate upload to S3
        s3_upload_delay = random.uniform(0.5, 2.0) # 0.5-2 seconds for S3 upload
        logger.info(f"[{self.env.now:.4f}] SnapshotService: All local snapshots complete. Uploading to S3 (estimated {s3_upload_delay:.4f}s).")
        yield self.env.timeout(s3_upload_delay)

        logger.info(f"[{self.env.now:.4f}] SnapshotService: Snapshot {request.snapshot_id} completed.")
        response = SnapshotResponse(request_id=request.request_id, timestamp=self.env.now, snapshot_id=request.snapshot_id, status='COMPLETED')
        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=client_id,
                payload=response,
                timestamp=self.env.now
            )
        )
