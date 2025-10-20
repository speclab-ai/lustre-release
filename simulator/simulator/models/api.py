from typing import Optional, List, Dict
from pydantic import BaseModel
from .base import Request, Response


class CreateFileRequest(Request):
    """Client request to create a file in Lustre."""
    path: str
    stripe_count: int = 1  # Number of OSTs to stripe across
    stripe_size: int = 1048576  # Stripe size in bytes (default 1MB)


class CreateFileResponse(Response):
    """Response to file creation."""
    path: str
    fid: Optional[str] = None  # File Identifier assigned by MDS


class WriteRequest(Request):
    """Client request to write data to a file."""
    fid: str  # File Identifier
    offset: int  # Offset in bytes
    data: str  # Data to write
    size: int  # Size of data in bytes


class WriteResponse(Response):
    """Response to write request."""
    fid: str
    bytes_written: int = 0


class ReadRequest(Request):
    """Client request to read data from a file."""
    fid: str  # File Identifier
    offset: int  # Offset in bytes
    size: int  # Number of bytes to read


class ReadResponse(Response):
    """Response to read request."""
    fid: str
    data: Optional[str] = None
    bytes_read: int = 0


class StatRequest(Request):
    """Client request to get file metadata/stats."""
    path: str


class StatResponse(Response):
    """Response with file metadata."""
    path: str
    fid: Optional[str] = None
    size: int = 0
    stripe_count: int = 1
    stripe_size: int = 1048576
    mtime: float = 0.0  # Last modification time


class DeleteFileRequest(Request):
    """Client request to delete a file."""
    path: str


class DeleteFileResponse(Response):
    """Response to file deletion."""
    path: str


class MkdirRequest(Request):
    """Client request to create a directory."""
    path: str


class MkdirResponse(Response):
    """Response to directory creation."""
    path: str


class ListDirRequest(Request):
    """Client request to list directory contents."""
    path: str


class ListDirResponse(Response):
    """Response with directory contents."""
    path: str
    entries: List[str] = []  # List of file/directory names


class LockRequest(Request):
    """Request to acquire a distributed lock (LDLM)."""
    fid: str  # File Identifier
    lock_type: str  # "READ" or "WRITE"
    extent_start: int = 0  # Start of byte range
    extent_end: int = -1  # End of byte range (-1 for EOF)


class LockResponse(Response):
    """Response to lock request."""
    fid: str
    lock_id: Optional[str] = None  # Lock identifier if granted


class UnlockRequest(Request):
    """Request to release a distributed lock."""
    lock_id: str


class UnlockResponse(Response):
    """Response to unlock request."""
    lock_id: str


class GetLayoutRequest(Request):
    """MDS request to get file layout (stripe information)."""
    fid: str


class GetLayoutResponse(Response):
    """Response with file layout information."""
    fid: str
    layout: Optional['FileLayout'] = None


# Forward reference resolved
class FileLayout(BaseModel):
    """File layout describing how file is striped across OSTs."""
    fid: str
    stripe_count: int
    stripe_size: int
    ost_indices: List[int]  # List of OST indices where stripes are stored


# Update forward reference
GetLayoutResponse.model_rebuild()
