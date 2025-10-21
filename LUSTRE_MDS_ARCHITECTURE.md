# Lustre Real MDS Implementation Architecture Analysis

## Overview

The Lustre Metadata Server (MDS) is implemented in two main layers:
- **MDT (Metadata Target)**: Request handler layer - receives and processes client RPCs
- **MDD (Metadata Device)**: Implementation layer - executes the actual metadata operations on the underlying storage

This is a classic layer architecture where MDT acts as the frontend and MDD as the backend, both coordinating through a shared interface.

---

## 1. ARCHITECTURE LAYERS

### MDT Layer (lustre/mdt/)
- **Role**: Network request handler
- **Responsibilities**:
  - RPC request parsing and unpacking
  - Client credential processing
  - Locking coordination (LDLM - Lustre Distributed Lock Manager)
  - Permission checking
  - Transaction coordination
  - Version-based recovery (VBR)
  - Reply caching for resent requests

### MDD Layer (lustre/mdd/)
- **Role**: Metadata operation implementation
- **Responsibilities**:
  - Directory operations (lookup, insert, delete)
  - Object creation and deletion
  - Attribute manipulation
  - Extended attributes and ACLs
  - Linkea (link EA) management
  - Changelog recording
  - Orphan handling
  - ChangeLog garbage collection

### Data Flow
```
Client RPC Request
    ↓
[MDT] mdt_handler.c - Parse request
    ↓
[MDT] mdt_reint.c - Route to operation handler (create/delete/rename/setattr)
    ↓
[MDT] mdt_lib.c - Setup locking, prepare parameters
    ↓
[MDD] mdd_dir.c / mdd_object.c - Execute actual operation
    ↓
[DT] dt_device (storage layer) - Write to disk
    ↓
[MDT] Pack response, return to client
```

---

## 2. KEY DATA STRUCTURES

### MDT Core Structures

#### struct mdt_device (mdt_internal.h:225-342)
- **Purpose**: Root MDT device object
- **Key Fields**:
  ```c
  struct ldlm_namespace *mdt_namespace;        // DLM lock namespace
  struct md_device *mdt_child;                 // Underlying MDD device
  struct dt_device *mdt_bottom;                // Storage (OSD) device
  struct lu_target mdt_lut;                    // Target device base
  struct coordinator mdt_coordinator;          // HSM coordinator
  struct mdt_dir_restriper mdt_restriper;     // Directory auto-split
  ```
- **Capabilities**: Configurable features like ACLs, user xattrs, CoS (Commit on Share)

#### struct mdt_object (mdt_internal.h:349-380)
- **Purpose**: Server-side metadata object wrapper
- **Key Fields**:
  ```c
  struct lu_object_header mot_header;
  unsigned int mot_lov_created:1;   // LOV object created
  int mot_write_count;               // Write operation counter
  struct rw_semaphore mot_dom_sem;  // Data-on-MDT lock
  struct rw_semaphore mot_open_sem; // Lease/open lock
  atomic_t mot_lease_count;
  atomic_t mot_open_count;
  ```
- **Purpose**: Tracks open files, lease operations, write operations

#### struct mdt_thread_info (mdt_internal.h:451-582)
- **Purpose**: Per-thread context - allocated per request to reduce stack usage
- **Key Components**:
  ```c
  struct req_capsule *mti_pill;           // Request/reply marshalling
  struct mdt_lock_handle mti_lh[MDT_LH_NR]; // Lock handles (8 types)
  struct mdt_reint_record mti_rr;         // Reintegration record
  struct md_attr mti_attr;                // Object attributes
  struct mdt_object *mti_object;          // Working object
  __u64 mti_transno;                      // Transaction number
  ```
- **Lock Handle Types**: PARENT, CHILD, OLD, LAYOUT, NEW, RMT, LOCAL, LOOKUP

#### struct mdt_lock_handle (mdt_internal.h:382-400)
- **Purpose**: Encapsulates all lock information for an operation
- **Components**:
  ```c
  struct lustre_handle mlh_reg_lh;   // Regular lock handle
  struct lustre_handle mlh_pdo_lh;   // Parent directory operation lock
  struct lustre_handle mlh_rreg_lh;  // Remote regular lock
  enum ldlm_mode mlh_reg_mode;       // Lock mode (PR, PW, EX)
  ```

### MDD Core Structures

