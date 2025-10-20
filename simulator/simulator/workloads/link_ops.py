"""Link operations workload."""
from simulator.workloads.base import BaseWorkload


class LinkOpsWorkload(BaseWorkload):
    """Workload for link operations (link, symlink, readlink)."""

    def run(self):
        """Run the link operations workload."""
        # To be implemented
        yield self.env.timeout(0)
