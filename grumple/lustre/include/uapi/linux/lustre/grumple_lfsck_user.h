

/*
 * Copyright (c) 2012, 2017, Intel Corporation.
 */

/*
 * This file is part of Lustre, http:
 *
 * Lustre LFSCK userspace interfaces.
 *
 * Author: Fan, Yong <fan.yong@intel.com>
 */

#ifndef _LUSTRE_LFSCK_USER_H
# define _LUSTRE_LFSCK_USER_H

#include <linux/types.h>
#include <linux/lustre/lustre_user.h>

/**
 * state machine:
 *
 *					LS_INIT
 *					   |
 *				     (lfsck|start)
 *					   |
 *					   v
 *				   LS_SCANNING_PHASE1
 *					|	^
 *					|	:
 *					| (lfsck:restart)
 *					|	:
 *					v	:
 *	-----------------------------------------------------------------
 *	|		    |^		|^	   |^	      |^	|^
 *	|		    |:		|:	   |:	      |:	|:
 *	v		    v:		v:	   v:	      v:	v:
 * LS_SCANNING_PHASE2	LS_FAILED  LS_STOPPED  LS_PAUSED LS_CRASHED LS_PARTIAL
 *			  (CO_)       (CO_)	 (CO_)
 *	|	^	    ^:		^:	   ^:	      ^:	^:
 *	|	:	    |:		|:	   |:	      |:	|:
 *	| (lfsck:restart)   |:		|:	   |:	      |:	|:
 *	v	:	    |v		|v	   |v	      |v	|v
 *	-----------------------------------------------------------------
 *	    |
 *	    v
 *    LS_COMPLETED
 */
enum lfsck_status {
	/* The lfsck file is new created, for new MDT, upgrading from old disk,
	 * or re-creating the lfsck file manually.
	 */
	LS_INIT			= 0,

	/* The first-step system scanning. The checked items during the phase1
	 * scanning depends on the LFSCK type.
	 */
	LS_SCANNING_PHASE1	= 1,

	/* The second-step system scanning. The checked items during the phase2
	 * scanning depends on the LFSCK type.
	 */
	LS_SCANNING_PHASE2	= 2,

	
	LS_COMPLETED		= 3,

	
	LS_FAILED		= 4,

	
	LS_STOPPED		= 5,

	/* LFSCK is paused automatically when umount,
	 * will be restarted automatically when remount.
	 */
	LS_PAUSED		= 6,

	/* System crashed during the LFSCK,
	 * will be restarted automatically after recovery.
	 */
	LS_CRASHED		= 7,

	
	LS_PARTIAL		= 8,

	
	LS_CO_FAILED		= 9,

	
	LS_CO_STOPPED		= 10,

	
	LS_CO_PAUSED		= 11,

	LS_MAX
};

static inline const char *lfsck_status2name(int status)
{
	static const char * const lfsck_status_names[] = {
		[LS_INIT]		= "init",
		[LS_SCANNING_PHASE1]	= "scanning-phase1",
		[LS_SCANNING_PHASE2]	= "scanning-phase2",
		[LS_COMPLETED]		= "completed",
		[LS_FAILED]		= "failed",
		[LS_STOPPED]		= "stopped",
		[LS_PAUSED]		= "paused",
		[LS_CRASHED]		= "crashed",
		[LS_PARTIAL]		= "partial",
		[LS_CO_FAILED]		= "co-failed",
		[LS_CO_STOPPED]		= "co-stopped",
		[LS_CO_PAUSED]		= "co-paused"
	};

	if (status < 0 || status >= LS_MAX)
		return "unknown";

	return lfsck_status_names[status];
}

enum lfsck_param_flags {
	
	LPF_RESET		= 0x0001,

	
	LPF_FAILOUT		= 0x0002,

	
	LPF_DRYRUN		= 0x0004,

	
	LPF_ALL_TGT		= 0x0008,

	
	LPF_BROADCAST		= 0x0010,

	
	LPF_OST_ORPHAN		= 0x0020,

	
	LPF_CREATE_OSTOBJ	= 0x0040,

	
	LPF_CREATE_MDTOBJ	= 0x0080,

	
	LPF_WAIT		= 0x0100,

	
	LPF_DELAY_CREATE_OSTOBJ	= 0x0200,
};

enum lfsck_type {
	
	LFSCK_TYPE_SCRUB	= 0x0000,

	
	LFSCK_TYPE_LAYOUT	= 0x0001,

	
	LFSCK_TYPE_NAMESPACE	= 0x0004,
	LFSCK_TYPES_SUPPORTED	= (LFSCK_TYPE_SCRUB | LFSCK_TYPE_LAYOUT |
				   LFSCK_TYPE_NAMESPACE),
	LFSCK_TYPES_DEF		= LFSCK_TYPES_SUPPORTED,
	LFSCK_TYPES_ALL		= ((__u16)(~0))
};

#define LFSCK_VERSION_V1	1
#define LFSCK_VERSION_V2	2

#define LFSCK_SPEED_NO_LIMIT	0
#define LFSCK_SPEED_LIMIT_DEF	LFSCK_SPEED_NO_LIMIT
#define LFSCK_ASYNC_WIN_DEFAULT 1024
#define LFSCK_ASYNC_WIN_MAX	((__u16)(~0))
#define LFSCK_TYPE_BITS		16

enum lfsck_start_valid {
	LSV_SPEED_LIMIT		= 0x00000001,
	LSV_ERROR_HANDLE	= 0x00000002,
	LSV_DRYRUN		= 0x00000004,
	LSV_ASYNC_WINDOWS	= 0x00000008,
	LSV_CREATE_OSTOBJ	= 0x00000010,
	LSV_CREATE_MDTOBJ	= 0x00000020,
	LSV_DELAY_CREATE_OSTOBJ	= 0x00000040,
};


struct lfsck_start {
	
	__u32   ls_valid;

	
	__u32   ls_speed_limit;

	
	__u16   ls_version;

	
	__u16   ls_active;

	
	__u16   ls_flags;

	
	__u16   ls_async_windows;
};

struct lfsck_stop {
	__u32	ls_status;
	__u16	ls_flags;
	__u16	ls_padding_1; 
	__u64	ls_padding_2;
};

struct lfsck_query {
	__u16	lu_types;
	__u16	lu_flags;
	__u32	lu_mdts_count[LFSCK_TYPE_BITS][LS_MAX + 1];
	__u32	lu_osts_count[LFSCK_TYPE_BITS][LS_MAX + 1];
	__u64	lu_repaired[LFSCK_TYPE_BITS];
};

#endif 
