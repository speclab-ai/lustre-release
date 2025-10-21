# Lustre Client Implementation Guide (llite)

## Overview
The Lustre client (llite) is the VFS layer that implements the Linux filesystem interface for Lustre. It communicates with the MDS (Metadata Server) for metadata operations and with the OSS (Object Storage Server) for data operations.

### Architecture Layers
1. **VFS Layer** - Linux kernel filesystem interface (inode_operations, file_operations)
2. **LLITE Layer** - Lustre client logic (llite/)
3. **Cache Layer** - Coherent Local Object (cl_object) - abstracts caching
4. **LOV/LOD Layer** - Logical Object Volume - handles striping
5. **OSC/MDC Layer** - Object/Metadata Storage Clients - RPC communication
6. **LDLM Layer** - Lock management for cache coherency
7. **PTLRPC Layer** - RPC transport layer

---

## 1. FILE OPERATIONS

### Key Files
- `/home/user/lustre-release/lustre/llite/file.c` (7151 lines) - Main file operations
- `/home/user/lustre-release/lustre/llite/rw.c` (2211 lines) - Read/write cache operations
- `/home/user/lustre-release/lustre/llite/rw26.c` (1033 lines) - Kernel 2.6+ specific
- `/home/user/lustre-release/lustre/llite/vvp_io.c` (1905 lines) - VFS-to-cache layer

### File Operations Structure (file.c:6652)
```c
static const struct file_operations ll_file_operations = {
    .read_iter      = ll_file_read_iter,
    .write_iter     = ll_file_write_iter,
    .unlocked_ioctl = ll_file_ioctl,
    .open           = ll_file_open,
    .release        = ll_file_release,
    .mmap           = ll_file_mmap,
    .llseek         = ll_file_seek,
    .splice_read    = ll_splice_read,
    .fsync          = ll_fsync,
    .flush          = ll_flush,
    .fallocate      = ll_fallocate,
};
```

### File Open Operation (file.c:986)
**Function**: `ll_file_open(struct inode *inode, struct file *file)`

**Key Steps**:
1. Create `ll_file_data` structure (per-file context)
2. Create `lookup_intent` structure with open flags
3. Convert kernel open flags to MDS open flags
4. Check if there's already an open handle on MDS
5. If not, call `ll_intent_file_open()` to get MDS lock
6. Store MDS open handle (och) in inode/file context
7. Initialize read-ahead state for the file

**Data Structures**:
- `ll_file_data` - Per-file client-side state
- `obd_client_handle (och)` - MDS open handle
- `lookup_intent (it)` - Intent for MDS operation

### File Close Operation (file.c:412)
**Function**: `ll_file_release(struct inode *inode, struct file *file)`

**Key Steps**:
1. Get `ll_file_data` from `file->private_data`
2. Handle directory statahead cleanup if needed
3. Clear async RC for regular files
4. Call `ll_md_close()` to close MDS handle
5. Update file access statistics

**Internal Helper**: `ll_md_close()` (file.c:327)
- Checks for group locks and leases
- Decrements open count for read/write/exec modes
- Tests LDLM open lock for cache reuse
- Calls `ll_md_real_close()` if lock not held

### File Read Operation (file.c:2538)
**Function**: `ll_file_read_iter(struct kiocb *iocb, struct iov_iter *iter)`

**Implementation Path**:
1. `ll_file_read_iter()` - Entry point, handles unaligned DIO
2. `do_file_read_iter()` - Main read logic
3. Creates `lu_env` (Lustre execution environment)
4. Allocates `vvp_io_args` and initializes IO context
5. Creates `cl_io` (cache layer IO object)
6. Calls `cl_io_init()` and `cl_io_loop()`
7. Cache layer handles page cache and OSC communication

**Key Operations**:
- Read-ahead triggering via `ll_readahead()`
- Page cache management
- OSC RPC scheduling for OST read

### File Write Operation (file.c:2709)
**Function**: `ll_file_write_iter(struct kiocb *iocb, struct iov_iter *iter)`

