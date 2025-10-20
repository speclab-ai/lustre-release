# Lustre Simulator vs Real Lustre API Comparison

## Summary

The simulator implements **10 basic APIs** out of **200+ total Lustre APIs**.

**API Breakdown:**
- **Client-side APIs (VFS + IOCTLs):** 10 implemented / ~75 total
- **Portal RPC Operations:** 0 implemented / 113 total (MDS: 30+10, OST: 23, MGS: 7, LDLM: 6, OBD: 4, SEQ: 3, FLD: 2, UPDATE: 18)
- **Administrative IOCTLs:** 0 implemented / 47 total
- **Userspace Utilities:** 0 implemented / 63+ total tools

**Coverage: ~5% of full Lustre API surface**

The simulator focuses on basic file operations (create, read, write, delete, stat, mkdir, listdir) and simple striping. It does not implement:
- Advanced features (HSM, PCC, FLR, DNE)
- Distributed locking (LDLM)
- Recovery and failover mechanisms
- Quota systems
- Administrative tools
- Complete Portal RPC framework

---

## Implemented in Simulator (10 APIs)

### File Operations (7)
| API | Simulator | Real Lustre | User Pathway | Notes |
|-----|-----------|-------------|--------------|-------|
| CreateFile | ✅ | ✅ (via `open()` + `O_CREAT`) | POSIX → VFS → llite → MDS RPC | Supports stripe configuration |
| Read | ✅ | ✅ (`read()` syscall) | POSIX → VFS → llite → OST RPC | Basic read from OST |
| Write | ✅ | ✅ (`write()` syscall) | POSIX → VFS → llite → OST RPC | Basic write to OST |
| Delete | ✅ | ✅ (`unlink()` syscall) | POSIX → VFS → llite → MDS RPC | File deletion |
| Stat | ✅ | ✅ (`stat()` syscall) | POSIX → VFS → llite → MDS RPC | Get file metadata |

### Directory Operations (2)
| API | Simulator | Real Lustre | User Pathway | Notes |
|-----|-----------|-------------|--------------|-------|
| Mkdir | ✅ | ✅ (`mkdir()` syscall) | POSIX → VFS → llite → MDS RPC | Create directory |
| ListDir | ✅ | ✅ (`readdir()` syscall) | POSIX → VFS → llite → MDS RPC | List directory contents |

### Locking (3)
| API | Simulator | Real Lustre | User Pathway | Priority | Notes |
|-----|-----------|-------------|--------------|----------|-------|
| Lock | ✅ (defined) | ✅ (LDLM) | Internal (automatic on I/O) | 🔴 LOW | Not user-triggerable, automatic |
| Unlock | ✅ (defined) | ✅ (LDLM) | Internal (automatic on I/O) | 🔴 LOW | Not user-triggerable, automatic |
| GetLayout | ✅ (defined) | ✅ (`LL_IOC_LOV_GETSTRIPE`) | lfs getstripe → ioctl() → llite | 🟢 HIGH | User-triggerable via lfs |

---

## NOT Implemented - Core File System Operations (15+)

### Basic File Operations
| API | Real Lustre | User Pathway | Description |
|-----|-------------|--------------|-------------|
| Open | ✅ `open()` | POSIX → VFS → llite → MDS RPC | Open file descriptor |
| Close | ✅ `close()` / `release()` | POSIX → VFS → llite → MDS RPC | Close file descriptor |
| Seek | ✅ `ll_file_seek()` | POSIX lseek() → VFS → llite | Random access positioning |
| Fsync | ✅ `ll_fsync()` | POSIX fsync() → VFS → llite → OST RPC | Sync file to disk |
| Flush | ✅ `ll_flush()` | POSIX close() → VFS → llite → OST RPC | Flush file buffers |
| Mmap | ✅ `ll_file_mmap()` | POSIX mmap() → VFS → llite | Memory-mapped I/O |
| Fallocate | ✅ `ll_fallocate()` | POSIX fallocate() → VFS → llite → OST RPC | Pre-allocate space |
| Splice | ✅ `ll_splice_read()` | POSIX splice() → VFS → llite | Zero-copy data transfer |

### Directory Operations
| API | Real Lustre | User Pathway | Description |
|-----|-------------|--------------|-------------|
| Rmdir | ✅ `ll_rmdir()` | POSIX rmdir() → VFS → llite → MDS RPC | Remove directory |
| Rename | ✅ `ll_rename()` | POSIX rename() → VFS → llite → MDS RPC | Rename file/directory |
| Link | ✅ `ll_link()` | POSIX link() → VFS → llite → MDS RPC | Hard link |
| Symlink | ✅ `ll_symlink()` | POSIX symlink() → VFS → llite → MDS RPC | Symbolic link |
| Readlink | ✅ `readlink()` | POSIX readlink() → VFS → llite → MDS RPC | Read symbolic link |
| Mknod | ✅ `ll_mknod()` | POSIX mknod() → VFS → llite → MDS RPC | Create special file |

### File Attributes
| API | Real Lustre | User Pathway | Description |
|-----|-------------|--------------|-------------|
| Setattr | ✅ `ll_setattr()` | POSIX chmod/chown → VFS → llite → MDS RPC | Set file attributes (size, mode, owner, times) |
| Getattr | ✅ `ll_getattr()` | POSIX stat() → VFS → llite → MDS RPC | Get file attributes |

