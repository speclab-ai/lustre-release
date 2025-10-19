from typing import Optional, List
from pydantic import BaseModel
from .base import Request, Response, ReadConsistency


class PutRequest(Request):
    key: str
    value: str
    metadata: Optional[List[str]] = None
    ttl: Optional[int] = None


class PutResponse(Response):
    key: str


class GetRequest(Request):
    key: str
    consistency: ReadConsistency = ReadConsistency.LINEARIZABLE


class GetResponse(Response):
    key: str
    value: Optional[str] = None
    metadata: Optional[List[str]] = None


class DeleteRequest(Request):
    key: str


class DeleteResponse(Response):
    key: str


class AppendMetadataRequest(Request):
    key: str
    metadata_entry: str


class AppendMetadataResponse(Response):
    key: str


class ListRequest(Request):
    path: str


class ListResponse(Response):
    path: str
    keys: List[str] = []


class SnapshotRequest(Request):
    snapshot_id: str


class SnapshotResponse(Response):
    snapshot_id: str
    status: str # e.g., 'INITIATED', 'COMPLETED', 'FAILED'