**Implementation Path**:
1. `ll_file_write_iter()` - Entry point
2. Checks for tiny writes (< PAGE_SIZE) - `ll_do_tiny_write()`
   - Can write directly to page cache if page already dirty
   - Avoids full IO path
3. `do_file_write_iter()` - Main write logic
4. Creates `cl_io` with CIT_WRITE type
5. Handles group locks if needed
6. Schedules OSC RPCs for OST write

**Key Features**:
- Hybrid DIO/buffered write optimization
- Tiny write optimization for small writes
- Data version tracking for mirrors
- Layout verification for striped files

---

## 2. DIRECTORY OPERATIONS

### Key Files
- `/home/user/lustre-release/lustre/llite/dir.c` (3040 lines) - Directory operations
- `/home/user/lustre-release/lustre/llite/namei.c` (2617 lines) - Name resolution

### Directory Operations Structure (dir.c:3027)
```c
const struct file_operations ll_dir_operations = {
    .llseek         = ll_dir_seek,
    .open           = ll_dir_open,
    .release        = ll_dir_release,
    .read           = generic_read_dir,
    .iterate_shared = ll_iterate,  // or .readdir = ll_readdir
    .unlocked_ioctl = ll_dir_ioctl,
    .fsync          = ll_fsync,
    .flush          = ll_dir_flush,
};
```

### Directory Inode Operations (file.c:6708)
```c
const struct inode_operations ll_file_inode_operations = {
    .setattr      = ll_setattr,
    .getattr      = ll_getattr,
    .permission   = ll_inode_permission,
    .setxattr     = ll_setxattr,
    .getxattr     = ll_getxattr,
    .removexattr  = ll_removexattr,
    .listxattr    = ll_listxattr,
    // ... more operations
};
```

### Create File (namei.c)
**Function**: `ll_create_nd()` → `ll_create_it()` → `ll_create_node()`

**Process**:
1. `ll_create_nd()` - VFS entry point for file creation
2. Prepares `md_op_data` with parent inode, file name
3. Calls `ll_intent_lock()` with IT_CREAT intent
   - Sends CREATE RPC to MDS
   - MDS returns new inode metadata
4. `ll_create_node()` - Processes MDS response
5. Creates local inode from server data
6. Sets security context and encryption flags
7. Returns inode to VFS

**Key Functions**:
- `ll_prep_md_op_data()` - Prepare metadata operation data
- `md_create()` - Send CREATE RPC to MDS
- `ll_prep_inode()` - Process server inode data

### Create Directory (namei.c:2276)
**Function**: `ll_mkdir(struct inode *dir, struct dentry *dchild, umode_t mode)`

**Process**:
1. Calls `do_mkdir()` helper
2. Prepares `md_op_data` with parent, dir name, mode
3. Calls `md_create()` with IFDIR flag
4. Similar to file creation but for directories

### Remove Directory (namei.c:2288)
**Function**: `ll_rmdir(struct inode *dir, struct dentry *dchild)`

**Key Steps**:
1. Validates dentry (not mount point, foreign-dir removable)
2. Prepares `md_op_data` with parent, dir name, mode=IFDIR
3. Sets `op_fid3` to target directory's FID
4. Calls `md_unlink()` RPC
5. Updates parent inode times from response
6. Updates link count on local inode

**MDS Communication**: `md_unlink(ll_i2sbi(dir)->ll_md_exp, op_data, &request)`

### Directory Readdir (dir.c:3027)
**Function**: `ll_iterate()` or `ll_readdir()` (depending on kernel version)

**Key Features**:
- **Hash-based readdir**: Uses filename hash as seek position
- **Page caching**: Directory pages cached by hash
- **Statahead**: Prefetch stat info during readdir
- **Handles striped directories**: Multiple MDTs

**Process**:
1. Check cache for already-fetched directory pages
2. If needed, request pages from MDS via `ll_get_dir_page()`
3. Parse directory entries (lu_dirent structures)
4. Fill VFS dir context with entries
5. Trigger statahead for next entries

---

## 3. EXTENDED ATTRIBUTES (XATTR)

