import simpy
import random
from typing import Dict, Optional, Tuple

from simulator.models.internal import NetworkMessage, NodeInfo, RequestContext
from simulator.models.api import Request, Response, PutRequest, GetRequest, ReadConsistency
from simulator.components.controller import Controller
from simulator.infra.network import Network
from simulator.infra.load_balancer import LoadBalancer
from simulator.infra.machine import Machine
from simulator.infra.base_service import BaseService
from simulator.infra.logger import ContextLogger
from simulator.models.metrics import MetricsCollector, ErrorCategory

import logging
logger = logging.getLogger(__name__)


class GatewayNode(BaseService):
    """Gateway node that routes client requests to appropriate data nodes.

    Refactored to use BaseService for common crash/recover patterns.
    """
    # BaseService provides: id, env, network, machine, is_crashed, _listen_process

    controller: Controller
    load_balancer: LoadBalancer
    az: str
    address: str
    is_up: bool = True
    pending_requests: Dict[str, Tuple[Request, str]] = {}
    metrics: 'MetricsCollector'
    _context_logger: Optional[ContextLogger] = None

    class Config:
        arbitrary_types_allowed = True

    def __init__(self, env: simpy.Environment, network: Network, controller: Controller, load_balancer: LoadBalancer, machine: Machine, az: str, address: str, metrics: 'MetricsCollector', **data):
        # Initialize BaseService (handles id, env, network, machine, callbacks, listen process)
        # Pass all parameters including gateway-specific ones
        super().__init__(
            env=env,
            network=network,
            machine=machine,
            controller=controller,
            load_balancer=load_balancer,
            az=az,
            address=address,
            metrics=metrics,
            **data
        )

        # Register node with AZ
        self.network.register_node(self.id, az_id=self.az)

        # Register with load balancer
        self.load_balancer.register_gateway(self.id)

        # Create context logger
        self._context_logger = ContextLogger(f"GatewayNode {self.id}", self.machine, self.env)

        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] GatewayNode {self.id} initialized in AZ {self.az}.")

    def _on_machine_fail(self, machine_id: str):
        """Override to add gateway-specific behavior on machine failure."""
        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] GatewayNode {self.id}: Underlying machine {machine_id} failed. Gateway going down.")
        self.is_up = False
        self.load_balancer.unregister_gateway(self.id)
        # Call base class crash()
        super()._on_machine_fail(machine_id)

    def _on_machine_recover(self, machine_id: str):
        """Override to add gateway-specific behavior on machine recovery."""
        logger.info(f"[{self.machine.get_current_time(self.env.now):.4f}] GatewayNode {self.id}: Underlying machine {machine_id} recovered. Gateway coming up.")
        self.is_up = True
        self.load_balancer.register_gateway(self.id)
        # Call base class recover()
        super()._on_machine_recover(machine_id)

    def _handle_message(self, msg: NetworkMessage):
        """Handle received messages. Called by BaseService._listen_for_messages()."""
        # Use context logger
        if self._context_logger:
            log_prefix_func = lambda ctx: self._context_logger._get_prefix(ctx)
        else:
            # Fallback if logger not initialized
            log_prefix_func = lambda ctx: f"[{self.machine.get_current_time(self.env.now):.4f}] GatewayNode {self.id}"

        log_prefix = log_prefix_func(msg.request_context)

        if not self.is_up:
            logger.info(f"{log_prefix} is down, dropping message from {msg.sender_id}: {msg.payload.__class__.__name__}")
            return

        logger.info(f"{log_prefix} received message from {msg.sender_id}: {msg.payload.__class__.__name__}")

        if isinstance(msg.payload, Request):
            self.env.process(self._handle_client_request(msg.payload, msg.sender_id, msg.request_context))
        elif isinstance(msg.payload, Response):
            self._handle_response(msg.payload, msg.request_context, log_prefix_func)

    def _handle_response(self, response: Response, request_context: Optional[RequestContext], log_prefix_func):
        """Handle response messages from data nodes."""
        request_id = response.request_id
        log_prefix = log_prefix_func(request_context)

        if request_id in self.pending_requests:
            original_request, client_id = self.pending_requests[request_id]

            if response.redirect_to:
                if not request_context:
                    request_context = RequestContext(request_id=request_id)

                if request_context.retries >= 5:
                    del self.pending_requests[request_id]
                    logger.error(f"{log_prefix}: Too many redirects for request {request_id}. Failing.")
                    self.metrics.increment_failure_reason(ErrorCategory.INFRASTRUCTURE_ERROR, "Too many redirects")
                    error_response = Response(request_id=request_id, timestamp=self.machine.get_current_time(self.env.now), success=False, message="Too many redirects")
                    self.network.send_message(
                        NetworkMessage(
                            sender_id=self.id,
                            receiver_id=client_id,
                            payload=error_response,
                            timestamp=self.machine.get_current_time(self.env.now),
                            request_context=request_context
                        )
                    )
                    return

                request_context.retries += 1
                self.metrics.increment_redirects()
                logger.info(f"{log_prefix}: Redirecting request {request_id} to {response.redirect_to}")
                self.network.send_message(
                    NetworkMessage(
                        sender_id=self.id,
                        receiver_id=response.redirect_to,
                        payload=original_request,
                        timestamp=self.machine.get_current_time(self.env.now),
                        request_context=request_context
                    )
                )
            else:
                # Final response
                del self.pending_requests[request_id]
                self.network.send_message(
                    NetworkMessage(
                        sender_id=self.id,
                        receiver_id=client_id,
                        payload=response,
                        timestamp=self.machine.get_current_time(self.env.now),
                        request_context=request_context
                    )
                )

    def _handle_client_request(self, request: Request, client_id: str, request_context: Optional[RequestContext]):
        """Handle client requests by routing to appropriate data nodes."""
        if self._context_logger:
            log_prefix = self._context_logger._get_prefix(request_context)
        else:
            log_prefix = f"[{self.machine.get_current_time(self.env.now):.4f}] GatewayNode {self.id}"

        self.pending_requests[request.request_id] = (request, client_id)
        routing_table = self.controller.get_routing_table()
        shard_id = self.controller.get_shard_for_key(request.key if hasattr(request, 'key') else "")  # Assuming key for routing

        target_node_id: Optional[str] = None

        if isinstance(request, PutRequest):
            target_node_id = routing_table.shard_to_leader.get(shard_id)
        elif isinstance(request, GetRequest):
            if request.consistency == ReadConsistency.LINEARIZABLE:
                target_node_id = routing_table.shard_to_leader.get(shard_id)
            else:  # STALE read
                replicas = routing_table.shard_to_replicas.get(shard_id, [])
                if replicas:
                    target_node_id = random.choice(replicas)
        # TODO: Handle Delete, AppendMetadata, List

        if target_node_id:
            logger.info(f"{log_prefix}: Resolved target_node_id: {target_node_id}. Forwarding {request.__class__.__name__} for {request.key if hasattr(request, 'key') else ''} to {target_node_id}.")
            self.network.send_message(
                NetworkMessage(
                    sender_id=self.id,  # Gateway is the sender when forwarding
                    receiver_id=target_node_id,
                    payload=request,
                    timestamp=self.machine.get_current_time(self.env.now),
                    request_context=request_context
                )
            )
        else:
            logger.info(f"{log_prefix}: No target node found for {request.__class__.__name__} for {request.key if hasattr(request, 'key') else ''}. Returning error. Current routing table: {routing_table}")
            self.metrics.increment_failure_reason(ErrorCategory.INFRASTRUCTURE_ERROR, "No target node available")
            error_response = Response(request_id=request.request_id, timestamp=self.machine.get_current_time(self.env.now), success=False, message="No target node available")
            self.network.send_message(
                NetworkMessage(
                    sender_id=self.id,
                    receiver_id=client_id,
                    payload=error_response,
                    timestamp=self.machine.get_current_time(self.env.now),
                    request_context=request_context
                )
            )
        yield self.env.timeout(0)  # Allow other processes to run


GatewayNode.model_rebuild()
