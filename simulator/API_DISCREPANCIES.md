# Lustre Simulator API Discrepancies Analysis

This document analyzes discrepancies between the simulator implementation and real Lustre source code.

## Key Findings from Real Lustre Source

### 1. Operation Classification

**MDS Operations (Metadata):**
- `MDS_GETATTR` (33) - Get file attributes
- `MDS_GETATTR_NAME` (34) - Get attributes by name (includes lookup)
- `MDS_CLOSE` (35) - Close file handle
- `MDS_REINT` (36) - Metadata reintegration (umbrella for modify operations)
- `MDS_READPAGE` (37) - Read directory page
- `MDS_CONNECT` (38) - Client connection
- `MDS_DISCONNECT` (39) - Client disconnection
- `MDS_GET_ROOT` (40) - Get root directory FID
- `MDS_STATFS` (41) - Filesystem statistics
- `MDS_SYNC` (44) - Metadata sync

**MDS REINT Sub-Operations:**
1. `REINT_SETATTR` - Set attributes (chmod, chown, truncate, utimes)
2. `REINT_CREATE` - Create file/directory
3. `REINT_LINK` - Create hard link
4. `REINT_UNLINK` - Delete file/directory
5. `REINT_RENAME` - Rename file/directory
6. `REINT_OPEN` - Open file (with optional create)
7. `REINT_SETXATTR` - Set extended attribute
8. `REINT_RMENTRY` - Remove directory entry (internal)
9. `REINT_MIGRATE` - Migrate file (DNE)
10. `REINT_RESYNC` - Resync file (FLR)

**OST Operations (Data):**
- `OST_READ` (3) - Read file data
- `OST_WRITE` (4) - Write file data
- `OST_PUNCH` (10) - Punch hole in file
- `OST_SYNC` (16) - Sync data to disk
- `OST_FALLOCATE` (21) - Pre-allocate space

### 2. Major Discrepancies Found

#### A. CreateFile vs REINT_CREATE
**Real Lustre:**
- Uses `REINT_CREATE` for file creation
- Combined with `REINT_OPEN` for atomic create+open
- Checks parent directory exists
- Validates permissions
- Allocates FID from sequence manager
- Creates inode with proper mode, uid, gid, timestamps
- For files: may allocate LOV (layout) immediately
- For directories: may allocate LMV (directory layout)
- Returns MDT body with full attributes

**Current Simulator:**
- Separate CreateFile operation
- Does not validate parent directory properly
- Does not set proper POSIX attributes on creation
- Does not handle create-if-not-exists vs must-not-exist semantics

**Fix Needed:**
1. Add parent directory validation
2. Set proper initial attributes (mode, uid, gid, timestamps)
3. Validate file doesn't already exist (unless O_CREAT | O_EXCL)
4. Return full metadata in response

#### B. Open vs Close
**Real Lustre:**
- Open uses `REINT_OPEN`
- Creates file handle on MDS
- May allocate layout on first open
- Returns file handle ID and attributes
- Close uses `MDS_CLOSE`
- Releases file handle
- May trigger layout release for HSM files

**Current Simulator:**
- Open/Close are separate operations
- Do not manage file handles
- Do not track open file descriptors on MDS

**Fix Needed:**
1. Add file handle tracking in MDS
2. Open should return a handle ID
3. Close should validate and release handle
4. Track which clients have files open

#### C. Read/Write
**Real Lustre:**
- Client gets file layout from MDS (stripe count, OST list)
- Client calculates which OST holds which byte range
- Client sends `OST_READ`/`OST_WRITE` directly to OSS
- Locking handled by LDLM (lock distributed lock manager)

**Current Simulator:**
- Client specifies OSS ID manually
- No layout calculation
- No lock management
- Simplified stripe mapping

**Assessment:** This is acceptable for simulation - full layout calculation would add complexity

#### D. Stat vs GETATTR
**Real Lustre:**
- Uses `MDS_GETATTR` RPC
- Returns `mdt_body` structure with:
  * FID
  * Mode, nlink, uid, gid, rdev
  * Size, blocks, blksize
  * atime, mtime, ctime
  * Layout version
  * Flags (encrypted, compressed, etc.)
  * Striping info for files

**Current Simulator:**
- Returns simplified metadata
- Missing: blocks, blksize, rdev, flags, layout version

