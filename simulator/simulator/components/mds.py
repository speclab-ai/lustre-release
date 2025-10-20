import simpy
import uuid
from typing import Dict, List, Optional, cast
from pydantic import BaseModel

from simulator.models.internal import (
    FileMetadata, LockInfo, ServerInfo, MDTInfo, ConfigUpdateMessage,
    NetworkMessage, ServerStatusMessage, MDTStatusMessage, RequestContext
)
from simulator.models.api import (
    CreateFileRequest, CreateFileResponse,
    StatRequest, StatResponse,
    DeleteFileRequest, DeleteFileResponse,
    MkdirRequest, MkdirResponse,
    ListDirRequest, ListDirResponse,
    LockRequest, LockResponse,
    UnlockRequest, UnlockResponse,
    GetLayoutRequest, GetLayoutResponse, FileLayout,
    # High priority APIs
    OpenRequest, OpenResponse,
    CloseRequest, CloseResponse,
    SeekRequest, SeekResponse,
    RmdirRequest, RmdirResponse,
    RenameRequest, RenameResponse,
    SetattrRequest, SetattrResponse,
    GetattrRequest, GetattrResponse,
    LinkRequest, LinkResponse,
    SymlinkRequest, SymlinkResponse,
    ReadlinkRequest, ReadlinkResponse,
)
from simulator.infra.network import Network
from simulator.infra.machine import Machine
from simulator.infra.base_service import BaseService
from simulator.infra.logger import ContextLogger
from simulator.components.mgs import MGS

import logging
logger = logging.getLogger(__name__)


