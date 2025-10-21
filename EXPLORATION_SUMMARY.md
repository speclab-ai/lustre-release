# Lustre MDS Exploration Summary

## Overview

This analysis explores the real Lustre Metadata Server (MDS) implementation to understand how it handles metadata operations, focusing on the MDT (Metadata Target) and MDD (Metadata Device) layers.

**Date**: 2025-10-21  
**Scope**: Lustre 2.x MDS implementation  
**Purpose**: Guide simulator development and comparison

---

## Documents Generated

1. **LUSTRE_MDS_ARCHITECTURE.md** (812 lines)
   - Complete architectural overview
   - Data structure definitions
   - Detailed operation flows (CREATE, DELETE, RENAME, SETATTR)
   - Locking and concurrency strategy
   - Transaction handling
   - FID management
   - Object lifecycle
   - Direct comparison with simulator requirements

2. **MDS_KEY_FILES_SUMMARY.md**
   - Quick reference to key source files
   - Operation call stacks
   - Implementation guidance for simulators
   - Data structure examples with code
   - Testing and debugging tips

3. **EXPLORATION_SUMMARY.md** (this file)
   - Index of all explored files
   - Directory structure
   - Key findings

---

## Directory Structure Explored

```
lustre/mdt/                          - Metadata Target (Request Handler)
├── mdt_internal.h                   - Core MDT structures
├── mdt_handler.c                    - RPC request handling
├── mdt_reint.c                      - Reintegration (core metadata operations)
├── mdt_lib.c                        - Helper functions
├── mdt_open.c                       - File open handling
├── mdt_lock.c                       - Lock management
├── mdt_lproc.c                      - Proc/sysfs interface
├── mdt_hsm.c                        - HSM state
├── mdt_coordinator.c                - HSM coordinator
└── mdt_hsm_cdt_*.c                 - HSM request/agent handling

lustre/mdd/                          - Metadata Device (Implementation)
├── mdd_internal.h                   - Core MDD structures
├── mdd_device.c                     - Device initialization
├── mdd_object.c                     - Object management
├── mdd_dir.c                        - Directory operations
├── mdd_lock.c                       - Object locking
├── mdd_trans.c                      - Transaction handling
├── mdd_acl.c                        - ACL/permission handling
├── mdd_orphans.c                    - Orphan object handling
├── mdd_lproc.c                      - Proc/sysfs interface
└── mdd_permission.c                 - Permission checks
```

---

## Key Findings

### Architecture Pattern
- **Two-layer design**: MDT (request handler) + MDD (implementation)
- **Clear separation of concerns**: Network/RPC vs metadata logic
- **Layered approach allows multiple storage backends**

### Critical Components

#### 1. FID Management
- Globally unique 96-bit identifiers: `[SEQ:OID:VER]`
- Never recycled, persistent across operations
- Allocated in ranges from Sequence Server
- Enables distributed metadata tracking

#### 2. Locking Strategy
- **PDO Locks** (Parent Directory Operations): hash-based per-directory locks
- **LDLM** (Lustre Distributed Lock Manager): distributed lock infrastructure
- **Lock ordering**: Compare FIDs to prevent deadlocks
- **Multiple lock types**: CR, CW, PR, PW, EX modes

#### 3. Metadata Operations
- **CREATE**: FID allocation + directory insertion + LinkEA creation
- **DELETE**: Directory removal + LinkEA cleanup + orphan handling
- **RENAME**: Atomic directory manipulation + LinkEA updates
- **SETATTR**: Attribute updates with permission checks

#### 4. Concurrency Control
- **Transaction atomicity**: Declaration + Execution pattern
- **Reference counting**: Track open files and operations
- **Lock ordering rules**: Always lock lower FID first
- **Orphan handling**: PENDING directory for deleted files in use

#### 5. LinkEA (Link Extended Attribute)
- Backup of `(parent_FID, filename)` pairs
- Essential for hard link tracking
- Supports rename history reconstruction
- Enables path-based recovery

#### 6. Transaction Handling
- **Declare phase**: Pre-calculate space needs, allocate credits
- **Execution phase**: Perform actual changes
- **Stop phase**: Sync and release resources
- **Atomic commitment**: All-or-nothing semantics