---

## NOT Implemented - Advanced Features (50+ IOCTLs)

### Striping & Layout Management (8)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `LL_IOC_LOV_SETSTRIPE` | lfs setstripe → ioctl() → llite | Set file striping parameters |
| `LL_IOC_LOV_GETSTRIPE` | lfs getstripe → ioctl() → llite | Get file striping layout |
| `LL_IOC_LOV_SETEA` | lfs setstripe → ioctl() → llite | Set extended attributes for striping |
| `LL_IOC_LMV_SETSTRIPE` | lfs setdirstripe → ioctl() → llite | Set directory striping (DNE) |
| `LL_IOC_LMV_GETSTRIPE` | lfs getdirstripe → ioctl() → llite | Get directory striping |
| `LL_IOC_LMV_SET_DEFAULT_STRIPE` | lfs setdirstripe -D → ioctl() → llite | Set default directory striping |
| `LL_IOC_LOV_SWAP_LAYOUTS` | lfs swap_layouts → ioctl() → llite | Swap file layouts |
| `LL_IOC_MIGRATE` | lfs migrate → ioctl() → llite → MDS RPC | Migrate file to different OSTs |

### File Locking (3)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `LL_IOC_GROUP_LOCK` | lfs flushctx / direct ioctl() → llite | Group lock for coordinated access |
| `LL_IOC_GROUP_UNLOCK` | lfs flushctx / direct ioctl() → llite | Release group lock |
| `flock()` | POSIX flock() → VFS → llite → LDLM | POSIX file locking |

### Leases (3)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `LL_IOC_SET_LEASE` | fcntl(F_SETLEASE) → VFS → llite | Acquire file lease |
| `LL_IOC_GET_LEASE` | fcntl(F_GETLEASE) → VFS → llite | Get current lease state |
| Lease types | fcntl() → VFS → llite | `LL_LEASE_RDLCK`, `LL_LEASE_WRLCK`, `LL_LEASE_UNLCK` |

### HSM - Hierarchical Storage Management (11)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `LL_IOC_HSM_STATE_GET` | lfs hsm_state → ioctl() → llite | Get HSM state |
| `LL_IOC_HSM_STATE_SET` | lfs hsm_set → ioctl() → llite → MDS RPC | Set HSM state |
| `LL_IOC_HSM_CT_START` | lhsmtool_posix (copytool) → ioctl() → llite | Start copytool |
| `LL_IOC_HSM_COPY_START` | Copytool → ioctl() → llite → MDS RPC | Start HSM copy |
| `LL_IOC_HSM_COPY_END` | Copytool → ioctl() → llite → MDS RPC | End HSM copy |
| `LL_IOC_HSM_PROGRESS` | Copytool → ioctl() → llite → MDS RPC | Report HSM progress |
| `LL_IOC_HSM_REQUEST` | lfs hsm_archive/restore → ioctl() → llite → MDS RPC | HSM archive/restore request |
| `LL_IOC_HSM_ACTION` | Copytool → ioctl() → llite → MDS RPC | Get current HSM action |
| `LL_IOC_HSM_IMPORT` | lfs hsm_import → ioctl() → llite | Import archived file |
| `LL_IOC_HSM_DATA_VERSION` | lfs data_version → ioctl() → llite | Get data version for HSM |
| HSM Flags | lfs hsm_* → ioctl() → llite | `HS_DIRTY`, `HS_ARCHIVED`, `HS_RELEASED`, etc. |

### PCC - Persistent Client Cache (4)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `LL_IOC_PCC_ATTACH` | lfs pcc attach → ioctl() → llite | Attach file to PCC |
| `LL_IOC_PCC_DETACH` | lfs pcc detach → ioctl() → llite | Detach file from PCC |
| `LL_IOC_PCC_DETACH_BY_FID` | lfs pcc detach_fid → ioctl() → llite | Detach by FID |
| `LL_IOC_PCC_STATE` | lfs pcc state → ioctl() → llite | Get PCC state |

### File-Level Mirroring (FLR) (2)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `LL_IOC_FLR_SET_MIRROR` | lfs mirror create/extend → ioctl() → llite | Set mirror configuration |
| Mirror operations | lfs mirror resync/split → ioctl() → llite | Resync, split, extend mirrors |

### Extended Attributes (4)
| Operation | User Pathway | Description |
|-----------|--------------|-------------|
| `setxattr()` | POSIX setxattr() → VFS → llite → MDS RPC | Set extended attribute |
| `getxattr()` | POSIX getxattr() → VFS → llite → MDS RPC | Get extended attribute |
| `listxattr()` | POSIX listxattr() → VFS → llite → MDS RPC | List extended attributes |
| `removexattr()` | POSIX removexattr() → VFS → llite → MDS RPC | Remove extended attribute |

