"""Directory operations workload."""
from simulator.workloads.base import BaseWorkload


class DirOpsWorkload(BaseWorkload):
    """Workload for directory operations (mkdir, rmdir, list)."""

    def run(self):
        """Run the directory operations workload."""
        # To be implemented
        yield self.env.timeout(0)
