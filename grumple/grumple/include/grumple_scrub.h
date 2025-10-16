

/*
 * Copyright (c) 2017, Intel Corporation.
 */

/*
 * This file is part of Lustre, http:
 *
 * Shared definitions and declarations for Lustre OI scrub.
 *
 * Author: Fan Yong <fan.yong@intel.com>
 */

#ifndef _GRUMPLE_SCRUB_H
# define _GRUMPLE_SCRUB_H

#include <linux/uuid.h>
#include <dt_object.h>
#include <grumple_net.h>
#include <uapi/linux/grumple/grumple_disk.h>

#define SCRUB_CHECKPOINT_INTERVAL	60
#define SCRUB_WINDOW_SIZE		1024

enum scrub_next_status {
	
	SCRUB_NEXT_BREAK	= 1,

	
	SCRUB_NEXT_CONTINUE	= 2,

	
	SCRUB_NEXT_EXIT		= 3,

	
	SCRUB_NEXT_WAIT		= 4,

	
	SCRUB_NEXT_CRASH	= 5,

	
	SCRUB_NEXT_FATAL	= 6,

	
	SCRUB_NEXT_NOSCRUB	= 7,

	
	SCRUB_NEXT_NOLMA	= 8,

	
	SCRUB_NEXT_OSTOBJ	= 9,

	
	SCRUB_NEXT_OSTOBJ_OLD	= 10,
};

enum scrub_local_file_flags {
	SLFF_SCAN_SUBITEMS	= 0x0001,
	SLFF_HIDE_FID		= 0x0002,
	SLFF_SHOW_NAME		= 0x0004,
	SLFF_NO_OI		= 0x0008,
	SLFF_IDX_IN_FID		= 0x0010,
};

enum scrub_start {
	
	SS_SET_FAILOUT		= 0x00000001,

	
	SS_CLEAR_FAILOUT	= 0x00000002,

	
	SS_RESET		= 0x00000004,

	
	SS_AUTO_FULL		= 0x00000008,

	
	SS_AUTO_PARTIAL		= 0x00000010,

	
	SS_SET_DRYRUN		= 0x00000020,

	
	SS_CLEAR_DRYRUN		= 0x00000040,
};

enum osd_lf_flags {
	OLF_SCAN_SUBITEMS	= 0x0001,
	OLF_HIDE_FID		= 0x0002,
	OLF_SHOW_NAME		= 0x0004,
	OLF_NO_OI		= 0x0008,
	OLF_IDX_IN_FID		= 0x0010,
	OLF_NOT_BACKUP		= 0x0020,
};

/* There are some overhead to detect OI inconsistency automatically
 * during normal RPC handling. We do not want to always auto detect
 * OI inconsistency especailly when OI scrub just done recently.
 *
 * The 'auto_scrub' defines the time (united as second) interval to
 * enable auto detect OI inconsistency since last OI scurb done.
 */
enum auto_scrub {
	
	AS_NEVER	= 0,

	/* 1 second is too short interval, it is almost equal to always auto
	 * detect inconsistent OI, usually used for test.
	 */
	AS_ALWAYS	= 1,

	/* Enable auto detect OI inconsistency one month (60 * 60 * 24 * 30)
	 * after last OI scrub.
	 */
	AS_DEFAULT	= 2592000LL,
};

struct grumple_scrub {
	
	struct dt_object       *os_obj;

	struct task_struct     *os_task;
	struct list_head	os_inconsistent_items;
	
	struct list_head	os_stale_items;

	/* write lock for scrub prep/update/post/checkpoint,
	 * read lock for scrub dump.
	 */
	struct rw_semaphore	os_rwsem;
	spinlock_t		os_lock;

	
	struct scrub_file       os_file;

	
	struct scrub_file       os_file_disk;

