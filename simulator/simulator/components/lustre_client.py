import simpy
import uuid
from typing import Dict, List, Optional, Any
from pydantic import BaseModel

from simulator.models.api import (
    CreateFileRequest, CreateFileResponse,
    WriteRequest, WriteResponse,
    ReadRequest, ReadResponse,
    StatRequest, StatResponse,
    DeleteFileRequest, DeleteFileResponse,
    MkdirRequest, MkdirResponse,
    ListDirRequest, ListDirResponse,
    GetLayoutRequest, GetLayoutResponse, FileLayout,
    # High priority APIs
    OpenRequest, OpenResponse,
    CloseRequest, CloseResponse,
    SeekRequest, SeekResponse,
    FsyncRequest, FsyncResponse,
    RmdirRequest, RmdirResponse,
    RenameRequest, RenameResponse,
    SetattrRequest, SetattrResponse,
    GetattrRequest, GetattrResponse,
    LinkRequest, LinkResponse,
    SymlinkRequest, SymlinkResponse,
    ReadlinkRequest, ReadlinkResponse,
)
from simulator.models.internal import NetworkMessage, RequestContext
from simulator.infra.network import Network
from simulator.infra.machine import Machine
from simulator.infra.request_context import RequestContext as ReqCtx

import logging
logger = logging.getLogger(__name__)


