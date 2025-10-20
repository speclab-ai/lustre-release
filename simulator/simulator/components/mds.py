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
    # Extended attributes
    SetxattrRequest, SetxattrResponse,
    GetxattrRequest, GetxattrResponse,
    ListxattrRequest, ListxattrResponse,
    RemovexattrRequest, RemovexattrResponse,
    # Additional operations
    FlushRequest, FlushResponse,
    StatfsRequest, StatfsResponse,
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

        # Create root directory with proper attributes
        root_fid = "0x200000001:0x1:0x0"  # Lustre-style FID
        current_time = self.machine.get_current_time(self.env.now)
        self.files[root_fid] = FileMetadata(
            fid=root_fid,
            path="/",
            is_directory=True,
            # Initialize root with proper POSIX attributes
            mode=0o755,  # Root directory permissions
            uid=0,  # Root owned by root
            gid=0,
            nlink=2,  # Root has . and ..
            # Initialize all timestamps
            atime=current_time,
            mtime=current_time,
            ctime=current_time,
            parent_fid=None  # Root has no parent
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
        # Extended attributes
        elif isinstance(payload, SetxattrRequest):
            self._handle_setxattr(msg)
        elif isinstance(payload, GetxattrRequest):
            self._handle_getxattr(msg)
        elif isinstance(payload, ListxattrRequest):
            self._handle_listxattr(msg)
        elif isinstance(payload, RemovexattrRequest):
            self._handle_removexattr(msg)
        # Additional operations
        elif isinstance(payload, FlushRequest):
            self._handle_flush(msg)
        elif isinstance(payload, StatfsRequest):
            self._handle_statfs(msg)

    def _handle_create_file(self, msg: NetworkMessage):
        """Handle file creation request.

        Implements proper validation like real Lustre:
        - Validates parent directory exists
        - Sets proper initial attributes (mode, uid, gid, timestamps)
        - Checks file doesn't already exist
        """
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
            # Validate parent directory exists (like real Lustre REINT_CREATE)
            parent_path = req.path.rsplit("/", 1)[0] or "/"
            if parent_path not in self.path_to_fid:
                logger.info(f"{log_prefix}: Parent directory {parent_path} does not exist")
                response = CreateFileResponse(
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    success=False,
                    message="Parent directory does not exist"
                )
            else:
                parent_fid = self.path_to_fid[parent_path]
                # Verify parent FID exists and is a directory
                if parent_fid not in self.files or not self.files[parent_fid].is_directory:
                    logger.info(f"{log_prefix}: Parent {parent_path} is not a directory")
                    response = CreateFileResponse(
                        request_id=req.request_id,
                        timestamp=self.machine.get_current_time(self.env.now),
                        path=req.path,
                        success=False,
                        message="Parent is not a directory"
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
                        # Create file metadata with proper initial attributes
                        current_time = self.machine.get_current_time(self.env.now)
                        file_meta = FileMetadata(
                            fid=fid,
                            path=req.path,
                            is_directory=False,
                            stripe_count=len(ost_indices),
                            stripe_size=req.stripe_size,
                            ost_indices=ost_indices,
                            size_bytes=0,
                            # Initialize POSIX attributes (like real Lustre)
                            mode=0o644,  # Default file permissions
                            uid=0,  # Would be set from request in real implementation
                            gid=0,  # Would be set from request in real implementation
                            nlink=1,  # New file has 1 link
                            # Initialize all timestamps
                            atime=current_time,
                            mtime=current_time,
                            ctime=current_time,
                            parent_fid=parent_fid
                        )

                        self.files[fid] = file_meta
                        self.path_to_fid[req.path] = fid

                        # Update parent directory timestamps (like real Lustre)
                        self._update_parent_timestamps(parent_fid)

                        logger.info(f"{log_prefix}: Created file {req.path} with FID {fid}, stripes on OSTs {ost_indices}")
                        response = CreateFileResponse(
                            request_id=req.request_id,
                            timestamp=current_time,
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
        """Handle stat request for file metadata.

        Returns complete metadata like real Lustre MDS_GETATTR.
        """
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
                # Calculate blocks (number of 512-byte blocks)
                blocks = (file_meta.size_bytes + 511) // 512
                response = StatResponse(
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    fid=fid,
                    size=file_meta.size_bytes,
                    stripe_count=file_meta.stripe_count,
                    stripe_size=file_meta.stripe_size,
                    # POSIX attributes
                    mode=file_meta.mode,
                    nlink=file_meta.nlink,
                    uid=file_meta.uid,
                    gid=file_meta.gid,
                    # Timestamps
                    atime=file_meta.atime,
                    mtime=file_meta.mtime,
                    ctime=file_meta.ctime,
                    # Block information
                    blocks=blocks,
                    blksize=4096,  # Standard block size
                    flags=0,  # No special flags in simulator
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
        """Handle file deletion request.

        Implements proper nlink handling like real Lustre:
        - If nlink > 1: decrements nlink and removes directory entry only
        - If nlink == 1: removes directory entry and deletes inode
        """
        req = cast(DeleteFileRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        if req.path in self.path_to_fid:
            fid = self.path_to_fid[req.path]
            # Check if file still exists (might have been deleted already)
            if fid in self.files:
                file_meta = self.files[fid]

                # Get parent_fid before removing path, for timestamp update
                parent_fid = file_meta.parent_fid

                # Remove the directory entry (this path)
                del self.path_to_fid[req.path]

                # Decrement nlink counter
                file_meta.nlink -= 1
                # Update ctime when nlink changes (like real Lustre)
                file_meta.ctime = self.machine.get_current_time(self.env.now)

                # Only delete inode if nlink reaches 0
                if file_meta.nlink <= 0:
                    del self.files[fid]
                    logger.info(f"{log_prefix}: Deleted file {req.path} (nlink reached 0, inode removed)")
                else:
                    logger.info(f"{log_prefix}: Unlinked {req.path} (nlink now {file_meta.nlink}, inode kept)")

                # Update parent directory timestamps (like real Lustre)
                if parent_fid:
                    self._update_parent_timestamps(parent_fid)

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
        """Handle directory creation request.

        Implements proper validation like real Lustre:
        - Validates parent directory exists
        - Sets proper initial attributes (mode, uid, gid, timestamps)
        - Initializes nlink=2 (. and ..)
        """
        req = cast(MkdirRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        if req.path in self.path_to_fid:
            # Check if it's actually a file or directory
            fid = self.path_to_fid[req.path]
            if fid in self.files:
                existing = self.files[fid]
                if existing.is_directory:
                    error_msg = "Directory already exists"
                else:
                    error_msg = "File exists"
            else:
                error_msg = "Path already exists"

            response = MkdirResponse(
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                success=False,
                message=error_msg
            )
        else:
            # Validate parent directory exists (like real Lustre)
            parent_path = req.path.rsplit("/", 1)[0] or "/"
            if parent_path not in self.path_to_fid:
                logger.info(f"{log_prefix}: Parent directory {parent_path} does not exist")
                response = MkdirResponse(
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    success=False,
                    message="Parent directory does not exist"
                )
            else:
                parent_fid = self.path_to_fid[parent_path]
                # Verify parent FID exists and is a directory
                if parent_fid not in self.files or not self.files[parent_fid].is_directory:
                    logger.info(f"{log_prefix}: Parent {parent_path} is not a directory")
                    response = MkdirResponse(
                        request_id=req.request_id,
                        timestamp=self.machine.get_current_time(self.env.now),
                        path=req.path,
                        success=False,
                        message="Parent is not a directory"
                    )
                else:
                    fid = self._generate_fid()
                    current_time = self.machine.get_current_time(self.env.now)
                    dir_meta = FileMetadata(
                        fid=fid,
                        path=req.path,
                        is_directory=True,
                        # Initialize POSIX attributes
                        mode=0o755,  # Default directory permissions
                        uid=0,
                        gid=0,
                        nlink=2,  # Directories start with nlink=2 (. and ..)
                        # Initialize all timestamps
                        atime=current_time,
                        mtime=current_time,
                        ctime=current_time,
                        parent_fid=parent_fid
                    )

                    self.files[fid] = dir_meta
                    self.path_to_fid[req.path] = fid

                    # Update parent directory timestamps (like real Lustre)
                    self._update_parent_timestamps(parent_fid)

                    logger.info(f"{log_prefix}: Created directory {req.path}")
                    response = MkdirResponse(
                        request_id=req.request_id,
                        timestamp=current_time,
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
        """Handle directory listing request.

        Validates that the path is actually a directory before listing.
        """
        req = cast(ListDirRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Check if path exists and is a directory
        if req.path not in self.path_to_fid:
            logger.info(f"{log_prefix}: Path {req.path} not found for listdir")
            response = ListDirResponse(
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                entries=[],
                success=False,
                message="Directory not found"
            )
        else:
            fid = self.path_to_fid[req.path]
            if fid not in self.files:
                logger.info(f"{log_prefix}: Path {req.path} has stale FID mapping")
                response = ListDirResponse(
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    entries=[],
                    success=False,
                    message="Directory not found"
                )
            elif not self.files[fid].is_directory:
                logger.info(f"{log_prefix}: Path {req.path} is not a directory")
                response = ListDirResponse(
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    entries=[],
                    success=False,
                    message="Not a directory"
                )
            else:
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
        """Handle directory removal request.

        Implements proper validation like real Lustre:
        - Verifies directory is empty before removal
        - Checks for . and .. entries
        """
        req = cast(RmdirRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Check if directory exists
        if req.path in self.path_to_fid:
            fid = self.path_to_fid[req.path]
            file_meta = self.files.get(fid)

            if file_meta and file_meta.is_directory:
                # Check if directory is empty (like real Lustre)
                # Look for any paths that are children of this directory
                dir_prefix = req.path if req.path.endswith("/") else req.path + "/"
                has_children = any(
                    path.startswith(dir_prefix) and path != req.path
                    for path in self.path_to_fid.keys()
                )

                if has_children:
                    logger.info(f"{log_prefix}: Directory {req.path} is not empty")
                    response = RmdirResponse(
                        client_id=req.client_id,
                        request_id=req.request_id,
                        timestamp=self.machine.get_current_time(self.env.now),
                        path=req.path,
                        success=False,
                        message="Directory not empty"
                    )
                else:
                    # Get parent_fid before removing directory
                    parent_fid = file_meta.parent_fid

                    # Remove directory
                    del self.files[fid]
                    del self.path_to_fid[req.path]

                    # Update parent directory timestamps (like real Lustre)
                    if parent_fid:
                        self._update_parent_timestamps(parent_fid)

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
        """Handle file/directory rename request.

        Implements atomic replacement like real Lustre:
        - If target exists, atomically replaces it
        - Handles nlink correctly for replaced files
        - Updates parent directory timestamps
        """
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

            # Get old and new parent directories for timestamp updates
            old_parent_fid = file_meta.parent_fid
            new_parent_path = req.new_path.rsplit("/", 1)[0] or "/"
            new_parent_fid = self.path_to_fid.get(new_parent_path)

            # Handle atomic replacement if target exists (like real Lustre REINT_RENAME)
            if req.new_path in self.path_to_fid:
                target_fid = self.path_to_fid[req.new_path]
                if target_fid in self.files:
                    target_meta = self.files[target_fid]
                    # Atomically unlink the target
                    target_meta.nlink -= 1
                    # Update ctime when nlink changes (like real Lustre)
                    target_meta.ctime = self.machine.get_current_time(self.env.now)
                    if target_meta.nlink <= 0:
                        del self.files[target_fid]
                        logger.info(f"{log_prefix}: Atomically replaced {req.new_path} during rename")
                    else:
                        logger.info(f"{log_prefix}: Decremented nlink of {req.new_path} to {target_meta.nlink}")
                # Remove target path mapping
                del self.path_to_fid[req.new_path]

            # Update path mappings
            del self.path_to_fid[req.old_path]
            self.path_to_fid[req.new_path] = fid
            file_meta.path = req.new_path
            # Update parent_fid if moving to different directory
            if new_parent_fid:
                file_meta.parent_fid = new_parent_fid

            # Update both old and new parent directory timestamps (like real Lustre)
            if old_parent_fid:
                self._update_parent_timestamps(old_parent_fid)
            if new_parent_fid and new_parent_fid != old_parent_fid:
                self._update_parent_timestamps(new_parent_fid)

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

            # Update attributes with validation
            if req.mode is not None:
                # Validate mode bits (must be in range 0-0o7777)
                if req.mode < 0 or req.mode > 0o7777:
                    logger.info(f"{log_prefix}: Invalid mode bits: {oct(req.mode)}")
                    response = SetattrResponse(
                        client_id=req.client_id,
                        request_id=req.request_id,
                        timestamp=self.machine.get_current_time(self.env.now),
                        path=req.path,
                        success=False,
                        message=f"Invalid mode bits: {oct(req.mode)}"
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
                nlink=file_meta.nlink,
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
        """Handle hard link creation request.

        Implements proper validation like real Lustre:
        - Prevents hard links to directories
        - Checks filesystem boundaries
        - Increments nlink counter
        """
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

            # Prevent hard links to directories (like real Lustre REINT_LINK)
            if file_meta.is_directory:
                logger.info(f"{log_prefix}: Cannot create hard link to directory {req.existing_path}")
                response = LinkResponse(
                    client_id=req.client_id,
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    existing_path=req.existing_path,
                    link_path=req.link_path,
                    success=False,
                    message="Cannot create hard link to directory"
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

            # Check if link path already exists
            if req.link_path in self.path_to_fid:
                logger.info(f"{log_prefix}: Link path {req.link_path} already exists")
                response = LinkResponse(
                    client_id=req.client_id,
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    existing_path=req.existing_path,
                    link_path=req.link_path,
                    success=False,
                    message="File already exists"
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

            # Create hard link by adding new path pointing to same FID
            self.path_to_fid[req.link_path] = fid
            file_meta.nlink += 1
            # Update ctime when nlink changes (like real Lustre)
            file_meta.ctime = self.machine.get_current_time(self.env.now)

            logger.info(f"{log_prefix}: Created hard link from {req.existing_path} to {req.link_path} (nlink now {file_meta.nlink})")
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
        """Handle symbolic link creation request.

        Implements proper validation like real Lustre:
        - Validates parent directory exists
        - Sets complete attributes (mode, uid, gid, timestamps, parent_fid)
        """
        req = cast(SymlinkRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Check if link path already exists
        if req.link_path in self.path_to_fid:
            logger.info(f"{log_prefix}: Symlink path {req.link_path} already exists")
            response = SymlinkResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                target_path=req.target_path,
                link_path=req.link_path,
                success=False,
                message="File already exists"
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

        # Validate parent directory exists (like CreateFile and Mkdir)
        parent_path = req.link_path.rsplit("/", 1)[0] or "/"
        if parent_path not in self.path_to_fid:
            logger.info(f"{log_prefix}: Parent directory {parent_path} does not exist")
            response = SymlinkResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                target_path=req.target_path,
                link_path=req.link_path,
                success=False,
                message="Parent directory does not exist"
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

        parent_fid = self.path_to_fid[parent_path]
        # Verify parent FID exists and is a directory
        if parent_fid not in self.files or not self.files[parent_fid].is_directory:
            logger.info(f"{log_prefix}: Parent {parent_path} is not a directory")
            response = SymlinkResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                target_path=req.target_path,
                link_path=req.link_path,
                success=False,
                message="Parent is not a directory"
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

        # Create symlink metadata with complete attributes
        fid = self._generate_fid()
        current_time = self.machine.get_current_time(self.env.now)

        file_meta = FileMetadata(
            fid=fid,
            path=req.link_path,
            is_directory=False,
            is_symlink=True,
            symlink_target=req.target_path,
            size_bytes=0,
            # Complete POSIX attributes
            mode=0o777,  # Symlinks typically have 777 permissions
            uid=0,
            gid=0,
            nlink=1,
            # Initialize all timestamps
            atime=current_time,
            mtime=current_time,
            ctime=current_time,
            parent_fid=parent_fid
        )

        self.files[fid] = file_meta
        self.path_to_fid[req.link_path] = fid

        # Update parent directory timestamps (like real Lustre)
        self._update_parent_timestamps(parent_fid)

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

    # Extended Attributes Handlers

    def _handle_setxattr(self, msg: NetworkMessage):
        """Handle set extended attribute request.

        Validates xattr namespace like real Lustre (user.*, trusted.*, etc.)
        """
        req = cast(SetxattrRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Validate xattr namespace (like real Lustre)
        is_valid, error_msg = self._validate_xattr_name(req.name)
        if not is_valid:
            logger.info(f"{log_prefix}: {error_msg}")
            response = SetxattrResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                name=req.name,
                success=False,
                message=error_msg
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

        # Validate xattr value size (like real Lustre)
        is_valid, error_msg = self._validate_xattr_value(req.value)
        if not is_valid:
            logger.info(f"{log_prefix}: {error_msg}")
            response = SetxattrResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                name=req.name,
                success=False,
                message=error_msg
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

        # Check if file exists
        if req.path in self.path_to_fid:
            fid = self.path_to_fid[req.path]

            # Defensive check for race conditions
            if fid not in self.files:
                del self.path_to_fid[req.path]
                logger.info(f"{log_prefix}: File {req.path} has stale FID mapping")
                response = SetxattrResponse(
                    client_id=req.client_id,
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    name=req.name,
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

            # Set the extended attribute
            file_meta.xattrs[req.name] = req.value
            # Update ctime after xattr change (like real Lustre)
            file_meta.ctime = self.machine.get_current_time(self.env.now)

            logger.info(f"{log_prefix}: Set xattr '{req.name}' on {req.path}")
            response = SetxattrResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                name=req.name,
                success=True
            )
        else:
            logger.info(f"{log_prefix}: File {req.path} not found for setxattr")
            response = SetxattrResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                name=req.name,
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

    def _handle_getxattr(self, msg: NetworkMessage):
        """Handle get extended attribute request.

        Validates xattr namespace like real Lustre.
        """
        req = cast(GetxattrRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Validate xattr namespace
        is_valid, error_msg = self._validate_xattr_name(req.name)
        if not is_valid:
            logger.info(f"{log_prefix}: {error_msg}")
            response = GetxattrResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                name=req.name,
                success=False,
                message=error_msg
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

        # Check if file exists
        if req.path in self.path_to_fid:
            fid = self.path_to_fid[req.path]

            # Defensive check
            if fid not in self.files:
                del self.path_to_fid[req.path]
                logger.info(f"{log_prefix}: File {req.path} has stale FID mapping")
                response = GetxattrResponse(
                    client_id=req.client_id,
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    name=req.name,
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

            # Get the extended attribute
            value = file_meta.xattrs.get(req.name)
            if value is not None:
                logger.info(f"{log_prefix}: Get xattr '{req.name}' from {req.path}")
                response = GetxattrResponse(
                    client_id=req.client_id,
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    name=req.name,
                    value=value,
                    success=True
                )
            else:
                logger.info(f"{log_prefix}: Xattr '{req.name}' not found on {req.path}")
                response = GetxattrResponse(
                    client_id=req.client_id,
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    name=req.name,
                    success=False,
                    message="Attribute not found"
                )
        else:
            logger.info(f"{log_prefix}: File {req.path} not found for getxattr")
            response = GetxattrResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                name=req.name,
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

    def _handle_listxattr(self, msg: NetworkMessage):
        """Handle list extended attributes request."""
        req = cast(ListxattrRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Check if file exists
        if req.path in self.path_to_fid:
            fid = self.path_to_fid[req.path]

            # Defensive check
            if fid not in self.files:
                del self.path_to_fid[req.path]
                logger.info(f"{log_prefix}: File {req.path} has stale FID mapping")
                response = ListxattrResponse(
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

            # List all extended attribute names
            names = list(file_meta.xattrs.keys())
            logger.info(f"{log_prefix}: List xattrs from {req.path}: {len(names)} attributes")
            response = ListxattrResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                names=names,
                success=True
            )
        else:
            logger.info(f"{log_prefix}: File {req.path} not found for listxattr")
            response = ListxattrResponse(
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

    def _handle_removexattr(self, msg: NetworkMessage):
        """Handle remove extended attribute request.

        Validates xattr namespace like real Lustre.
        """
        req = cast(RemovexattrRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Validate xattr namespace
        is_valid, error_msg = self._validate_xattr_name(req.name)
        if not is_valid:
            logger.info(f"{log_prefix}: {error_msg}")
            response = RemovexattrResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                name=req.name,
                success=False,
                message=error_msg
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

        # Check if file exists
        if req.path in self.path_to_fid:
            fid = self.path_to_fid[req.path]

            # Defensive check
            if fid not in self.files:
                del self.path_to_fid[req.path]
                logger.info(f"{log_prefix}: File {req.path} has stale FID mapping")
                response = RemovexattrResponse(
                    client_id=req.client_id,
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    name=req.name,
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

            # Remove the extended attribute
            if req.name in file_meta.xattrs:
                del file_meta.xattrs[req.name]
                # Update ctime after xattr change
                file_meta.ctime = self.machine.get_current_time(self.env.now)

                logger.info(f"{log_prefix}: Removed xattr '{req.name}' from {req.path}")
                response = RemovexattrResponse(
                    client_id=req.client_id,
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    name=req.name,
                    success=True
                )
            else:
                logger.info(f"{log_prefix}: Xattr '{req.name}' not found on {req.path}")
                response = RemovexattrResponse(
                    client_id=req.client_id,
                    request_id=req.request_id,
                    timestamp=self.machine.get_current_time(self.env.now),
                    path=req.path,
                    name=req.name,
                    success=False,
                    message="Attribute not found"
                )
        else:
            logger.info(f"{log_prefix}: File {req.path} not found for removexattr")
            response = RemovexattrResponse(
                client_id=req.client_id,
                request_id=req.request_id,
                timestamp=self.machine.get_current_time(self.env.now),
                path=req.path,
                name=req.name,
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

    # Additional Operations Handlers

    def _handle_flush(self, msg: NetworkMessage):
        """Handle flush request (error reporting mechanism)."""
        req = cast(FlushRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Flush in Lustre is mainly for error reporting, not actual sync
        # For simplicity, just acknowledge the flush
        logger.info(f"{log_prefix}: Flush for {req.path}")
        response = FlushResponse(
            client_id=req.client_id,
            request_id=req.request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            path=req.path,
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

    def _handle_statfs(self, msg: NetworkMessage):
        """Handle filesystem statistics request."""
        req = cast(StatfsRequest, msg.payload)
        log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] MDS {self.id}"

        # Calculate MDT statistics
        total_files = len(self.files)
        # Simple calculation - in reality this would query actual storage capacity
        total_capacity = 10_000  # Max inodes
        used_files = total_files
        available_files = total_capacity - used_files

        logger.info(f"{log_prefix}: Statfs - {used_files}/{total_capacity} inodes")
        response = StatfsResponse(
            client_id=req.client_id,
            request_id=req.request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            total_files=total_capacity,
            used_files=used_files,
            available_files=available_files,
            # OSS will fill in capacity stats
            total_capacity_bytes=0,
            used_bytes=0,
            available_bytes=0,
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

    def _generate_fid(self) -> str:
        """Generate a Lustre-style FID (File Identifier)."""
        # Simplified FID generation: seq:oid:ver format
        seq = self.mdt_index + 0x200000000
        oid = len(self.files) + 1
        ver = 0
        return f"0x{seq:x}:0x{oid:x}:0x{ver:x}"

    def _validate_xattr_name(self, name: str) -> tuple[bool, str]:
        """Validate extended attribute name against allowed namespaces.

        Real Lustre validates namespaces: user.*, trusted.*, security.*, system.*
        Reserved names: trusted.lov, trusted.lmv, trusted.fid, etc.

        Returns: (is_valid, error_message)
        """
        # Check valid namespaces
        valid_prefixes = ("user.", "trusted.", "security.", "system.")
        if not any(name.startswith(prefix) for prefix in valid_prefixes):
            return False, f"Invalid xattr namespace. Must start with {', '.join(valid_prefixes)}"

        # Check for reserved Lustre xattr names
        reserved_names = {
            "trusted.lov",  # Layout information
            "trusted.lmv",  # Directory layout
            "trusted.fid",  # File identifier
            "trusted.link", # Hard link info
        }
        if name in reserved_names:
            return False, f"Reserved xattr name: {name}"

        return True, ""

    def _validate_xattr_value(self, value: str) -> tuple[bool, str]:
        """Validate extended attribute value size.

        Real Lustre enforces size limits on xattr values (typically 64KB).

        Returns: (is_valid, error_message)
        """
        # Real Lustre typically limits xattr values to 64KB
        MAX_XATTR_SIZE = 65536
        value_size = len(value.encode('utf-8'))
        if value_size > MAX_XATTR_SIZE:
            return False, f"Xattr value too large: {value_size} bytes (max {MAX_XATTR_SIZE})"
        return True, ""

    def _update_parent_timestamps(self, parent_fid: str) -> None:
        """Update parent directory mtime and ctime.

        In real Lustre, modifying directory contents (create/delete/rename)
        updates the parent directory's mtime and ctime.
        """
        if parent_fid in self.files:
            parent_meta = self.files[parent_fid]
            current_time = self.machine.get_current_time(self.env.now)
            parent_meta.mtime = current_time
            parent_meta.ctime = current_time

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