### Key Files
- `/home/user/lustre-release/lustre/llite/xattr.c` (1053 lines) - xattr operations
- `/home/user/lustre-release/lustre/llite/xattr_cache.c` (706 lines) - xattr caching
- `/home/user/lustre-release/lustre/llite/xattr_security.c` - Security xattr

### Inode Operations for XATTR (file.c:6712)
```c
#ifdef HAVE_IOP_XATTR
    .setxattr    = ll_setxattr,
    .getxattr    = ll_getxattr,
    .removexattr = ll_removexattr,
#endif
    .listxattr = ll_listxattr,
```

### Set XATTR (xattr.c)
**Function**: `ll_xattr_set_common()`

**Process**:
1. Validate xattr name and size
2. Convert xattr name to full name (with prefix)
3. Prepare `md_op_data` with xattr data
4. Call `md_setattr()` RPC to MDS
5. MDS updates xattr on object
6. Update xattr cache on client

**Key Handling**:
- **User xattrs**: require LL_SBI_USER_XATTR flag
- **ACL xattrs**: require LL_SBI_ACL flag
- **Trusted xattrs**: require CAP_SYS_ADMIN capability
- **Security xattrs**: handled by security module

### Get XATTR (xattr.c:745)
**Function**: `ll_listxattr(struct dentry *dentry, char *buffer, size_t size)`

**Features**:
- Returns all xattr names for an inode
- Special handling for LOV xattr (striping info)
- Builds list of xattr names with prefixes

**Special Case**: LOV xattr
- `ll_getxattr_lov()` - Gets layout/striping info
- Returns LOV metadata from inode structure
- No MDS RPC needed

---

## 4. FILE LOCKING (FLOCK)

### Key Files
- `/home/user/lustre-release/lustre/llite/file.c` - Flock/POSIX lock handling
- `/home/user/lustre-release/lustre/ldlm/` - LDLM lock manager

### Flock Operations (file.c:5563)
**Function**: `ll_file_flock(struct file *file, int cmd, struct file_lock *file_lock)`

**Process**:
1. Convert kernel file_lock to LDLM flock policy
2. **For lock acquisition**:
   - Call `ll_file_flock_lock()` to apply kernel lock
   - Send LDLM ENQUEUE RPC to MDS with flock policy
   - Store lock handle in client
3. **For unlock**:
   - Call `ll_file_flock_async_unlock()`
   - Send ENQUEUE with LCK_NL (null lock) to cancel
4. Handle async completion via `ll_flock_completion_ast_async()`

**Lock Modes**:
- `LCK_PR` - Protected read
- `LCK_CW` - Concurrent write
- `LCK_EX` - Exclusive
- `LCK_NL` - Null lock (for cancellation)

### LDLM Integration
**Structures**:
- `ldlm_lock` - LDLM lock descriptor
- `ldlm_resource` - Lock resource (identified by FID)
- `lustre_handle` - Lock handle reference
- `ldlm_enqueue_info` - Enqueue parameters

**Key Operations**:
```c
// Acquire lock
md_enqueue_async(exp, &einfo, callback, op_data, &flock, flags)

// Release lock
ldlm_lock_decref_and_cancel(&handle, mode)

// Test lock
md_lock_match(exp, flags, fid, type, policy, mode, bits, &handle)
```

### Completion Handling
- Server grants/denies lock
- LDLM calls completion callback `ll_flock_completion_ast_async()`
- Completion handler calls kernel lock function
- Notify application of lock status

---

## 5. MDS AND OSS COMMUNICATION

### Communication Flow Architecture

```
Application
    ↓
VFS (open, read, write, mkdir, etc.)
    ↓
LLITE (file.c, namei.c, dir.c)
    ├─→ MDS Communication (MDC)
    │   └─→ Metadata operations
    └─→ Data Communication (LOV→OSC)
        └─→ Read/Write operations
    ↓
PTLRPC (RPC transport)
    ↓
Network
```

### MDS Communication (Metadata)

#### Key Data Structures

**`md_op_data`** (from `lustre_md.h`):
- Parent inode FID
- Target inode FID
- Object name
- Attributes (size, mode, times)
- Valid mask
- Open flags
- XATTR data

