# Lustre Client Exploration - Documentation Index

## Overview
This directory contains comprehensive documentation about how the real Lustre client (LLITE) implements file operations, directory operations, extended attributes, file locking, and communication with MDS and OSS.

## Documentation Files

### 1. LUSTRE_CLIENT_ARCHITECTURE_SUMMARY.md
**Length**: ~8KB | **Read Time**: 15-20 minutes

High-level architectural overview suitable for getting started. Covers:
- Architecture layers (9 layers from user to network)
- Two communication channels (metadata vs data)
- Core responsibilities of LLITE
- How metadata and data operations work
- Lock management (2 levels)
- Performance optimizations
- Implementation priorities for simulator

**Start here if**: You want quick understanding of overall architecture

### 2. lustre_client_implementation_guide.md
**Length**: ~21KB | **Read Time**: 45-60 minutes

Comprehensive deep-dive with detailed operation flows. Covers:
- File operations (open, close, read, write)
- Directory operations (create, readdir, rmdir)
- Extended attributes (setxattr, getxattr, listxattr)
- File locking (FLOCK, LDLM, lock modes)
- MDS and OSS communication patterns
- Complete data structures
- RPC communication flow diagrams
- Configuration and optimization points

**Read after**: Understanding basic architecture

### 3. lustre_implementation_quick_reference.md
**Length**: ~12KB | **Reference Guide**

Quick lookup tables and reference material:
- File sizes and purposes of each source file
- Functions with exact line numbers (file:line format)
- Data structure field definitions
- Constants and enums (open modes, lock modes, intent types)
- RPC communication patterns
- Debugging commands
- Reading order recommendations

**Use as**: Quick lookup while reading source code

---

## Key Files in /lustre/llite Directory

### By Function Size (Lines of Code)

```
file.c              7,151  ← Start here (all file operations)
llite_lib.c         4,448  ← Then here (utilities, init)
pcc.c               4,330  (Persistent Client Cache - optional)
namei.c             2,617  ← Read next (create/delete/rename)
dir.c               3,040  ← Then directory operations
statahead.c         2,801  (Readdir optimization)
rw.c                2,211  ← Read/write cache layer
vvp_io.c            1,905  (VFS-to-cache abstraction)
xattr.c             1,053  ← Extended attributes
rw26.c              1,033  (Kernel 2.6+ specific)
llite_internal.h          ← Data structures (read with file.c)
```

### By Functionality

**Essential Core Files**
- `file.c` - File open/close/read/write/locking
- `namei.c` - File/dir creation and deletion
- `dir.c` - Directory iteration
- `rw.c` - Read/write cache management
- `llite_internal.h` - Key data structures

**Important Secondary Files**
- `llite_lib.c` - Client initialization, utilities
- `xattr.c` - Extended attributes
- `vvp_io.c` - Cache layer integration

**Advanced/Optional Files**
- `statahead.c` - Directory readahead optimization
- `pcc.c` - Persistent client cache
- `crypto.c` - Encryption support
- `acl.c` - ACL handling

---

## Key Concepts You Need to Understand

### 1. Open Handle Caching
**Files**: file.c, llite_internal.h

The client caches MDS open handles to avoid repeated CREATE/OPEN/CLOSE RPCs:
- First open: Talk to MDS, get handle
- Subsequent opens: Reuse handle, increment refcount
- Last close: Release handle to server

### 2. Intent Operations
**Files**: file.c (ll_intent_lock), namei.c

Combined lock + operation in single RPC:
- CREATE: Send intent to create file
- LOOKUP: Send intent to get attributes
- MDS: Performs operation and grants locks
- Result: Single round-trip instead of two

### 3. Two Communication Channels
**Files**: file.c (metadata), rw.c (data), llite_lib.c

Metadata operations (create/unlink/getattr):
- Use MDS (Metadata Server) via MDC client
- RPC pattern: Prepare → Send intent → Process response

Data operations (read/write):
- Use OSS (Object Storage Server) via OSC client
- Via cache layer: cl_io abstraction
- RPC pattern: Batching → Send RPCs → Cache pages

### 4. Lock Modes and Coherency
**Files**: file.c, llite_internal.h, ldlm headers

LDLM lock modes for data:
- EX (Exclusive) - Only one writer
- CW (Concurrent Write) - Multiple writers allowed
- CR (Concurrent Read) - Many readers
- PR (Protected Read) - Read protection

Lock revocation via callbacks:
- Server sends CANCEL when another client needs access
- Client drops cache
- Returns lock to server

### 5. Page Cache Integration
**Files**: rw.c, vvp_io.c

All read data goes to Linux page cache:
- Indexed by file offset
- Managed by kernel LRU
- Survives application crashes
- Used by read-ahead, mmap, regular read

---

## Study Path

### For Quick Understanding (1-2 hours)
1. Read: LUSTRE_CLIENT_ARCHITECTURE_SUMMARY.md
2. Skim: lustre_implementation_quick_reference.md
3. Glance at: file.c lines 986-1200 (open)

### For Moderate Understanding (4-6 hours)
1. Read: LUSTRE_CLIENT_ARCHITECTURE_SUMMARY.md (20 min)
2. Read: lustre_client_implementation_guide.md sections 1-4 (40 min)
3. Study: file.c:986-1200 (open) with reference guide (30 min)
4. Study: file.c:412-467 (close) (20 min)
5. Study: namei.c:1567-1632 (create) (30 min)
6. Skim: file.c:2538-2715 (read/write) (20 min)