#### struct mdd_device (mdd_internal.h:121-152)
- **Purpose**: MDD layer device
- **Key Fields**:
  ```c
  struct md_device mdd_md_dev;           // MD device interface
  struct dt_device *mdd_child;           // Underlying OSD device
  struct dt_object *mdd_orphans;         // PENDING orphan directory
  struct mdd_changelog mdd_cl;           // ChangeLog metadata
  struct lu_fid mdd_root_fid;            // Root FID
  struct mdd_object *mdd_dot_lustre;     // .lustre directory
  ```
- **Features**: ACL support, ChangeLog management, orphan handling, striped directories

#### struct mdd_object (mdd_internal.h:161-173)
- **Purpose**: MDD layer object
- **Key Fields**:
  ```c
  struct md_object mod_obj;
  struct lu_fid mod_striped_pfid;  // Master dir parent FID (for striped dirs)
  u32 mod_count;                    // Open count
  unsigned long mod_flags;          // DEAD_OBJ, ORPHAN_OBJ, VOLATILE_OBJ
  struct list_head mod_users;       // Unique user opens
  ```
- **Flags**: DEAD_OBJ (unlinked), ORPHAN_OBJ (in PENDING), VOLATILE_OBJ

#### struct mdd_thread_info (mdd_internal.h:177-208)
- **Purpose**: Per-thread context for MDD operations
- **Key Fields**:
  ```c
  struct lu_fid mdi_fid, mdi_fid2;
  struct lu_attr mdi_pattr, mdi_cattr;  // Parent and child attributes
  struct lu_dirent mdi_ent;             // Directory entry
  char mdi_key[NAME_MAX + 16];          // Lookup key
  struct lu_buf mdi_buf[4];             // Working buffers
  struct linkea_data mdi_link_data;     // LinkEA data
  struct md_op_spec mdi_spec;           // Operation spec
  ```

#### struct mdt_reint_record (mdt_internal.h:428-440)
- **Purpose**: Encapsulates metadata operation parameters
- **Fields**:
  ```c
  enum mds_reint_op rr_opcode;    // CREATE, UNLINK, RENAME, SETATTR, LINK, RMDIR, OPEN
  const struct lu_fid *rr_fid1;   // First FID
  const struct lu_fid *rr_fid2;   // Second FID
  struct lu_name rr_name;         // Filename
  struct lu_name rr_tgt_name;     // Target filename (for rename)
  void *rr_eadata;                // Extended attribute data
  int rr_eadatalen;               // EA data length
  __u32 rr_flags;                 // Flags (MRF_OPEN_TRUNC, MRF_OPEN_RESEND)
  ```

---

## 3. METADATA OPERATIONS

### 3.1 CREATE Operation

**Flow**: `mdt_reint_create()` → `mdd_create()` → `mdd_create_object_internal()`

**MDT Layer (mdt_reint.c)**:
```
1. Unpack request: parent FID, filename, mode, EA data
2. Acquire locks:
   - Parent directory write lock (PDO - parent directory operations lock)
   - Allocate new FID for child
3. Permission check: parent directory must be writable
4. Start transaction
5. Call MDD create
6. Pack response with child FID, attributes, and LOV metadata
```

**MDD Layer (mdd_dir.c/mdd_object.c)**:
```
1. Check if parent is a directory
2. Check permission (MAY_WRITE | MAY_EXEC on parent)
3. Verify child doesn't already exist
4. Lock parent directory (write)
5. Create object:
   - mdo_create_object(): creates underlying dt_object
   - dt_create() on storage layer
6. Insert into parent directory:
   - mdo_declare_index_insert()
   - dt_insert() with FID → filename mapping
7. Update parent directory:
   - mtime, ctime, link count
8. Record changelog entry (if enabled)
9. Unlock parent
```

**Key Points**:
- FID allocation happens at MDT level
- PDO locks prevent concurrent creates/deletes in same directory
- LinkEA created for hard links
- Changelog tracks all creates for audit/backup

---

### 3.2 DELETE/UNLINK Operation

**Flow**: `mdt_reint_unlink()` → `mdd_unlink()` → `mdd_finish_unlink()`

**MDT Layer**:
```
1. Lookup child by filename in parent
2. Acquire locks:
   - Parent write lock
   - Child lock (to prevent operations during deletion)
3. Start transaction
4. Check conditions: file not in use, correct FID
5. Call MDD unlink
6. Update parent directory entry count
```