**`lookup_intent`**:
- `it_op` - Operation type (IT_OPEN, IT_CREAT, IT_LOOKUP)
- `it_flags` - Operation flags
- `it_disposition` - Result flags

**`obd_client_handle`**:
- `och_open_handle` - MDS open handle
- `och_fh` - File handle
- `och_flags` - Open mode flags

#### Preparation: `ll_prep_md_op_data()` (from llite_lib.c)
1. Allocates `md_op_data` structure
2. Sets parent/child FIDs
3. Sets object name
4. Encodes attributes if needed
5. Returns prepared data for RPC

#### Intent Lock: `ll_intent_lock()` (file.c:763)
```c
rc = ll_intent_lock(sbi->ll_md_exp, op_data, itp, &req,
                    &ll_md_blocking_ast, 0, true);
```

**Purpose**: 
- Sends intent to MDS
- Enqueues lock on resource
- Returns server response with metadata

**Operations**:
- `IT_OPEN` - Open file/dir
- `IT_CREAT` - Create file
- `IT_LOOKUP` - Lookup by name
- `IT_GETATTR` - Get attributes
- `IT_UNLINK` - Unlink file

#### Standard Operations

**Create File/Dir**:
```c
md_create(sbi->ll_md_exp, op_data, data, datalen, mode, ...)
```

**Remove File/Dir**:
```c
md_unlink(ll_i2sbi(dir)->ll_md_exp, op_data, &request)
```

**Rename**:
```c
md_rename(sbi->ll_md_exp, op_data, ...)
```

**Set Attributes**:
```c
md_setattr(sbi->ll_md_exp, op_data, ...)
```

#### Lock Callback: `ll_md_blocking_ast()` (file.c:1245)
- Called when server revokes lock
- Drops client-side caches
- Returns lock to server

### OSS Communication (Data)

#### Read Path (file.c:2433 → rw.c)

**Flow**:
```
do_file_read_iter()
    ↓
cl_io_init(io, CIT_READ)
    ↓
cl_io_loop(io)
    ├─→ vvp_io_read_pages()
    ├─→ cl_page_cache_add()
    └─→ cl_io_rw_in_parallel()
        ↓
        OSC schedules READ RPC
        ↓
        OST returns data pages
        ↓
        Pages placed in page cache
```

**Key Operations**:
- `ll_readahead()` - Prefetch pages (rw.c:738)
- `ll_read_ahead_pages()` - Read ahead batch (rw.c:411)
- `ll_io_read_page()` - Single page read (rw.c:1702)
- `cl_io_read()` - Cache layer read

**Caching**: 
- Pages stored in Linux page cache
- Indexed by file offset
- LRU eviction managed by kernel

#### Write Path (file.c:2606 → rw.c)

**Flow**:
```
do_file_write_iter()
    ↓
Try ll_do_tiny_write() - if <PAGE_SIZE
    ↓
__generic_file_write_iter()
    ├─→ Direct to page cache
    └─→ No full RPC needed
    
OR

Full write via cl_io:
    ↓
cl_io_init(io, CIT_WRITE)
    ↓
cl_io_loop(io)
    ├─→ vvp_io_write_pages()
    ├─→ Mark pages dirty
    └─→ Schedule OSC WRITE RPC
        ↓
        OSC batches pages into RPC
        ↓
        Send to OST (size-limited)
        ↓
        OST commits to disk
        ↓
        Client receives completion
```

#### Cache Layer Integration (vvp_io.c)

**Key Functions**:
- `vvp_io_read_pages()` - Get pages for read
- `vvp_io_write_pages()` - Prepare pages for write
- `vvp_io_commit_write()` - Finalize write

**Page States**:
- `CPS_CACHED` - In page cache
- `CPS_BEING_IO` - Currently being written
- `CPS_PAGINATED` - Paginated to disk

#### OSC Layer (Object Storage Client)

**Responsible for**:
- Batching pages into RPCs
- Maintaining IO queues
- Handling OST responses
- Stripe selection for LOV

