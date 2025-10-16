

/*
 * Copyright (c) 2008, 2010, Oracle and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 *
 * Copyright (c) 2012, 2015, Intel Corporation.
 */

/*
 * This file is part of Lustre, http:
 *
 * Hashing routines
 */

#ifndef __LIBCFS_HASH_H__
#define __LIBCFS_HASH_H__

#include <linux/spinlock.h>
#include <linux/workqueue.h>
#include <linux/refcount.h>
#include <linux/libcfs/libcfs_debug.h>
#include <linux/libcfs/libcfs_private.h>


#define CFS_HASH_DEBUG_NONE	0
/* record hash depth and output to console when it's too deep,
 *  computing overhead is low but consume more memory
 */
#define CFS_HASH_DEBUG_1	1

#define CFS_HASH_DEBUG_2	2

#define CFS_HASH_DEBUG_LEVEL	CFS_HASH_DEBUG_NONE

struct cfs_hash_ops;
struct cfs_hash_lock_ops;
struct cfs_hash_hlist_ops;

union cfs_hash_lock {
	rwlock_t		rw;		
	spinlock_t		spin;		
	struct rw_semaphore	rw_sem;		
};

/*
 * cfs_hash_bucket is a container of:
 * - lock, counter ...
 * - array of hash-head starting from hsb_head[0], hash-head can be one of
 *   . struct cfs_hash_head
 *   . struct cfs_hash_head_dep
 *   . struct cfs_hash_dhead
 *   . struct cfs_hash_dhead_dep
 *   which depends on requirement of user
 * - some extra bytes (caller can require it while creating hash)
 */
struct cfs_hash_bucket {
	union cfs_hash_lock	hsb_lock;	
	__u32			hsb_count;	
	__u32			hsb_version;	
	unsigned int		hsb_index;	
	int			hsb_depmax;	
	long			hsb_head[];	
};

/*
 * cfs_hash bucket descriptor, it's normally in stack of caller
 */
struct cfs_hash_bd {
	
	struct cfs_hash_bucket	*bd_bucket;
	
	unsigned int		 bd_offset;
};

#define CFS_HASH_NAME_LEN           16      
#define CFS_HASH_BIGNAME_LEN        64      

#define CFS_HASH_BKT_BITS           3       
#define CFS_HASH_BITS_MAX           30      
#define CFS_HASH_BITS_MIN           CFS_HASH_BKT_BITS

/*
 * common hash attributes.
 */
enum cfs_hash_tag {
	/*
	 * don't need any lock, caller will protect operations with it's
	 * own lock. With this flag:
	 *  . CFS_HASH_NO_BKTLOCK, CFS_HASH_RW_BKTLOCK, CFS_HASH_SPIN_BKTLOCK
	 *    will be ignored.
	 *  . Some functions will be disabled with this flag, i.e:
	 *    cfs_hash_for_each_empty, cfs_hash_rehash
	 */
	CFS_HASH_NO_LOCK	= BIT(0),
	
	CFS_HASH_NO_BKTLOCK	= BIT(1),
	
	CFS_HASH_RW_BKTLOCK	= BIT(2),
	
	CFS_HASH_SPIN_BKTLOCK	= BIT(3),
	
	CFS_HASH_ADD_TAIL	= BIT(4),
	
	CFS_HASH_NO_ITEMREF	= BIT(5),
	
	CFS_HASH_BIGNAME	= BIT(6),
	
	CFS_HASH_COUNTER	= BIT(7),
	
	CFS_HASH_REHASH_KEY	= BIT(8),
	
	CFS_HASH_REHASH		= BIT(9),
	
	CFS_HASH_SHRINK		= BIT(10),
	
	CFS_HASH_ASSERT_EMPTY	= BIT(11),
	
	CFS_HASH_DEPTH		= BIT(12),
	/*
	 * rehash is always scheduled in a different thread, so current
	 * change on hash table is non-blocking
	 */
	CFS_HASH_NBLK_CHANGE	= BIT(13),
	