**MDD Layer**:
```
1. Check preconditions:
   - Parent must be directory (mdd_may_delete check)
   - Object exists
   - No name conflicts
2. Update LinkEA:
   - Remove parent/filename entry from link EA
   - If last link, mark object for deletion
3. Delete from parent directory:
   - dt_delete() removes directory entry
4. If last link (link count = 0):
   - Move object to PENDING orphan directory
   - Set DEAD_OBJ flag
5. Update parent directory:
   - Decrement link count
   - Update mtime/ctime
6. Record changelog: DELETE or UNLINK
```

**Key Points**:
- Multiple links supported via LinkEA
- Last-unlink moves object to PENDING directory
- DEAD_OBJ flag tracks unlinked objects
- Cleanup deferred until reference count = 0

---

### 3.3 RENAME Operation

**Flow**: `mdt_reint_rename()` → Uses mdd_dir.c operations

**MDT Layer**:
```
1. Lookup source and target
2. Acquire locks in FID order:
   - Source parent write lock
   - Target parent write lock (if different)
   - Source child lock
   - Target child lock (if exists)
3. Check source != target
4. Start transaction
5. Call MDD rename via mdd_dir operations
```

**MDD Layer**:
```
For rename source → target:
1. Validate both parents are directories
2. Validate target doesn't exist (if not cross-directory)
3. Update LinkEA:
   - Update parent FID/name in source LinkEA
   - Remove from source parent
   - Add to target parent
4. Directory updates:
   - Delete entry from source parent
   - Insert entry in target parent
5. Cross-directory rename:
   - Update parent pointer if target is directory
   - Adjust link counts
6. Update both parent directories:
   - mtime, ctime modifications
7. Record changelog: RENAME with oldname/newname
```

**Lock Strategy**:
```
FID comparison to prevent deadlock:
  if (src_fid < tgt_fid):
    lock(src_parent)
    lock(tgt_parent)
  else:
    lock(tgt_parent)
    lock(src_parent)
```

**Key Points**:
- Rename is atomic transaction
- Cross-directory support with parent pointer updates
- LinkEA tracks all rename history
- Deadlock prevention via FID ordering

---

### 3.4 SETATTR Operation

**Flow**: `mdt_reint_setattr()` → `mdd_attr_set()`

**MDT Layer**:
```
1. Get object FID
2. Acquire layout lock if changing stripes
3. Start transaction
4. Call MDD setattr
5. Pack updated attributes in response
```

**MDD Layer**:
```
1. Lock object for write (DT_TGT_CHILD)
2. Get current attributes
3. Update requested attributes:
   - Mode (permissions)
   - Size (for truncation)
   - mtime/atime/ctime
   - Owner (uid/gid)
   - Flags (encryption, SUID, etc.)
4. Call dt_attr_set() on storage layer
5. Update ctime if needed
6. Record changelog if enabled
7. Unlock object
```

**Special Cases**:
- **Truncation**: Updates size, may involve data cleaning
- **Encryption**: Sets LUSTRE_ENCRYPT_FL flag and xattr
- **Mode changes**: May update ACLs if present

---

## 4. DIRECTORY MANAGEMENT

### Directory Structure

**Metadata**:
- Stored as B-tree indexed directory on underlying filesystem
- Entries: filename → FID mapping
- Special entries: "." (self), ".." (parent)

**LinkEA**:
- Extended attribute storing parent directory + filename
- Format: Multiple (parent_FID, filename) pairs
- Used for:
  - Hard link tracking
  - Rename tracking
  - File path reconstruction

**Striped Directories (Directory Sharding)**:
```
Master directory has:
  - LMV (Lustre Metadata Vector) EA
  - Stripe information (count, hash type)
  
Striped directory structure:
  Master Dir
    ├── Shard 0 (MDT 0)
    ├── Shard 1 (MDT 1)
    ├── Shard 2 (MDT 2)
    └── Shard N (MDT N)
    
Each shard independently indexed on its MDT
Hash determines which shard holds entry
```

### Key Directory Operations

#### mdd_lookup (mdd_dir.c:94-110)
```c
int mdd_lookup(env, parent_md_obj, name, fid, spec):
  1. Get parent attributes (permission check)
  2. Check parent is directory
  3. Permission check (MAY_EXEC)
  4. dt_lookup() on parent's dt_object
  5. Return child FID
```

#### mdd_dir_layout_split (for auto-split)
```
When directory exceeds split threshold:
1. Allocate stripe count for resharding
2. Create new shard directories
3. Migrate entries:
   - Read old directory
   - Hash each entry to new shard
   - Insert in target shard
4. Update master LMV EA
5. Atomically switch layout
```

---

## 5. FID (File Identifier) MANAGEMENT

### FID Structure