### File Identifiers & Metadata (7)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `LL_IOC_PATH2FID` | lfs path2fid → ioctl() → llite | Path to FID conversion |
| `LL_IOC_FID2MDTIDX` | lfs fid2mdtidx → ioctl() → llite | FID to MDT index |
| `LL_IOC_GET_MDTIDX` | lfs getstripe -m → ioctl() → llite | Get MDT index for file |
| `LL_IOC_GETOBDCOUNT` | lfs osts/df → ioctl() → llite | Get OST/MDT count |
| `LL_IOC_GETPARENT` | lfs fid2path --parents → ioctl() → llite | Get parent FID |
| `LL_IOC_DATA_VERSION` | lfs data_version → ioctl() → llite | Get file data version |
| `LL_IOC_RMFID` | lfs rmfid → ioctl() → llite → MDS RPC | Remove by FID |

### Performance & I/O Hints (3)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `LL_IOC_LADVISE` | lfs ladvise → ioctl() → llite → OST RPC | I/O advice (willneed, dontneed) |
| `LL_IOC_LADVISE2` | lfs ladvise → ioctl() → llite → OST RPC | Extended I/O advice |
| `LL_IOC_HEAT_GET` / `HEAT_SET` | lfs heat_get/set → ioctl() → llite | File heat tracking |

### Security & Permissions (3)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `LL_IOC_GETFLAGS` | lfs getstripe / lsattr → ioctl() → llite | Get file flags |
| `LL_IOC_SETFLAGS` | lfs setstripe / chattr → ioctl() → llite | Set file flags (immutable, append, etc.) |
| `LL_IOC_CLRFLAGS` | chattr → ioctl() → llite | Clear file flags |

### Project Quotas (1)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `LL_IOC_PROJECT` | lfs project → ioctl() → llite → MDS RPC | Project ID management |

### Foreign Files (1)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `LL_IOC_UNLOCK_FOREIGN` | lfs unlock_foreign → ioctl() → llite | Unlock foreign file |

### Utilities & Debug (5)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `LL_IOC_GETVERSION` | lfs getversion → ioctl() → llite | Get file version |
| `LL_IOC_FUTIMES_3` | Direct ioctl() → llite | Set file times |
| `LL_IOC_FLUSHCTX` | lfs flushctx → ioctl() → llite | Flush security context |
| `LL_IOC_GET_CONNECT_FLAGS` | Internal / lctl get_param → ioctl() → llite | Get connection flags |
| `LL_IOC_RESIZE_FS` | lctl resize_fs → ioctl() → llite | Resize filesystem |

### Loop Device (4)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `LL_IOC_LLOOP_ATTACH` | ldev → ioctl() → llite | Attach loop device |
| `LL_IOC_LLOOP_DETACH` | ldev → ioctl() → llite | Detach loop device |
| `LL_IOC_LLOOP_INFO` | ldev → ioctl() → llite | Get loop info |
| `LL_IOC_LLOOP_DETACH_BY DEV` | ldev → ioctl() → llite | Detach by device |

---

## NOT Implemented - Server-Side Features

### MDS-Specific Operations
- DNE (Distributed Namespace) management
- Remote directory operations
- Namespace snapshots
- MDT pool management
- Changelog operations
- FID allocation and management

### OSS/OST-Specific Operations
- Object versioning
- Grant management (space reservation)
- Precreation of objects
- OST pool management
- Echo client (testing)

### MGS Operations
- Configuration log management
- Parameter tuning (`lctl set_param`)
- Server registration/deregistration
- Failover configuration
- NIDs (Network IDs) management

---

## NOT Implemented - Distributed Features

### LDLM (Distributed Lock Manager)
- Extent locks (byte-range locking)
- Inode bit locks
- Plain locks
- Flock emulation
- Lock modes: `LCK_CR`, `LCK_CW`, `LCK_PR`, `LCK_PW`, `LCK_EX`, `LCK_GROUP`
- Lock conversion and cancellation
- Lock callbacks and blocking ASTs

### Recovery & Failover
- Connection recovery
- Transaction replay
- Version-based recovery (VBR)
- Adaptive timeouts
- Import/export management

### Quota System
- User quotas
- Group quotas
- Project quotas
- Quota grace periods
- Pool quotas

---

## NOT Implemented - Lustre-Specific Abstractions

### Portal RPC (ptlrpc)
- Client-server RPC framework
- Request queues and batching
- Server threads and load balancing
- RPC timeout handling

### LOV/LOD (Logical Object Volume)
- Stripe allocation policies
- QoS (Quality of Service) allocations
- Self-healing
- Component management

### Object-Based Parallel Disk (OBDCLASS)
- Device stack abstraction
- OBD device types

### LNet (Lustre Networking)
- Network abstraction
- Multi-rail support
- Router functionality

---

## NOT Implemented - Portal RPC Operations (70+ RPCs)

### MDS (Metadata Server) RPCs (30)
Real Lustre uses Portal RPC for client-server communication. The simulator uses simple message passing instead.

**User Pathway:** These are internal RPCs sent by llite (Lustre client kernel module) to MDS. Not directly accessible to users.