	CFS_HASH_RW_SEM_BKTLOCK	= BIT(14),
	/* NB, we typed hs_flags as  __u16, please change it
	 * if you need to extend >=16 flags
	 */
};


#define CFS_HASH_DEFAULT       (CFS_HASH_RW_BKTLOCK |			\
				CFS_HASH_COUNTER | CFS_HASH_REHASH)

/*
 * cfs_hash is a hash-table implementation for general purpose, it can support:
 *    . two refcount modes
 *      hash-table with & without refcount
 *    . four lock modes
 *      nolock, one-spinlock, rw-bucket-lock, spin-bucket-lock
 *    . general operations
 *      lookup, add(add_tail or add_head), delete
 *    . rehash
 *      grows or shrink
 *    . iteration
 *      locked iteration and unlocked iteration
 *    . bigname
 *      support long name hash
 *    . debug
 *      trace max searching depth
 *
 * Rehash:
 * When the htable grows or shrinks, a separate task (cfs_hash_rehash_worker)
 * is spawned to handle the rehash in the background, it's possible that other
 * processes can concurrently perform additions, deletions, and lookups
 * without being blocked on rehash completion, because rehash will release
 * the global wrlock for each bucket.
 *
 * rehash and iteration can't run at the same time because it's too tricky
 * to keep both of them safe and correct.
 * As they are relatively rare operations, so:
 *   . if iteration is in progress while we try to launch rehash, then
 *     it just giveup, iterator will launch rehash at the end.
 *   . if rehash is in progress while we try to iterate the hash table,
 *     then we just wait (shouldn't be very long time), anyway, nobody
 *     should expect iteration of whole hash-table to be non-blocking.
 *
 * During rehashing, a (key,object) pair may be in one of two buckets,
 * depending on whether the worker task has yet to transfer the object
 * to its new location in the table. Lookups and deletions need to search both
 * locations; additions must take care to only insert into the new bucket.
 */

struct cfs_hash {
	/* serialize with rehash, or serialize all operations if
	 * the hash-table has CFS_HASH_NO_BKTLOCK
	 */
	union cfs_hash_lock		hs_lock;
	
	struct cfs_hash_ops		*hs_ops;
	
	struct cfs_hash_lock_ops	*hs_lops;
	
	struct cfs_hash_hlist_ops	*hs_hops;
	
	struct cfs_hash_bucket		**hs_buckets;
	
	atomic_t			hs_count;
	
	__u16                       hs_flags;
	
	__u16                       hs_extra_bytes;
	
	__u8                        hs_iterating;
	
	__u8                        hs_exiting;
	
	__u8                        hs_cur_bits;
	
	__u8                        hs_min_bits;
	
	__u8                        hs_max_bits;
	
	__u8                        hs_rehash_bits;
	
	__u8                        hs_bkt_bits;
	
	__u16                       hs_min_theta;
	
	__u16                       hs_max_theta;
	
	__u32                       hs_rehash_count;
	
	__u32                       hs_iterators;
	
	struct work_struct		hs_rehash_work;
	
	struct kref			hs_refcount;
	
	struct cfs_hash_bucket		**hs_rehash_buckets;
#if CFS_HASH_DEBUG_LEVEL >= CFS_HASH_DEBUG_1
	
	spinlock_t		    hs_dep_lock;
	
	unsigned int                hs_dep_max;
	
	unsigned int                hs_dep_bkt;
	
	unsigned int                hs_dep_off;
	
	unsigned int                hs_dep_bits;
	
	struct work_struct		hs_dep_work;
#endif
	
	char                        hs_name[];
};

struct cfs_hash_lock_ops {
	
	void    (*hs_lock)(union cfs_hash_lock *lock, int exclusive);
	
	void    (*hs_unlock)(union cfs_hash_lock *lock, int exclusive);
	
	void    (*hs_bkt_lock)(union cfs_hash_lock *lock, int exclusive);
	
	void    (*hs_bkt_unlock)(union cfs_hash_lock *lock, int exclusive);
};

struct cfs_hash_hlist_ops {
	
	struct hlist_head *(*hop_hhead)(struct cfs_hash *hs,
					struct cfs_hash_bd *bd);
	
