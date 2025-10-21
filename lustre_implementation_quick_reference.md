# Lustre Client Implementation - Quick Reference

## Core Files Summary

| File | Lines | Purpose |
|------|-------|---------|
| file.c | 7,151 | File open/close/read/write, locking |
| llite_lib.c | 4,448 | Client initialization, utilities |
| pcc.c | 4,330 | Persistent Client Cache |
| namei.c | 2,617 | Create/delete/rename operations |
| dir.c | 3,040 | Directory operations, readdir |
| rw.c | 2,211 | Read/write cache operations |
| vvp_io.c | 1,905 | VFS-to-cache layer abstraction |
| statahead.c | 2,801 | Directory stat prefetch |
| xattr.c | 1,053 | Extended attributes |
| llite_internal.h | Data structures and inline functions |

---

## Key Functions by Operation

### FILE OPEN/CLOSE

| Operation | Function | File | Line | Purpose |
|-----------|----------|------|------|---------|
| Open | ll_file_open() | file.c | 986 | Open file, get MDS handle |
| Close | ll_file_release() | file.c | 412 | Close file, release MDS handle |
| Internal | ll_md_close() | file.c | 327 | Close MDS handle logic |
| Intent | ll_intent_file_open() | file.c | 706 | Send open intent to MDS |

### FILE READ/WRITE

| Operation | Function | File | Line | Purpose |
|-----------|----------|------|------|---------|
| Read Entry | ll_file_read_iter() | file.c | 2,538 | Kernel read entry point |
| Read Main | do_file_read_iter() | file.c | 2,433 | Main read implementation |
| Write Entry | ll_file_write_iter() | file.c | 2,709 | Kernel write entry point |
| Write Main | do_file_write_iter() | file.c | 2,606 | Main write implementation |
| Tiny Write | ll_do_tiny_write() | file.c | 2,563 | Optimized small write |
| Readahead | ll_readahead() | rw.c | 738 | Prefetch pages |
| Read Pages | ll_read_ahead_pages() | rw.c | 411 | Batch read ahead |
| Read Page | ll_io_read_page() | rw.c | 1,702 | Single page read |

### DIRECTORY OPERATIONS

| Operation | Function | File | Line | Purpose |
|-----------|----------|------|------|---------|
| Create File | ll_create_nd() | namei.c | ~1,700+ | Create file |
| Create Node | ll_create_node() | namei.c | Main creation logic | |
| Create Intent | ll_create_it() | namei.c | 1,567 | Process create result |
| Mkdir | ll_mkdir() | namei.c | 2,276 | Create directory |
| Rmdir | ll_rmdir() | namei.c | 2,288 | Remove directory |
| Readdir | ll_iterate() | dir.c | Hash-based iteration | |
| Get Dir Page | ll_get_dir_page() | dir.c | Fetch directory page | |
| Dir Read | ll_dir_read() | dir.c | Parse directory entries | |

### EXTENDED ATTRIBUTES

| Operation | Function | File | Line | Purpose |
|-----------|----------|------|------|---------|
| Set XATTR | ll_xattr_set_common() | xattr.c | 80 | Set extended attribute |
| Get XATTR | ll_listxattr() | xattr.c | 745 | List all xattrs |
| Get LOV | ll_getxattr_lov() | xattr.c | 667 | Get stripe layout |

### FILE LOCKING

| Operation | Function | File | Line | Purpose |
|-----------|----------|------|------|---------|
| Flock | ll_file_flock() | file.c | 5,563 | File lock/unlock |
| Flock Lock | ll_file_flock_lock() | file.c | 5,396 | Apply kernel lock |
| Flock Unlock | ll_file_flock_async_unlock() | file.c | 5,426 | Async unlock |
| Lock Callback | ll_flock_completion_ast_async() | file.c | 5,424 | Lock grant callback |
| No Flock | ll_file_noflock() | file.c | 5,989 | Return ENOSYS |

### MDS COMMUNICATION

| Operation | Function | File | Purpose |
|-----------|----------|------|---------|
| Prep MD Op | ll_prep_md_op_data() | llite_lib.c | Prepare metadata operation |
| Intent Lock | ll_intent_lock() | Via mdc export | Send intent + enqueue lock |
| Finish Op | ll_finish_md_op_data() | llite_lib.c | Clean up after operation |
| Prep Inode | ll_prep_inode() | llite_lib.c | Process server inode data |
| Blocking AST | ll_md_blocking_ast() | file.c | 1,245 | Lock revocation handler |

