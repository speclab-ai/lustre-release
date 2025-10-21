# Lustre MDS Key Files Quick Reference

## File Organization and Key Entry Points

### MDT (Request Handler Layer)

**Core Files**:
- `/lustre/mdt/mdt_internal.h` - Core MDT structures and macros
  - `struct mdt_device` - Root MDT device
  - `struct mdt_object` - Server-side object wrapper
  - `struct mdt_thread_info` - Per-request context
  - `struct mdt_lock_handle` - Lock handle array
  - `struct mdt_reint_record` - Operation parameters

- `/lustre/mdt/mdt_handler.c` - RPC request handler
  - Request unpacking and marshaling
  - Object cache management
  - Device initialization

- `/lustre/mdt/mdt_reint.c` - Reintegration handlers (CORE OPERATIONS)
  - `mdt_reint_create()` - File/dir creation
  - `mdt_reint_unlink()` - File deletion
  - `mdt_reint_rename()` - File renaming
  - `mdt_reint_setattr()` - Attribute updates
  - Version tracking for recovery

- `/lustre/mdt/mdt_lib.c` - Helper functions
  - Credential processing
  - Permission checking
  - Object lookup utilities

- `/lustre/mdt/mdt_open.c` - Open file handling
  - Open file descriptor management
  - Lease operations

- `/lustre/mdt/mdt_lock.c` - Lock handling (probably similar to mdd_lock.c)
  - Lock acquisition and release
  - PDO lock management

- `/lustre/mdt/mdt_lproc.c` - Proc/sysfs interface
  - Statistics and debug info

**HSM (Hierarchical Storage Management)**:
- `/lustre/mdt/mdt_hsm.c` - HSM state management
- `/lustre/mdt/mdt_coordinator.c` - HSM coordinator thread
- `/lustre/mdt/mdt_hsm_cdt_*.c` - Coordinator request/agent handling

---

### MDD (Implementation Layer)

**Core Files**:
- `/lustre/mdd/mdd_internal.h` - Core MDD structures
  - `struct mdd_device` - MDD device
  - `struct mdd_object` - MDD object wrapper
  - `struct mdd_thread_info` - Per-thread context
  - Inline helper functions for all operations

- `/lustre/mdd/mdd_device.c` - Device initialization and lifecycle
  - Device setup
  - Object allocation
  - Root filesystem setup
  - Local file creation

- `/lustre/mdd/mdd_object.c` - Object management (LARGE FILE)
  - Object creation and initialization
  - User tracking for open files
  - Changelog entry recording
  - Object state transitions

- `/lustre/mdd/mdd_dir.c` - Directory operations (CORE OPERATIONS)
  - `mdd_lookup()` - Directory lookup
  - `mdd_create()` - Create object in directory
  - `mdd_unlink()` - Remove from directory
  - `mdd_links_*()` - LinkEA management
  - Permission checks
  - Directory validation

- `/lustre/mdd/mdd_lock.c` - Object-level locking
  - `mdd_write_lock()` / `mdd_read_lock()`
  - `mdd_write_unlock()` / `mdd_read_unlock()`
  - Wrappers around dt_object locks

- `/lustre/mdd/mdd_trans.c` - Transaction management
  - `mdd_trans_create()` - Start transaction
  - `mdd_trans_start()` - Begin transaction
  - Transaction state tracking

- `/lustre/mdd/mdd_acl.c` - ACL and permission handling
  - POSIX ACL support
  - Permission checks

- `/lustre/mdd/mdd_orphans.c` - Orphan object handling
  - PENDING directory management
  - Orphan cleanup
  - Lost+found handling

- `/lustre/mdd/mdd_lproc.c` - Proc/sysfs interface

---

## Operation Flow Examples

### CREATE Operation Call Stack
```
Client RPC Request
  ↓
mdt_handler.c: mdt_handler() - unpack request
  ↓
mdt_reint.c: mdt_reint_create() - main handler
  ├─ mdt_lib.c: mdt_object_find() - get/create parent object
  ├─ mdt_lock.c: mdt_object_lock() - acquire parent lock
  ├─ mdd_device.c: allocated FID from seq server
  ├─ mdd_trans.c: mdd_trans_create() - start transaction
  ├─ (MDD Layer)
  │   ├─ mdd_object.c: mdd_create()
  │   ├─ mdd_dir.c: insert into parent directory
  │   ├─ mdd_object.c: mdd_changelog_store() - log operation
  ├─ mdd_trans.c: mdd_trans_stop() - commit
  ├─ mdt_lock.c: mdt_object_unlock() - release locks
  ├─ mdt_lib.c: pack response
  └─ mdt_handler.c: send reply
```

### RENAME Operation Call Stack
```
Client RPC Request
  ↓
mdt_reint.c: mdt_reint_rename()
  ├─ mdt_lib.c: lookup source and target objects
  ├─ mdt_lock.c: acquire locks in FID order
  │   ├─ source parent (PDO write)
  │   ├─ target parent (PDO write)
  │   ├─ source child
  │   └─ target child (if exists)
  ├─ mdd_trans.c: mdd_trans_create()
  ├─ (MDD Layer)
  │   ├─ mdd_dir.c: delete from source parent
  │   ├─ mdd_dir.c: insert into target parent
  │   ├─ mdd_dir.c: mdd_links_rename() - update LinkEA
  │   ├─ mdd_object.c: update parent times
  │   ├─ mdd_object.c: mdd_changelog_store()
  ├─ mdd_trans.c: mdd_trans_stop()
  ├─ mdt_lock.c: release all locks in reverse order
  └─ mdt_handler.c: send reply
```

---

