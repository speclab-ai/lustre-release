"""Directory operations workload."""
import random
import uuid
from typing import List
from simulator.workloads.base import BaseWorkload

import logging
logger = logging.getLogger(__name__)


class DirOpsWorkload(BaseWorkload):
    """Workload for directory operations (mkdir, rmdir, list)."""

    def run(self):
        """Run the directory operations workload."""
        client = self.get_client()
        created_dirs: List[str] = []  # Track created directories

        while True:
            yield self.wait_interval()

            # Choose operation based on state
            if created_dirs:
                operation = random.choice(['mkdir', 'list', 'rmdir'])
            else:
                operation = 'mkdir'

            if operation == 'mkdir':
                dir_path = f"/testdir_{uuid.uuid4().hex[:8]}"
                logger.info(f"[{self.env.now:.4f}] DirOps: Creating directory {dir_path}")
                client.mkdir(dir_path)
                created_dirs.append(dir_path)

            elif operation == 'list':
                # List either root or one of the created directories
                if random.random() < 0.5 or not created_dirs:
                    dir_path = "/"
                else:
                    dir_path = random.choice(created_dirs)
                logger.info(f"[{self.env.now:.4f}] DirOps: Listing directory {dir_path}")
                client.list_dir(dir_path)

            elif operation == 'rmdir' and created_dirs:
                dir_path = random.choice(created_dirs)
                logger.info(f"[{self.env.now:.4f}] DirOps: Removing directory {dir_path}")
                client.rmdir(dir_path)
                created_dirs.remove(dir_path)