---

## Data Structures

### struct ll_inode_info (per-inode state)

```
Location: llite_internal.h:134

Key Fields:
- lli_fid                    // Object FID from server
- lli_clob                   // Cached object (page cache)
- lli_mds_read_och           // MDS read open handle
- lli_mds_write_och          // MDS write open handle
- lli_mds_exec_och           // MDS exec open handle
- lli_open_fd_read_count     // Reference count for read
- lli_open_fd_write_count    // Reference count for write
- lli_open_fd_exec_count     // Reference count for exec
- lli_attr_valid             // Cached attribute validity
- lli_layout_gen             // Stripe layout version
- lli_flags                  // Inode state flags
- lli_och_mutex              // Protect open handle changes
- lli_lsm_obj                // Stripe metadata object
```

### struct ll_file_data (per-file handle state)

```
Location: llite_internal.h:1144

Key Fields:
- fd_file                    // Kernel file pointer
- fd_och                     // Regular open handle
- fd_lease_och               // Lease open handle
- fd_ras                     // Read-ahead state
- fd_write_failed            // Write failure flag
- fd_open_mode               // Open mode (MDS_FMODE_*)
- fd_designated_mirror       // Mirror for IO
- fd_layout_version          // Layout version for IO
- fd_grouplock               // Group lock state
- fd_pcc_file                // PCC cache state
- fd_sai                     // Statahead info
```

### struct md_op_data (metadata operation)

```
Location: lustre_md.h

Key Fields:
- op_fid1                    // Parent FID
- op_fid2                    // Child FID (target)
- op_fid3                    // Additional FID
- op_attr                    // Attributes
- op_valid                   // Valid attribute mask
- op_name                    // Object name
- op_namelen                 // Name length
- op_mode                    // File mode
- op_data                    // Extended data (xattr, etc)
- op_data_size               // Extended data size
- op_open_flags              // Open flags
- op_cli_flags               // Client flags
- op_bias                    // Operation bias
```

### struct lookup_intent (operation intent)

```
Key Fields:
- it_op                      // Operation (IT_OPEN, IT_CREAT, etc)
- it_open_flags              // Open flags
- it_flags                   // Intent flags
- it_disposition             // Result disposition
- it_status                  // Operation status
- it_lock_mode               // Lock mode granted
- it_lock_handle             // Lock handle
```

---

## RPC Communication Patterns

### Metadata Operation Flow

```
1. Prepare: ll_prep_md_op_data()
   ├─ Allocate md_op_data
   ├─ Set FIDs (parent, child)
   ├─ Set name
   └─ Set attributes if needed

2. Lock: ll_intent_lock() [for intent operations]
   ├─ Create lookup_intent
   ├─ Pack RPC with md_op_data
   ├─ Send to MDS via MDC export
   ├─ MDS processes and responds
   ├─ LDLM grants lock if needed
   └─ Return with metadata

3. Process: ll_prep_inode()
   ├─ Unpack server response
   ├─ Update local inode
   └─ Update attribute cache

4. Cleanup: ll_finish_md_op_data()
   ├─ Release md_op_data
   └─ Clean up temporary buffers
```

### Standard Operations (non-intent)

```
md_create() / md_unlink() / md_rename()
    ├─ Prepare md_op_data
    ├─ Call md_* function through export
    ├─ PTLRPC packs and sends RPC
    ├─ MDC sends to MDS
    ├─ MDS processes
    ├─ Response returned
    └─ Caller processes ptlrpc_request
```

### Data Operation Flow

```
do_file_read_iter() or do_file_write_iter()
    ├─ Create lu_env context
    ├─ Create vvp_io_args
    ├─ Create cl_io (cache layer IO)
    ├─ cl_io_init()
    ├─ cl_io_loop()
    │   ├─ VVP layer handling
    │   ├─ LOV stripe selection
    │   ├─ OSC batch formation
    │   └─ PTLRPC RPC scheduling
    ├─ Wait for completion
    └─ Process results
```

---

## Important Constants and Enums

### Open Modes (from mdc_local.h)