**FID Format**: `[SEQ:OID:VER]`
- **SEQ** (16 bits): Sequence number - identifies object allocation pool
- **OID** (32 bits): Object ID within sequence
- **VER** (16 bits): Version for object reuse

**Example**: `[0x200000404:0x2a5:0x0]` = SEQ=0x200000404, OID=0x2a5, VER=0x0

### FID Allocation

**MDT Role in FID Allocation**:
```
1. MDT contacts Sequence Server (can be local or remote)
2. Seq Server allocates FID ranges
3. MDT caches range locally
4. Per-request allocation from cache
```

**FID Types**:
- **Regular FID**: `[SEQ > 0, OID, VER]` - normal files
- **Root FID**: `[0x200000404, 0x0, 0x0]` - filesystem root
- **OBF FID**: `[0x100000000, N, 0x0]` - .obf (Objects By FID) special directory
- **LPF FID**: For lost+found (LFSCK recovery)

### FID Implications for Simulator

**Key Differences from Inode**:
1. **Globally unique**: Same FID across all MDTs and time
2. **Never recycled**: VER changes if OID reused
3. **Distributed allocation**: Multiple MDTs allocate independently
4. **Persistent**: Survives rename, migration, etc.
5. **Hierarchical knowledge**: SEQ encodes allocation context

---

## 6. LOCKING AND CONCURRENCY CONTROL

### Lock Types

#### LDLM (Lustre Distributed Lock Manager) Locks

**Lock Modes**:
```
NULL    - No lock
CR      - Concurrent Read
CW      - Concurrent Write
PR      - Protected Read (blocks CR/CW)
PW      - Protected Write (blocks all)
EX      - Exclusive (blocks all)
```

**Lock Bits (for IBITS locks)**:
```
MDS_INODELOCK_LOOKUP   - Directory entry lookup
MDS_INODELOCK_UPDATE   - Attribute updates
MDS_INODELOCK_OPEN     - File open state
MDS_INODELOCK_LAYOUT   - Stripe layout
MDS_INODELOCK_DOM      - Data-on-MDT
MDS_INODELOCK_PERM     - Permission bits
```

### MDT Locking Strategy

**mdt_lock_handle (per operation)**:
```
8 lock slots:
  0. MDT_LH_PARENT   - Parent directory lock
  1. MDT_LH_CHILD    - Child object lock
  2. MDT_LH_OLD      - Source in rename
  3. MDT_LH_LAYOUT   - Layout lock (reuse of OLD)
  4. MDT_LH_NEW      - Target in rename
  5. MDT_LH_RMT      - Remote lock
  6. MDT_LH_LOCAL    - Local-only lock (not returned to client)
  7. MDT_LH_LOOKUP   - Lookup lock for remote objects
```

### Operation-Specific Locking

**CREATE**:
```
1. Parent lock: PDO write lock (parent directory operations)
   - Prevents concurrent creates/deletes in same directory
2. Format: Parent_FID + hash(name) → lock resource ID
3. Blocking prevents name conflicts
```

**DELETE**:
```
1. Parent lock: PDO write lock
2. Child lock: Lookup lock or update lock
   - Prevents concurrent deletes
   - Prevents operations on file being deleted
```

**RENAME**:
```
1. Source parent: PDO write lock
2. Target parent: PDO write lock (if different)
3. Source child: Update lock
4. Target child: Update lock (if exists)
5. FID ordering prevents deadlock:
   - Lock in FID order
   - Compare FIDs to determine lock sequence
```

**SETATTR**:
```
1. Object lock: Update lock (for timestamps) or Layout lock (for stripe)
2. Blocking prevents concurrent modifications
```

### MDD Locking

**Local Object-Level Locks** (via dt_object):
```
mdd_write_lock()   → dt_write_lock()   → OSD-level write lock
mdd_read_lock()    → dt_read_lock()    → OSD-level read lock
mdd_write_unlock() → dt_write_unlock()
mdd_read_unlock()  → dt_read_unlock()
```

**Lock Order Rules** (to prevent deadlocks):
```
When locking multiple objects:
  1. Compare FIDs numerically
  2. Always lock lower FID first
  3. Then lock higher FID
  
Example:
  fid1 = [0x200000404:0x100:0x0]  (lower)
  fid2 = [0x200000404:0x200:0x0]  (higher)
  
  mdd_write_lock(env, obj1, DT_TGT_CHILD)
  mdd_write_lock(env, obj2, DT_TGT_CHILD)
```

---

## 7. TRANSACTION HANDLING

### Transaction Lifecycle