### For Deep Understanding (12-16 hours)
1. Read all three documentation files (2 hours)
2. Study file.c completely (3-4 hours)
3. Study namei.c completely (2-3 hours)
4. Study dir.c operations (1-2 hours)
5. Study rw.c operations (1-2 hours)
6. Study xattr.c operations (1 hour)
7. Study locking in file.c (1-2 hours)
8. Practice with live system (2-3 hours)

---

## Function Cross-Reference

### File Open/Close
- VFS Entry: `ll_file_open()` file.c:986
- VFS Entry: `ll_file_release()` file.c:412
- Core Logic: `ll_md_close()` file.c:327
- Intent: `ll_intent_file_open()` file.c:706
- Prep: `ll_prep_md_op_data()` llite_lib.c
- Process: `ll_prep_inode()` llite_lib.c

### File Read
- VFS Entry: `ll_file_read_iter()` file.c:2538
- Core: `do_file_read_iter()` file.c:2433
- Readahead: `ll_readahead()` rw.c:738
- Batch: `ll_read_ahead_pages()` rw.c:411
- Single: `ll_io_read_page()` rw.c:1702

### File Write
- VFS Entry: `ll_file_write_iter()` file.c:2709
- Core: `do_file_write_iter()` file.c:2606
- Tiny: `ll_do_tiny_write()` file.c:2563

### Directory Operations
- Create: `ll_create_nd()` namei.c:~1900+
- Create: `ll_create_it()` namei.c:1567
- Mkdir: `ll_mkdir()` namei.c:2276
- Rmdir: `ll_rmdir()` namei.c:2288
- Readdir: `ll_iterate()` dir.c

### Locking
- Flock: `ll_file_flock()` file.c:5563
- Apply: `ll_file_flock_lock()` file.c:5396
- Unlock: `ll_file_flock_async_unlock()` file.c:5426
- Callback: `ll_flock_completion_ast_async()` file.c:5424

### Extended Attributes
- Set: `ll_xattr_set_common()` xattr.c:80
- List: `ll_listxattr()` xattr.c:745
- LOV: `ll_getxattr_lov()` xattr.c:667

---

## Important Data Structures

### Per-Inode State
- `struct ll_inode_info` (llite_internal.h:134)
- Contains: FID, open handles, cached attributes, lock state

### Per-File Handle State
- `struct ll_file_data` (llite_internal.h:1144)
- Contains: Read-ahead state, write failures, mirror selection

### Metadata Operation
- `struct md_op_data` (lustre_md.h)
- Contains: FIDs, names, attributes, open flags

### Operation Intent
- `struct lookup_intent` (lustre_intent.h)
- Contains: Operation type, flags, disposition, lock info

---

## Debugging on Live System

```bash
# Enable Lustre debug logging
sysctl -w lustre.llite.debug=0xffffffff

# Check mounted Lustre filesystems
mount | grep lustre

# View client statistics
cat /proc/fs/lustre/llite/*/stats

# Check cached memory
cat /proc/fs/lustre/llite/*/cached_mb

# Trace operations
strace -e open,openat,read,write,close,ioctl ls /mnt/lustre

# Network traffic capture
tcpdump -i lo port 988  # MDS port
```

---

## Quick Architecture Diagram

```
┌──────────────────┐
│  User App        │
├──────────────────┤
│  Linux VFS       │
├──────────────────┤
│  LLITE Layer     │ ← Our focus
├──────────────────┤
│  Cache (cl_io)   │
├──────────────────┤
│  LOV/LMV         │
├──────────────────┤
│  MDC/OSC         │ → RPC to servers
├──────────────────┤
│  LDLM Locks      │
├──────────────────┤
│  PTLRPC          │ → Network
└──────────────────┘
```

---

## Document Statistics

| Document | Size | Type | Purpose |
|----------|------|------|---------|
| LUSTRE_CLIENT_ARCHITECTURE_SUMMARY | 8KB | Summary | Architecture overview |
| lustre_client_implementation_guide | 21KB | Guide | Detailed flows |
| lustre_implementation_quick_reference | 12KB | Reference | Function tables |
| CLIENT_EXPLORATION_INDEX | This file | Index | Navigation |

Total: ~52KB of documentation covering llite architecture and implementation

---

## Simulator Implementation Checklist

### Phase 1: Core (Essential)
- [ ] File open with handle caching
- [ ] File close with handle release
- [ ] Basic file read (no read-ahead)
- [ ] Basic file write (direct write)
- [ ] File create via MDS
- [ ] File delete via MDS
- [ ] Directory readdir (basic iteration)

### Phase 2: Performance (Important)
- [ ] Read-ahead prefetching
- [ ] Write batching (1MB chunks)
- [ ] Tiny write optimization
- [ ] Handle cache reuse
- [ ] Lock caching

### Phase 3: Advanced (Nice to Have)
- [ ] Statahead during readdir
- [ ] Multi-stripe read/write
- [ ] Lock revocation callbacks
- [ ] Encryption support
- [ ] PCC (persistent cache)

---

## See Also

- EXPLORATION_SUMMARY.md - Previous exploration results
- LUSTRE_MDS_ARCHITECTURE.md - Server-side implementation
- MDS_KEY_FILES_SUMMARY.md - MDS source file guide
- ANSWERS.md - Specific implementation questions

---

## Contact Points in Codebase

When you start reading the code:
- Start with: `llite_internal.h` (data structures)
- Then study: `file.c` (file operations)
- Compare patterns in: `namei.c` (name operations)
- Understand caching via: `rw.c` (read/write cache)

Each file builds on concepts from previous files.