| RPC Operation | Triggered By | Priority | Description |
|---------------|--------------|----------|-------------|
| `MDS_GETATTR` | stat(), getattr() → llite | 🟢 HIGH | Get file/directory attributes |
| `MDS_GETATTR_NAME` | lookup() → llite | 🟢 HIGH | Get attributes by name |
| `MDS_CLOSE` | close() → llite | 🟢 HIGH | Close file handle |
| `MDS_REINT` | create/unlink/rename/etc → llite | 🟢 HIGH | Metadata reintegration (create, unlink, rename, etc.) |
| `MDS_READPAGE` | readdir() → llite | 🟢 HIGH | Read directory page |
| `MDS_CONNECT` | mount.lustre → llite | 🟢 HIGH | Client connection to MDS |
| `MDS_DISCONNECT` | umount → llite | 🟢 HIGH | Client disconnection from MDS |
| `MDS_GET_ROOT` | mount → llite | 🟢 HIGH | Get root directory FID |
| `MDS_STATFS` | statfs() → llite | 🟢 HIGH | Get filesystem statistics |
| `MDS_PIN` | Internal caching (no user trigger) | 🔴 LOW | Pin file in cache |
| `MDS_UNPIN` | Internal caching (no user trigger) | 🔴 LOW | Unpin file from cache |
| `MDS_SYNC` | sync() → llite | 🟢 HIGH | Synchronize metadata |
| `MDS_DONE_WRITING` | close() → llite | 🟡 MED | Signal write completion |
| `MDS_SET_INFO` | lctl set_param → llite | 🟡 MED | Set MDS configuration |
| `MDS_QUOTACHECK` | lfs quotacheck → ioctl() → llite | 🟡 MED | Check quota |
| `MDS_QUOTACTL` | lfs quota/setquota → ioctl() → llite | 🟡 MED | Control quota operations |
| `MDS_GETXATTR` | getxattr() → llite | 🟢 HIGH | Get extended attribute |
| `MDS_SETXATTR` | setxattr() → llite | 🟢 HIGH | Set extended attribute |
| `MDS_WRITEPAGE` | Internal directory update (no user trigger) | 🔴 LOW | Write directory page |
| `MDS_IS_SUBDIR` | Internal path resolution (no user trigger) | 🔴 LOW | Check if path is subdirectory |
| `MDS_GET_INFO` | lfs check → ioctl() → llite | 🟡 MED | Get MDS information |
| `MDS_HSM_STATE_GET` | lfs hsm_state → ioctl() → llite | 🟡 MED | Get HSM state |
| `MDS_HSM_STATE_SET` | lfs hsm_set → ioctl() → llite | 🟡 MED | Set HSM state |
| `MDS_HSM_ACTION` | Copytool → ioctl() → llite | 🟡 MED | HSM action request |
| `MDS_HSM_PROGRESS` | Copytool → ioctl() → llite | 🟡 MED | HSM progress update |
| `MDS_HSM_REQUEST` | lfs hsm_archive/restore → ioctl() → llite | 🟡 MED | HSM archive/restore request |
| `MDS_HSM_CT_REGISTER` | lhsmtool_posix → ioctl() → llite | 🟡 MED | Register HSM copytool |
| `MDS_HSM_CT_UNREGISTER` | Copytool exit → llite | 🟡 MED | Unregister HSM copytool |
| `MDS_SWAP_LAYOUTS` | lfs swap_layouts → ioctl() → llite | 🟡 MED | Swap file layouts |
| `MDS_RMFID` | lfs rmfid → ioctl() → llite | 🟡 MED | Remove by FID |

#### MDS_REINT Sub-operations (10)
The `MDS_REINT` RPC handles multiple metadata modification operations:

| Operation | Triggered By | Priority | Description |
|-----------|--------------|----------|-------------|
| `REINT_SETATTR` | chmod/chown/truncate → llite | 🟢 HIGH | Set file attributes |
| `REINT_CREATE` | open(O_CREAT)/mknod → llite | 🟢 HIGH | Create file |
| `REINT_LINK` | link() → llite | 🟢 HIGH | Create hard link |
| `REINT_UNLINK` | unlink() → llite | 🟢 HIGH | Delete file |
| `REINT_RENAME` | rename() → llite | 🟢 HIGH | Rename file/directory |
| `REINT_OPEN` | open() → llite | 🟢 HIGH | Open file |
| `REINT_SETXATTR` | setxattr() → llite | 🟢 HIGH | Set extended attribute |
| `REINT_RMENTRY` | Internal cleanup (no user trigger) | 🔴 LOW | Remove directory entry |
| `REINT_MIGRATE` | lfs migrate → ioctl() → llite | 🟡 MED | Migrate directory to another MDT |
| `REINT_RESYNC` | lfs mirror resync → ioctl() → llite | 🟡 MED | Resync mirrored file |

### OST (Object Storage Target) RPCs (23)
**User Pathway:** Internal RPCs sent by llite to OST. Not directly accessible to users.