## Key Data Structures at a Glance

### Lock Management
```c
struct mdt_lock_handle {
  struct lustre_handle mlh_reg_lh;    // Regular lock
  struct lustre_handle mlh_pdo_lh;    // Parent directory op lock
  struct lustre_handle mlh_rreg_lh;   // Remote lock
  enum ldlm_mode mlh_reg_mode;        // Lock mode (PR/PW/EX)
};

// Per-operation: 8 locks
mdt_thread_info.mti_lh[MDT_LH_NR]:
  0. PARENT - parent directory
  1. CHILD - child object
  2. OLD - source in rename
  3. LAYOUT - layout lock
  4. NEW - target in rename
  5. RMT - remote object
  6. LOCAL - local only (not to client)
  7. LOOKUP - remote object lookup
```

### Transaction Pattern
```c
struct thandle *th = mdd_trans_create(env, mdd);
if (IS_ERR(th)) return PTR_ERR(th);

// Declare phase (pre-allocate space)
mdd_declare_create_object_internal(env, parent, child, attr, th, spec, hint);
mdd_declare_index_insert(env, parent, child_fid, type, name, th);
mdo_declare_attr_set(env, parent, attr, th);

// Execution phase (actual changes)
mdd_trans_start(env, mdd, th);
mdd_create_object_internal(env, parent, child, attr, th, spec, hint);
mdo_index_insert(env, parent, child_fid, type, name, th);
mdo_attr_set(env, parent, attr, th);
mdd_changelog_store(env, mdd, changelog_rec, th);

// Stop transaction
mdd_trans_stop(env, mdd, rc, th);
```

### File Identifier (FID)
```c
// FID = [SEQ:OID:VER]
struct lu_fid {
  __u64 f_seq;   // Sequence number (16 bits used)
  __u32 f_oid;   // Object ID (32 bits)
  __u32 f_ver;   // Version (16 bits used)
};

// Examples:
// Root: [0x200000404:0x0:0x0]
// Regular file: [0x200000404:0x1a2:0x0]
// Special .obf: [0x100000000:N:0x0]
```

---

## Critical Implementation Details

### Permission Checks
**File**: `mdd_dir.c`, `mdd_permission.c`

```
mdd_may_create()    - Check write+exec on parent for CREATE
mdd_may_delete()    - Check write+exec on parent for DELETE
mdd_permission()    - General POSIX permission check
```

### Concurrency Control
**Files**: `mdt_lock.c`, `mdd_lock.c`

```
PDO Locks: Parent_FID + hash(name) - Prevents name conflicts
           Essential for preventing concurrent creates/deletes in same dir

Lock Order: Always lock lower FID first
           Prevents deadlocks in cross-directory operations

Reference Counts: Prevent deletion while in use
```

### Orphan Management
**File**: `mdd_orphans.c`

```
Last-link DELETE:
  1. Remove entry from parent directory
  2. Link count becomes 0
  3. Move to .lustre/PENDING
  4. Set DEAD_OBJ flag
  
Final CLOSE:
  1. Last reference closes
  2. Object physically deleted from PENDING
  3. Cleanup resources
```

### LinkEA (Link Extended Attribute)
**Files**: `mdd_dir.c`, `mdd_object.c`

```
Purpose: Backup of (parent_FID, name) pairs
Usage:   File path reconstruction, hard link tracking
Format:  Multiple entries, each with parent FID and filename
Update:  On rename, link creation, link deletion
Storage: Extended attribute on object inode
```

---

## Testing and Debugging

### Sanity Tests
Location: `lustre/tests/sanity.sh` (not MDS-specific, but exercises MDS)

Key test patterns:
- `test_1()` - Simple create/delete
- `test_2()` - Rename operations
- `test_3()` - Permission checks
- `test_*() ` - Various metadata operations

### Debug Macros
```c
ENTRY/EXIT           - Entry/exit functions
LASSERT(condition)   - Assertion (fails if false)
CDEBUG(level, fmt)   - Conditional debug output
CERROR(fmt)          - Error logging
```

### Lock Debugging
```
Enable lock debugging in LDLM for deadlock detection
Check lock state with:
  cat /proc/fs/lustre/ldlm/namespaces/*/state
```

---

## Simulator Implementation Guidance

### Must Implement
1. FID management (allocation, tracking)
2. Directory operations (lookup, insert, delete)
3. Basic locking (prevent concurrent conflicts)
4. Transaction atomicity
5. Permission checks

### Can Simplify
1. Use local counters for FID instead of sequence server
2. Simplified PDO locks (just exclusive per parent)
3. Transaction declaration (pre-allocate all space upfront)
4. LinkEA (just track link count)
5. Single MDT (no cross-MDT operations)

### Optional Features
1. ChangeLog recording
2. Orphan handling with PENDING directory
3. Striped directories
4. ACL support beyond basic permissions
5. Extended attributes beyond essentials

---

## Key Files Summary Table

| File | Purpose | Key Functions |
|------|---------|----------------|
| mdt_reint.c | Operation handlers | mdt_reint_create/unlink/rename/setattr |
| mdd_dir.c | Directory operations | mdd_lookup/create/unlink/links_rename |
| mdd_trans.c | Transactions | mdd_trans_create/start/stop |
| mdd_lock.c | Object locks | mdd_write_lock/read_lock/unlock |
| mdd_object.c | Object management | mdd_create/changelog recording |
| mdt_lock.c | LDLM locks | mdt_object_lock/unlock |
| mdd_orphans.c | Orphan handling | mdd_orphan_insert/delete/cleanup |
| mdd_internal.h | Core structures | struct definitions, inline helpers |