	int (*hop_hhead_size)(struct cfs_hash *hs);
	
	int (*hop_hnode_add)(struct cfs_hash *hs, struct cfs_hash_bd *bd,
				struct hlist_node *hnode);
	
	int (*hop_hnode_del)(struct cfs_hash *hs, struct cfs_hash_bd *bd,
				struct hlist_node *hnode);
};

struct cfs_hash_ops {
	
	unsigned int (*hs_hash)(struct cfs_hash *hs, const void *key,
				const unsigned int bits);
	
	void *   (*hs_key)(struct hlist_node *hnode);
	
	void     (*hs_keycpy)(struct hlist_node *hnode, void *key);
	/*
	 *  compare @key with key of @hnode
	 *  returns 1 on a match
	 */
	int      (*hs_keycmp)(const void *key, struct hlist_node *hnode);
	
	void *   (*hs_object)(struct hlist_node *hnode);
	
	void     (*hs_get)(struct cfs_hash *hs, struct hlist_node *hnode);
	
	void     (*hs_put)(struct cfs_hash *hs, struct hlist_node *hnode);
	
	void     (*hs_put_locked)(struct cfs_hash *hs, struct hlist_node *node);
	
	void     (*hs_exit)(struct cfs_hash *hs, struct hlist_node *hnode);
};


#define CFS_HASH_NBKT(hs)       \
	(1U << ((hs)->hs_cur_bits - (hs)->hs_bkt_bits))


#define CFS_HASH_RH_NBKT(hs)    \
	(1U << ((hs)->hs_rehash_bits - (hs)->hs_bkt_bits))


#define CFS_HASH_BKT_NHLIST(hs) (1U << (hs)->hs_bkt_bits)


#define CFS_HASH_NHLIST(hs)     (1U << (hs)->hs_cur_bits)


#define CFS_HASH_RH_NHLIST(hs)  (1U << (hs)->hs_rehash_bits)

static inline int
cfs_hash_with_no_lock(struct cfs_hash *hs)
{
	
	return (hs->hs_flags & CFS_HASH_NO_LOCK) != 0;
}

static inline int
cfs_hash_with_no_bktlock(struct cfs_hash *hs)
{
	
	return (hs->hs_flags & CFS_HASH_NO_BKTLOCK) != 0;
}

static inline int
cfs_hash_with_rw_bktlock(struct cfs_hash *hs)
{
	
	return (hs->hs_flags & CFS_HASH_RW_BKTLOCK) != 0;
}

static inline int
cfs_hash_with_spin_bktlock(struct cfs_hash *hs)
{
	
	return (hs->hs_flags & CFS_HASH_SPIN_BKTLOCK) != 0;
}

static inline int
cfs_hash_with_rw_sem_bktlock(struct cfs_hash *hs)
{
	
	return (hs->hs_flags & CFS_HASH_RW_SEM_BKTLOCK) != 0;
}

static inline int
cfs_hash_with_add_tail(struct cfs_hash *hs)
{
	return (hs->hs_flags & CFS_HASH_ADD_TAIL) != 0;
}

static inline int
cfs_hash_with_no_itemref(struct cfs_hash *hs)
{
	/* hash-table doesn't keep refcount on item, item can't be removed from
	 * hash unless it's ZERO refcount
	 */
	return (hs->hs_flags & CFS_HASH_NO_ITEMREF) != 0;
}

static inline int
cfs_hash_with_bigname(struct cfs_hash *hs)
{
	return (hs->hs_flags & CFS_HASH_BIGNAME) != 0;
}

static inline int
cfs_hash_with_counter(struct cfs_hash *hs)
{
	return (hs->hs_flags & CFS_HASH_COUNTER) != 0;
}

static inline int
cfs_hash_with_rehash(struct cfs_hash *hs)
{
	return (hs->hs_flags & CFS_HASH_REHASH) != 0;
}

static inline int
cfs_hash_with_rehash_key(struct cfs_hash *hs)
{
	return (hs->hs_flags & CFS_HASH_REHASH_KEY) != 0;
}

