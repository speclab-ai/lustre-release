"""Metadata operations workload."""
from simulator.workloads.base import BaseWorkload


class MetadataOpsWorkload(BaseWorkload):
    """Workload for metadata operations (stat, getattr, setattr, rename)."""

    def run(self):
        """Run the metadata operations workload."""
        # To be implemented
        yield self.env.timeout(0)
