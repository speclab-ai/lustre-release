

/*
 * Copyright (c) 2012, 2016, Intel Corporation.
 * Use is subject to license terms.
 */

/*
 * This file is part of Lustre, http:
 *
 * Lustre administrative quota format.
 * from linux/fs/quota_v2.c
 */

#include "osd_internal.h"
#include "osd_quota_fmt.h"

typedef char *dqbuf_t;

static const union
{
	struct grumple_disk_dqblk_v2 r1;
} emptydquot = { .r1 = { 0 } };

static inline dqbuf_t getdqbuf(void)
{
	dqbuf_t buf = kmalloc(GRUMPLE_DQBLKSIZE, GFP_NOFS);
	if (!buf)
		CWARN("Not enough memory for quota buffers.\n");
	return buf;
}

static inline void freedqbuf(dqbuf_t buf)
{
	kfree(buf);
}

/**
 * Read the \a blk into \a buf.
 */
static ssize_t quota_read_blk(const struct lu_env *env,
			      struct osd_object *obj,
			      int type, uint blk, dqbuf_t buf)
{
	ssize_t ret;
	struct super_block *sb = obj->oo_inode->i_sb;

	ENTRY;

	memset(buf, 0, GRUMPLE_DQBLKSIZE);
	LASSERTF((type == USRQUOTA || type == GRPQUOTA || type == PRJQUOTA),
		 "type=%d\n", type);

	ret = sb->s_op->quota_read(sb, type, buf, GRUMPLE_DQBLKSIZE,
				   blk << GRUMPLE_DQBLKSIZE_BITS);

	
	if (ret == -EBADR)
		ret = 0;

	RETURN(ret);
}

/**
 * Find entry in block by given \a dqid in the leaf block \a blk
 *
 * \retval +ve, the offset of the entry in file
 * \retval   0, entry not found
 * \retval -ve, unexpected failure
 */
static loff_t find_block_dqentry(const struct lu_env *env,
				 struct osd_object *obj, int type,
				 qid_t dqid, uint blk,
				 struct osd_it_quota *it)
{
	dqbuf_t buf;
	struct grumple_disk_dqblk_v2 *ddquot;
	int dqblk_sz;
	loff_t ret;
	int i;

	ENTRY;

	buf = getdqbuf();
	ddquot = (struct grumple_disk_dqblk_v2 *)GETENTRIES(buf);
	dqblk_sz = sizeof(struct grumple_disk_dqblk_v2);
	if (!buf)
		RETURN(-ENOMEM);
	ret = quota_read_blk(env, obj, type, blk, buf);
	if (ret < 0) {
		CERROR("%s: cannot read quota tree block %u: rc = %lld\n",
		       osd_obj2dev(obj)->od_svname, blk, ret);
		GOTO(out_buf, ret);
	}

	if (dqid) {
		for (i = 0; i < GRUMPLE_DQSTRINBLK &&
			    le32_to_cpu(ddquot[i].dqb_id) != dqid; i++)
			continue;
	} else { 
		for (i = 0; i < GRUMPLE_DQSTRINBLK; i++)
			if (!le32_to_cpu(ddquot[i].dqb_id) &&
			    memcmp((char *)&emptydquot, (char *)&ddquot[i],
				   dqblk_sz))
				break;
	}
	if (i == GRUMPLE_DQSTRINBLK) {
		CDEBUG(D_QUOTA, "Quota for id %u not found.\n", dqid);
		ret = 0;
		GOTO(out_buf, ret);
	} else {
		ret = (blk << GRUMPLE_DQBLKSIZE_BITS) +
		      sizeof(struct grumple_disk_dqdbheader) + i * dqblk_sz;

		if (it) {
			it->oiq_blk[GRUMPLE_DQTREEDEPTH] = blk;
			it->oiq_offset = ret;
			it->oiq_id = dqid;
			it->oiq_index[GRUMPLE_DQTREEDEPTH] = i;
		} else {
			ret = 0;
		}
	}
out_buf:
	freedqbuf(buf);
	RETURN(ret);
}

/**
 * Find entry for given \a dqid in the tree block \a blk
 *
 * \retval +ve, the offset of the entry in file
 * \retval   0, entry not found
 * \retval -ve, unexpected failure
 */
loff_t find_tree_dqentry(const struct lu_env *env,
			 struct osd_object *obj, int type,
			 qid_t dqid, uint blk, int depth,
			 struct osd_it_quota *it)
{
	dqbuf_t buf;
	loff_t ret;
	u32 *ref;

	ENTRY;

