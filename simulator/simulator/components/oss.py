import simpy
from typing import Dict, List, Optional, cast
from pydantic import BaseModel

from simulator.models.internal import (
    FileStripe, OSTInfo, ServerInfo, ConfigUpdateMessage,
    NetworkMessage, ServerStatusMessage, OSTStatusMessage, RequestContext
)
from simulator.models.api import (
    WriteRequest, WriteResponse,
    ReadRequest, ReadResponse,
    FileLayout,
    FsyncRequest, FsyncResponse
)
from simulator.infra.network import Network
from simulator.infra.machine import Machine
from simulator.infra.base_service import BaseService
from simulator.infra.logger import ContextLogger
from simulator.components.mgs import MGS

import logging
logger = logging.getLogger(__name__)


class OSS(BaseService):
    """Object Storage Server - Stores file data across OSTs."""

    mgs: MGS
    az: str
    address: str
    num_osts: int = 2  # Number of OSTs on this OSS

    # Storage state
    osts: Dict[int, OSTInfo] = {}  # ost_index -> OSTInfo
    stripes: Dict[str, FileStripe] = {}  # "fid:stripe_index" -> FileStripe

    _context_logger: Optional[ContextLogger] = None

    class Config:
        arbitrary_types_allowed = True

    def __init__(self, env: simpy.Environment, network: Network, mgs: MGS,
                 machine: Machine, az: str, address: str, num_osts: int = 2, **data):
        super().__init__(
            env=env,
            network=network,
            machine=machine,
            mgs=mgs,
            az=az,
            address=address,
            num_osts=num_osts,
            **data
        )

        self._context_logger = ContextLogger(f"OSS {self.id}", self.machine, self.env)

        # Initialize OSTs
        for i in range(num_osts):
            ost_index = self._get_global_ost_index(i)
            ost_id = f"{self.id}_ost{ost_index}"
            ost_info = OSTInfo(
                ost_id=ost_id,
                ost_index=ost_index,
                oss_id=self.id,
                capacity_bytes=1_000_000_000,  # 1GB per OST
                used_bytes=0,
                is_available=True,
                availability_zone=self.az
            )
            self.osts[ost_index] = ost_info

        # Register with MGS
        self.env.process(self._register_with_mgs())

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] OSS {self.id} initialized "
                   f"with {num_osts} OSTs in AZ {self.az}.")

    def _get_global_ost_index(self, local_index: int) -> int:
        """Convert local OST index to global OST index."""
        # Extract numeric portion of OSS ID and use it to compute global index
        # e.g., oss_0 -> indices 0,1,2; oss_1 -> indices 3,4,5
        oss_num = int(self.id.split('_')[-1]) if '_' in self.id else 0
        return oss_num * self.num_osts + local_index

    def _register_with_mgs(self):
        """Register this OSS and its OSTs with the MGS."""
        yield self.env.timeout(0.1)  # Small delay for initialization

        # Register OSS server
        server_info = ServerInfo(
            server_id=self.id,
            server_type="OSS",
            address=self.address,
            availability_zone=self.az,
            is_up=True
        )
        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.mgs.id,
                payload=ServerStatusMessage(server_info=server_info, status='REGISTER'),
                timestamp=self.machine.get_current_time(self.env.now)
            )
        )

        # Register each OST
        for ost_index, ost_info in self.osts.items():
            self.network.send_message(
                NetworkMessage(
                    sender_id=self.id,
                    receiver_id=self.mgs.id,
                    payload=OSTStatusMessage(ost_info=ost_info, status='ACTIVE'),
                    timestamp=self.machine.get_current_time(self.env.now)
                )
            )

    def _handle_message(self, msg: NetworkMessage):
        """Handle received messages."""
        payload = msg.payload

        if isinstance(payload, WriteRequest):
            self._handle_write(msg)
        elif isinstance(payload, ReadRequest):
            self._handle_read(msg)
        elif isinstance(payload, FsyncRequest):
            self._handle_fsync(msg)
        elif isinstance(payload, ConfigUpdateMessage):
            self._handle_config_update(msg)

    def _handle_write(self, msg: NetworkMessage):
        """Handle write request for file data."""
        req = cast(WriteRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] OSS {self.id}"

        # For simplicity, we assume the client has already determined which OST to write to
        # In real Lustre, client gets layout from MDS and calculates stripe placement

        # Extract stripe info from the request (we'll use a simple scheme)
        # Assuming the offset determines which stripe
        # For now, just store the write

        stripe_key = f"{req.fid}:0"  # Simplified - always use stripe 0
        if stripe_key not in self.stripes:
            # Create new stripe
            # We'd need to know which OST index this is - for now, use first OST
            ost_index = list(self.osts.keys())[0] if self.osts else 0
            self.stripes[stripe_key] = FileStripe(
                fid=req.fid,
                stripe_index=0,
                ost_index=ost_index,
                data={},
                size_bytes=0
            )

        stripe = self.stripes[stripe_key]

        # Store data at offset
        stripe.data[req.offset] = req.data
        stripe.size_bytes = max(stripe.size_bytes, req.offset + req.size)

        # Update OST usage
        if stripe.ost_index in self.osts:
            self.osts[stripe.ost_index].used_bytes += req.size

        logger.info(f"{log_prefix}: Wrote {req.size} bytes to FID {req.fid} at offset {req.offset}")

        response = WriteResponse(
            request_id=req.request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            fid=req.fid,
            bytes_written=req.size,
            success=True
        )

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=msg.sender_id,
                payload=response,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=msg.request_context
            )
        )

    def _handle_read(self, msg: NetworkMessage):
        """Handle read request for file data."""
        req = cast(ReadRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] OSS {self.id}"

        # Find the stripe
        stripe_key = f"{req.fid}:0"  # Simplified
        if stripe_key in self.stripes:
            stripe = self.stripes[stripe_key]
            # Get data at offset
            data = stripe.data.get(req.offset, "")
            bytes_read = min(len(data), req.size)

            logger.info(f"{log_prefix}: Read {bytes_read} bytes from FID {req.fid} at offset {req.offset}")
            response = ReadResponse(
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                fid=req.fid,
                data=data[:bytes_read],
                bytes_read=bytes_read,
                success=True
            )
        else:
            logger.info(f"{log_prefix}: Stripe not found for FID {req.fid}")
            response = ReadResponse(
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                fid=req.fid,
                data=None,
                bytes_read=0,
                success=False,
                message="Stripe not found"
            )

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=msg.sender_id,
                payload=response,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=msg.request_context
            )
        )

    def _handle_fsync(self, msg: NetworkMessage):
        """Handle fsync request to sync file to disk."""
        req = cast(FsyncRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] OSS {self.id}"

        # For simulation, just acknowledge the fsync
        # In real Lustre, this would flush buffers to disk
        logger.info(f"{log_prefix}: Fsync for FID {req.fid}")
        response = FsyncResponse(
            client_id=req.client_id,
            request_id=req.request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            fid=req.fid,
            success=True
        )

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=msg.sender_id,
                payload=response,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=msg.request_context
            )
        )

    def _handle_config_update(self, msg: NetworkMessage):
        """Handle configuration update from MGS."""
        config = cast(ConfigUpdateMessage, msg.payload)
        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] OSS {self.id}: "
                   f"Updated configuration to v{config.config_version}")

    def _on_machine_fail(self, machine_id: str):
        """Handle machine failure."""
        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] OSS {self.id}: "
                   f"Underlying machine {machine_id} failed.")
        super()._on_machine_fail(machine_id)

        # Mark OSTs as unavailable
        for ost_index, ost_info in self.osts.items():
            ost_info.is_available = False
            self.network.send_message(
                NetworkMessage(
                    sender_id=self.id,
                    receiver_id=self.mgs.id,
                    payload=OSTStatusMessage(ost_info=ost_info, status='OFFLINE'),
                    timestamp=self.machine.get_current_time(self.env.now)
                )
            )

        # Notify MGS
        server_info = ServerInfo(
            server_id=self.id,
            server_type="OSS",
            address=self.address,
            availability_zone=self.az,
            is_up=False
        )
        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.mgs.id,
                payload=ServerStatusMessage(server_info=server_info, status='UNREGISTER'),
                timestamp=self.machine.get_current_time(self.env.now)
            )
        )

    def _on_machine_recover(self, machine_id: str):
        """Handle machine recovery."""
        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] OSS {self.id}: "
                   f"Underlying machine {machine_id} recovered.")
        super()._on_machine_recover(machine_id)

        # Mark OSTs as available
        for ost_index, ost_info in self.osts.items():
            ost_info.is_available = True

        # Re-register with MGS
        self.env.process(self._register_with_mgs())