| RPC Operation | Triggered By | Priority | Description |
|---------------|--------------|----------|-------------|
| `OST_REPLY` | Internal RPC framework (no user trigger) | 🔴 LOW | OST response message |
| `OST_GETATTR` | stat() on striped file → llite | 🟢 HIGH | Get object attributes |
| `OST_SETATTR` | truncate() → llite | 🟢 HIGH | Set object attributes |
| `OST_READ` | read() → llite | 🟢 HIGH | Read object data |
| `OST_WRITE` | write() → llite | 🟢 HIGH | Write object data |
| `OST_CREATE` | open(O_CREAT) → llite | 🟢 HIGH | Create object |
| `OST_DESTROY` | unlink() → llite | 🟢 HIGH | Destroy object |
| `OST_GET_INFO` | lfs check/df → ioctl() → llite | 🟡 MED | Get OST information |
| `OST_CONNECT` | mount.lustre → llite | 🟢 HIGH | Client connection to OST |
| `OST_DISCONNECT` | umount → llite | 🟢 HIGH | Client disconnection from OST |
| `OST_PUNCH` | fallocate(PUNCH_HOLE) → llite | 🟡 MED | Punch hole in object (deallocate range) |
| `OST_OPEN` | open() → llite | 🟢 HIGH | Open object |
| `OST_CLOSE` | close() → llite | 🟢 HIGH | Close object |
| `OST_STATFS` | statfs() → llite | 🟢 HIGH | Get OST filesystem statistics |
| `OST_SYNC` | fsync() → llite | 🟢 HIGH | Synchronize object to disk |
| `OST_SET_GRANT_INFO` | Internal grant management (no user trigger) | 🔴 LOW | Set grant information |
| `OST_SET_INFO` | lctl set_param → llite | 🟡 MED | Set OST configuration |
| `OST_QUOTACHECK` | lfs quotacheck → ioctl() → llite | 🟡 MED | Check quota on OST |
| `OST_QUOTACTL` | lfs quota/setquota → ioctl() → llite | 🟡 MED | Control OST quota |
| `OST_QUOTA_ADJUST_QUNIT` | Internal quota adjustment (no user trigger) | 🔴 LOW | Adjust quota unit |
| `OST_LADVISE` | lfs ladvise → ioctl() → llite | 🟡 MED | I/O advice to OST |
| `OST_FALLOCATE` | fallocate() → llite | 🟢 HIGH | Pre-allocate space |
| `OST_SEEK` | lseek(SEEK_DATA/HOLE) → llite | 🟢 HIGH | Seek to data/hole |

### MGS (Management Server) RPCs (7)
**User Pathway:** Internal RPCs sent by servers and clients to MGS. Some triggered by lctl commands.

| RPC Operation | Triggered By | Priority | Description |
|---------------|--------------|----------|-------------|
| `MGS_CONNECT` | mount.lustre / server startup | 🟢 HIGH | Connect to MGS |
| `MGS_DISCONNECT` | umount / server shutdown | 🟢 HIGH | Disconnect from MGS |
| `MGS_EXCEPTION` | Internal error handling (no user trigger) | 🔴 LOW | Exception notification |
| `MGS_TARGET_REG` | Server startup (MDT/OST) | 🟡 MED | Register target (MDT/OST) |
| `MGS_TARGET_DEL` | Server shutdown | 🟡 MED | Deregister target |
| `MGS_SET_INFO` | lctl conf_param / set_param -P | 🟡 MED | Set MGS configuration |
| `MGS_CONFIG_READ` | mount / lctl get_param | 🟢 HIGH | Read configuration log |

### LDLM (Distributed Lock Manager) RPCs (6)
**User Pathway:** Internal RPCs triggered automatically by I/O operations. Not directly user-accessible.

| RPC Operation | Triggered By | Priority | Description |
|---------------|--------------|----------|-------------|
| `LDLM_ENQUEUE` | open/read/write → llite | 🟢 HIGH | Acquire lock |
| `LDLM_CONVERT` | Lock escalation → llite | 🟡 MED | Convert lock mode |
| `LDLM_CANCEL` | close / memory pressure → llite | 🟢 HIGH | Cancel lock |
| `LDLM_BL_CALLBACK` | Lock conflict (server-initiated, no user trigger) | 🔴 LOW | Blocking lock callback |
| `LDLM_CP_CALLBACK` | Lock granted (server-initiated, no user trigger) | 🔴 LOW | Completion callback |
| `LDLM_GL_CALLBACK` | Other client's stat (server-initiated) | 🔴 LOW | Glimpse callback (get size) |

### OBD (Object-Based Disk) RPCs (4)
**User Pathway:** Internal server-to-server and monitoring RPCs.

| RPC Operation | Triggered By | Priority | Description |
|---------------|--------------|----------|-------------|
| `OBD_PING` | lctl ping / internal health check | 🟡 MED | Health check ping |
| `OBD_LOG_CANCEL` | Internal log management (no user trigger) | 🔴 LOW | Cancel log record |
| `OBD_QC_CALLBACK` | Quota enforcement (server-initiated) | 🔴 LOW | Quota callback |
| `OBD_IDX_READ` | Internal index operations (no user trigger) | 🔴 LOW | Read index |

### SEQ (Sequence Manager) RPCs (3)
**User Pathway:** Internal FID allocation between servers. Not user-accessible.

Manages FID sequence allocation:

| RPC Operation | Triggered By | Priority | Description |
|---------------|--------------|----------|-------------|
| `SEQ_QUERY` | MDS needs FIDs (server-initiated, no user trigger) | 🔴 LOW | Query sequence range |
| `SEQ_ALLOC_SUPER` | Server startup (server-initiated) | 🔴 LOW | Allocate super sequence |
| `SEQ_ALLOC_META` | MDS needs sequences (server-initiated) | 🔴 LOW | Allocate meta sequence |

