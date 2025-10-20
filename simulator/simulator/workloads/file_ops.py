"""File operations workload."""
from simulator.workloads.base import BaseWorkload


class FileOpsWorkload(BaseWorkload):
    """Workload for file operations (create, open, close, read, write, delete)."""

    def run(self):
        """Run the file operations workload."""
        # To be implemented
        yield self.env.timeout(0)
