"""Metadata operations workload."""
import random
import uuid
from typing import List
from simulator.workloads.base import BaseWorkload

import logging
logger = logging.getLogger(__name__)


class MetadataOpsWorkload(BaseWorkload):
    """Workload for metadata operations (stat, getattr, setattr, rename)."""

    def run(self):
        """Run the metadata operations workload."""
        client = self.get_client()
        file_count = 0
        created_files: List[str] = []  # Track created files for metadata operations

        while True:
            yield self.wait_interval()

            # Create some files first
            if file_count < 5:
                file_path = f"/metafile_{file_count}"
                logger.info(f"[{self.env.now:.4f}] MetadataOps: Creating file {file_path}")
                client.create_file(file_path, stripe_count=1)
                created_files.append(file_path)
                file_count += 1
                continue

            # Choose metadata operation
            operation = random.choice(['stat', 'getattr', 'setattr', 'rename'])

            if operation == 'stat' and created_files:
                file_path = random.choice(created_files)
                logger.info(f"[{self.env.now:.4f}] MetadataOps: Stat {file_path}")
                client.stat_file(file_path)

            elif operation == 'getattr' and created_files:
                file_path = random.choice(created_files)
                logger.info(f"[{self.env.now:.4f}] MetadataOps: Getattr {file_path}")
                client.getattr(file_path)

            elif operation == 'setattr' and created_files:
                file_path = random.choice(created_files)
                # Set random attributes
                mode = random.choice([0o644, 0o755, 0o600, 0o777])
                uid = random.randint(1000, 2000)
                gid = random.randint(1000, 2000)
                logger.info(f"[{self.env.now:.4f}] MetadataOps: Setattr {file_path} "
                           f"(mode={oct(mode)}, uid={uid}, gid={gid})")
                client.setattr(file_path, mode=mode, uid=uid, gid=gid)

            elif operation == 'rename' and created_files:
                old_path = random.choice(created_files)
                new_path = f"/renamed_{uuid.uuid4().hex[:8]}"
                logger.info(f"[{self.env.now:.4f}] MetadataOps: Rename {old_path} -> {new_path}")
                client.rename(old_path, new_path)
                # Update tracking
                created_files.remove(old_path)
                created_files.append(new_path)
