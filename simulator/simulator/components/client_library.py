import simpy
import uuid
from typing import Dict, List, Optional

from simulator.models.internal import NetworkMessage
from simulator.models.api import Request, Response, PutRequest, GetRequest, ReadConsistency
from simulator.infra.network import Network
from simulator.infra.load_balancer import LoadBalancer
from simulator.infra.machine import Machine
from simulator.infra.base_service import BaseService
from simulator.infra.logger import ContextLogger

import logging
logger = logging.getLogger(__name__)


class ClientLibrary(BaseService):
    """Client library for sending requests to the distributed KV store.

    Refactored to use BaseService for common crash/recover patterns.
    """
    # BaseService provides: id, env, network, machine, is_crashed, _listen_process

    load_balancer: LoadBalancer
    request_latencies: Dict[str, float] = {}
    request_results: Dict[str, bool] = {}
    _context_logger: Optional[ContextLogger] = None

    class Config:
        arbitrary_types_allowed = True

    def __init__(self, env: simpy.Environment, network: Network, load_balancer: LoadBalancer, machine: Machine, **data):
        # Initialize BaseService (handles id, env, network, machine, callbacks, listen process)
        super().__init__(
            env=env,
            network=network,
            machine=machine,
            load_balancer=load_balancer,
            **data
        )

        # Create context logger
        self._context_logger = ContextLogger(f"ClientLibrary {self.id}", self.machine, self.env)

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] ClientLibrary {self.id} initialized.")

    def _handle_message(self, msg: NetworkMessage):
        """Handle received messages. Called by BaseService._listen_for_messages()."""
        log_prefix = self._context_logger._get_prefix(msg.request_context) if self._context_logger else f"[{self.machine.get_current_time(self.env.now):.4f}] ClientLibrary {self.id}"

        logger.info(f"{log_prefix} received message from {msg.sender_id}: {msg.payload.__class__.__name__}")

        if isinstance(msg.payload, Response):
            self._handle_response(msg.payload)

    def _handle_response(self, response: Response):
        if response.request_id in self.request_latencies:
            start_time = self.request_latencies[response.request_id]
            latency = self.machine.get_current_time(self.env.now) - start_time
            self.request_latencies[response.request_id] = latency # Store the actual latency
            logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] ClientLibrary {self.id}: Request {response.request_id} finished in {latency:.4f}s. Success: {response.success}")
            self.request_results[response.request_id] = response.success
            logger.debug(f"DEBUG: ClientLibrary {self.id} received response for {response.request_id} with success={response.success}")
        else:
            logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] ClientLibrary {self.id}: Received unexpected response for {response.request_id}.")

    def send_request(self, request: Request):
        if self.is_crashed:
            logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] ClientLibrary {self.id} is crashed, cannot send request {request.request_id}.")
            self.request_latencies[request.request_id] = 0.0 # Indicate immediate failure/no latency
            self.request_results[request.request_id] = False
            return

        gateway_id = self.load_balancer.get_next_gateway()
        self.request_latencies[request.request_id] = self.machine.get_current_time(self.env.now) # Store start time
        self.request_results[request.request_id] = False # Initialize result to False (pending/failed)
        if not gateway_id:
            logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] ClientLibrary {self.id}: No available Gateway Nodes to send request {request.request_id}.")
            self.request_latencies[request.request_id] = 0.0 # Indicate immediate failure/no latency
            return

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] ClientLibrary {self.id}: Sending {request.__class__.__name__} {request.request_id} to Gateway {gateway_id}.")
        self.network.send_message(
            NetworkMessage(
                sender_id=self.id,
                receiver_id=gateway_id,
                payload=request,
                timestamp=self.machine.get_current_time(self.env.now)
            )
        )
        yield self.env.timeout(0) # Allow other processes to run

    def put(self, key: str, value: str, metadata: Optional[List[str]] = None, ttl: Optional[int] = None):
        request_id = str(uuid.uuid4())
        put_request = PutRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            key=key,
            value=value,
            metadata=metadata,
            ttl=ttl
        )
        self.env.process(self.send_request(put_request))
        return request_id

    def get(self, key: str, consistency: ReadConsistency = ReadConsistency.LINEARIZABLE):
        request_id = str(uuid.uuid4())
        get_request = GetRequest(
            client_id=self.id,
            request_id=request_id,
            timestamp=self.machine.get_current_time(self.env.now),
            key=key,
            consistency=consistency
        )
        self.env.process(self.send_request(get_request))
        return request_id


ClientLibrary.model_rebuild()
