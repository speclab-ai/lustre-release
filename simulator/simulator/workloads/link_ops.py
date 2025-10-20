"""Link operations workload."""
import random
import uuid
from typing import List
from simulator.workloads.base import BaseWorkload

import logging
logger = logging.getLogger(__name__)


class LinkOpsWorkload(BaseWorkload):
    """Workload for link operations (link, symlink, readlink)."""

    def run(self):
        """Run the link operations workload."""
        client = self.get_client()
        file_count = 0
        created_files: List[str] = []  # Track created files for linking
        created_symlinks: List[str] = []  # Track created symlinks for readlink

        while True:
            yield self.wait_interval()

            # Create some files first
            if file_count < 3:
                file_path = f"/linkfile_{file_count}"
                logger.info(f"[{self.env.now:.4f}] LinkOps: Creating file {file_path}")
                client.create_file(file_path, stripe_count=1)
                created_files.append(file_path)
                file_count += 1
                continue

            # Choose link operation
            operations = ['link', 'symlink']
            if created_symlinks:
                operations.append('readlink')

            operation = random.choice(operations)

            if operation == 'link' and created_files:
                existing_path = random.choice(created_files)
                link_path = f"/hardlink_{uuid.uuid4().hex[:8]}"
                logger.info(f"[{self.env.now:.4f}] LinkOps: Creating hard link "
                           f"{existing_path} -> {link_path}")
                client.link(existing_path, link_path)
                # Hard link points to same file, so add to created_files
                created_files.append(link_path)

            elif operation == 'symlink' and created_files:
                target_path = random.choice(created_files)
                link_path = f"/symlink_{uuid.uuid4().hex[:8]}"
                logger.info(f"[{self.env.now:.4f}] LinkOps: Creating symlink "
                           f"{link_path} -> {target_path}")
                client.symlink(target_path, link_path)
                created_symlinks.append(link_path)

            elif operation == 'readlink' and created_symlinks:
                link_path = random.choice(created_symlinks)
                logger.info(f"[{self.env.now:.4f}] LinkOps: Reading symlink {link_path}")
                client.readlink(link_path)
