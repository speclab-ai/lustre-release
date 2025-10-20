"""Base workload class for Lustre simulator workloads."""
import simpy
import random
from typing import List, Dict, Any
from abc import ABC, abstractmethod

import logging
logger = logging.getLogger(__name__)


class BaseWorkload(ABC):
    """Base class for all workload generators."""

    def __init__(self, env: simpy.Environment, client_id: str,
                 clients: Dict[str, Any], oss_servers: Dict[str, Any],
                 request_interval: float = 0.01):
        """Initialize base workload.

        Args:
            env: SimPy environment
            client_id: ID of the client running this workload
            clients: Dictionary of all clients
            oss_servers: Dictionary of all OSS servers
            request_interval: Average time between requests in seconds
        """
        self.env = env
        self.client_id = client_id
        self.clients = clients
        self.oss_servers = oss_servers
        self.request_interval = request_interval

    def get_client(self):
        """Get the client instance."""
        return self.clients[self.client_id]

    def get_random_oss_id(self) -> str:
        """Get a random OSS ID."""
        if not self.oss_servers:
            raise ValueError("No OSS servers available")
        return random.choice(list(self.oss_servers.keys()))

    def wait_interval(self):
        """Wait for a random interval around the configured request interval."""
        delay = self.request_interval * random.uniform(0.8, 1.2)
        return self.env.timeout(delay)

    @abstractmethod
    def run(self):
        """Run the workload. Must be implemented by subclasses."""
        pass