```c
MDS_FMODE_READ      0x01    // Read mode
MDS_FMODE_WRITE     0x02    // Write mode
MDS_FMODE_EXEC      0x04    // Execute mode
MDS_OPEN_CREAT      0x08    // Create flag
MDS_OPEN_EXCL       0x10    // Exclusive
MDS_OPEN_BY_FID     0x20    // Open by FID (not name)
MDS_OPEN_OWNEROVERRIDE 0x40 // Owner override
```

### Intent Operations

```c
IT_OPEN             // Open operation
IT_CREAT            // Create operation
IT_LOOKUP           // Lookup operation
IT_GETATTR          // Get attributes
IT_SETATTR          // Set attributes
IT_UNLINK           // Unlink operation
IT_RENAME           // Rename operation
IT_RENAME_TGET      // Rename target
```

### LDLM Lock Modes

```c
LCK_EX              // Exclusive lock
LCK_CW              // Concurrent write
LCK_CR              // Concurrent read
LCK_PR              // Protected read
LCK_PW              // Protected write
LCK_NL              // Null lock (for cancellation)
```

### MDS Inode Locks

```c
MDS_INODELOCK_OPEN      // Open lock
MDS_INODELOCK_LOOKUP    // Lookup lock
MDS_INODELOCK_UPDATE    // Update (attributes) lock
MDS_INODELOCK_LAYOUT    // Layout (stripe) lock
MDS_INODELOCK_XATTR     // Extended attributes lock
MDS_INODELOCK_DOM       // Data on MDT lock
```

---

## Reading Order for Understanding Implementation

1. **Start with basics**:
   - llite_internal.h - Key data structures
   - llite_lib.c - Initialization and utilities
   - file.c lines 986-1200 - File open implementation

2. **Understand file operations**:
   - file.c lines 412-467 - File close
   - file.c lines 2538-2604 - File read
   - file.c lines 2709-2715 - File write

3. **Learn directory operations**:
   - namei.c lines 1567-1632 - Create file
   - namei.c lines 2288-2350 - Remove directory
   - dir.c - Directory readdir

4. **Study advanced features**:
   - file.c lines 5396-5563 - File locking
   - xattr.c - Extended attributes
   - rw.c - Read-ahead optimization

5. **Understand communication**:
   - file.c lines 706-810 - Intent lock
   - file.c lines 327-405 - MDS close
   - rw.c - Cache layer interaction

---

## Debugging Tips

### Enable Debug Logging
```bash
# See all LLITE debug messages
sysctl -w lustre.llite.debug=0xffffffff

# See only file operations
sysctl -w lustre.llite.debug=0x1  # DLMTRACE
```

### Trace Operations
```bash
# Trace file operations
strace -e open,openat,read,write,close ls /mnt/lustre

# Trace network traffic (requires tcpdump)
tcpdump -i lo -n dst port 988  # MDS default port
```

### Check Client State
```bash
# See mounted filesystems
mount | grep lustre

# Check proc for llite stats
cat /proc/fs/lustre/llite/*/stats

# See client cache info
cat /proc/fs/lustre/llite/*/cached_mb
```

---

## Connection to Your Simulator

### What You Need to Simulate

1. **MDS Communication Module**
   - Implement intent lock RPC protocol
   - Handle CREATE, UNLINK, LOOKUP operations
   - Manage open handles (och)
   - Track reference counts

2. **OSC Communication Module**
   - Implement READ/WRITE RPC batching
   - Handle stripe selection
   - Manage extent locks
   - Track page cache coherency

3. **Page Cache Module**
   - Manage Linux page cache
   - Handle dirty page tracking
   - Implement LRU eviction
   - Track page states

4. **Lock Manager (LDLM)**
   - Grant/revoke locks
   - Handle blocking callbacks
   - Manage lock modes
   - Track lock resources by FID

5. **State Tracking**
   - ll_inode_info per-inode state
   - ll_file_data per-file handle state
   - Open handle caching
   - Attribute caching

### Key Algorithms to Implement

- **Hash-based readdir**: Use filename hash as seek position
- **Read-ahead**: Adaptive window adjustment based on access pattern
- **Tiny write optimization**: Avoid RPC for small buffered writes
- **Lock caching**: Reuse locks for repeated opens
- **Statahead**: Prefetch stats during directory iteration