class LustreClient(BaseModel):
    """Lustre client that performs file system operations."""

    id: str
    env: simpy.Environment
    network: Network
    machine: Machine
    mds_id: str  # ID of the MDS to connect to

    # Client state
    is_crashed: bool = False
    file_layouts: Dict[str, FileLayout] = {}  # fid -> FileLayout cache
    request_results: Dict[str, bool] = {}  # request_id -> success
    request_latencies: Dict[str, float] = {}  # request_id -> latency
    request_failures: Dict[str, str] = {}  # request_id -> failure reason
    request_types: Dict[str, str] = {}  # request_id -> operation type
    _pending_requests: Dict[str, float] = {}  # request_id -> start_time

    class Config:
        arbitrary_types_allowed = True

    def __init__(self, env: simpy.Environment, network: Network, machine: Machine,
                 mds_id: str, **data):
        super().__init__(
            env=env,
            network=network,
            machine=machine,
            mds_id=mds_id,
            **data
        )
        self.network.register_node(self.id)
        self.machine.register_callbacks(self._on_machine_fail, self._on_machine_recover)
        self.env.process(self._listen_for_responses())

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id} initialized.")

    def _listen_for_responses(self):
        """Listen for responses from MDS and OSS."""
        while True:
            if self.is_crashed:
                yield self.env.timeout(1)
                continue

            msg: NetworkMessage = yield self.network.get_inbox(self.id).get()
            self._handle_response(msg)

    def _handle_response(self, msg: NetworkMessage):
        """Handle response messages."""
        payload = msg.payload
        request_id = getattr(payload, 'request_id', None)

        if request_id and request_id in self._pending_requests:
            # Calculate latency
            start_time = self._pending_requests[request_id]
            latency = self.env.now - start_time
            self.request_latencies[request_id] = latency
            success = getattr(payload, 'success', True)
            self.request_results[request_id] = success

            # Track failure reason if request failed
            if not success:
                failure_reason = getattr(payload, 'message', 'Unknown error')
                self.request_failures[request_id] = failure_reason
                logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                           f"Request {request_id} failed: {failure_reason}")

            del self._pending_requests[request_id]

            logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                       f"Received response for {payload.__class__.__name__} "
                       f"(latency: {latency:.4f}s, success: {success})")

            # Cache file layout if applicable
            if isinstance(payload, GetLayoutResponse) and payload.success and payload.layout:
                self.file_layouts[payload.fid] = payload.layout

    def create_file(self, path: str, stripe_count: int = 1, stripe_size: int = 1048576):
        """Create a new file."""
        request_id = str(uuid.uuid4())

        if self.is_crashed:
            logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                          "Cannot create file - client crashed")
            self.request_results[request_id] = False
            self.request_failures[request_id] = "Client crashed"
            self.request_types[request_id] = "CreateFile"
            return

        req = CreateFileRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            path=path,
            stripe_count=stripe_count,
            stripe_size=stripe_size
        )

        self._pending_requests[request_id] = self.env.now
        self.request_types[request_id] = "CreateFile"

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.mds_id,
                payload=req,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=ReqCtx(request_id=request_id)
            )
        )

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Sent CreateFile request for {path}")

    def write_file(self, fid: str, offset: int, data: str, oss_id: str):
        """Write data to a file."""
        request_id = str(uuid.uuid4())

        if self.is_crashed:
            logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                          "Cannot write - client crashed")
            self.request_results[request_id] = False
            self.request_failures[request_id] = "Client crashed"
            self.request_types[request_id] = "Write"
            return

        req = WriteRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            fid=fid,
            offset=offset,
            data=data,
            size=len(data)
        )

        self._pending_requests[request_id] = self.env.now
        self.request_types[request_id] = "Write"

        # In real Lustre, client would determine which OSS based on layout
        # For now, we pass the OSS ID directly
        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=oss_id,
                payload=req,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=ReqCtx(request_id=request_id)
            )
        )

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Sent Write request for FID {fid}, {len(data)} bytes at offset {offset}")

    def read_file(self, fid: str, offset: int, size: int, oss_id: str):
        """Read data from a file."""
        request_id = str(uuid.uuid4())

        if self.is_crashed:
            logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                          "Cannot read - client crashed")
            self.request_results[request_id] = False
            self.request_failures[request_id] = "Client crashed"
            self.request_types[request_id] = "Read"
            return

        req = ReadRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            fid=fid,
            offset=offset,
            size=size
        )

        self._pending_requests[request_id] = self.env.now
        self.request_types[request_id] = "Read"

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=oss_id,
                payload=req,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=ReqCtx(request_id=request_id)
            )
        )

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Sent Read request for FID {fid}, {size} bytes at offset {offset}")

    def stat_file(self, path: str):
        """Get file metadata."""
        request_id = str(uuid.uuid4())

        if self.is_crashed:
            logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                          "Cannot stat - client crashed")
            self.request_results[request_id] = False
            self.request_failures[request_id] = "Client crashed"
            self.request_types[request_id] = "Stat"
            return

        req = StatRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            path=path
        )

        self._pending_requests[request_id] = self.env.now
        self.request_types[request_id] = "Stat"

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.mds_id,
                payload=req,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=ReqCtx(request_id=request_id)
            )
        )

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Sent Stat request for {path}")

    def delete_file(self, path: str):
        """Delete a file."""
        request_id = str(uuid.uuid4())

        if self.is_crashed:
            logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                          "Cannot delete - client crashed")
            self.request_results[request_id] = False
            self.request_failures[request_id] = "Client crashed"
            self.request_types[request_id] = "Delete"
            return

        req = DeleteFileRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            path=path
        )

        self._pending_requests[request_id] = self.env.now
        self.request_types[request_id] = "Delete"

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.mds_id,
                payload=req,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=ReqCtx(request_id=request_id)
            )
        )

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Sent Delete request for {path}")

    def mkdir(self, path: str):
        """Create a directory."""
        request_id = str(uuid.uuid4())

        if self.is_crashed:
            logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                          "Cannot mkdir - client crashed")
            self.request_results[request_id] = False
            self.request_failures[request_id] = "Client crashed"
            self.request_types[request_id] = "Mkdir"
            return

        req = MkdirRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            path=path
        )

        self._pending_requests[request_id] = self.env.now
        self.request_types[request_id] = "Mkdir"

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.mds_id,
                payload=req,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=ReqCtx(request_id=request_id)
            )
        )

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Sent Mkdir request for {path}")

    def list_dir(self, path: str):
        """List directory contents."""
        request_id = str(uuid.uuid4())

        if self.is_crashed:
            logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                          "Cannot list - client crashed")
            self.request_results[request_id] = False
            self.request_failures[request_id] = "Client crashed"
            self.request_types[request_id] = "ListDir"
            return

        req = ListDirRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            path=path
        )

        self._pending_requests[request_id] = self.env.now
        self.request_types[request_id] = "ListDir"

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.mds_id,
                payload=req,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=ReqCtx(request_id=request_id)
            )
        )

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Sent ListDir request for {path}")

    # HIGH PRIORITY APIs - Basic File Operations

    def open_file(self, path: str, flags: str = "r"):
        """Open a file."""
        request_id = str(uuid.uuid4())

        if self.is_crashed:
            logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                          "Cannot open - client crashed")
            self.request_results[request_id] = False
            self.request_failures[request_id] = "Client crashed"
            self.request_types[request_id] = "Open"
            return

        req = OpenRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            path=path,
            flags=flags
        )

        self._pending_requests[request_id] = self.env.now
        self.request_types[request_id] = "Open"

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.mds_id,
                payload=req,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=ReqCtx(request_id=request_id)
            )
        )

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Sent Open request for {path} with flags {flags}")

    def close_file(self, path: str, fd: Optional[int] = None):
        """Close a file."""
        request_id = str(uuid.uuid4())

        if self.is_crashed:
            logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                          "Cannot close - client crashed")
            self.request_results[request_id] = False
            self.request_failures[request_id] = "Client crashed"
            self.request_types[request_id] = "Close"
            return

        req = CloseRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            path=path,
            fd=fd
        )

        self._pending_requests[request_id] = self.env.now
        self.request_types[request_id] = "Close"

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.mds_id,
                payload=req,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=ReqCtx(request_id=request_id)
            )
        )

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Sent Close request for {path}")

    def seek_file(self, fid: str, offset: int, whence: str = "SET"):
        """Seek within a file."""
        request_id = str(uuid.uuid4())

        if self.is_crashed:
            logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                          "Cannot seek - client crashed")
            self.request_results[request_id] = False
            self.request_failures[request_id] = "Client crashed"
            self.request_types[request_id] = "Seek"
            return

        req = SeekRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            fid=fid,
            offset=offset,
            whence=whence
        )

        self._pending_requests[request_id] = self.env.now
        self.request_types[request_id] = "Seek"

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.mds_id,
                payload=req,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=ReqCtx(request_id=request_id)
            )
        )

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Sent Seek request for FID {fid}")

    def fsync_file(self, fid: str, oss_id: str):
        """Sync file to disk."""
        request_id = str(uuid.uuid4())

        if self.is_crashed:
            logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                          "Cannot fsync - client crashed")
            self.request_results[request_id] = False
            self.request_failures[request_id] = "Client crashed"
            self.request_types[request_id] = "Fsync"
            return

        req = FsyncRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            fid=fid
        )

        self._pending_requests[request_id] = self.env.now
        self.request_types[request_id] = "Fsync"

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=oss_id,
                payload=req,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=ReqCtx(request_id=request_id)
            )
        )

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Sent Fsync request for FID {fid}")

    # HIGH PRIORITY APIs - Directory Operations

    def rmdir(self, path: str):
        """Remove a directory."""
        request_id = str(uuid.uuid4())

        if self.is_crashed:
            logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                          "Cannot rmdir - client crashed")
            self.request_results[request_id] = False
            self.request_failures[request_id] = "Client crashed"
            self.request_types[request_id] = "Rmdir"
            return

        req = RmdirRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            path=path
        )

        self._pending_requests[request_id] = self.env.now
        self.request_types[request_id] = "Rmdir"

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.mds_id,
                payload=req,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=ReqCtx(request_id=request_id)
            )
        )

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Sent Rmdir request for {path}")

    def rename(self, old_path: str, new_path: str):
        """Rename a file or directory."""
        request_id = str(uuid.uuid4())

        if self.is_crashed:
            logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                          "Cannot rename - client crashed")
            self.request_results[request_id] = False
            self.request_failures[request_id] = "Client crashed"
            self.request_types[request_id] = "Rename"
            return

        req = RenameRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            old_path=old_path,
            new_path=new_path
        )

        self._pending_requests[request_id] = self.env.now
        self.request_types[request_id] = "Rename"

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.mds_id,
                payload=req,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=ReqCtx(request_id=request_id)
            )
        )

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Sent Rename request from {old_path} to {new_path}")

    # HIGH PRIORITY APIs - Metadata Operations

    def setattr(self, path: str, mode: Optional[int] = None, uid: Optional[int] = None,
                gid: Optional[int] = None, size: Optional[int] = None,
                atime: Optional[float] = None, mtime: Optional[float] = None):
        """Set file attributes."""
        request_id = str(uuid.uuid4())

        if self.is_crashed:
            logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                          "Cannot setattr - client crashed")
            self.request_results[request_id] = False
            self.request_failures[request_id] = "Client crashed"
            self.request_types[request_id] = "Setattr"
            return

        req = SetattrRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            path=path,
            mode=mode,
            uid=uid,
            gid=gid,
            size=size,
            atime=atime,
            mtime=mtime
        )

        self._pending_requests[request_id] = self.env.now
        self.request_types[request_id] = "Setattr"

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.mds_id,
                payload=req,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=ReqCtx(request_id=request_id)
            )
        )

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Sent Setattr request for {path}")

    def getattr(self, path: str):
        """Get file attributes."""
        request_id = str(uuid.uuid4())

        if self.is_crashed:
            logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                          "Cannot getattr - client crashed")
            self.request_results[request_id] = False
            self.request_failures[request_id] = "Client crashed"
            self.request_types[request_id] = "Getattr"
            return

        req = GetattrRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            path=path
        )

        self._pending_requests[request_id] = self.env.now
        self.request_types[request_id] = "Getattr"

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.mds_id,
                payload=req,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=ReqCtx(request_id=request_id)
            )
        )

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Sent Getattr request for {path}")

    # HIGH PRIORITY APIs - Link Operations

    def link(self, existing_path: str, link_path: str):
        """Create a hard link."""
        request_id = str(uuid.uuid4())

        if self.is_crashed:
            logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                          "Cannot link - client crashed")
            self.request_results[request_id] = False
            self.request_failures[request_id] = "Client crashed"
            self.request_types[request_id] = "Link"
            return

        req = LinkRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            existing_path=existing_path,
            link_path=link_path
        )

        self._pending_requests[request_id] = self.env.now
        self.request_types[request_id] = "Link"

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.mds_id,
                payload=req,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=ReqCtx(request_id=request_id)
            )
        )

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Sent Link request from {existing_path} to {link_path}")

    def symlink(self, target_path: str, link_path: str):
        """Create a symbolic link."""
        request_id = str(uuid.uuid4())

        if self.is_crashed:
            logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                          "Cannot symlink - client crashed")
            self.request_results[request_id] = False
            self.request_failures[request_id] = "Client crashed"
            self.request_types[request_id] = "Symlink"
            return

        req = SymlinkRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            target_path=target_path,
            link_path=link_path
        )

        self._pending_requests[request_id] = self.env.now
        self.request_types[request_id] = "Symlink"

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.mds_id,
                payload=req,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=ReqCtx(request_id=request_id)
            )
        )

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Sent Symlink request from {target_path} to {link_path}")

    def readlink(self, link_path: str):
        """Read a symbolic link."""
        request_id = str(uuid.uuid4())

        if self.is_crashed:
            logger.warning(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                          "Cannot readlink - client crashed")
            self.request_results[request_id] = False
            self.request_failures[request_id] = "Client crashed"
            self.request_types[request_id] = "Readlink"
            return

        req = ReadlinkRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            link_path=link_path
        )

        self._pending_requests[request_id] = self.env.now
        self.request_types[request_id] = "Readlink"

        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=self.mds_id,
                payload=req,
                timestamp=self.machine.get_current_time(self.env.now),
                request_context=ReqCtx(request_id=request_id)
            )
        )

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Sent Readlink request for {link_path}")

    def crash(self):
        """Simulate client crash."""
        self.is_crashed = True
        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: Crashed")

    def recover(self):
        """Recover from crash."""
        self.is_crashed = False
        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: Recovered")

    def _on_machine_fail(self, machine_id: str):
        """Handle machine failure."""
        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Underlying machine {machine_id} failed.")
        self.crash()

    def _on_machine_recover(self, machine_id: str):
        """Handle machine recovery."""
        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] LustreClient {self.id}: "
                   f"Underlying machine {machine_id} recovered.")
        self.recover()