static inline int
cfs_hash_with_shrink(struct cfs_hash *hs)
{
	return (hs->hs_flags & CFS_HASH_SHRINK) != 0;
}

static inline int
cfs_hash_with_assert_empty(struct cfs_hash *hs)
{
	return (hs->hs_flags & CFS_HASH_ASSERT_EMPTY) != 0;
}

static inline int
cfs_hash_with_depth(struct cfs_hash *hs)
{
	return (hs->hs_flags & CFS_HASH_DEPTH) != 0;
}

static inline int
cfs_hash_with_nblk_change(struct cfs_hash *hs)
{
	return (hs->hs_flags & CFS_HASH_NBLK_CHANGE) != 0;
}

static inline int
cfs_hash_is_exiting(struct cfs_hash *hs)
{
	
	return hs->hs_exiting;
}

static inline int
cfs_hash_is_rehashing(struct cfs_hash *hs)
{
	
	return hs->hs_rehash_bits != 0;
}

static inline int
cfs_hash_is_iterating(struct cfs_hash *hs)
{
	
	return hs->hs_iterating || hs->hs_iterators != 0;
}

static inline int
cfs_hash_bkt_size(struct cfs_hash *hs)
{
	return offsetof(struct cfs_hash_bucket, hsb_head[0]) +
		hs->hs_hops->hop_hhead_size(hs) * CFS_HASH_BKT_NHLIST(hs) +
		hs->hs_extra_bytes;
}

static inline unsigned int
cfs_hash_id(struct cfs_hash *hs, const void *key, const unsigned int bits)
{
	return hs->hs_ops->hs_hash(hs, key, bits);
}

static inline void *
cfs_hash_key(struct cfs_hash *hs, struct hlist_node *hnode)
{
	return hs->hs_ops->hs_key(hnode);
}

static inline void
cfs_hash_keycpy(struct cfs_hash *hs, struct hlist_node *hnode, void *key)
{
	if (hs->hs_ops->hs_keycpy != NULL)
		hs->hs_ops->hs_keycpy(hnode, key);
}

/*
 * Returns 1 on a match,
 */
static inline int
cfs_hash_keycmp(struct cfs_hash *hs, const void *key, struct hlist_node *hnode)
{
	return hs->hs_ops->hs_keycmp(key, hnode);
}

static inline void *
cfs_hash_object(struct cfs_hash *hs, struct hlist_node *hnode)
{
	return hs->hs_ops->hs_object(hnode);
}

static inline void
cfs_hash_get(struct cfs_hash *hs, struct hlist_node *hnode)
{
	return hs->hs_ops->hs_get(hs, hnode);
}

static inline void
cfs_hash_put_locked(struct cfs_hash *hs, struct hlist_node *hnode)
{
	return hs->hs_ops->hs_put_locked(hs, hnode);
}

static inline void
cfs_hash_put(struct cfs_hash *hs, struct hlist_node *hnode)
{
	return hs->hs_ops->hs_put(hs, hnode);
}

static inline void
cfs_hash_exit(struct cfs_hash *hs, struct hlist_node *hnode)
{
	if (hs->hs_ops->hs_exit)
		hs->hs_ops->hs_exit(hs, hnode);
}

static inline void cfs_hash_lock(struct cfs_hash *hs, int excl)
{
	hs->hs_lops->hs_lock(&hs->hs_lock, excl);
}

static inline void cfs_hash_unlock(struct cfs_hash *hs, int excl)
{
	hs->hs_lops->hs_unlock(&hs->hs_lock, excl);
}

static inline int cfs_hash_dec_and_lock(struct cfs_hash *hs,
					atomic_t *condition)
{
	LASSERT(cfs_hash_with_no_bktlock(hs));
	return atomic_dec_and_lock(condition, &hs->hs_lock.spin);
}

static inline void cfs_hash_bd_lock(struct cfs_hash *hs,
				    struct cfs_hash_bd *bd, int excl)
{
	hs->hs_lops->hs_bkt_lock(&bd->bd_bucket->hsb_lock, excl);
}