### FLD (FID Location Database) RPCs (2)
**User Pathway:** Internal FID-to-location mapping. Not user-accessible.

Maps FIDs to MDT locations:

| RPC Operation | Triggered By | Priority | Description |
|---------------|--------------|----------|-------------|
| `FLD_QUERY` | Lookup FID on wrong MDT (internal routing) | 🔴 LOW | Query FID location |
| `FLD_READ` | Internal FLD sync (no user trigger) | 🔴 LOW | Read FLD entries |

### UPDATE (DNE - Distributed Namespace) RPCs (18)
**User Pathway:** Internal RPCs for multi-MDT operations (DNE). Triggered by cross-MDT operations.

Used for distributed metadata operations across multiple MDTs:

| RPC Operation | Triggered By | Priority | Description |
|---------------|--------------|----------|-------------|
| `OUT_UPDATE` | Cross-MDT operation (internal) | 🟡 MED | Distributed update |
| `OUT_CREATE` | mkdir on remote MDT | 🟡 MED | Create on remote MDT |
| `OUT_DESTROY` | rmdir on remote MDT | 🟡 MED | Destroy on remote MDT |
| `OUT_REF_ADD` | link() across MDTs | 🟡 MED | Add reference on remote MDT |
| `OUT_REF_DEL` | unlink() across MDTs | 🟡 MED | Delete reference on remote MDT |
| `OUT_ATTR_SET` | setattr() on remote MDT | 🟡 MED | Set attributes on remote MDT |
| `OUT_ATTR_GET` | getattr() on remote MDT | 🟡 MED | Get attributes from remote MDT |
| `OUT_XATTR_SET` | setxattr() on remote MDT | 🟡 MED | Set xattr on remote MDT |
| `OUT_XATTR_GET` | getxattr() on remote MDT | 🟡 MED | Get xattr from remote MDT |
| `OUT_XATTR_LIST` | listxattr() on remote MDT | 🟡 MED | List xattrs on remote MDT |
| `OUT_INDEX_LOOKUP` | Lookup in remote directory | 🟡 MED | Lookup in remote index |
| `OUT_INDEX_INSERT` | Create in remote directory | 🟡 MED | Insert into remote index |
| `OUT_INDEX_DELETE` | Delete from remote directory | 🟡 MED | Delete from remote index |
| `OUT_WRITE` | Write to remote striped dir | 🟡 MED | Write to remote object |
| `OUT_READ` | Read from remote striped dir | 🟡 MED | Read from remote object |
| `OUT_NOOP` | Testing framework | 🔴 LOW | No-op for testing |
| `OUT_XATTR_DEL` | removexattr() on remote MDT | 🟡 MED | Delete xattr on remote MDT |
| `OUT_PUNCH` | Punch on remote striped dir | 🟡 MED | Punch on remote object |

---

## NOT Implemented - Administrative IOCTLs (47+)

These are server-side and administrative operations accessible via `lctl` and other tools.

**User Pathway:** All accessed via `lctl` command → ioctl() → kernel module (llite/obd/lmv/etc.)

### OBD Device Management (12)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `OBD_IOC_CREATE` | lctl --device → ioctl() | Create OBD device |
| `OBD_IOC_DESTROY` | lctl --device → ioctl() | Destroy OBD device |
| `OBD_IOC_PREALLOCATE` | lctl → ioctl() | Preallocate objects |
| `OBD_IOC_SETATTR` | lctl → ioctl() | Set OBD attributes |
| `OBD_IOC_GETATTR` | lctl → ioctl() | Get OBD attributes |
| `OBD_IOC_READ` | lctl → ioctl() | Read OBD data |
| `OBD_IOC_WRITE` | lctl → ioctl() | Write OBD data |
| `OBD_IOC_STATFS` | lctl → ioctl() | Get OBD filesystem stats |
| `OBD_IOC_SYNC` | lctl → ioctl() | Sync OBD device |
| `OBD_IOC_DESTROY_ORPHAN` | lctl → ioctl() | Destroy orphaned objects |
| `OBD_IOC_BRW_READ` | lctl → ioctl() | Bulk read/write read |
| `OBD_IOC_BRW_WRITE` | lctl → ioctl() | Bulk read/write write |

### Quota Management (4)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `OBD_IOC_QUOTACHECK` | lfs quotacheck → ioctl() | Check quota consistency |
| `OBD_IOC_POLL_QUOTACHECK` | lfs quotacheck → ioctl() | Poll quota check status |
| `OBD_IOC_QUOTACTL` | lfs quota/setquota → ioctl() | Quota control operations |
| `OBD_IOC_QUOTA_ADJUST_QUNIT` | Internal quota system | Adjust quota unit |

### Changelog (6)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `OBD_IOC_CHANGELOG_SEND` | lfs changelog → ioctl() | Send changelog records |
| `OBD_IOC_CHANGELOG_CLEAR` | lfs changelog_clear → ioctl() | Clear changelog |
| `OBD_IOC_CHANGELOG_REG` | lctl --device changelog_register | Register changelog user |
| `OBD_IOC_CHANGELOG_DEREG` | lctl --device changelog_deregister | Deregister changelog user |
| `OBD_IOC_CHANGELOG` | lfs changelog → ioctl() | Get changelog entries |
| `OBD_IOC_CATLOGLIST` | lctl catlist → ioctl() | List catalog logs |

