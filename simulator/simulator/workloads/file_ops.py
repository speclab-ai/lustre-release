"""File operations workload."""
import random
import uuid
from typing import Dict
from simulator.workloads.base import BaseWorkload

import logging
logger = logging.getLogger(__name__)


class FileOpsWorkload(BaseWorkload):
    """Workload for file operations (create, open, close, read, write, seek, fsync, delete)."""

    def run(self):
        """Run the file operations workload."""
        client = self.get_client()
        file_count = 0
        open_files: Dict[str, int] = {}  # path -> fd mapping

        while True:
            yield self.wait_interval()

            # Choose operation based on state
            operations = ['create']
            if file_count > 0:
                operations.extend(['write', 'read', 'delete', 'open', 'stat'])
            if open_files:
                operations.extend(['close', 'seek', 'fsync'])

            operation = random.choice(operations)

            if operation == 'create':
                file_path = f"/testfile_{file_count}"
                stripe_count = random.choice([1, 2, 4])
                logger.info(f"[{self.env.now:.4f}] FileOps: Creating file {file_path} "
                           f"with stripe_count={stripe_count}")
                client.create_file(file_path, stripe_count=stripe_count)
                file_count += 1

            elif operation == 'open' and file_count > 0:
                file_path = f"/testfile_{random.randint(0, file_count-1)}"
                flags = random.choice(['r', 'w', 'r+'])
                logger.info(f"[{self.env.now:.4f}] FileOps: Opening file {file_path} with flags {flags}")
                client.open_file(file_path, flags=flags)
                # Simulate file descriptor tracking
                open_files[file_path] = random.randint(3, 1000)  # Simulated FD

            elif operation == 'close' and open_files:
                file_path = random.choice(list(open_files.keys()))
                fd = open_files[file_path]
                logger.info(f"[{self.env.now:.4f}] FileOps: Closing file {file_path} (fd={fd})")
                client.close_file(file_path, fd=fd)
                del open_files[file_path]

            elif operation == 'write' and file_count > 0:
                fid = f"0x200000000:0x{random.randint(1, file_count)}:0x0"
                data = f"data_{uuid.uuid4()}"
                oss_id = self.get_random_oss_id()
                offset = random.randint(0, 1000) * 4096  # Aligned to 4KB
                logger.info(f"[{self.env.now:.4f}] FileOps: Writing {len(data)} bytes to FID {fid} at offset {offset}")
                client.write_file(fid, offset=offset, data=data, oss_id=oss_id)

            elif operation == 'read' and file_count > 0:
                fid = f"0x200000000:0x{random.randint(1, file_count)}:0x0"
                oss_id = self.get_random_oss_id()
                offset = random.randint(0, 10) * 4096
                size = random.choice([4096, 8192, 16384])
                logger.info(f"[{self.env.now:.4f}] FileOps: Reading {size} bytes from FID {fid} at offset {offset}")
                client.read_file(fid, offset=offset, size=size, oss_id=oss_id)

            elif operation == 'seek' and open_files:
                fid = f"0x200000000:0x{random.randint(1, file_count)}:0x0"
                offset = random.randint(0, 100) * 4096
                whence = random.choice(['SET', 'CUR', 'END'])
                logger.info(f"[{self.env.now:.4f}] FileOps: Seeking FID {fid} to offset {offset} (whence={whence})")
                client.seek_file(fid, offset=offset, whence=whence)

            elif operation == 'fsync' and open_files:
                fid = f"0x200000000:0x{random.randint(1, file_count)}:0x0"
                oss_id = self.get_random_oss_id()
                logger.info(f"[{self.env.now:.4f}] FileOps: Fsyncing FID {fid}")
                client.fsync_file(fid, oss_id=oss_id)

            elif operation == 'stat' and file_count > 0:
                file_path = f"/testfile_{random.randint(0, file_count-1)}"
                logger.info(f"[{self.env.now:.4f}] FileOps: Stat {file_path}")
                client.stat_file(file_path)

            elif operation == 'delete' and file_count > 0:
                file_path = f"/testfile_{random.randint(0, file_count-1)}"
                logger.info(f"[{self.env.now:.4f}] FileOps: Deleting {file_path}")
                client.delete_file(file_path)