---

## Code Statistics

| Directory | Files | Purpose |
|-----------|-------|---------|
| lustre/mdt/ | 22+ | Request handling, locking, recovery |
| lustre/mdd/ | 10+ | Metadata operations, transactions |

**Largest Files**:
- `mdt_reint.c` - Main operation handlers
- `mdd_object.c` - Object lifecycle management
- `mdd_dir.c` - Directory operations

---

## Key Data Structures

### MDT Layer
```c
struct mdt_device           - Root MDT device
struct mdt_object           - Server-side object wrapper
struct mdt_thread_info      - Per-request context (130+ fields)
struct mdt_lock_handle      - Lock array management
struct mdt_reint_record     - Operation parameters
struct mdt_file_data        - Open file descriptor
```

### MDD Layer
```c
struct mdd_device           - MDD device
struct mdd_object           - MDD object wrapper
struct mdd_thread_info      - Per-thread context
struct mdd_changelog        - ChangeLog metadata
struct mdd_generic_thread   - Background thread helper
```

---

## Operation Deep Dives

### CREATE Flow
1. Parse request (parent FID, name, mode)
2. Allocate new FID
3. Acquire parent PDO write lock
4. Start transaction
5. Create underlying object (dt_create)
6. Insert into parent directory (dt_insert)
7. Create LinkEA
8. Record ChangeLog entry
9. Commit transaction
10. Release locks
11. Pack response

### DELETE Flow
1. Lookup child by name
2. Acquire parent write lock + child lock
3. Check preconditions (not in use, permissions)
4. Start transaction
5. Remove from parent directory (dt_delete)
6. Update LinkEA
7. If last link: move to PENDING + set DEAD_OBJ
8. Update parent times
9. Record ChangeLog entry
10. Commit transaction
11. Release locks

### RENAME Flow
1. Lookup source and target
2. Acquire locks in FID order (prevent deadlock)
3. Validate paths
4. Start transaction
5. Delete from source parent
6. Insert into target parent
7. Update LinkEA with new parent/name
8. If cross-directory: update parent pointer
9. Update both parent times
10. Record ChangeLog entry
11. Commit transaction
12. Release locks in reverse order

### SETATTR Flow
1. Get object
2. Acquire update lock or layout lock
3. Start transaction
4. Retrieve current attributes
5. Merge requested changes
6. Call dt_attr_set
7. Update ctime if modified
8. Record ChangeLog entry
9. Commit transaction
10. Release lock

---

## Concurrency Examples

### Preventing Name Conflicts (PDO Lock)
```
Operation 1: Create /dir/file1
  Lock: PDO_LOCK(/dir, hash("file1"))
  
Operation 2 (concurrent): Create /dir/file1
  Lock: PDO_LOCK(/dir, hash("file1"))
  Blocks! Cannot proceed until Op1 releases lock
  
Result: First creator wins, second gets EEXIST
```

### Preventing Deadlock (FID Ordering)
```
Operation 1: Rename /dir1/file -> /dir2/file
  fid1 = dir1_FID, fid2 = dir2_FID
  if (fid1 < fid2):
    Lock(dir1)
    Lock(dir2)
  else:
    Lock(dir2)
    Lock(dir1)

Result: All operations lock in same order
        Prevents circular wait -> no deadlock
```

---

## Simulator Implementation Priorities

### Phase 1: Essential (Must Have)
1. FID generation and tracking
2. Basic directory structure (parent-child mappings)
3. Simple locking (prevent concurrent conflicts)
4. Transaction atomicity (all-or-nothing)
5. POSIX permission checks
6. Basic attributes (uid, gid, mode, size, times)

### Phase 2: Important (Should Have)
1. PDO-like locks (per-directory concurrency control)
2. LinkEA or equivalent (hard link tracking)
3. Reference counting (prevent deletion while in use)
4. ChangeLog or event log (audit trail)
5. Orphan directory (for deleted files in use)
6. Lock ordering to prevent deadlocks