**RPC Size**: Typically 1MB (configurable)

### LDLM Locks for Cache Coherency

**Extent Locks** (data):
- Protect page cache ranges
- Granted in EX (exclusive) or PR (protected read)
- Revoked when other clients access

**Inode Bits Locks**:
- `MDS_INODELOCK_OPEN` - File open lock
- `MDS_INODELOCK_LAYOUT` - Layout (striping) lock
- `MDS_INODELOCK_UPDATE` - Attributes lock
- `MDS_INODELOCK_XATTR` - Extended attributes lock

**Lock Callback Chain**:
```
Server cancels lock
    ↓
LDLM delivers cancel callback
    ↓
llite blocking AST (ll_md_blocking_ast)
    ↓
Drop caches (pages, attributes)
    ↓
Return lock to server
```

---

## 6. KEY DATA STRUCTURES

### `struct ll_inode_info` (llite_internal.h:134)
Per-inode client state:
- `lli_fid` - Object FID from server
- `lli_clob` - Cached object (page cache)
- `lli_mds_*_och` - Open handles (read/write/exec)
- `lli_attr_valid` - Cached attribute validity
- `lli_open_fd_*_count` - Open count by mode
- `lli_layout_gen` - Stripe layout version
- `lli_flags` - Inode flags (DATA_MODIFIED, etc.)

### `struct ll_file_data` (llite_internal.h:1144)
Per-file handle state:
- `fd_file` - Kernel file pointer
- `fd_och` - Non-lease open handle
- `fd_lease_och` - Lease open handle
- `fd_ras` - Read-ahead state
- `fd_write_failed` - Write failure flag
- `fd_designated_mirror` - Mirror selection (for mirrored files)
- `fd_pcc_file` - PCC (Persistent Client Cache) state

### `struct md_op_data` (lustre_md.h)
Metadata operation parameters:
- `op_fid1`, `op_fid2`, `op_fid3` - FIDs
- `op_attr` - Attributes
- `op_valid` - Attribute valid mask
- `op_name`, `op_namelen` - Object name
- `op_data`, `op_data_size` - Extended data (xattr)
- `op_open_flags` - Open flags
- `op_cli_flags` - Client flags

### `struct ll_sb_info` (llite_internal.h:885)
Per-superblock state:
- `ll_md_exp` - MDS export
- `ll_dt_exp` - OST export list
- `ll_cache` - Cache context
- `ll_flags` - Feature flags
- `ll_nameset` - Sysfs namespace

---

## 7. OPERATION FLOW DIAGRAMS

### File Open Flow
```
User: open("file.txt", O_RDONLY)
    ↓
VFS: llite_file_open()
    ↓
Check existing MDS open handle
    ├─ Found → Increment count → Return
    └─ Not found → Continue
    ↓
Create lookup_intent (IT_OPEN)
    ↓
ll_intent_file_open(dentry, NULL, 0, &intent)
    ├─ Prepare md_op_data
    ├─ Call ll_intent_lock()
    │   ├─ Pack RPC with filename/FID and open flags
    │   └─ Send to MDS
    ├─ Receive response with server inode metadata
    └─ ll_prep_inode() - Process server metadata
    ↓
Store MDS open handle in inode
    ↓
Create ll_file_data structure
    ↓
Return file handle to user
```

### File Read Flow
```
User: read(fd, buf, 1000)
    ↓
VFS: ll_file_read_iter()
    ↓
do_file_read_iter()
    ├─ Create lu_env context
    ├─ Create cl_io (cache layer IO)
    ├─ cl_io_init(io, CIT_READ)
    └─ cl_io_loop()
        ├─ Check page cache
        ├─ Missing pages?
        │   ├─ ll_readahead() - Prefetch nearby pages
        │   ├─ Schedule OSC READ RPCs
        │   └─ Wait for OST responses
        └─ Copy pages to user buffer
    ↓
Return bytes read
```

