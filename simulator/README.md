# Lustre Filesystem Simulator

A Python-based discrete event simulator for the Lustre distributed parallel filesystem, built with SimPy.

## Overview

This simulator models the core distributed architecture of Lustre, including:
- **MGS** (Management Server): Configuration and service coordination
- **MDS** (Metadata Server): Filesystem namespace and metadata operations
- **OSS** (Object Storage Servers): File data storage across multiple OSTs
- **Clients**: File system operations and workload generation

## What Can Be Simulated

### ✅ Core Capabilities

- **File Operations**: create, read, write, delete, stat, open, close
- **Directory Operations**: mkdir, rmdir, listdir, rename
- **Extended Attributes**: setxattr, getxattr, listxattr, removexattr
- **Hard/Symbolic Links**: link, symlink, readlink with proper nlink tracking
- **File Striping**: Distribute file data across multiple OSTs
- **POSIX Semantics**: Timestamps (atime/mtime/ctime), permissions, ownership
- **Distributed Architecture**: Realistic message passing between components
- **Fault Injection**: Machine crashes, network partitions, disk failures
- **Resource Constraints**: Disk capacity, IOPS, throughput, network bandwidth limits
- **Performance Metrics**: Latency, throughput, resource utilization tracking

### ❌ Limitations

- **No Real LDLM**: Simplified locking (no distributed lock manager)
- **No Recovery**: No transaction replay or failover mechanisms
- **No Advanced Features**: No HSM, PCC, FLR, DNE, PFL, or quotas
- **Simplified FID**: Counter-based instead of SEQ:OID:VER scheme
- **No VFS Integration**: Direct API calls, not a real kernel filesystem
- **Simulated Performance**: Not suitable for real performance benchmarking

**Coverage**: ~5-10% of full Lustre API surface, focused on core operations.

## Use Cases

**Good For:**
- Understanding Lustre architecture
- Testing failure scenarios (network partitions, disk failures, component crashes)
- Capacity planning (storage sizing, OST count estimation)
- Workload modeling (file access patterns, read/write ratios)
- Educational purposes and prototyping

**Not Suitable For:**
- Concurrency/race condition testing (no real locking)
- Performance benchmarking (simulated, not real I/O)
- Production deployment planning (too simplified)
- Advanced feature development (missing HSM, DNE, etc.)

## Quick Start

### Prerequisites

- Python 3.9+
- uv (Python package manager)

### Installation

```bash
cd simulator/
uv sync  # Install dependencies
```

### Running

```bash
# Basic simulation
uv run simulation.py

# The simulation will:
# 1. Initialize MGS, MDS, OSS, and clients
# 2. Run predefined workloads (file_ops, dir_ops, metadata_ops, etc.)
# 3. Inject failures (optional)
# 4. Output metrics and trace logs
```

### Example Output

```
[0.0000] MGS mgs initialized
[0.1000] MDS mds_0 initialized with 1 MDTs
[0.2000] OSS oss_0 initialized with 2 OSTs
[0.5000] Client client_0 created file /test/file1.txt (FID: 0x200000001:0x2:0x0)
[1.2000] Client client_0 wrote 1048576 bytes to /test/file1.txt
[2.5000] OSS oss_0 disk full - returning ENOSPC
...
```

## Architecture

```
┌─────────────────────────────────────────┐
│  Clients (LustreClient)                 │
│  - File operations                      │
│  - Workload generation                  │
└────────┬───────────────────┬────────────┘
         │                   │
    ┌────▼─────┐      ┌──────▼────────┐
    │   MDS    │      │     OSS       │
    │ (Metadata)│      │  (Data)       │
    └────┬─────┘      └──────┬────────┘
         │                   │
         └───────┬───────────┘
              ┌──▼──┐
              │ MGS │
              │(Mgmt)│
              └─────┘
```

**Layers:**
- `components/`: Lustre-specific components (MGS, MDS, OSS, Client)
- `models/`: Data structures (requests/responses, metadata, internal types)
- `infra/`: Reusable distributed systems primitives (network, machines, fault injection)
- `workloads/`: Predefined test workloads

## Documentation

- **[SIMULATOR_VS_LUSTRE_CURRENT_STATE.md](./SIMULATOR_VS_LUSTRE_CURRENT_STATE.md)** - Comprehensive comparison with real Lustre (START HERE)
- **[API_COMPARISON.md](./API_COMPARISON.md)** - Detailed API coverage analysis (30 implemented / 200+ total)
- **[API_DISCREPANCIES.md](./API_DISCREPANCIES.md)** - Implementation status and known gaps
- **[ARCHITECTURE.md](./ARCHITECTURE.md)** - Simulator architecture and design patterns
- **[TODO.md](./TODO.md)** - Refactoring roadmap and improvement plan
- **[LUSTRE_SOURCE_ANALYSIS.md](./LUSTRE_SOURCE_ANALYSIS.md)** - Real Lustre implementation notes

## Project Status

**Completed Features:**
- ✅ Core file and directory operations
- ✅ Extended attributes with namespace validation
- ✅ Hard links with proper nlink tracking
- ✅ Atomic rename with target replacement
- ✅ Parent directory validation
- ✅ Timestamp management (atime/mtime/ctime)
- ✅ Disk capacity, IOPS, and throughput limits
- ✅ Network bandwidth and message simulation
- ✅ Fault injection framework

**Known Gaps:**
- ❌ Distributed locking (LDLM)
- ❌ Transaction layer (declare-execute pattern)
- ❌ Recovery and failover
- ❌ LinkEA (link extended attributes)
- ❌ Advanced features (HSM, PCC, FLR, DNE)

See [API_DISCREPANCIES.md](./API_DISCREPANCIES.md) for complete implementation status.

## Development

### Running Tests

```bash
# Run all workloads
uv run simulation.py

# Run specific workload (modify simulation.py)
# - file_ops: Basic file create/read/write/delete
# - dir_ops: Directory operations
# - metadata_ops: Extended attributes and metadata
# - link_ops: Hard links and symbolic links
```

### Adding Custom Workloads

See `simulator/workloads/` for examples. Workloads inherit from `BaseWorkload` and implement:

```python
class MyWorkload(BaseWorkload):
    def run(self):
        # Perform operations using self.client
        self.client.create_file("/myfile", mode=0o644)
        yield self.env.timeout(1.0)  # Simulate delay
        self.client.write("/myfile", b"data")
```

### Fault Injection

```python
from simulator.infra.fault_injector import FaultInjector

fault_injector = FaultInjector(env, network)
fault_injector.register_machine("oss_0", oss_machine)

# Crash OSS for 10 seconds
env.process(fault_injector.crash_machine("oss_0", duration=10.0))

# Create network partition
env.process(fault_injector.partition_azs("us-west", "us-east", duration=30.0))
```

## References

**Real Lustre Documentation:**
- Official Lustre Wiki: https://wiki.lustre.org/
- Lustre Manual: https://doc.lustre.org/
- Source Code: https://git.whamcloud.com/

**Simulator Documentation:**
- All markdown files in `simulator/` directory
- Inline code documentation (docstrings)

## License

This simulator is part of the Lustre project and follows the same license (GPL v2).

---

**Note:** This is a *simulation* for educational and research purposes. It does not implement the full Lustre protocol and should not be used for production deployment planning or performance benchmarking. For realistic testing, use an actual Lustre installation.