### Phase 3: Advanced (Nice to Have)
1. Striped directories (multi-shard simulation)
2. Full POSIX ACLs
3. Extended attributes
4. ChangeLog garbage collection
5. Version-based recovery
6. Multi-MDT simulation

### Phase 4: Specialized (Out of Scope)
1. HSM (Hierarchical Storage Management)
2. LFSCK (Lustre File System Check)
3. Encryption
4. Data-on-MDT (DOM)
5. Remote objects (cross-MDT references)

---

## Critical Lessons for Simulator

### 1. FID is Central
- Everything identified by FID, not inode number
- FID generation must be consistent across lifetime
- FID never changes (unlike inode which can be recycled)

### 2. Locking Prevents Race Conditions
- PDO locks prevent directory entry conflicts
- LDLM locks prevent concurrent modifications
- Lock ordering is essential to prevent deadlocks
- Must enforce lock mode semantics (CR, CW, PR, PW, EX)

### 3. Transactions Must Be Atomic
- All-or-nothing semantics critical for consistency
- Declaration phase prevents mid-operation failures
- Changelog must record atomically with operation

### 4. LinkEA Tracks Everything
- Not just used for hard links
- Tracks rename history
- Enables path reconstruction
- Critical for recovery

### 5. Orphans Need Special Handling
- Deleted files in use don't disappear immediately
- Moved to PENDING directory
- Cleanup on final close
- Recovery can restore from PENDING

### 6. Permissions Must Be Checked Consistently
- mdd_may_create: parent must be writable
- mdd_may_delete: parent must be writable
- General mdd_permission: standard POSIX rules
- Applied uniformly across all operations

---

## References

### Source Files Analyzed
- `/lustre/mdt/mdt_internal.h` - Main MDT structures
- `/lustre/mdd/mdd_internal.h` - Main MDD structures
- `/lustre/mdt/mdt_reint.c` - Operation handlers
- `/lustre/mdd/mdd_dir.c` - Directory operations
- `/lustre/mdd/mdd_trans.c` - Transaction handling
- `/lustre/mdt/mdt_handler.c` - Request handling
- `/lustre/mdd/mdd_object.c` - Object management
- `/lustre/mdd/mdd_lock.c` - Locking
- `/lustre/mdt/mdt_lib.c` - Utilities

### Documentation Files Generated
- `LUSTRE_MDS_ARCHITECTURE.md` - Comprehensive technical guide
- `MDS_KEY_FILES_SUMMARY.md` - Quick reference and implementation tips
- `EXPLORATION_SUMMARY.md` - This index and findings

---

## Next Steps

1. **Study LUSTRE_MDS_ARCHITECTURE.md**
   - Understand complete operation flows
   - Learn locking strategy
   - Review data structures

2. **Review MDS_KEY_FILES_SUMMARY.md**
   - Identify key files to read
   - Understand call stacks
   - Get implementation guidance

3. **Examine Specific Operations**
   - Read mdt_reint_create in detail
   - Trace through mdd_dir.c operations
   - Study mdd_trans.c transaction pattern

4. **Design Simulator Architecture**
   - Map MDS patterns to simulator design
   - Identify simplifications needed
   - Plan implementation phases

5. **Implement and Test**
   - Start with Phase 1 essentials
   - Add concurrency features
   - Compare behavior with real MDS

---

## Summary Statistics

- **Total Lines Analyzed**: ~10,000 lines of core MDS code
- **Key Structures Identified**: 20+
- **Critical Operations Documented**: 4 (CREATE, DELETE, RENAME, SETATTR)
- **Lock Types**: 6 (NULL, CR, CW, PR, PW, EX)
- **Lock Bits**: 6+ (LOOKUP, UPDATE, OPEN, LAYOUT, DOM, PERM)
- **Files Explored**: 30+ in mdt/ and mdd/
- **Documentation Generated**: 3 comprehensive guides

---

## Contact & Questions

For questions about the Lustre MDS architecture or how to apply these findings to your simulator, refer to:
- LUSTRE_MDS_ARCHITECTURE.md for detailed explanations
- MDS_KEY_FILES_SUMMARY.md for quick references
- Source code at `/home/user/lustre-release/lustre/mdt/` and `/lustre/mdd/`