### File Write Flow
```
User: write(fd, buf, 1000)
    ↓
VFS: ll_file_write_iter()
    ↓
Check if tiny write (<PAGE_SIZE) → Yes
    ├─ Write directly to page cache if page dirty
    └─ Return immediately
    
    OR full write path:
    ├─ do_file_write_iter()
    ├─ Create cl_io (CIT_WRITE)
    ├─ __generic_file_write_iter()
    │   ├─ Get/create page cache pages
    │   ├─ Copy user data to pages
    │   └─ Mark pages dirty
    ├─ Schedule OSC WRITE RPCs (1MB batches)
    └─ Wait for commits (configurable: wait/background)
    ↓
Return bytes written
```

### Directory Create Flow
```
User: open("newfile", O_CREAT)
    ↓
VFS: ll_create_nd()
    ↓
ll_create_it()
    ├─ Prepare md_op_data (parent FID, name, mode)
    ├─ Create lookup_intent (IT_CREAT)
    ├─ ll_intent_lock()
    │   ├─ Pack RPC with parent FID, filename
    │   └─ Send CREATE intent to MDS
    ├─ MDS processes:
    │   ├─ Allocate new inode
    │   ├─ Create direntry
    │   └─ Return new inode metadata
    ├─ ll_prep_inode() - Process new inode metadata
    ├─ Create local inode
    └─ d_instantiate(dentry, inode)
    ↓
Return file handle
```

### Directory Readdir Flow
```
User: readdir(dirfd)
    ↓
VFS: ll_iterate()
    ↓
ll_dir_read()
    ├─ Check cache for directory pages
    ├─ If missing → ll_get_dir_page()
    │   ├─ Prepare md_op_data
    │   ├─ Request directory page via GETATTR intent
    │   ├─ MDS returns lu_dirent structures
    │   └─ Cache page
    ├─ Trigger statahead for next entries
    ├─ Parse lu_dirent entries
    └─ Fill VFS dir context with entries
    ↓
Return entries to user
```

---

## 8. IMPORTANT CONFIGURATION & OPTIMIZATION POINTS

### Feature Flags (ll_sb_info->ll_flags)
- `LL_SBI_ACL` - ACL support
- `LL_SBI_USER_XATTR` - User xattr
- `LL_SBI_FAST_READ` - Fast read (page cache checking)
- `LL_SBI_FILE_HEAT` - File heat tracking
- `LL_SBI_PARALLEL_DIO` - Parallel direct IO
- `LL_SBI_UNALIGNED_DIO` - Unaligned direct IO support

### Optimizations

**Tiny Write Optimization** (file.c:2563):
- For writes <PAGE_SIZE that hit already-dirty pages
- Avoids full IO path
- Saves latency

**Read-Ahead** (rw.c:738):
- Context-based: tracks access patterns
- Adaptive: adjusts window size
- Prevents thundering herd on server

**Statahead** (statahead.c):
- Prefetch inode stats during readdir
- Caches inodes for subsequent getattr
- Significant performance win for 'ls -l'

**Lock Caching**:
- Reuses MDS open locks when possible
- Avoids close-open RPC on seek/reopen

---

## 9. COMPARISON WITH SIMULATOR

### Areas for Simulator Implementation
1. **MDS RPC Protocol** - Intent locks, metadata operations
2. **OSC READ/WRITE** - Data RPC batching, stripe selection
3. **LDLM Locks** - Lock granting/revocation, callbacks
4. **Page Cache** - Coherency, lock-protected ranges
5. **Dir Hashing** - Hash-based directory readdir
6. **Statahead** - Prefetch during readdir
7. **Lock Modes** - PR/CW/EX for data, ibits for metadata
8. **IO Optimization** - Tiny writes, read-ahead adaptation

### Files to Study First
1. **file.c** - All basic operations
2. **namei.c** - Create/unlink/lookup
3. **dir.c** - Readdir and directory handling
4. **rw.c** - Read/write caching
5. **llite_lib.c** - Client initialization, utility functions
6. **llite_internal.h** - Data structures and inline functions

### RPC Patterns
- Metadata ops use `md_*` functions (through MDC)
- Data ops use `cl_io` loop (through LOV→OSC)
- All RPCs serialized through PTLRPC layer
- Callbacks handle async completion