### Server Administration (9)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `OBD_IOC_PING_TARGET` | lctl ping → ioctl() | Ping server target |
| `OBD_IOC_ADD_CONN` | lctl add_conn → ioctl() | Add connection |
| `OBD_IOC_DEL_CONN` | lctl del_conn → ioctl() | Delete connection |
| `OBD_IOC_BARRIER` | lctl barrier freeze/thaw → ioctl() | Write barrier operations |
| `OBD_IOC_BARRIER_STAT` | lctl barrier_stat → ioctl() | Get barrier status |
| `OBD_IOC_POOL_LIST` | lctl pool_list → ioctl() | List OST pools |
| `OBD_IOC_POOL_INFO` | lfs pool_list → ioctl() | Get pool information |
| `OBD_IOC_POOL_NEW` | lctl pool_new → ioctl() | Create new OST pool |
| `OBD_IOC_POOL_DEL` | lctl pool_destroy → ioctl() | Delete OST pool |

### FID and Path Operations (3)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `OBD_IOC_FID2PATH` | lfs fid2path → ioctl() | Convert FID to path |
| `OBD_IOC_PATH2FID` | lfs path2fid → ioctl() | Convert path to FID |
| `OBD_IOC_GETNAME` | lctl get_param → ioctl() | Get device name |

### Logging and Debugging (6)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `OBD_IOC_LLOG_PRINT` | lctl --device llog_print → ioctl() | Print llog records |
| `OBD_IOC_LLOG_CANCEL` | lctl --device llog_cancel → ioctl() | Cancel llog record |
| `OBD_IOC_LLOG_REMOVE` | lctl --device llog_remove → ioctl() | Remove llog |
| `OBD_IOC_LLOG_CHECK` | lctl --device llog_check → ioctl() | Check llog consistency |
| `OBD_IOC_LLOG_INFO` | lctl --device llog_info → ioctl() | Get llog information |
| `OBD_IOC_LLOG_CATINFO` | lctl --device llog_catinfo → ioctl() | Get catalog info |

### Other Administrative Operations (7)
| IOCTL | User Pathway | Description |
|-------|--------------|-------------|
| `OBD_IOC_PARAM` | lctl set_param / get_param → ioctl() | Set/get parameters |
| `OBD_IOC_DUMP_LOG` | lctl --device dump_log → ioctl() | Dump server log |
| `OBD_IOC_CLEAR_LOG` | lctl --device clear_log → ioctl() | Clear server log |
| `OBD_IOC_PARSE` | Internal configuration parser | Parse configuration |
| `OBD_IOC_PROCESS_CFG` | lctl --device process_cfg → ioctl() | Process configuration |
| `OBD_IOC_REPLACE_NIDS` | lctl replace_nids → ioctl() | Replace NIDs |
| `OBD_IOC_START` | lctl --device startup → ioctl() | Start OBD device |

---

## NOT Implemented - Userspace Utility APIs (63+ utilities)

The `lustre/utils/` directory contains extensive userspace APIs:

### Core Utilities (8)
- `lfs` - Lustre File System utility (striping, migration, pools, HSM)
- `lctl` - Lustre control utility (configuration, parameters, debugging)
- `llog_reader` - Read Lustre log files
- `lr_reader` - Last rcvd file reader
- `mount.lustre` - Mount Lustre filesystems
- `mkfs.lustre` - Create Lustre filesystems
- `tunefs.lustre` - Tune Lustre filesystem parameters
- `llverfs` - Lustre filesystem verification

### HSM Tools (5)
- `lhsmtool_posix` - POSIX HSM copytool
- `lhsm_import` - Import archived files
- `lhsm_state` - Get/set HSM state
- `lhsm_release` - Release archived files
- `lhsm_restore` - Restore archived files

### Debugging Tools (7)
- `llog_test` - Test llog operations
- `obdctl` - OBD device control
- `lstress` - Lustre stress testing
- `lstripe` - Stripe testing
- `llobdstat` - OBD statistics
- `plot-llstat` - Plot statistics
- `llstat` - Lustre statistics

### Network Tools (4)
- `lnetctl` - LNet control utility
- `routerstat` - LNet router statistics
- `lstclient` - Lustre self-test client
- `wirecheck` - Wire protocol checker

### Library APIs (3)
- `liblustreapi` - Main Lustre API library
  - File striping APIs (40+ functions)
  - HSM APIs (20+ functions)
  - Path/FID conversion (10+ functions)
  - Pool management (8+ functions)
  - Changelog APIs (6+ functions)
  - Mirror/FLR APIs (12+ functions)
  - Quota APIs (5+ functions)
- `liblnetconfig` - LNet configuration library
- `libmount_utils_ldiskfs` - Mount utilities for ldiskfs

### Other Utilities (36)
Including: `l_getidentity`, `gss` tools, `ltrack_stats`, `portals`, `wiretest`, `create_iam`, various test utilities, and server-side tools.

