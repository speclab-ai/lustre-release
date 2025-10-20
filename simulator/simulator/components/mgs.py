import simpy
import random
from typing import Dict, List, Optional
from pydantic import BaseModel

from simulator.models.internal import (
    ServerInfo, OSTInfo, MDTInfo, NetworkMessage,
    ServerStatusMessage, OSTStatusMessage, MDTStatusMessage,
    ConfigUpdateMessage, RequestContext
)
from simulator.infra.network import Network

import logging
logger = logging.getLogger(__name__)


class MGS(BaseModel):
    """Management Server - Stores and distributes Lustre configuration."""

    id: str = "mgs"
    env: simpy.Environment
    network: Network

    # Configuration state
    servers: Dict[str, ServerInfo] = {}  # server_id -> ServerInfo
    osts: Dict[str, OSTInfo] = {}  # ost_id -> OSTInfo
    mdts: Dict[str, MDTInfo] = {}  # mdt_id -> MDTInfo
    config_version: int = 0

    class Config:
        arbitrary_types_allowed = True

    def __init__(self, env: simpy.Environment, network: Network, **data):
        super().__init__(env=env, network=network, **data)
        self.network.register_node(self.id)
        self.env.process(self._listen_for_messages())
        logger.info(f"[{self.env.now:.4f}] MGS initialized.")

    def _get_log_prefix(self, request_context: Optional[RequestContext]) -> str:
        if request_context and request_context.request_id:
            return f"[{self.env.now:.4f}] [ReqID: {request_context.request_id}] MGS"
        return f"[{self.env.now:.4f}] MGS"

    def _listen_for_messages(self):
        """Listen for server/target registration messages."""
        while True:
            msg: NetworkMessage = yield self.network.get_inbox(self.id).get()
            log_prefix = self._get_log_prefix(msg.request_context)
            logger.info(f"{log_prefix} received message from {msg.sender_id}: {msg.payload.__class__.__name__}")

            if isinstance(msg.payload, ServerStatusMessage):
                self._handle_server_status(msg.payload, msg.request_context)
            elif isinstance(msg.payload, OSTStatusMessage):
                self._handle_ost_status(msg.payload, msg.request_context)
            elif isinstance(msg.payload, MDTStatusMessage):
                self._handle_mdt_status(msg.payload, msg.request_context)

    def _handle_server_status(self, msg: ServerStatusMessage, request_context: Optional[RequestContext]):
        """Handle server registration/unregistration."""
        log_prefix = self._get_log_prefix(request_context)
        server_info = msg.server_info

        if msg.status == 'REGISTER':
            self.servers[server_info.server_id] = server_info
            logger.info(f"{log_prefix}: Registered {server_info.server_type} server {server_info.server_id}")
            self._increment_config_version()
            self._distribute_config()

        elif msg.status == 'UNREGISTER':
            if server_info.server_id in self.servers:
                del self.servers[server_info.server_id]
                logger.info(f"{log_prefix}: Unregistered server {server_info.server_id}")
                self._increment_config_version()
                self._distribute_config()

        elif msg.status == 'HEARTBEAT':
            # Update server status
            if server_info.server_id in self.servers:
                self.servers[server_info.server_id].is_up = server_info.is_up

    def _handle_ost_status(self, msg: OSTStatusMessage, request_context: Optional[RequestContext]):
        """Handle OST status updates."""
        log_prefix = self._get_log_prefix(request_context)
        ost_info = msg.ost_info

        if msg.status == 'ACTIVE':
            self.osts[ost_info.ost_id] = ost_info
            logger.info(f"{log_prefix}: OST {ost_info.ost_id} (index {ost_info.ost_index}) registered")
            self._increment_config_version()
            self._distribute_config()

        elif msg.status == 'OFFLINE':
            if ost_info.ost_id in self.osts:
                self.osts[ost_info.ost_id].is_available = False
                logger.info(f"{log_prefix}: OST {ost_info.ost_id} went offline")
                self._increment_config_version()
                self._distribute_config()

    def _handle_mdt_status(self, msg: MDTStatusMessage, request_context: Optional[RequestContext]):
        """Handle MDT status updates."""
        log_prefix = self._get_log_prefix(request_context)
        mdt_info = msg.mdt_info

        if msg.status == 'ACTIVE':
            self.mdts[mdt_info.mdt_id] = mdt_info
            logger.info(f"{log_prefix}: MDT {mdt_info.mdt_id} (index {mdt_info.mdt_index}) registered")
            self._increment_config_version()
            self._distribute_config()

        elif msg.status == 'OFFLINE':
            if mdt_info.mdt_id in self.mdts:
                self.mdts[mdt_info.mdt_id].is_available = False
                logger.info(f"{log_prefix}: MDT {mdt_info.mdt_id} went offline")
                self._increment_config_version()
                self._distribute_config()

    def _increment_config_version(self):
        """Increment configuration version number."""
        self.config_version += 1
        logger.info(f"[{self.env.now:.4f}] MGS: Configuration version updated to {self.config_version}")

    def _distribute_config(self):
        """Distribute configuration updates to all registered servers."""
        logger.info(f"[{self.env.now:.4f}] MGS: Distributing configuration v{self.config_version}")

        config_msg = ConfigUpdateMessage(
            config_version=self.config_version,
            ost_list=list(self.osts.values()),
            mdt_list=list(self.mdts.values()),
            server_list=list(self.servers.values())
        )

        # Send to all registered servers
        for server_id in self.servers.keys():
            self.network.send_message(
                NetworkMessage(
                    sender_id=self.id,
                    receiver_id=server_id,
                    payload=config_msg,
                    timestamp=self.env.now
                )
            )

    def get_available_osts(self) -> List[OSTInfo]:
        """Get list of available OSTs for stripe allocation."""
        return [ost for ost in self.osts.values() if ost.is_available]

    def get_available_mdts(self) -> List[MDTInfo]:
        """Get list of available MDTs."""
        return [mdt for mdt in self.mdts.values() if mdt.is_available]

    def allocate_osts_for_file(self, stripe_count: int) -> List[int]:
        """Allocate OSTs for a new file based on stripe count."""
        available_osts = self.get_available_osts()

        if not available_osts:
            logger.warning(f"[{self.env.now:.4f}] MGS: No available OSTs for allocation")
            return []

        # Simple round-robin allocation
        # In real Lustre, this would consider space, load, etc.
        actual_stripe_count = min(stripe_count, len(available_osts))

        # Sort by used space to balance load
        sorted_osts = sorted(available_osts, key=lambda x: x.used_bytes)
        selected_osts = sorted_osts[:actual_stripe_count]

        ost_indices = [ost.ost_index for ost in selected_osts]
        logger.info(f"[{self.env.now:.4f}] MGS: Allocated OST indices {ost_indices} for stripe_count={stripe_count}")

        return ost_indices