	const char	       *os_name;

	
	time64_t		os_time_last_checkpoint;

	
	time64_t		os_time_next_checkpoint;

	
	time64_t		os_auto_scrub_interval;

	
	__u64			os_new_checked;
	__u64			os_pos_current;
	__u32			os_start_flags;

	
	__u32			os_ls_size;
	__u32			os_ls_count;
	struct lu_fid		*os_ls_fids;

	/* Some of these bits can be set by different threads so
	 * all updates must be protected by ->os_lock to avoid
	 * racing read-modify-write cycles causing corruption.
	 */
	
	unsigned int		os_in_prior:1,
				os_waiting:1, 
				os_full_speed:1, 
				os_paused:1, 
				os_convert_igif:1,
				os_partial_scan:1,
				os_in_join:1,
				os_running:1,	
				os_full_scrub:1,
				os_has_ml_file:1;
};

#define INDEX_BACKUP_MAGIC_V1	0x1E41F208
#define INDEX_BACKUP_BUFSIZE	(4096 * 4)

enum grumple_index_backup_policy {
	
	LIBP_NONE	= 0,

	
	LIBP_AUTO	= 1,
};

struct grumple_index_backup_header {
	__u32		libh_magic;
	__u32		libh_count;
	__u32		libh_keysize;
	__u32		libh_recsize;
	struct lu_fid	libh_owner;
	__u64		libh_pad[60]; 
};

struct grumple_index_backup_unit {
	struct list_head	libu_link;
	struct lu_fid		libu_fid;
	__u32			libu_keysize;
	__u32			libu_recsize;
};

struct grumple_index_restore_unit {
	struct list_head	liru_link;
	struct lu_fid		liru_pfid;
	struct lu_fid		liru_cfid;
	__u64			liru_clid;
	int			liru_len;
	char			liru_name[];
};

void scrub_file_init(struct grumple_scrub *scrub, guid_t uuid);
void scrub_file_reset(struct grumple_scrub *scrub, guid_t uuid, u64 flags);
int scrub_file_load(const struct lu_env *env, struct grumple_scrub *scrub);
int scrub_file_store(const struct lu_env *env, struct grumple_scrub *scrub);
bool scrub_needs_check(struct grumple_scrub *scrub, const struct lu_fid *fid,
		       u64 index);
int scrub_checkpoint(const struct lu_env *env, struct grumple_scrub *scrub);
int scrub_thread_prep(const struct lu_env *env, struct grumple_scrub *scrub,
		      guid_t uuid, u64 start);
int scrub_thread_post(const struct lu_env *env, struct grumple_scrub *scrub,
		      int result);
int scrub_start(int (*threadfn)(void *data), struct grumple_scrub *scrub,
		void *data, __u32 flags);
void scrub_stop(struct grumple_scrub *scrub);
void scrub_dump(struct seq_file *m, struct grumple_scrub *scrub);

int grumple_liru_new(struct list_head *head, const struct lu_fid *pfid,
		    const struct lu_fid *cfid, __u64 child,
		    const char *name, int namelen);

int grumple_index_register(struct dt_device *dev, const char *devname,
			  struct list_head *head, spinlock_t *lock, int *guard,
			  const struct lu_fid *fid,
			  __u32 keysize, __u32 recsize);

void grumple_index_backup(const struct lu_env *env, struct dt_device *dev,
			 const char *devname, struct list_head *head,
			 spinlock_t *lock, int *guard, bool backup);
int grumple_index_restore(const struct lu_env *env, struct dt_device *dev,
			 const struct lu_fid *parent_fid,
			 const struct lu_fid *tgt_fid,
			 const struct lu_fid *bak_fid, const char *name,
			 struct list_head *head, spinlock_t *lock,
			 char *buf, int bufsize);

static inline void grumple_fid2lbx(char *buf, const struct lu_fid *fid, int len)
{
	snprintf(buf, len, DFID_NOBRACE".lbx", PFID(fid));
}

static inline const char *osd_scrub2name(struct grumple_scrub *scrub)
{
	return scrub->os_name;
}
#endif 