static inline void cfs_hash_bd_unlock(struct cfs_hash *hs,
				      struct cfs_hash_bd *bd, int excl)
{
	hs->hs_lops->hs_bkt_unlock(&bd->bd_bucket->hsb_lock, excl);
}

/*
 * operations on cfs_hash bucket (bd: bucket descriptor),
 * they are normally for hash-table without rehash
 */
void cfs_hash_bd_get(struct cfs_hash *hs, const void *key,
		     struct cfs_hash_bd *bd);

static inline void
cfs_hash_bd_get_and_lock(struct cfs_hash *hs, const void *key,
			 struct cfs_hash_bd *bd, int excl)
{
	cfs_hash_bd_get(hs, key, bd);
	cfs_hash_bd_lock(hs, bd, excl);
}

static inline unsigned
cfs_hash_bd_index_get(struct cfs_hash *hs, struct cfs_hash_bd *bd)
{
	return bd->bd_offset | (bd->bd_bucket->hsb_index << hs->hs_bkt_bits);
}

static inline void
cfs_hash_bd_index_set(struct cfs_hash *hs, unsigned int index,
		      struct cfs_hash_bd *bd)
{
	bd->bd_bucket = hs->hs_buckets[index >> hs->hs_bkt_bits];
	bd->bd_offset = index & (CFS_HASH_BKT_NHLIST(hs) - 1U);
}

static inline void *
cfs_hash_bd_extra_get(struct cfs_hash *hs, struct cfs_hash_bd *bd)
{
	LASSERT(hs->hs_extra_bytes);
	return (void *)bd->bd_bucket +
		cfs_hash_bkt_size(hs) - hs->hs_extra_bytes;
}

static inline __u32
cfs_hash_bd_version_get(struct cfs_hash_bd *bd)
{
	
	return bd->bd_bucket->hsb_version;
}

static inline __u32
cfs_hash_bd_count_get(struct cfs_hash_bd *bd)
{
	
	return bd->bd_bucket->hsb_count;
}

static inline int
cfs_hash_bd_depmax_get(struct cfs_hash_bd *bd)
{
	return bd->bd_bucket->hsb_depmax;
}

static inline int
cfs_hash_bd_compare(struct cfs_hash_bd *bd1, struct cfs_hash_bd *bd2)
{
	if (bd1->bd_bucket->hsb_index != bd2->bd_bucket->hsb_index)
		return bd1->bd_bucket->hsb_index - bd2->bd_bucket->hsb_index;

	if (bd1->bd_offset != bd2->bd_offset)
		return bd1->bd_offset - bd2->bd_offset;

	return 0;
}

void cfs_hash_bd_add_locked(struct cfs_hash *hs, struct cfs_hash_bd *bd,
			    struct hlist_node *hnode);
void cfs_hash_bd_del_locked(struct cfs_hash *hs, struct cfs_hash_bd *bd,
			    struct hlist_node *hnode);
void cfs_hash_bd_move_locked(struct cfs_hash *hs, struct cfs_hash_bd *bd_old,
			     struct cfs_hash_bd *bd_new,
			     struct hlist_node *hnode);

static inline int
cfs_hash_bd_dec_and_lock(struct cfs_hash *hs, struct cfs_hash_bd *bd,
			 refcount_t *condition)
{
	LASSERT(cfs_hash_with_spin_bktlock(hs));
	return refcount_dec_and_lock(condition, &bd->bd_bucket->hsb_lock.spin);
}

static inline struct hlist_head *
cfs_hash_bd_hhead(struct cfs_hash *hs, struct cfs_hash_bd *bd)
{
	return hs->hs_hops->hop_hhead(hs, bd);
}

struct hlist_node *
cfs_hash_bd_lookup_locked(struct cfs_hash *hs, struct cfs_hash_bd *bd,
			  const void *key);
struct hlist_node *
cfs_hash_bd_peek_locked(struct cfs_hash *hs, struct cfs_hash_bd *bd,
			const void *key);
