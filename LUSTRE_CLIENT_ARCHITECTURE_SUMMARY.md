# Lustre Client (LLITE) Architecture - Executive Summary

## Overview

The Lustre client implementation in `/lustre/llite/` is the Linux VFS layer that provides POSIX filesystem semantics to applications while communicating with distributed Lustre servers (MDS for metadata, OSS for data).

### Key Insight
The client has **two independent communication channels**:
1. **Metadata channel** (to MDS) - Handles file system operations
2. **Data channel** (to OSS) - Handles file content operations

These channels use different RPC protocols and lock mechanisms.

---

## Architecture Layers (Bottom-Up)

```
┌─────────────────────────────────┐
│  User Applications              │
├─────────────────────────────────┤
│  VFS (Linux Kernel)             │
├─────────────────────────────────┤
│  LLITE Layer                    │  ← Our main interest
│  (file.c, namei.c, dir.c,      │    Implementation logic
│   rw.c, xattr.c, etc.)         │    Call real MDS/OSS
├─────────────────────────────────┤
│  Cache Layer (cl_object)        │  Abstraction for caching
├─────────────────────────────────┤
│  LOV/LMV Layer                  │  Striping logic
├─────────────────────────────────┤
│  MDC/OSC Layers                 │  RPC client interfaces
├─────────────────────────────────┤
│  LDLM Lock Manager              │  Cache coherency
├─────────────────────────────────┤
│  PTLRPC Transport Layer         │  RPC over network
├─────────────────────────────────┤
│  Network (TCP, IB, O2IB)        │
└─────────────────────────────────┘
```

---

## Core Responsibilities

### LLITE Layer Handles

1. **File Operations**
   - Open/close with handle caching
   - Read/write with page cache optimization
   - Locking (flock, POSIX locks)
   - Seeking, truncation, fallocate

2. **Directory Operations**
   - Create/delete files and directories
   - Rename/move files
   - Readdir with hash-based iteration
   - Statahead optimization

3. **Metadata Operations**
   - Getting/setting attributes
   - Extended attributes (xattr)
   - ACLs
   - Encryption context

4. **Caching & Coherency**
   - Page cache coordination
   - Attribute caching
   - Lock-based invalidation
   - Read-ahead optimization

5. **Error Handling**
   - Lock conflicts
   - Network failures
   - Server unavailability
   - Grace period recovery

---

## How Metadata Operations Work

### Typical Sequence: File Creation

```
1. User: open("foo", O_CREAT)
2. VFS: calls ll_create_nd()
3. LLITE: Prepares md_op_data with parent FID, filename, mode
4. LLITE: Creates lookup_intent with IT_CREAT
5. LLITE: Calls ll_intent_lock() to send intent to MDS
6. PTLRPC: Serializes and sends RPC over network
7. MDS: Allocates inode, creates directory entry
8. MDS: Returns response with new inode metadata + lock grant
9. LDLM: Delivers lock handle to client
10. LLITE: Processes response, creates local inode
11. LLITE: Updates VFS inode cache with server metadata
12. VFS: Returns file descriptor to user
```

### Key Design Patterns

**Open Handle Caching**
- When a file is opened, the client gets an open handle from MDS
- Future opens to the same file can reuse this handle
- Closes only decrement reference count until last close
- Avoids close-open RPC round-trips

**Intent Operations**
- Client sends INTENT flag with operation (CREATE, LOOKUP, UNLINK)
- Server performs operation AND grants locks in one RPC
- Enables single round-trip for many operations
- Avoids separate lock acquisition

**FID-based Access**
- After first lookup, files referred to by FID (File ID) not name
- Path traversal only needed once per file
- Faster reconnection after network issues

---

## How Data Operations Work

### Typical Sequence: File Read

```
1. User: read(fd, buf, 4096)
2. VFS: calls ll_file_read_iter()
3. LLITE: Creates cl_io (cache layer IO context)
4. LLITE: Checks page cache
5. If pages missing:
   a. ll_readahead() predicts future access
   b. Schedules OSC READ RPCs for batched pages
   c. OSC combines pages into 1MB RPC
   d. RPC sent to OST over network
   e. OST reads data, sends response
   f. Pages placed in Linux page cache
6. LLITE: Copies from cache to user buffer
7. Return bytes read to user
```

### Optimizations

**Read-Ahead** (rw.c:738)
- Learns access patterns (sequential, random)
- Adaptively adjusts prefetch window
- Prevents repeated small RPCs
- Can prefetch 100s of pages at once