**Fix Needed:**
1. Add blocks and blksize to StatResponse
2. Add flags field for file attributes
3. Return layout info in stat

#### E. Delete/Unlink
**Real Lustre:**
- Uses `REINT_UNLINK`
- Checks nlink count
- If nlink > 1: just decrements nlink and removes directory entry
- If nlink == 1: marks inode for deletion, removes entry
- Orphan handling for open files
- Layout destroyed asynchronously
- OST objects deleted via OST_DESTROY

**Current Simulator:**
- Immediately deletes file
- Does not check nlink
- Does not handle open files
- Does not trigger OST cleanup

**Fix Needed:**
1. Check nlink before deletion
2. Only delete inode when nlink reaches 0
3. Remove path from directory but keep inode if nlink > 0
4. Add orphan handling for files deleted while open

#### F. Mkdir vs Rmdir
**Real Lustre:**
- Mkdir uses `REINT_CREATE` with S_IFDIR mode
- Can specify directory striping (DNE - Distributed Namespace)
- Rmdir uses `REINT_UNLINK` with directory check
- Rmdir fails if directory not empty
- Checks "." and ".." entries

**Current Simulator:**
- Mkdir is separate operation
- Does not support directory striping
- Rmdir doesn't properly check if directory is empty

**Fix Needed:**
1. Make Mkdir use REINT_CREATE with directory flag
2. Add directory empty check to Rmdir
3. Track directory entries properly

#### G. Rename
**Real Lustre:**
- Uses `REINT_RENAME`
- Takes source and target parent FIDs
- Handles cross-directory renames
- Handles renaming over existing files
- Updates parent directory mtimes and ctimes
- May involve cross-MDT rename (DNE)

**Current Simulator:**
- Simple path rename
- Does not track parent directories
- Does not handle rename-over-existing
- Does not update parent timestamps

**Fix Needed:**
1. Validate source exists
2. Handle target exists case (atomic replace)
3. Update parent directory timestamps
4. Validate same filesystem

#### H. Link Operations
**Real Lustre:**
- Hard link: Uses `REINT_LINK`
  * Increments nlink
  * Adds new directory entry
  * Both paths point to same FID
  * Cannot link directories
  * Cannot link across filesystems

- Symlink: Uses `REINT_CREATE` with S_IFLNK mode
  * Target stored in inode body
  * readlink reads target from inode

**Current Simulator:**
- Implements basic functionality
- Missing: directory link prevention
- Missing: cross-filesystem check

**Fix Needed:**
1. Prevent directory hard links
2. Add filesystem boundary checks

#### I. Setattr/Getattr
**Real Lustre:**
- Setattr uses `REINT_SETATTR`
- Validates permission for each attribute change
- Size changes may trigger OST truncate
- Handles special bits (setuid, setgid, sticky)
- Updates ctime on any metadata change
- Getattr uses `MDS_GETATTR`

**Current Simulator:**
- Basic implementation
- Does not validate permissions
- Does not handle size changes to OST
- Updates ctime correctly

**Fix Needed:**
1. Add permission validation
2. Handle size changes (truncate) with OST notification
3. Validate special mode bits

#### J. Extended Attributes
**Real Lustre:**
- Namespace validation: user.*, trusted.*, security.*, system.*
- Permissions: trusted.* requires CAP_SYS_ADMIN
- Special xattrs: trusted.lov (layout), trusted.lmv (dir layout)
- Size limits enforced
- Updates ctime on xattr changes

**Current Simulator:**
- Basic implementation
- No namespace validation
- No permission checks
- No size limits
- Correctly updates ctime

**Fix Needed:**
1. Add namespace validation
2. Add size limits
3. Reserve special xattr names (lov, lmv, fid, etc.)

### 3. Critical Missing Features

1. **Lock Management (LDLM)**
   - Real Lustre uses distributed lock manager
   - Locks acquired for metadata and data operations
   - Multiple lock modes (read, write, exclusive)
   - Simulator has stub lock operations

2. **Sequence/FID Management**
   - Real Lustre: FID = [sequence:object_id:version]
   - Sequences allocated by sequence manager
   - Object IDs must be unique within sequence
   - Simulator: Simple counter-based FID

