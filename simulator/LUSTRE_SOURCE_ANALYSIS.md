# Lustre Source Code Analysis for Simulator Implementation

This document summarizes findings from analyzing the real Lustre source code to guide accurate simulator implementation.

## Extended Attributes (xattr)

### Client-Side Implementation (`lustre/llite/xattr.c`)

**Setxattr Flow:**
1. Client calls `ll_xattr_set_common()` (line 80-207)
2. Validates xattr type and permissions:
   - `XATTR_USER_T`: user.* namespace (requires OBD_CONNECT_XATTR capability)
   - `XATTR_TRUSTED_T`: trusted.* namespace (requires CAP_SYS_ADMIN)
   - `XATTR_SECURITY_T`: security.* namespace
   - `XATTR_ACL_ACCESS_T`/`XATTR_ACL_DEFAULT_T`: POSIX ACLs
3. Constructs full attribute name with prefix (line 181)
4. Calls `md_setxattr()` RPC to MDS (line 185-187):
   ```c
   rc = md_setxattr(sbi->ll_md_exp, ll_inode2fid(inode), valid, fullname,
                    pv, size, flags, ll_i2suppgid(inode),
                    ll_i2projid(inode), &req);
   ```
5. `valid` flag: `OBD_MD_FLXATTR` for set, `OBD_MD_FLXATTRRM` for remove
6. Flags: `XATTR_REPLACE` (replace existing) or `XATTR_CREATE` (create new)

**Getxattr Flow:**
1. Client calls `ll_xattr_get_common()` (line 551-606)
2. Checks xattr cache if enabled (line 493-514)
3. If cache miss, calls `ll_xattr_list()` → `md_getxattr()` RPC (line 517-518):
   ```c
   rc = md_getxattr(sbi->ll_md_exp, ll_inode2fid(inode), valid,
                    name, size, ll_i2projid(inode), &req);
   ```
4. Returns xattr value from response buffer (line 530-535)

**Listxattr:** Uses `OBD_MD_FLXATTRLS` flag to request all xattr names

**Removexattr:** Uses `OBD_MD_FLXATTRRM` flag with NULL value

### Server-Side Implementation (`lustre/mdt/mdt_xattr.c`)

**Setxattr Handler `mdt_reint_setxattr()` (line 509-686):**
1. Validates xattr namespace and permissions (line 538-606)
2. Acquires appropriate locks:
   - `MDS_INODELOCK_UPDATE` for most xattrs
   - `MDS_INODELOCK_XATTR` for xattr cache invalidation
   - `MDS_INODELOCK_PERM` for ACLs
   - `MDS_INODELOCK_LAYOUT` for LOV xattrs
3. Calls storage layer (line 658 or 665):
   ```c
   if (valid & OBD_MD_FLXATTR) {
       rc = mo_xattr_set(env, child, buf, xattr_name, flags);
   } else if (valid & OBD_MD_FLXATTRRM) {
       rc = mo_xattr_del(env, child, xattr_name);
   }
   ```
4. Updates ctime after xattr modification (line 660-663, 667-670)

**Getxattr Handler `mdt_getxattr_pack_reply()` (line 32-122):**
1. Determines operation type from `valid` flags:
   - `OBD_MD_FLXATTR`: Get single xattr
   - `OBD_MD_FLXATTRLS`: List all xattr names
   - `OBD_MD_FLXATTRALL`: Get all xattrs (bulk)
2. Calls storage layer (line 59-61):
   ```c
   size = mo_xattr_get(info->mti_env,
                      mdt_object_child(info->mti_object),
                      &LU_BUF_NULL, xattr_name);
   ```
3. Returns size or full value depending on buffer size

**Storage:** Extended attributes are stored in the backend object storage (OSD layer - ldiskfs or ZFS)

## Flush Operation (`lustre/llite/file.c`)

**ll_flush() (line 5199-5225):**
- Called when VFS closes a file (not when user calls fsync)
- Checks for async write errors that occurred during writeback
- Returns the error status from `lli->lli_async_rc`
- Does NOT actually flush data to disk - that's fsync's job
- Purpose: Report write errors that occurred asynchronously

**Key insight:** Flush in Lustre is mainly for error reporting, not actual sync

## Fsync Operation (`lustre/llite/file.c`)

**ll_fsync() (line 5285-5352):**
1. Flushes kernel page cache first: `filemap_write_and_wait_range()` (line 5302)
2. For regular files, syncs metadata to MDS (line 5324-5325):
   ```c
   err = md_fsync(ll_i2sbi(inode)->ll_md_exp,
                  ll_inode2fid(inode), &req);
   ```
3. Syncs data to OSTs (line 5343-5345):
   ```c
   err = cl_sync_file_range(inode, start, end,
                           CL_FSYNC_ALL, 0,
                           IO_PRIO_NORMAL);
   ```
4. Updates `lli->lli_synced_to_mds` flag

**Key insight:** Fsync involves both MDS (metadata) and OST (data) sync operations

## Statfs Operation (`lustre/llite/llite_lib.c`)

**ll_statfs() (line 2763-2811):**
1. Calls `ll_statfs_internal()` with `OBD_STATFS_SUM` flag (line 2776)
2. Unpacks results into `kstatfs` structure

**ll_statfs_internal() (line 2616-2673):**
1. Gets MDT statistics via `obd_statfs(sbi->ll_md_exp, ...)` (line 2629)
2. Gets OST statistics via `obd_statfs(sbi->ll_dt_exp, ...)` (line 2641)
3. Combines stats (line 2649-2668):
   - Uses OST stats for block/space info (`os_blocks`, `os_bfree`, `os_bavail`)
   - Uses MDT stats for inode/file info (`os_files`, `os_ffree`)
   - If OST has fewer free objects than MDT inodes, adjusts inode count
4. Returns aggregated filesystem statistics

**Key fields in `obd_statfs`:**
- `os_blocks`: Total blocks
- `os_bfree`: Free blocks
- `os_bavail`: Available blocks (to non-root)
- `os_files`: Total inodes
- `os_ffree`: Free inodes
- `os_bsize`: Block size
- `os_state`: State flags
- `os_maxbytes`: Max file size

**Key insight:** Statfs aggregates statistics from both MDS and OSS, with OSTs providing capacity info and MDS providing inode info.

## Implementation Notes for Simulator

1. **Xattrs:** Store as `Dict[str, str]` in FileMetadata, implement namespace validation
2. **Flush:** Simple error reporting mechanism, no actual I/O
3. **Fsync:** Send sync request to both MDS and OSS
4. **Statfs:** Aggregate stats from MDS (file count) and all OSSs (capacity)
5. **Locking:** Simulator can simplify lock acquisition (no LDLM needed)
6. **Permissions:** Simulator can skip most permission checks for simplicity