**Tiny Write** (file.c:2563)
- Writes <4KB directly to page cache
- If page already dirty, no server communication needed
- Huge latency savings for small buffered writes

**Page Cache Reuse**
- All read data goes to Linux page cache
- mmap uses same cache
- Read-only repeated opens share pages
- Direct IO can coexist with buffered

---

## Lock Management

### Two Levels of Locks

**LDLM Locks** (Lustre Distributed Lock Manager)
- Granted by MDS/OSS
- Protect server resources
- Modes: EX (exclusive), CW (concurrent write), CR, PR, NL
- Can be revoked when other clients need access

**Inode Bits Locks** (MDS-specific)
- `OPEN` - Protects open state
- `LOOKUP` - Protects name resolution
- `UPDATE` - Protects attributes/size
- `LAYOUT` - Protects stripe configuration
- `XATTR` - Protects extended attributes

### Lock Workflow

```
Client needs lock (e.g., for read):
  ↓
Send LDLM ENQUEUE RPC to server with resource FID and mode
  ↓
Server grants lock if compatible with other locks
  ↓
Server returns lock grant + server state (if intent operation)
  ↓
Client stores lock handle, uses for cache validation
  ↓
[If other client accesses]
  ↓
Server sends LDLM CANCEL callback
  ↓
Client drops cache for that range
  ↓
Client returns lock to server
```

---

## Critical Data Structures

### struct ll_inode_info (per-inode)
- Stores MDS open handles for read/write/exec modes
- Tracks reference counts to avoid unnecessary closes
- Caches attributes (size, times, permissions)
- Stores stripe metadata (layout generation, stripe count)
- Maintains dirty page information for HSM

### struct ll_file_data (per-file descriptor)
- Stores read-ahead state (current position, window)
- Tracks write failures for error reporting
- Holds designation for mirrored file IO
- Contains layout version for IO verification
- Links to statahead cache for directory reads

### struct md_op_data (metadata operation context)
- Parent and child FIDs
- Object name for lookup/create
- Attributes to set
- XATTR data if applicable
- Open flags and other hints

---

## Communication Protocol Patterns

### Metadata RPC Pattern
```
Client:
  ll_prep_md_op_data()        // Build operation data
  ll_intent_lock()            // Enqueue + intent
  ll_prep_inode()             // Process response
  
Server:
  1. Receives ENQUEUE RPC with intent flag
  2. Processes operation (create, lookup, etc.)
  3. Reads from LDLM for attribute locks
  4. Prepares response with metadata + lock grant
  5. Sends response
  
Timeline: ~2-5ms LAN, ~20-50ms WAN
```

### Data RPC Pattern
```
Client:
  do_file_read_iter()         // Initiate read
  cl_io_loop()                // Cache layer loop
  OSC batches pages           // Groups pages
  Send 1MB RPC                // Network transfer
  
Server:
  1. Receives READ RPC
  2. Reads from OST objects
  3. Packs response
  4. Sends over network
  
Timeline: ~1-2ms LAN read, network bandwidth limited (typically 10-100ms for 1MB)
```

---

## Performance Optimizations

### Caching Strategies

1. **Aggressive Page Caching**
   - All data goes to Linux page cache first
   - Survives application restarts (page cache stays)
   - Shared across processes
   - Subject to global kernel pressure

2. **Attribute Caching**
   - Cached until lock revoked
   - 24-hour soft timeout if needed
   - Quick getattr without server round-trip

3. **Lock Caching**
   - Open handles stay cached
   - Reused for repeated opens
   - Survives close if other opens active
   - Reduces CREATE round-trips

### Batching Optimizations

1. **Read-Ahead Batching**
   - Prefetch multiple pages in single RPC
   - Up to max 1MB per RPC
   - Reduces server load, improves throughput

2. **Write Batching**
   - Collect dirty pages
   - Send in 1MB chunks
   - Can write multiple stripes parallel

3. **Directory Prefetch (Statahead)**
   - Readdir + next stat in parallel
   - Benefits 'ls -l' by 100x+
   - Configurable via mount options

---

## What Makes This Implementation Interesting

### Challenges Solved

1. **Coherency Across Clients**
   - Multiple clients reading/writing same file
   - Solved with mandatory LDLM locks
   - Callbacks invalidate caches immediately

2. **Stateless Servers**
   - MDS handles thousands of clients
   - Uses FID instead of inode number
   - Handles network failures gracefully