3. **Layout Management (LOV/LMV)**
   - Real files have layout describing stripe pattern
   - Directories can be striped (DNE)
   - Layouts include: stripe count, stripe size, OST pool, pattern
   - Simulator: Simplified striping

4. **Version Management**
   - Real Lustre tracks object versions
   - Used for distributed consistency
   - VBR (Version-Based Recovery)
   - Simulator: No versioning

5. **Intents and Disposition**
   - Real Lustre uses intent-based locking
   - Operations declare intent before execution
   - Disposition tracks what was executed
   - Simulator: No intent system

## Summary of Required Fixes

### High Priority (Correctness Issues) - ALL FIXED ✅
1. ✅ **Nlink handling in delete** - Only delete when nlink==0 [FIXED: simulator/components/mds.py:314-377]
2. ✅ **Parent directory validation in create** - Check parent exists [FIXED: simulator/components/mds.py:196-301]
3. ✅ **Initial file attributes** - Set mode, uid, gid, timestamps on create [FIXED: simulator/components/mds.py:259-278]
4. ✅ **Directory empty check in rmdir** - Prevent deleting non-empty dirs [FIXED: simulator/components/mds.py:714-789]
5. ✅ **Rename atomic replace** - Handle target exists case [FIXED: simulator/components/mds.py:791-881]
6. ✅ **Prevent directory hard links** - No hard links to directories [FIXED: simulator/components/mds.py:1034-1131]

### Medium Priority (Functionality Improvements)
7. ⚠️ **File handle tracking** - Track open files on MDS [NOT IMPLEMENTED: Low simulation value]
8. ✅ **Stat response completeness** - Add blocks, blksize, flags [FIXED: api.py:52-79, mds.py:303-369]
9. ⚠️ **Setattr size changes** - Notify OST of truncate operations [NOT IMPLEMENTED: Requires OST communication]
10. ✅ **Xattr namespace validation** - Validate xattr prefixes [FIXED: mds.py:1688-1711, xattr handlers]

### Additional Improvements Completed
11. ✅ **Mkdir proper initialization** - Set proper attributes like CreateFile [FIXED: mds.py:436-517]
12. ✅ **Symlink proper initialization** - Validate parent, set complete attributes [FIXED: mds.py:1191-1293]
13. ✅ **Getattr response completeness** - Include nlink field [FIXED: api.py:258-269, mds.py:1015-1030]
14. ✅ **Parent timestamp updates** - Update parent mtime/ctime on content changes [FIXED: mds.py:1853-1863, applied to CreateFile, Mkdir, Symlink, Delete, Rmdir, Rename]
15. ✅ **Delete ctime update** - Update ctime when nlink decrements [FIXED: mds.py:408-409]
16. ✅ **Rename ctime update** - Update ctime when replacing file [FIXED: mds.py:934-935]
17. ✅ **Mkdir error messages** - Distinguish "Directory exists" vs "File exists" [FIXED: mds.py:469-487]
18. ✅ **ListDir validation** - Check path is directory before listing [FIXED: mds.py:555-610]
19. ✅ **Xattr flags handling** - Implement XATTR_CREATE/XATTR_REPLACE [FIXED: api.py:6-8, mds.py:35, mds.py:1628-1669]
20. ✅ **Link ctime update** - Update ctime when nlink changes (previous session)
21. ✅ **Xattr value size validation** - 64KB limit (previous session)
22. ✅ **Mode bits validation** - Validate 0-0o7777 range in setattr (previous session)
23. ✅ **Root directory initialization** - Proper attributes for root (previous session)
24. ✅ **Symlink/Link duplicate checks** - Prevent duplicate paths (previous session)

### Low Priority (Nice to Have)
11. ⏸️ **Layout calculation** - Proper stripe to OST mapping
12. ⏸️ **Permission checks** - Validate user permissions
13. ⏸️ **Orphan handling** - Files deleted while open
14. ⏸️ **Intent-based operations** - Atomic lookup+open patterns

## Implementation Plan

1. Fix nlink handling throughout (delete, link, unlink)
2. Add parent directory validation
3. Improve file creation with proper attributes
4. Add directory entry tracking for rmdir validation
5. Improve rename to handle all edge cases
6. Add basic namespace validation for xattrs
7. Document remaining limitations clearly
