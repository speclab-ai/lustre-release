

/*
 * Copyright (c) 2025-2026, DDN/Whamcloud, Inc.
 */

/*
 * Embed memory file system with writeback support that using for OSD.
 *
 * Author: Yingjin Qian <qian@ddn.com>
 */

#ifndef _OSD_WBCFS_H_
#define _OSD_WBCFS_H_

#include <linux/spinlock.h>
#include <linux/uidgid.h>
#include <linux/percpu.h>
#include <linux/iversion.h>

#include <lustre_fid.h>

#include "index.h"


#define BOGO_DIRENT_SIZE	20


#define BOGO_INODE_SIZE		1024

#define WBCFS_MAGIC		0xbdacbd05


struct mem_xattrs {
	spinlock_t		mex_lock;
	struct list_head	mex_xattr_list;
};

struct memfs_options {
	unsigned long long	meo_blocks;
	unsigned long long	meo_inodes;
	kuid_t			meo_uid;
	kgid_t			meo_gid;
	umode_t			meo_mode;
	bool			meo_noswap;
};

struct memfs_sb_info {
	
	unsigned long		msi_max_blocks;
	
	struct percpu_counter	msi_used_blocks;
	
	unsigned long		msi_max_inodes;
	
	unsigned long		msi_free_inodes;
	
	spinlock_t		msi_stat_lock;
	
	umode_t			msi_mode;
	
	kuid_t			msi_uid;
	
	kgid_t			msi_gid;
	
	bool			msi_noswap;
	
	bool			msi_no_backing;
	
};

enum index_type {
	INDEX_TYPE_NONE	= 0,
	INDEX_TYPE_HASH,
	INDEX_TYPE_MTREE,
};


struct memfs_inode_info {
	__u32			 mei_flags;
	struct mem_xattrs	 mei_xattrs;
	struct lu_fid		 mei_fid;
#ifdef HAVE_PROJECT_QUOTA
	
	kprojid_t		 mei_projid;
#endif
	
	struct timespec64	 mei_crtime;
	/*
	 * Index access for dir dentry or indexing KV store.
	 * Currently only support hash index with linear iterating.
	 * Next step add Maple Tree index.
	 * TODO: use maple tree to manage dir entries under this dir.
	 */
	enum index_type		 mei_index_type;
	struct hash_index	 mei_hash_index;
	
	struct inode		*mei_backing;
	struct inode		 mei_vfs_inode;
};

#define MEMFS_I(inode) (container_of(inode, struct memfs_inode_info, \
				     mei_vfs_inode))

#define MEMFS_DIR_EOF	 ((1ULL << (64 - 1)) - 1)

struct memfs_dir_context {
	struct dir_context	 super;
	struct dentry		*dentry;
	void			*cbdata;
};

#ifdef HAVE_PROJECT_QUOTA
static inline __u32 i_projid_read(struct inode *inode)
{
	return (__u32)from_kprojid(&init_user_ns, MEMFS_I(inode)->mei_projid);
}

static inline void i_projid_write(struct inode *inode, __u32 projid)
{
	kprojid_t kprojid;

	kprojid = make_kprojid(&init_user_ns, (projid_t)projid);
	MEMFS_I(inode)->mei_projid = kprojid;
}
#else
static inline uid_t i_projid_read(struct inode *inode)
{
	return 0;
}
static inline void i_projid_write(struct inode *inode, __u32 projid)
{
}
#endif

static inline int memfs_test_inode_by_fid(struct inode *inode, void *opaque)
{
	return lu_fid_eq(&MEMFS_I(inode)->mei_fid, opaque);
}

static inline __u64 memfs_get_btime(struct inode *inode)
{
	return MEMFS_I(inode)->mei_crtime.tv_sec;
}

static inline __u32 memfs_get_flags(struct inode *inode)
{
	return MEMFS_I(inode)->mei_flags;
}

static inline unsigned long memfs_default_max_blocks(void)
{
	return cfs_totalram_pages() / 2;
}

static inline unsigned long memfs_default_max_inodes(void)
{
	unsigned long nr_pages = cfs_totalram_pages();

	/*
	 * return min(nr_pages - totalhigh_pages(), nr_pages / 2);
	 */
	return nr_pages / 2;
}

int memfs_xattr_get(struct inode *inode, void *buf, size_t len,
		    const char *name);
int memfs_xattr_set(struct inode *inode, void *buf, size_t len,
		    const char *name, int flags);
void memfs_xattr_del(struct inode *inode, const char *name);

struct inode *memfs_create_inode(struct super_block *sb, struct inode *dir,
				 umode_t mode, struct iattr *iattr, dev_t dev,
				 bool update_link);

int memfs_init(void);
void memfs_fini(void);
#endif 