3. **Distributed Filesystem Semantics**
   - Looks like local filesystem to apps
   - Actually distributed across network
   - Consistent with POSIX requirements

4. **Performance Under Scale**
   - Handles striping across many OSTs
   - Parallel data transfers
   - Batching reduces transaction count

### Elegant Design Patterns

1. **Intent Operations** - Combine lock + operation
2. **FID-based Navigation** - Path traversal once
3. **Handle Caching** - Reduce close-open overhead
4. **Two-level Locking** - Kernel VFS + network locks
5. **Callback-based Invalidation** - Event-driven cache coherency

---

## For Your Simulator Implementation

### Priorities

**Must Implement** (Core Path)
1. File open with handle caching
2. File read with page cache
3. File write with dirty tracking
4. File close with handle release
5. Basic metadata operations (create, unlink, mkdir)
6. Directory readdir with page caching

**Should Implement** (Performance)
1. Read-ahead prefetching
2. Tiny write optimization
3. Lock caching/reuse
4. Intent operations
5. Attribute caching

**Nice to Have** (Completeness)
1. Statahead (readdir optimization)
2. Multi-stripe handling
3. Lock revocation callbacks
4. Encryption/compression
5. PCC (Persistent Client Cache)

### Key Algorithms

**Hash-based Directory Navigation**
- Seek position = filename hash
- Entries with same hash in overflow pages
- Enables distributed directory striping

**Adaptive Read-Ahead**
- Track sequential vs random access
- Grow window on sequential access
- Shrink on random access
- Cap at available resources

**Smart Handle Caching**
- Keep handle until last close
- Track read/write/exec opens separately
- Reuse for subsequent opens
- Release LDLM lock only when cache not needed

---

## Resources for Implementation

### Documentation Files Created

1. **lustre_client_implementation_guide.md**
   - 450+ lines of detailed operation flows
   - Data structure explanations
   - RPC communication patterns
   - Lock management details

2. **lustre_implementation_quick_reference.md**
   - Tables of all key functions with line numbers
   - Data structure field explanations
   - Important constants and enums
   - Debugging tips and commands

### Key Source Files to Study

**Start Here** (In order)
1. `llite/llite_internal.h` - Key data structures
2. `llite/file.c:986-1200` - File open
3. `llite/file.c:412-467` - File close
4. `llite/file.c:2538-2715` - Read and write
5. `llite/namei.c:1567-1632` - File creation
6. `llite/rw.c:738+` - Read-ahead logic
7. `llite/dir.c:3027+` - Directory operations

**Then Study**
8. `llite/xattr.c` - Extended attributes
9. `llite/file.c:5563+` - Locking
10. `llite/llite_lib.c` - Utilities and init

---

## Key Takeaways

1. **Two Independent Paths**
   - Metadata ops use intent locks + MDS communication
   - Data ops use cache layer + OSC communication

2. **Handle-Based Caching**
   - Open handles enable lock reuse
   - Reduces server load significantly
   - Requires careful reference counting

3. **Lock-Driven Coherency**
   - All consistency through LDLM locks
   - Callbacks invalidate caches on-demand
   - No background invalidation needed

4. **Optimization is Everywhere**
   - Read-ahead for throughput
   - Tiny write for latency
   - Batching for efficiency
   - Caching at every level

5. **Distributed Filesystem Complexity**
   - Looks simple from application view
   - Complex machinery underneath
   - Handles network failures gracefully
   - Scales to thousands of clients

---

## Connecting to Real-World Usage

```bash
# What happens when user types:
$ cat /mnt/lustre/myfile

1. VFS opens file
   → LLITE: ll_file_open() creates handle
   → MDS ENQUEUE RPC (if first time)
   
2. VFS seeks to start
   → Page cache checked
   
3. VFS reads sequentially
   → LLITE: ll_readahead() predicts access
   → OSC schedules READ RPCs
   → OST returns data in parallel
   
4. VFS copies to terminal
   → Pages in cache reused
   
5. VFS closes file
   → LLITE: ll_file_release() decrements count
   → Handle kept cached for next open
```

Each step uses sophisticated caching and batching to minimize network traffic while maintaining consistency with multiple clients.

---

## Next Steps for Understanding

1. Read `lustre_client_implementation_guide.md` for flow diagrams
2. Reference `lustre_implementation_quick_reference.md` for specific line numbers
3. Study `file.c` for file operations first
4. Then study `namei.c` for metadata operations
5. Finally study `rw.c` for understanding cache layer integration
6. Use debugging commands to see real operations on live system