**Creation** (mdd_trans.c:29-56):
```c
struct thandle *mdd_trans_create(env, mdd):
  1. Check write barrier (if in progress)
  2. dt_trans_create() on underlying OSD
  3. Set quota ignore flags if privileged user
  return thandle (transaction handle)
```

**Start** (mdd_trans.c:58-62):
```c
int mdd_trans_start(env, mdd, th):
  return dt_trans_start(env, mdd->mdd_child, th)
```

**Stop** (mdd_trans.c:N/A but in dt_layer):
```
1. dt_trans_stop() on OSD
2. Sync to disk (fsync) if needed
3. Release locks
4. Cleanup handles
```

### Transaction Declaration Pattern

**Declare Phase** (Pre-allocation):
```c
mdd_declare_attr_set(env, obj, attr, handle)  // Declare intent to change attributes
mdd_declare_index_insert(env, obj, fid, type, name, handle)  // Declare intent to add dir entry
mdo_declare_ref_add(env, obj, handle)  // Declare link count increment

Purpose: Pre-calculate space/credits needed
Result: Aborts early if insufficient space (avoid mid-operation failure)
```

**Execution Phase**:
```c
mdo_attr_set(env, obj, attr, handle)          // Actually change attributes
mdo_index_insert(env, obj, fid, type, name, handle)  // Actually add dir entry
mdo_ref_add(env, obj, handle)                 // Actually increment link count

Uses pre-calculated credits from declare phase
```

### Transaction Examples

**CREATE Transaction**:
```
mdd_trans_create()
mdd_declare_create_object_internal()    // Space for new object
mdd_declare_index_insert()              // Space in parent dir
mdo_declare_attr_set() x2              // Parent mtime, child inode
mdd_trans_start()
mdd_create_object_internal()            // Create object
mdo_index_insert()                      // Add dir entry
mdo_attr_set()                          // Update times
mdd_changelog_store()                   // Log the change
mdd_trans_stop()
```

**RENAME Transaction**:
```
mdd_trans_create()
mdd_declare_index_delete() x2           // Space for both parent dirs
mdd_declare_index_insert() x2
mdd_declare_attr_set() x4               // Update 4 mtime values
mdd_trans_start()
mdo_index_delete()                      // Remove from source parent
mdo_index_insert()                      // Add to target parent
mdd_links_rename()                      // Update LinkEA
mdo_attr_set() x4                       // Update times
mdd_changelog_store()
mdd_trans_stop()
```

### ChangeLog Recording

**ChangeLog Entry Components**:
```
- Timestamp
- Record type (CREATE, UNLINK, RENAME, SETATTR, etc.)
- Target FID
- Parent FID
- Names (for renames)
- User ID, Group ID
- Job ID
- Nid (client address)
```

**Storage**:
- LLOG (Lustre Log) indexed by timestamp
- User can read from specific index
- GC (garbage collection) removes old entries
- Emergency GC if space running low

---

## 8. OBJECT LIFECYCLE

### State Transitions

```
[CREATED]
    ↓ (on delete)
[DEAD_OBJ] → moved to PENDING orphan directory
    ↓
[ORPHAN_OBJ] 
    ↓ (on cleanup/recovery)
[DESTROYED] → physically deleted from storage
```

### PENDING Orphan Directory

**Purpose**: Temporary storage for deleted files with open references

**Mechanism**:
1. Last-unlink: Move object to .lustre/PENDING
2. Client with open reference: Can still read/write
3. Final close: Object deleted from PENDING
4. Recovery: LFSCK can restore from PENDING to parent or archive

**Recovery on Server Restart**:
```
On MDT startup:
1. Scan PENDING directory
2. For each orphan:
   - If LinkEA exists: restore to parent
   - Otherwise: keep in PENDING or move to lost+found
3. Cleanup entries marked for deletion
```

---

## 9. CRITICAL ARCHITECTURAL DIFFERENCES FROM SIMPLE FS

### Differences the Simulator Needs to Handle

1. **FID vs Inode**:
   - **Real**: Globally unique, never recycled, allocated in ranges
   - **Simulator**: May use simpler local ID scheme, but must handle FID semantics

2. **Distributed Locks**:
   - **Real**: LDLM with network callbacks, blocking ASTs
   - **Simulator**: Simpler local lock mechanism, but must prevent same concurrency issues

3. **Transactions**:
   - **Real**: Declaration phase + execution phase, credit-based
   - **Simulator**: Can simplify but must maintain atomicity