---

## Recommendations for Simulator Enhancement

### High Priority (User-Visible Operations)
1. **Open/Close** - File descriptor management
2. **Seek** - Random access
3. **Fsync** - Data persistence
4. **Rename** - File/directory renaming
5. **Setattr/Chmod/Chown** - Permissions and ownership
6. **Link/Symlink** - Hard and symbolic links
7. **Extended Attributes** - xattr operations

### Medium Priority (Common Advanced Features)
1. **Striping Management** - `LOV_SETSTRIPE`/`LOV_GETSTRIPE`
2. **Group Locks** - Multi-file coordination
3. **File Versioning** - Data version tracking
4. **DNE** - Distributed directory operations
5. **I/O Hints** - `LADVISE` for performance

### Low Priority (Specialized Features)
1. **HSM** - Hierarchical Storage Management
2. **PCC** - Persistent Client Cache
3. **FLR** - File-Level Mirroring
4. **Leases** - Application-level synchronization
5. **Quota** - Space usage limits

---

## Key Architectural Differences

| Feature | Simulator | Real Lustre |
|---------|-----------|-------------|
| **VFS Integration** | ❌ No VFS layer | ✅ Full Linux VFS integration |
| **Portal RPC** | ❌ Simple message passing | ✅ Complete ptlrpc framework |
| **LDLM** | ⚠️ Basic stub | ✅ Full distributed lock manager |
| **Recovery** | ❌ None | ✅ Transaction replay, VBR |
| **Networking** | ⚠️ Simulated delays | ✅ LNet with multi-rail |
| **Object Storage** | ⚠️ In-memory dicts | ✅ ldiskfs/ZFS backends |
| **Metadata Storage** | ⚠️ In-memory dicts | ✅ ldiskfs/ZFS on MDT |
| **Striping** | ⚠️ Basic allocation | ✅ QoS, pools, PFL (Progressive File Layouts) |
| **Quotas** | ❌ None | ✅ User/group/project quotas |
| **Snapshots** | ❌ None | ✅ ZFS-based snapshots |

---

## Conclusion

The simulator provides a **basic functional model** covering:
- ✅ Core file operations (create, read, write, delete, stat)
- ✅ Basic directory operations (mkdir, list)
- ✅ Simple striping across OSTs
- ✅ Failure injection and recovery
- ✅ Basic client-server message passing

It is **suitable for**:
- Understanding Lustre architecture at a high level
- Testing basic distributed file system scenarios
- Simulating failures and performance patterns
- Educational purposes and prototyping

It is **NOT suitable for**:
- Testing advanced Lustre features (HSM, PCC, FLR, DNE, PFL)
- Security/quota/changelog modeling
- Real performance benchmarking
- Recovery protocol testing (VBR, transaction replay)
- Detailed LDLM behavior (extent locks, lock modes, callbacks)
- Server administration workflows
- Production workload simulation

---

## API Coverage Breakdown

**Implemented (10 APIs):**
- File operations: CreateFile, Read, Write, Delete, Stat
- Directory operations: Mkdir, ListDir
- Internal: Lock, Unlock, GetLayout (defined but not exercised)

**Not Implemented:**
- **Client-side VFS operations:** 65+ APIs (open, close, seek, fsync, rename, link, symlink, setattr, xattrs, etc.)
- **Client-side IOCTLs:** 50+ (striping, HSM, PCC, FLR, leases, mirrors, heat tracking, etc.)
- **Portal RPCs:** 113 operations across all services
- **Administrative IOCTLs:** 47+ operations (lctl, llog, barriers, pools, quotas, etc.)
- **Userspace tools:** 63+ utilities (lfs, lctl, HSM tools, network tools, debugging tools)

**Total Coverage: ~5% of full Lustre API surface (10 / 200+)**

---

## Priority Legend

The APIs have been marked with priority levels based on user-triggerability:

- **🟢 HIGH Priority:** User can directly or indirectly trigger these via POSIX operations, lfs, or lctl commands
  - Examples: `MDS_GETATTR` (stat()), `OST_READ` (read()), `LDLM_ENQUEUE` (triggered by open/read/write)
  - **Recommendation:** Implement these first for realistic simulation

- **🟡 MED Priority:** User-triggerable but less common or advanced features
  - Examples: `MDS_QUOTACTL` (quotas), `OST_LADVISE` (I/O hints), `OUT_CREATE` (DNE multi-MDT)
  - **Recommendation:** Implement after HIGH priority APIs

- **🔴 LOW Priority:** Internal system operations NOT triggerable by users (directly or indirectly)
  - Examples: `MDS_PIN/UNPIN` (internal caching), `LDLM_BL_CALLBACK` (server-initiated), `SEQ_QUERY` (server-to-server)
  - **Recommendation:** Skip for simulation - these happen automatically without user involvement

**Priority Breakdown for Portal RPCs:**
- 🟢 HIGH: 46 operations (user-facing I/O and basic operations)
- 🟡 MED: 41 operations (advanced features, admin, DNE)
- 🔴 LOW: 26 operations (pure internal, no user trigger)

For a realistic simulator focusing on user-observable behavior, implement HIGH priority APIs first.