class MDS(BaseService):
    """Metadata Server - Manages file system namespace and metadata."""

    mgs: MGS
    mdt_index: int
    az: str
    address: str

    # Metadata state
    files: Dict[str, FileMetadata] = {}  # fid -> FileMetadata
    path_to_fid: Dict[str, str] = {}  # path -> fid
    locks: Dict[str, LockInfo] = {}  # lock_id -> LockInfo
    file_locks: Dict[str, List[str]] = {}  # fid -> [lock_ids]

    # Configuration
    ost_list: List = []  # Will be updated by MGS
    _context_logger: Optional[ContextLogger] = None

    class Config:
        arbitrary_types_allowed = True

    def __init__(self, env: simpy.Environment, network: Network, mgs: MGS,
                 machine: Machine, az: str, address: str, mdt_index: int = 0, **data):
        super().__init__(
            env=env,
            network=network,
            machine=machine,
            mgs=mgs,
            mdt_index=mdt_index,
            az=az,
            address=address,
            **data
        )

        self._context_logger = ContextLogger(f"MDS {self.id}", self.machine, self.env)

        # Create root directory
        root_fid = "0x200000001:0x1:0x0"  # Lustre-style FID
        self.files[root_fid] = FileMetadata(
            fid=root_fid,
            path="/",
            is_directory=True,
            mtime=self.env.now
        )
        self.path_to_fid["/"] = root_fid

        # Register with MGS
        self.env.process(self._register_with_mgs())

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id} initialized in AZ {self.az}.")

    def _register_with_mgs(self):
        """Register this MDS and its MDT with the MGS."""
        yield self.env.timeout(0.1)  # Small delay for initialization

        # Register MDS server
        server_info = ServerInfo(
            server_id=self.id,
            server_type="MDS",
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

        # Register MDT
        mdt_info = MDTInfo(
            mdt_id=f"{self.id}_mdt{self.mdt_index}",
            mdt_index=self.mdt_index,
            mds_id=self.id,
            is_available=True,
            availability_zone=self.az
        )
        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.mgs.id,
                payload=MDTStatusMessage(mdt_info=mdt_info, status='ACTIVE'),
                timestamp=self.machine.get_current_time(self.env.now)
            )
        )

    def _handle_message(self, msg: NetworkMessage):
        """Handle received messages."""
        payload = msg.payload

        if isinstance(payload, CreateFileRequest):
            self._handle_create_file(msg)
        elif isinstance(payload, StatRequest):
            self._handle_stat(msg)
        elif isinstance(payload, DeleteFileRequest):
            self._handle_delete_file(msg)
        elif isinstance(payload, MkdirRequest):
            self._handle_mkdir(msg)
        elif isinstance(payload, ListDirRequest):
            self._handle_list_dir(msg)
        elif isinstance(payload, LockRequest):
            self._handle_lock_request(msg)
        elif isinstance(payload, UnlockRequest):
            self._handle_unlock_request(msg)
        elif isinstance(payload, GetLayoutRequest):
            self._handle_get_layout(msg)
        elif isinstance(payload, ConfigUpdateMessage):
            self._handle_config_update(msg)
        # High priority APIs
        elif isinstance(payload, OpenRequest):
            self._handle_open(msg)
        elif isinstance(payload, CloseRequest):
            self._handle_close(msg)
        elif isinstance(payload, SeekRequest):
            self._handle_seek(msg)
        elif isinstance(payload, RmdirRequest):
            self._handle_rmdir(msg)
        elif isinstance(payload, RenameRequest):
            self._handle_rename(msg)
        elif isinstance(payload, SetattrRequest):
            self._handle_setattr(msg)
        elif isinstance(payload, GetattrRequest):
            self._handle_getattr(msg)
        elif isinstance(payload, LinkRequest):
            self._handle_link(msg)
        elif isinstance(payload, SymlinkRequest):
            self._handle_symlink(msg)
        elif isinstance(payload, ReadlinkRequest):
            self._handle_readlink(msg)

    def _handle_create_file(self, msg: NetworkMessage):
        """Handle file creation request."""
        req = cast(CreateFileRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Check if file already exists
        if req.path in self.path_to_fid:
            logger.info(f"{log_prefix}: File {req.path} already exists")
            response = CreateFileResponse(
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                success=False,
                message="File already exists"
            )
        else:
            # Generate FID
            fid = self._generate_fid()

            # Allocate OSTs for striping
            ost_indices = self.mgs.allocate_osts_for_file(req.stripe_count)

            if not ost_indices:
                logger.warning(f"{log_prefix}: No OSTs available for file creation")
                response = CreateFileResponse(
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    success=False,
                    message="No OSTs available"
                )
            else:
                # Create file metadata
                file_meta = FileMetadata(
                    fid=fid,
                    path=req.path,
                    is_directory=False,
                    stripe_count=len(ost_indices),
                    stripe_size=req.stripe_size,
                    ost_indices=ost_indices,
                    size_bytes=0,
                    mtime=self.env.now
                )

                self.files[fid] = file_meta
                self.path_to_fid[req.path] = fid

                logger.info(f"{log_prefix}: Created file {req.path} with FID {fid}, stripes on OSTs {ost_indices}")
                response = CreateFileResponse(
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    fid=fid,
                    success=True
                )

        # Send response
        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=msg.sender_id,
                payload=response,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=msg.request_context
            )
        )

    def _handle_stat(self, msg: NetworkMessage):
        """Handle stat request for file metadata."""
        req = cast(StatRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        if req.path in self.path_to_fid:
            fid = self.path_to_fid[req.path]
            # Check if file still exists (might have been deleted)
            if fid not in self.files:
                response = StatResponse(
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    success=False,
                    message="File was deleted"
                )
                logger.info(f"{log_prefix}: Stat request for {req.path} -> File was deleted")
            else:
                file_meta = self.files[fid]
                response = StatResponse(
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    fid=fid,
                    size=file_meta.size_bytes,
                    stripe_count=file_meta.stripe_count,
                    stripe_size=file_meta.stripe_size,
                    mtime=file_meta.mtime,
                    success=True
                )
                logger.info(f"{log_prefix}: Stat request for {req.path} -> FID {fid}")
        else:
            response = StatResponse(
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                success=False,
                message="File not found"
            )
            logger.info(f"{log_prefix}: Stat request for {req.path} -> Not found")

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=msg.sender_id,
                payload=response,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=msg.request_context
            )
        )

    def _handle_delete_file(self, msg: NetworkMessage):
        """Handle file deletion request."""
        req = cast(DeleteFileRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        if req.path in self.path_to_fid:
            fid = self.path_to_fid[req.path]
            # Check if file still exists (might have been deleted already)
            if fid in self.files:
                del self.files[fid]
                del self.path_to_fid[req.path]
                logger.info(f"{log_prefix}: Deleted file {req.path}")
                response = DeleteFileResponse(
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    success=True
                )
            else:
                # File was already deleted
                del self.path_to_fid[req.path]  # Clean up stale mapping
                logger.info(f"{log_prefix}: File {req.path} was already deleted")
                response = DeleteFileResponse(
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    success=False,
                    message="File already deleted"
                )
        else:
            response = DeleteFileResponse(
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                success=False,
                message="File not found"
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

    def _handle_mkdir(self, msg: NetworkMessage):
        """Handle directory creation request."""
        req = cast(MkdirRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        if req.path in self.path_to_fid:
            response = MkdirResponse(
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                success=False,
                message="Directory already exists"
            )
        else:
            fid = self._generate_fid()
            dir_meta = FileMetadata(
                fid=fid,
                path=req.path,
                is_directory=True,
                mtime=self.env.now
            )

            self.files[fid] = dir_meta
            self.path_to_fid[req.path] = fid

            logger.info(f"{log_prefix}: Created directory {req.path}")
            response = MkdirResponse(
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
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

    def _handle_list_dir(self, msg: NetworkMessage):
        """Handle directory listing request."""
        req = cast(ListDirRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Find all files in this directory
        entries = []
        for path in self.path_to_fid.keys():
            if path.startswith(req.path + "/") and "/" not in path[len(req.path)+1:]:
                entries.append(path.split("/")[-1])

        logger.info(f"{log_prefix}: List directory {req.path} -> {len(entries)} entries")
        response = ListDirResponse(
            request_id=req.request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            path=req.path,
            entries=entries,
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

    def _handle_lock_request(self, msg: NetworkMessage):
        """Handle distributed lock request (LDLM)."""
        req = cast(LockRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Simple lock granting - always grant for now
        # Real LDLM would check conflicts
        lock_id = str(uuid.uuid4())
        lock_info = LockInfo(
            lock_id=lock_id,
            fid=req.fid,
            lock_type=req.lock_type,
            extent_start=req.extent_start,
            extent_end=req.extent_end,
            client_id=req.client_id,
            granted_time=self.env.now
        )

        self.locks[lock_id] = lock_info
        if req.fid not in self.file_locks:
            self.file_locks[req.fid] = []
        self.file_locks[req.fid].append(lock_id)

        logger.info(f"{log_prefix}: Granted {req.lock_type} lock {lock_id} for FID {req.fid}")
        response = LockResponse(
            request_id=req.request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            fid=req.fid,
            lock_id=lock_id,
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

    def _handle_unlock_request(self, msg: NetworkMessage):
        """Handle lock release request."""
        req = cast(UnlockRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        if req.lock_id in self.locks:
            lock_info = self.locks[req.lock_id]
            fid = lock_info.fid

            # Remove lock
            del self.locks[req.lock_id]
            if fid in self.file_locks:
                self.file_locks[fid].remove(req.lock_id)

            logger.info(f"{log_prefix}: Released lock {req.lock_id}")
            response = UnlockResponse(
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                lock_id=req.lock_id,
                success=True
            )
        else:
            response = UnlockResponse(
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                lock_id=req.lock_id,
                success=False,
                message="Lock not found"
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

    def _handle_get_layout(self, msg: NetworkMessage):
        """Handle request for file layout information."""
        req = cast(GetLayoutRequest, msg.payload)

        if req.fid in self.files:
            file_meta = self.files[req.fid]
            layout = FileLayout(
                fid=req.fid,
                stripe_count=file_meta.stripe_count,
                stripe_size=file_meta.stripe_size,
                ost_indices=file_meta.ost_indices
            )
            response = GetLayoutResponse(
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                fid=req.fid,
                layout=layout,
                success=True
            )
        else:
            response = GetLayoutResponse(
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                fid=req.fid,
                success=False,
                message="File not found"
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
        self.ost_list = config.ost_list
        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}: "
                   f"Updated configuration to v{config.config_version}, {len(self.ost_list)} OSTs")

    # HIGH PRIORITY API Handlers

    def _handle_open(self, msg: NetworkMessage):
        """Handle file open request."""
        req = cast(OpenRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Check if file exists
        if req.path in self.path_to_fid:
            fid = self.path_to_fid[req.path]
            # For simulation, we don't track actual file descriptors, just acknowledge
            logger.info(f"{log_prefix}: Opened file {req.path} (FID: {fid})")
            response = OpenResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                fid=fid,
                fd=hash(req.path) % 10000,  # Simulated FD
                success=True
            )
        else:
            logger.info(f"{log_prefix}: File {req.path} not found for open")
            response = OpenResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                success=False,
                message="File not found"
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

    def _handle_close(self, msg: NetworkMessage):
        """Handle file close request."""
        req = cast(CloseRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # For simulation, just acknowledge the close
        logger.info(f"{log_prefix}: Closed file {req.path}")
        response = CloseResponse(
            client_id=req.client_id,
            request_id=req.request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            path=req.path,
            fd=req.fd,
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

    def _handle_seek(self, msg: NetworkMessage):
        """Handle file seek request."""
        req = cast(SeekRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # For simulation, just acknowledge the seek
        # In real Lustre, this would be handled client-side
        logger.info(f"{log_prefix}: Seek on FID {req.fid} to offset {req.offset}")
        response = SeekResponse(
            client_id=req.client_id,
            request_id=req.request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            fid=req.fid,
            new_offset=req.offset,
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

    def _handle_rmdir(self, msg: NetworkMessage):
        """Handle directory removal request."""
        req = cast(RmdirRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Check if directory exists
        if req.path in self.path_to_fid:
            fid = self.path_to_fid[req.path]
            file_meta = self.files.get(fid)

            if file_meta and file_meta.is_directory:
                # Remove directory
                del self.files[fid]
                del self.path_to_fid[req.path]
                logger.info(f"{log_prefix}: Removed directory {req.path}")
                response = RmdirResponse(
                    client_id=req.client_id,
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    success=True
                )
            else:
                logger.info(f"{log_prefix}: Path {req.path} is not a directory")
                response = RmdirResponse(
                    client_id=req.client_id,
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    success=False,
                    message="Not a directory"
                )
        else:
            logger.info(f"{log_prefix}: Directory {req.path} not found")
            response = RmdirResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                success=False,
                message="Directory not found"
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

    def _handle_rename(self, msg: NetworkMessage):
        """Handle file/directory rename request."""
        req = cast(RenameRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Check if old path exists
        if req.old_path in self.path_to_fid:
            fid = self.path_to_fid[req.old_path]

            # Check if FID exists in files (defensive check for race conditions)
            if fid not in self.files:
                del self.path_to_fid[req.old_path]  # Clean up stale mapping
                logger.info(f"{log_prefix}: Path {req.old_path} has stale FID mapping")
                response = RenameResponse(
                    client_id=req.client_id,
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    old_path=req.old_path,
                    new_path=req.new_path,
                    success=False,
                    message="File not found"
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
                return

            file_meta = self.files[fid]

            # Update path mappings
            del self.path_to_fid[req.old_path]
            self.path_to_fid[req.new_path] = fid
            file_meta.path = req.new_path

            logger.info(f"{log_prefix}: Renamed {req.old_path} to {req.new_path}")
            response = RenameResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                old_path=req.old_path,
                new_path=req.new_path,
                success=True
            )
        else:
            logger.info(f"{log_prefix}: Path {req.old_path} not found for rename")
            response = RenameResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                old_path=req.old_path,
                new_path=req.new_path,
                success=False,
                message="File not found"
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

    def _handle_setattr(self, msg: NetworkMessage):
        """Handle setattr request."""
        req = cast(SetattrRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Check if file exists
        if req.path in self.path_to_fid:
            fid = self.path_to_fid[req.path]

            # Check if FID exists in files (defensive check for race conditions)
            if fid not in self.files:
                del self.path_to_fid[req.path]  # Clean up stale mapping
                logger.info(f"{log_prefix}: File {req.path} has stale FID mapping")
                response = SetattrResponse(
                    client_id=req.client_id,
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    success=False,
                    message="File not found"
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
                return

            file_meta = self.files[fid]

            # Update attributes
            if req.mode is not None:
                file_meta.mode = req.mode
            if req.uid is not None:
                file_meta.uid = req.uid
            if req.gid is not None:
                file_meta.gid = req.gid
            if req.size is not None:
                file_meta.size_bytes = req.size
            if req.atime is not None:
                file_meta.atime = req.atime
            if req.mtime is not None:
                file_meta.mtime = req.mtime

            # Update ctime
            file_meta.ctime = self.machine.get_current_time(self.env.now)

            logger.info(f"{log_prefix}: Set attributes for {req.path}")
            response = SetattrResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                success=True
            )
        else:
            logger.info(f"{log_prefix}: File {req.path} not found for setattr")
            response = SetattrResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                success=False,
                message="File not found"
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

    def _handle_getattr(self, msg: NetworkMessage):
        """Handle getattr request."""
        req = cast(GetattrRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Check if file exists
        if req.path in self.path_to_fid:
            fid = self.path_to_fid[req.path]

            # Check if FID exists in files (defensive check for race conditions)
            if fid not in self.files:
                del self.path_to_fid[req.path]  # Clean up stale mapping
                logger.info(f"{log_prefix}: File {req.path} has stale FID mapping")
                response = GetattrResponse(
                    client_id=req.client_id,
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    success=False,
                    message="File not found"
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
                return

            file_meta = self.files[fid]

            logger.info(f"{log_prefix}: Get attributes for {req.path}")
            response = GetattrResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                fid=fid,
                mode=file_meta.mode,
                uid=file_meta.uid,
                gid=file_meta.gid,
                size=file_meta.size_bytes,
                atime=file_meta.atime,
                mtime=file_meta.mtime,
                ctime=file_meta.ctime,
                success=True
            )
        else:
            logger.info(f"{log_prefix}: File {req.path} not found for getattr")
            response = GetattrResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                success=False,
                message="File not found"
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

    def _handle_link(self, msg: NetworkMessage):
        """Handle hard link creation request."""
        req = cast(LinkRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Check if existing file exists
        if req.existing_path in self.path_to_fid:
            fid = self.path_to_fid[req.existing_path]

            # Check if FID exists in files (defensive check for race conditions)
            if fid not in self.files:
                del self.path_to_fid[req.existing_path]  # Clean up stale mapping
                logger.info(f"{log_prefix}: File {req.existing_path} has stale FID mapping")
                response = LinkResponse(
                    client_id=req.client_id,
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    existing_path=req.existing_path,
                    link_path=req.link_path,
                    success=False,
                    message="File not found"
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
                return

            file_meta = self.files[fid]

            # Create hard link by adding new path pointing to same FID
            self.path_to_fid[req.link_path] = fid
            file_meta.nlink += 1

            logger.info(f"{log_prefix}: Created hard link from {req.existing_path} to {req.link_path}")
            response = LinkResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                existing_path=req.existing_path,
                link_path=req.link_path,
                success=True
            )
        else:
            logger.info(f"{log_prefix}: File {req.existing_path} not found for link")
            response = LinkResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                existing_path=req.existing_path,
                link_path=req.link_path,
                success=False,
                message="File not found"
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

    def _handle_symlink(self, msg: NetworkMessage):
        """Handle symbolic link creation request."""
        req = cast(SymlinkRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Create symlink metadata
        fid = self._generate_fid()
        current_time = self.machine.get_current_time(self.env.now)

        file_meta = FileMetadata(
            fid=fid,
            path=req.link_path,
            is_directory=False,
            is_symlink=True,
            symlink_target=req.target_path,
            size_bytes=0,
            mode=0o777,  # Symlinks typically have 777 permissions
            mtime=current_time,
            atime=current_time,
            ctime=current_time
        )

        self.files[fid] = file_meta
        self.path_to_fid[req.link_path] = fid

        logger.info(f"{log_prefix}: Created symlink from {req.link_path} to {req.target_path}")
        response = SymlinkResponse(
            client_id=req.client_id,
            request_id=req.request_id,
            timestamp=current_time,
            target_path=req.target_path,
            link_path=req.link_path,
            success=True
        )

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=msg.sender_id,
                payload=response,
                timestamp=current_time,
                request_context=msg.request_context
            )
        )

    def _handle_readlink(self, msg: NetworkMessage):
        """Handle readlink request."""
        req = cast(ReadlinkRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Check if symlink exists
        if req.link_path in self.path_to_fid:
            fid = self.path_to_fid[req.link_path]

            # Check if FID exists in files (defensive check for race conditions)
            if fid not in self.files:
                del self.path_to_fid[req.link_path]  # Clean up stale mapping
                logger.info(f"{log_prefix}: Symlink {req.link_path} has stale FID mapping")
                response = ReadlinkResponse(
                    client_id=req.client_id,
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    link_path=req.link_path,
                    success=False,
                    message="Symlink not found"
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
                return

            file_meta = self.files[fid]

            if file_meta.is_symlink:
                logger.info(f"{log_prefix}: Read symlink {req.link_path} -> {file_meta.symlink_target}")
                response = ReadlinkResponse(
                    client_id=req.client_id,
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    link_path=req.link_path,
                    target_path=file_meta.symlink_target,
                    success=True
                )
            else:
                logger.info(f"{log_prefix}: Path {req.link_path} is not a symlink")
                response = ReadlinkResponse(
                    client_id=req.client_id,
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    link_path=req.link_path,
                    success=False,
                    message="Not a symbolic link"
                )
        else:
            logger.info(f"{log_prefix}: Symlink {req.link_path} not found")
            response = ReadlinkResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                link_path=req.link_path,
                success=False,
                message="Symlink not found"
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

    def _generate_fid(self) -> str:
        """Generate a Lustre-style FID (File Identifier)."""
        # Simplified FID generation: seq:oid:ver format
        seq = self.mdt_index + 0x200000000
        oid = len(self.files) + 1
        ver = 0
        return f"0x{seq:x}:0x{oid:x}:0x{ver:x}"

    def _on_machine_fail(self, machine_id: str):
        """Handle machine failure."""
        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}: "
                   f"Underlying machine {machine_id} failed.")
        super()._on_machine_fail(machine_id)

        # Notify MGS
        server_info = ServerInfo(
            server_id=self.id,
            server_type="MDS",
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
        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}: "
                   f"Underlying machine {machine_id} recovered.")
        super()._on_machine_recover(machine_id)

        # Re-register with MGS
        self.env.process(self._register_with_mgs())