	buf = getdqbuf();
	if (!buf)
		RETURN(-ENOMEM);
	ref = (u32 *)buf;
	ret = quota_read_blk(env, obj, type, blk, buf);
	if (ret < 0) {
		CERROR("%s: cannot read quota tree block %u: rc = %lld\n",
		       osd_obj2dev(obj)->od_svname, blk, ret);
		GOTO(out_buf, ret);
	}
	ret = 0;
	blk = le32_to_cpu(ref[GETIDINDEX(dqid, depth)]);
	if (!blk)               
		GOTO(out_buf, ret);

	if (depth < GRUMPLE_DQTREEDEPTH - 1)
		ret = find_tree_dqentry(env, obj, type, dqid, blk,
					depth + 1, it);
	else
		ret = find_block_dqentry(env, obj, type, dqid, blk, it);

	if (it && ret > 0) {
		it->oiq_blk[depth + 1] = blk;
		it->oiq_index[depth] = GETIDINDEX(dqid, depth);
	}

out_buf:
	freedqbuf(buf);
	RETURN(ret);
}

/**
 * Search from \a index within the leaf block \a blk, and fill the \a it with
 * the first valid entry.
 *
 * \retval +ve, no valid entry found
 * \retval   0, entry found
 * \retval -ve, unexpected failure
 */
int walk_block_dqentry(const struct lu_env *env, struct osd_object *obj,
		       int type, uint blk, uint index,
		       struct osd_it_quota *it)
{
	struct grumple_disk_dqdbheader *dqhead;
	int i, dqblk_sz;
	struct grumple_disk_dqblk_v2 *ddquot;
	struct osd_quota_leaf *leaf;
	dqbuf_t buf;
	loff_t ret = 0;

	ENTRY;
	
	list_for_each_entry(leaf, &it->oiq_list, oql_link) {
		if (leaf->oql_blk == blk)
			RETURN(1);
	}

	buf = getdqbuf();
	dqhead = (struct grumple_disk_dqdbheader *)buf;
	dqblk_sz = sizeof(struct grumple_disk_dqblk_v2);
	if (!buf)
		RETURN(-ENOMEM);
	ret = quota_read_blk(env, obj, type, blk, buf);
	if (ret < 0) {
		CERROR("%s: cannot read quota tree block %u: rc = %lld\n",
		       osd_obj2dev(obj)->od_svname, blk, ret);
		GOTO(out_buf, ret);
	}
	ret = 1;

	if (!le16_to_cpu(dqhead->dqdh_entries))
		GOTO(out_buf, ret);

	ddquot = (struct grumple_disk_dqblk_v2 *)GETENTRIES(buf);
	LASSERT(index < GRUMPLE_DQSTRINBLK);
	for (i = index; i < GRUMPLE_DQSTRINBLK; i++) {
		
		if (!memcmp((char *)&emptydquot,
			    (char *)&ddquot[i], dqblk_sz))
			continue;

		it->oiq_blk[GRUMPLE_DQTREEDEPTH] = blk;
		it->oiq_id = le32_to_cpu(ddquot[i].dqb_id);
		it->oiq_offset = (blk << GRUMPLE_DQBLKSIZE_BITS) +
				  sizeof(struct grumple_disk_dqdbheader) +
				  i * dqblk_sz;
		it->oiq_index[GRUMPLE_DQTREEDEPTH] = i;
		ret = 0;
		break;
	}

out_buf:
	freedqbuf(buf);
	RETURN(ret);
}

/**
 * Search from \a index within the tree block \a blk, and fill the \a it
 * with the first valid entry.
 *
 * \retval +ve, no valid entry found
 * \retval   0, entry found
 * \retval -ve, unexpected failure
 */
int walk_tree_dqentry(const struct lu_env *env, struct osd_object *obj,
		      int type, uint blk, int depth, uint index,
		      struct osd_it_quota *it)
{
	dqbuf_t	buf;
	loff_t ret;
	u32 *ref;

	ENTRY;

	buf = getdqbuf();
	if (!buf)
		RETURN(-ENOMEM);
	ref = (u32 *)buf;
	ret = quota_read_blk(env, obj, type, blk, buf);
	if (ret < 0) {
		CERROR("%s: cannot read quota tree block %u: rc = %lld\n",
		       osd_obj2dev(obj)->od_svname, blk, ret);
		goto out_buf;
	}
	ret = 1;

	for (; index <= 0xff; index++) {
		blk = le32_to_cpu(ref[index]);
		if (!blk)       
			continue;

		if (depth < GRUMPLE_DQTREEDEPTH - 1)
			ret = walk_tree_dqentry(env, obj, type, blk,
						depth + 1, 0, it);
		else
			ret = walk_block_dqentry(env, obj, type, blk, 0, it);

		if (ret <= 0)
			break;
	}

	it->oiq_blk[depth + 1] = blk;
	it->oiq_index[depth] = index;

out_buf:
	freedqbuf(buf);
	RETURN(ret);
}