struct hlist_node *
cfs_hash_bd_findadd_locked(struct cfs_hash *hs, struct cfs_hash_bd *bd,
			   const void *key, struct hlist_node *hnode,
			   int insist_add);
struct hlist_node *
cfs_hash_bd_finddel_locked(struct cfs_hash *hs, struct cfs_hash_bd *bd,
			   const void *key, struct hlist_node *hnode);

/*
 * operations on cfs_hash bucket (bd: bucket descriptor),
 * they are safe for hash-table with rehash
 */
void cfs_hash_dual_bd_get(struct cfs_hash *hs, const void *key,
			  struct cfs_hash_bd *bds);
void cfs_hash_dual_bd_lock(struct cfs_hash *hs, struct cfs_hash_bd *bds,
			   int excl);
void cfs_hash_dual_bd_unlock(struct cfs_hash *hs, struct cfs_hash_bd *bds,
			     int excl);

static inline void
cfs_hash_dual_bd_get_and_lock(struct cfs_hash *hs, const void *key,
			      struct cfs_hash_bd *bds, int excl)
{
	cfs_hash_dual_bd_get(hs, key, bds);
	cfs_hash_dual_bd_lock(hs, bds, excl);
}

struct hlist_node *
cfs_hash_dual_bd_lookup_locked(struct cfs_hash *hs, struct cfs_hash_bd *bds,
				const void *key);
struct hlist_node *
cfs_hash_dual_bd_findadd_locked(struct cfs_hash *hs, struct cfs_hash_bd *bds,
				const void *key, struct hlist_node *hnode,
				int insist_add);
struct hlist_node *
cfs_hash_dual_bd_finddel_locked(struct cfs_hash *hs, struct cfs_hash_bd *bds,
				const void *key, struct hlist_node *hnode);


struct cfs_hash *
cfs_hash_create(const char *name, unsigned int cur_bits, unsigned int max_bits,
		unsigned int bkt_bits, unsigned int extra_bytes,
		unsigned int min_theta, unsigned int max_theta,
		struct cfs_hash_ops *ops, unsigned int flags);

struct cfs_hash *cfs_hash_getref(struct cfs_hash *hs);
void cfs_hash_putref(struct cfs_hash *hs);


void cfs_hash_add(struct cfs_hash *hs, const void *key,
			struct hlist_node *hnode);
int cfs_hash_add_unique(struct cfs_hash *hs, const void *key,
			struct hlist_node *hnode);
void *cfs_hash_findadd_unique(struct cfs_hash *hs, const void *key,
			      struct hlist_node *hnode);


void *cfs_hash_del(struct cfs_hash *hs, const void *key,
		   struct hlist_node *hnode);
void *cfs_hash_del_key(struct cfs_hash *hs, const void *key);


#define CFS_HASH_LOOP_HOG       1024

typedef int (*cfs_hash_for_each_cb_t)(struct cfs_hash *hs,
				      struct cfs_hash_bd *bd,
				      struct hlist_node *node,
				      void *data);
void *cfs_hash_lookup(struct cfs_hash *hs, const void *key);
void cfs_hash_for_each(struct cfs_hash *hs, cfs_hash_for_each_cb_t func,
		       void *data);
void cfs_hash_for_each_safe(struct cfs_hash *hs, cfs_hash_for_each_cb_t func,
			    void *data);
int cfs_hash_for_each_nolock(struct cfs_hash *hs, cfs_hash_for_each_cb_t func,
			     void *data, int start);
int cfs_hash_for_each_empty(struct cfs_hash *hs, cfs_hash_for_each_cb_t func,
			    void *data);
void cfs_hash_for_each_key(struct cfs_hash *hs, const void *key,
			   cfs_hash_for_each_cb_t func, void *data);
typedef int (*cfs_hash_cond_opt_cb_t)(void *obj, void *data);
void cfs_hash_cond_del(struct cfs_hash *hs, cfs_hash_cond_opt_cb_t func,
		       void *data);

void cfs_hash_hlist_for_each(struct cfs_hash *hs, unsigned int hindex,
			     cfs_hash_for_each_cb_t func, void *data);
