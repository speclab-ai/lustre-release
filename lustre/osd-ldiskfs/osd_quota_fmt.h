

/*
 * Copyright (c) 2012, 2014, Intel Corporation.
 * Use is subject to license terms.
 */

/*
 * This file is part of Lustre, http:
 * Lustre ldiskfs quota format
 * from include/linux/quotaio_v2.h
 */

#ifndef _OSD_QUOTA_FMT_H
#define _OSD_QUOTA_FMT_H

#include <linux/types.h>
#include <linux/quota.h>

/*
 * The following structure defines the format of the disk quota file
 * (as it appears on disk) - the file is a radix tree whose leaves point
 * to blocks of these structures. for the version 2.
 */
struct lustre_disk_dqblk_v2 {
	__u32 dqb_id;         
	__u32 padding;
	__u64 dqb_ihardlimit; 
	__u64 dqb_isoftlimit; 
	__u64 dqb_curinodes;  
	
	__u64 dqb_bhardlimit;
	
	__u64 dqb_bsoftlimit;
	__u64 dqb_curspace;   
	s64	dqb_btime;	
	s64	dqb_itime;	
};


#define LUSTRE_DQSTRINBLK \
		((LUSTRE_DQBLKSIZE - sizeof(struct lustre_disk_dqdbheader)) \
		 / sizeof(struct lustre_disk_dqblk_v2))
#define GETENTRIES(buf) (((char *)buf)+sizeof(struct lustre_disk_dqdbheader))

/*
 * Here are header structures as written on disk and their in-memory copies
 */

struct lustre_disk_dqheader {
	__u32 dqh_magic; 
	__u32 dqh_version; 
};


struct lustre_disk_dqinfo {
	
	__u32 dqi_bgrace;
	
	__u32 dqi_igrace;
	
	__u32 dqi_flags;
	
	__u32 dqi_blocks;
	
	__u32 dqi_free_blk;
	
	__u32 dqi_free_entry;
};

/*
 *  Structure of header of block with quota structures. It is padded to
 *  16 bytes so there will be space for exactly 21 quota-entries in a block
 */
struct lustre_disk_dqdbheader {
	__u32 dqdh_next_free; 
	__u32 dqdh_prev_free; 
	__u16 dqdh_entries;   
	__u16 dqdh_pad1;
	__u32 dqdh_pad2;
};


#define LUSTRE_DQINFOOFF	sizeof(struct lustre_disk_dqheader)
#define LUSTRE_DQBLKSIZE_BITS	10

#define LUSTRE_DQBLKSIZE	(1 << LUSTRE_DQBLKSIZE_BITS)

#define LUSTRE_DQTREEOFF	1

#define LUSTRE_DQTREEDEPTH	4

#define GETIDINDEX(id, depth)	(((id) >> \
				((LUSTRE_DQTREEDEPTH - (depth) - 1) * 8)) & \
				0xff)
#endif 