4. **LinkEA/Hard Links**:
   - **Real**: Full link history tracking
   - **Simulator**: May simplify to just link count, but affects rename logic

5. **Striped Directories**:
   - **Real**: Multi-MDT sharding with hash-based routing
   - **Simulator**: Can simulate with local sharding

6. **ChangeLog**:
   - **Real**: Full audit trail with garbage collection
   - **Simulator**: Optional, can use simplified event log

7. **Orphan Handling**:
   - **Real**: PENDING directory with LinkEA recovery
   - **Simulator**: Can use simple linked list or queue

8. **Version-Based Recovery**:
   - **Real**: Version tracking for replay detection
   - **Simulator**: Can use simpler sequence numbers

---

## 10. DATA FLOW EXAMPLE: CREATE FILE

```
Client Request: Create file "foo" with mode 0644 in /home

1. CLIENT
   ├─ Resolve "/home" → FID [0x200000404:0x5:0x0]
   └─ Send CREATE RPC with:
      ├─ Parent FID: [0x200000404:0x5:0x0]
      ├─ Name: "foo"
      ├─ Mode: 0644
      ├─ Flags: MDS_OPEN_CREAT

2. MDT REQUEST HANDLER (mdt_handler.c)
   ├─ Unpack request
   ├─ Authenticate client (check gid/uid)
   └─ Route to mdt_reint_create()

3. MDT REINT (mdt_reint.c)
   ├─ Get parent FID
   ├─ Allocate new FID from seq server
   │  └─ FID = [0x200000404:0x1a2:0x0]
   ├─ Acquire locks:
   │  ├─ Parent PDO write lock (hash("foo"))
   │  └─ Child lock (not yet needed)
   ├─ Call md_create() → goes to MDD

4. MDD CREATE (mdd_dir.c + mdd_object.c)
   ├─ mdd_create()
   │  ├─ Permission check: parent writable?
   │  ├─ Check "foo" doesn't exist
   │  └─ mdd_create_object_internal()
   │
   ├─ mdd_create_object_internal()
   │  ├─ Start transaction
   │  ├─ Declare space needs
   │  │  ├─ Space for new inode
   │  │  └─ Space in parent directory
   │  ├─ dt_create() → OSD creates object on storage
   │  ├─ Insert in parent dir:
   │  │  └─ dt_insert(parent, "foo", FID, REG_FILE)
   │  ├─ Create LinkEA (backup of parent+name)
   │  ├─ Record ChangeLog entry
   │  │  └─ CHANGELOG_CREATE: [timestamp, UID, GID, parent_FID, child_FID, "foo"]
   │  ├─ Update parent times (mtime, ctime)
   │  └─ Commit transaction

5. MDT RESPONSE (mdt_handler.c)
   ├─ Lock returned to client:
   │  └─ Lock on [0x200000404:0x1a2:0x0]
   ├─ Attributes returned:
   │  ├─ FID: [0x200000404:0x1a2:0x0]
   │  ├─ Mode: 0644
   │  ├─ UID: 1000
   │  ├─ GID: 1000
   │  ├─ Size: 0
   │  └─ Timestamps: created just now
   └─ Version info for recovery

6. CLIENT
   ├─ Receives response
   ├─ Caches directory entry
   │  └─ "/home/foo" → [0x200000404:0x1a2:0x0]
   └─ Returns to application (success)

7. AUDIT/BACKUP SYSTEM
   └─ Reads ChangeLog:
      ├─ Sees CHANGELOG_CREATE entry
      ├─ Backs up /home/foo
      └─ Increments timestamp
```

---

## 11. COMPARISON MATRIX: Real MDS vs Simulator

| Aspect | Real Lustre | Simulator Should Support |
|--------|-------------|--------------------------|
| **FID Allocation** | Sequence server allocates ranges | Can use simple counter per MDT |
| **Distributed Locks** | LDLM with blocking ASTs | Local locks, prevent same conflicts |
| **Transactions** | Declaration + execution | Can simplify to simple atomicity |
| **LinkEA** | Full backup of (parent_FID, name) | Can track link count only |
| **Striped Dirs** | Full multi-MDT sharding | Can simulate within single server |
| **ChangeLog** | Full LLOG with GC | Optional, simple event log OK |
| **Orphan Handling** | PENDING dir with recovery | Simple linked list OK |
| **Version Tracking** | Version-based recovery | Simpler sequence numbers OK |
| **Permissions** | Full POSIX + ACLs | POSIX sufficient |
| **xattr/ACLs** | Full support | Can simplify or omit |