int  cfs_hash_is_empty(struct cfs_hash *hs);
__u64 cfs_hash_size_get(struct cfs_hash *hs);

/*
 * Rehash - Theta is calculated to be the average chained
 * hash depth assuming a perfectly uniform hash function.
 */
void cfs_hash_rehash_cancel_locked(struct cfs_hash *hs);
void cfs_hash_rehash_cancel(struct cfs_hash *hs);
void cfs_hash_rehash(struct cfs_hash *hs, int do_rehash);
void cfs_hash_rehash_key(struct cfs_hash *hs, const void *old_key,
			void *new_key, struct hlist_node *hnode);

#if CFS_HASH_DEBUG_LEVEL > CFS_HASH_DEBUG_1

static inline void
cfs_hash_key_validate(struct cfs_hash *hs, const void *key,
		      struct hlist_node *hnode)
{
	LASSERT(cfs_hash_keycmp(hs, key, hnode));
}


static inline void
cfs_hash_bucket_validate(struct cfs_hash *hs, struct cfs_hash_bd *bd,
			struct hlist_node *hnode)
{
	struct cfs_hash_bd bds[2];

	cfs_hash_dual_bd_get(hs, cfs_hash_key(hs, hnode), bds);
	LASSERT(bds[0].bd_bucket == bd->bd_bucket ||
		bds[1].bd_bucket == bd->bd_bucket);
}

#else 

static inline void
cfs_hash_key_validate(struct cfs_hash *hs, const void *key,
			struct hlist_node *hnode) {}

static inline void
cfs_hash_bucket_validate(struct cfs_hash *hs, struct cfs_hash_bd *bd,
			struct hlist_node *hnode) {}

#endif 

#define CFS_HASH_THETA_BITS  10
#define CFS_HASH_MIN_THETA  (1U << (CFS_HASH_THETA_BITS - 1))
#define CFS_HASH_MAX_THETA  (1U << (CFS_HASH_THETA_BITS + 1))


static inline int __cfs_hash_theta_int(int theta)
{
	return (theta >> CFS_HASH_THETA_BITS);
}


static inline int __cfs_hash_theta_frac(int theta)
{
	return ((theta * 1000) >> CFS_HASH_THETA_BITS) -
		(__cfs_hash_theta_int(theta) * 1000);
}

static inline int __cfs_hash_theta(struct cfs_hash *hs)
{
	return (atomic_read(&hs->hs_count) <<
		CFS_HASH_THETA_BITS) >> hs->hs_cur_bits;
}

static inline void
__cfs_hash_set_theta(struct cfs_hash *hs, int min, int max)
{
	LASSERT(min < max);
	hs->hs_min_theta = (__u16)min;
	hs->hs_max_theta = (__u16)max;
}


struct seq_file;
void cfs_hash_debug_header(struct seq_file *m);
void cfs_hash_debug_str(struct cfs_hash *hs, struct seq_file *m);


static inline unsigned
cfs_hash_djb2_hash(const void *key, size_t size, const unsigned int bits)
{
	unsigned int i, hash = 5381;

	LASSERT(key != NULL);

	for (i = 0; i < size; i++)
		hash = hash * 33 + ((char *)key)[i];

	return (hash & ((1U << bits) - 1));
}


#define cfs_hash_for_each_bd(bds, n, i)					\
	for (i = 0; i < n && (bds)[i].bd_bucket != NULL; i++)


#define cfs_hash_for_each_bucket(hs, bd, pos)				\
	for (pos = 0;							\
	     pos < CFS_HASH_NBKT(hs) &&					\
	     ((bd)->bd_bucket = (hs)->hs_buckets[pos]) != NULL; pos++)


#define cfs_hash_bd_for_each_hlist(hs, bd, hlist)			\
	for ((bd)->bd_offset = 0;					\
	     (bd)->bd_offset < CFS_HASH_BKT_NHLIST(hs) &&		\
	     (hlist = cfs_hash_bd_hhead(hs, bd)) != NULL;		\
	     (bd)->bd_offset++)


#endif
