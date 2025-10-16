

/* Copyright (c) 2007, 2010, Oracle and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 *
 * Copyright (c) 2012, 2016, Intel Corporation.
 */

/* This file is part of Lustre, http:
 *
 * Author: Liang Zhen <liangzhen@clusterfs.com>
 */

#ifndef __UAPI_LNET_ST_H__
#define __UAPI_LNET_ST_H__

#include <linux/types.h>
#include <linux/lnet/lnet-types.h>
#include <linux/time.h>

#define LST_FEAT_NONE		(0)
#define LST_FEAT_BULK_LEN	(1 << 0)	

#define LST_FEATS_EMPTY		(LST_FEAT_NONE)
#define LST_FEATS_MASK		(LST_FEAT_NONE | LST_FEAT_BULK_LEN)

#define LST_NAME_SIZE		32		

#define LSTIO_DEBUG		0xC00		
#define LSTIO_SESSION_NEW	0xC01		
#define LSTIO_SESSION_END	0xC02		
#define LSTIO_SESSION_INFO	0xC03		
#define LSTIO_GROUP_ADD		0xC10		
#define LSTIO_GROUP_LIST	0xC11		
#define LSTIO_GROUP_INFO	0xC12		
#define LSTIO_GROUP_DEL		0xC13		
#define LSTIO_NODES_ADD		0xC14		
#define LSTIO_GROUP_UPDATE	0xC15		
#define LSTIO_BATCH_ADD		0xC20		
#define LSTIO_BATCH_START	0xC21		
#define LSTIO_BATCH_STOP	0xC22		
#define LSTIO_BATCH_DEL		0xC23		
#define LSTIO_BATCH_LIST	0xC24		
#define LSTIO_BATCH_INFO	0xC25		
#define LSTIO_TEST_ADD		0xC26		
#define LSTIO_BATCH_QUERY	0xC27		
#define LSTIO_STAT_QUERY	0xC30		

/*
 * sparse kernel source annotations
 */
#ifndef __user
#define __user
#endif

struct lst_sid {
	lnet_nid_t	ses_nid;	
	__s64		ses_stamp;	
};					

struct lst_bid {
	__u64		bat_id;		
};


#define LST_NODE_ACTIVE		0x1	
#define LST_NODE_BUSY		0x2	
#define LST_NODE_DOWN		0x4	
#define LST_NODE_UNKNOWN	0x8	

struct lstcon_node_ent {
	struct lnet_process_id	nde_id;		
	int			nde_state;	
};						

struct lstcon_ndlist_ent {
	int	nle_nnode;	
	int	nle_nactive;	
	int	nle_nbusy;	
	int	nle_ndown;	
	int	nle_nunknown;	
};				

struct lstcon_test_ent {
	int	tse_type;	
	int	tse_loop;	
	int	tse_concur;	
};				

struct lstcon_batch_ent {
	int	bae_state;	
	int	bae_timeout;	
	int	bae_ntest;	
};				

struct lstcon_test_batch_ent {
	struct lstcon_ndlist_ent	tbe_cli_nle;	
	struct lstcon_ndlist_ent	tbe_srv_nle;	
	union {
		struct lstcon_test_ent  tbe_test;	
		struct lstcon_batch_ent tbe_batch;	
	} u;
};							/*** test/batch verbose information entry,
							 *** for list_batch command */


#if !defined(__KERNEL__) && !defined(__LIBCFS_UTIL_LIST_H__)
struct list_head {
	struct list_head *next, *prev;
};
#endif

struct lstcon_rpc_ent {
	struct list_head	rpe_link;		
	struct lnet_process_id	rpe_peer;		
	/* This has not been used since Lustre 2.2 so its safe to use.
	 * Update to allow future use of timespec64
	 */
	struct {
		__s64		tv_sec;
		__s64		tv_nsec;
	} rpe_stamp;					
	int			rpe_state;		
	int			rpe_rpc_errno;		

	struct lst_sid		rpe_sid;		
	int			rpe_fwk_errno;		
	int			rpe_priv[4];		
	char			rpe_payload[];		
};

struct lstcon_trans_stat {
	int	trs_rpc_stat[4];	
	int	trs_rpc_errno;		
	int	trs_fwk_stat[8];	
	int	trs_fwk_errno;		
	void   *trs_fwk_private;	
};

static inline int
lstcon_rpc_stat_total(struct lstcon_trans_stat *stat, int inc)
{
	return inc ? ++stat->trs_rpc_stat[0] : stat->trs_rpc_stat[0];
}

static inline int
lstcon_rpc_stat_success(struct lstcon_trans_stat *stat, int inc)
{
	return inc ? ++stat->trs_rpc_stat[1] : stat->trs_rpc_stat[1];
}

static inline int
lstcon_rpc_stat_failure(struct lstcon_trans_stat *stat, int inc)
{
	return inc ? ++stat->trs_rpc_stat[2] : stat->trs_rpc_stat[2];
}

static inline int
lstcon_sesop_stat_success(struct lstcon_trans_stat *stat, int inc)
{
	return inc ? ++stat->trs_fwk_stat[0] : stat->trs_fwk_stat[0];
}

static inline int
lstcon_sesop_stat_failure(struct lstcon_trans_stat *stat, int inc)
{
	return inc ? ++stat->trs_fwk_stat[1] : stat->trs_fwk_stat[1];
}

static inline int
lstcon_sesqry_stat_active(struct lstcon_trans_stat *stat, int inc)
{
	return inc ? ++stat->trs_fwk_stat[0] : stat->trs_fwk_stat[0];
}

static inline int
lstcon_sesqry_stat_busy(struct lstcon_trans_stat *stat, int inc)
{
	return inc ? ++stat->trs_fwk_stat[1] : stat->trs_fwk_stat[1];
}

static inline int
lstcon_sesqry_stat_unknown(struct lstcon_trans_stat *stat, int inc)
{
	return inc ? ++stat->trs_fwk_stat[2] : stat->trs_fwk_stat[2];
}

static inline int
lstcon_tsbop_stat_success(struct lstcon_trans_stat *stat, int inc)
{
	return inc ? ++stat->trs_fwk_stat[0] : stat->trs_fwk_stat[0];
}

static inline int
lstcon_tsbop_stat_failure(struct lstcon_trans_stat *stat, int inc)
{
	return inc ? ++stat->trs_fwk_stat[1] : stat->trs_fwk_stat[1];
}

static inline int
lstcon_tsbqry_stat_idle(struct lstcon_trans_stat *stat, int inc)
{
	return inc ? ++stat->trs_fwk_stat[0] : stat->trs_fwk_stat[0];
}

static inline int
lstcon_tsbqry_stat_run(struct lstcon_trans_stat *stat, int inc)
{
	return inc ? ++stat->trs_fwk_stat[1] : stat->trs_fwk_stat[1];
}

static inline int
lstcon_tsbqry_stat_failure(struct lstcon_trans_stat *stat, int inc)
{
	return inc ? ++stat->trs_fwk_stat[2] : stat->trs_fwk_stat[2];
}

static inline int
lstcon_statqry_stat_success(struct lstcon_trans_stat *stat, int inc)
{
	return inc ? ++stat->trs_fwk_stat[0] : stat->trs_fwk_stat[0];
}

static inline int
lstcon_statqry_stat_failure(struct lstcon_trans_stat *stat, int inc)
{
	return inc ? ++stat->trs_fwk_stat[1] : stat->trs_fwk_stat[1];
}


struct lstio_session_new_args {
	int			lstio_ses_key;		
	int			lstio_ses_timeout;	
	int			lstio_ses_force;	
	
	unsigned		lstio_ses_feats;
	struct lst_sid __user  *lstio_ses_idp;		
	int			lstio_ses_nmlen;	
	char __user	       *lstio_ses_namep;	
};


struct lstio_session_info_args {
	struct lst_sid __user	*lstio_ses_idp;		
	int __user		*lstio_ses_keyp;	
	
	unsigned __user		*lstio_ses_featp;
	struct lstcon_ndlist_ent __user *lstio_ses_ndinfo; 
	int			 lstio_ses_nmlen;	
	char __user		*lstio_ses_namep;	
};


struct lstio_session_end_args {
	int			lstio_ses_key;		
};

#define LST_OPC_SESSION		1
#define LST_OPC_GROUP		2
#define LST_OPC_NODES		3
#define LST_OPC_BATCHCLI	4
#define LST_OPC_BATCHSRV	5

struct lstio_debug_args {
	int			lstio_dbg_key;		
	int			lstio_dbg_type;		
	int			lstio_dbg_flags;	
	int			lstio_dbg_timeout;	

	int			lstio_dbg_nmlen;	
	char __user	       *lstio_dbg_namep;	
	int			lstio_dbg_count;	
	struct lnet_process_id __user *lstio_dbg_idsp;	
	
	struct list_head __user *lstio_dbg_resultp;
};

struct lstio_group_add_args {
	int			lstio_grp_key;		
	int			lstio_grp_nmlen;	
	char __user	       *lstio_grp_namep;	
};

struct lstio_group_del_args {
	int			lstio_grp_key;		
	int			lstio_grp_nmlen;	
	char __user	       *lstio_grp_namep;	
};

#define LST_GROUP_CLEAN		1			
#define LST_GROUP_REFRESH	2			
#define LST_GROUP_RMND		3			

struct lstio_group_update_args {
	int			lstio_grp_key;		
	int			lstio_grp_opc;		
	int			lstio_grp_args;		
	int			lstio_grp_nmlen;	
	char __user	       *lstio_grp_namep;	
	int			lstio_grp_count;	
	struct lnet_process_id __user *lstio_grp_idsp;	
	
	struct list_head __user	*lstio_grp_resultp;
};

struct lstio_group_nodes_args {
	int			 lstio_grp_key;		
	int			 lstio_grp_nmlen;	
	char __user		*lstio_grp_namep;	
	int			 lstio_grp_count;	
	
	unsigned __user		*lstio_grp_featp;
	struct lnet_process_id __user *lstio_grp_idsp;	
	
	struct list_head __user	*lstio_grp_resultp;
};

struct lstio_group_list_args {
	int			lstio_grp_key;		
	int			lstio_grp_idx;		
	int			lstio_grp_nmlen;	
	char __user	       *lstio_grp_namep;	
};

struct lstio_group_info_args {
	int			lstio_grp_key;		
	int			lstio_grp_nmlen;	
	char __user	       *lstio_grp_namep;	
	struct lstcon_ndlist_ent __user *lstio_grp_entp;

	int __user	       *lstio_grp_idxp;		
	int __user	       *lstio_grp_ndentp;	
	struct lstcon_node_ent __user *lstio_grp_dentsp;
};

#define LST_DEFAULT_BATCH	"batch"			

struct lstio_batch_add_args {
	int			lstio_bat_key;		
	int			lstio_bat_nmlen;	
	char __user	       *lstio_bat_namep;	
};

struct lstio_batch_del_args {
	int			lstio_bat_key;		
	int			lstio_bat_nmlen;	
	char __user	       *lstio_bat_namep;	
};

struct lstio_batch_run_args {
	
	int			 lstio_bat_key;
	
	int			 lstio_bat_timeout;
	
	int			 lstio_bat_nmlen;
	
	char __user		*lstio_bat_namep;
	
	struct list_head __user *lstio_bat_resultp;
};

struct lstio_batch_stop_args {
	
	int			 lstio_bat_key;
	
	int			 lstio_bat_force;
	
	int			 lstio_bat_nmlen;
	
	char __user		*lstio_bat_namep;
	
	struct list_head __user *lstio_bat_resultp;
};

struct lstio_batch_query_args {
	
	int			lstio_bat_key;
	
	int			lstio_bat_testidx;
	
	int			lstio_bat_client;
	
	int			lstio_bat_timeout;
	
	int			lstio_bat_nmlen;
	
	char __user		*lstio_bat_namep;
	
	struct list_head __user *lstio_bat_resultp;
};

struct lstio_batch_list_args {
	int			lstio_bat_key;		
	int			lstio_bat_idx;		
	int			lstio_bat_nmlen;	
	char __user	       *lstio_bat_namep;	
};

struct lstio_batch_info_args {
	int			lstio_bat_key;		
	int			lstio_bat_nmlen;	
	char __user	       *lstio_bat_namep;	
	int			lstio_bat_server;	
	int			lstio_bat_testidx;	
	struct lstcon_test_batch_ent __user *lstio_bat_entp;

	int __user	       *lstio_bat_idxp;		
	int __user	       *lstio_bat_ndentp;	
	struct lstcon_node_ent __user *lstio_bat_dentsp;
};


struct lstio_stat_args {
	
	int			lstio_sta_key;
	
	int			lstio_sta_timeout;
	
	int			lstio_sta_nmlen;
	
	char __user	       *lstio_sta_namep;
	
	int			lstio_sta_count;
	
	struct lnet_process_id __user *lstio_sta_idsp;
	
	struct list_head __user *lstio_sta_resultp;
};

enum lst_test_type {
	LST_TEST_BULK	= 1,
	LST_TEST_PING	= 2
};


#define LST_MAX_CONCUR		1024			

struct lstio_test_args {
	int			lstio_tes_key;		
	int			lstio_tes_bat_nmlen;	
	char __user	       *lstio_tes_bat_name;	
	int			lstio_tes_type;		
	int			lstio_tes_oneside;	
	int			lstio_tes_loop;		
	int			lstio_tes_concur;	

	int			lstio_tes_dist;		
	int			lstio_tes_span;		
	int			lstio_tes_sgrp_nmlen;	
	char __user	       *lstio_tes_sgrp_name;	
	int			lstio_tes_dgrp_nmlen;	
	char __user	       *lstio_tes_dgrp_name;	

	
	int			 lstio_tes_param_len;
	/* IN: parameter for specified test:
	       lstio_bulk_param_t,
	       lstio_ping_param_t,
	       ... more */
	void __user		*lstio_tes_param;
	
	int __user		*lstio_tes_retp;
	
	struct list_head __user *lstio_tes_resultp;
};

enum lst_brw_type {
	LST_BRW_READ	= 1,
	LST_BRW_WRITE	= 2
};

enum lst_brw_flags {
	LST_BRW_CHECK_NONE   = 1,
	LST_BRW_CHECK_SIMPLE = 2,
	LST_BRW_CHECK_FULL   = 3
};

struct lst_test_bulk_param {
	int blk_opc;		
	int blk_size;		
	int blk_time;		
	int blk_flags;		
	int blk_cli_off;	
	int blk_srv_off;	
};

struct lst_test_ping_param {
	int png_size;		
	int png_time;		
	int png_loop;		
	int png_flags;		
};


struct srpc_counters {
	__u32 errors;
	__u32 rpcs_sent;
	__u32 rpcs_rcvd;
	__u32 rpcs_dropped;
	__u32 rpcs_expired;
	__u64 bulk_get;
	__u64 bulk_put;
} __attribute__((packed));

struct sfw_counters {
	
	__u32 running_ms;
	__u32 active_batches;
	__u32 zombie_sessions;
	__u32 brw_errors;
	__u32 ping_errors;
} __attribute__((packed));

#define LNET_SELFTEST_GENL_NAME		"lnet_selftest"
#define LNET_SELFTEST_GENL_VERSION	0x1

/* enum lnet_selftest_commands	      - Supported core LNet Selftest Netlink
 *					commands
 *
 * @LNET_SELFTEST_CMD_UNSPEC:		unspecified command to catch errors
 * @LNET_SELFTEST_CMD_SESSIONS:		command to manage sessions
 * @LNET_SELFTEST_CMD_GROUPS:		command to manage selftest groups
 */
enum lnet_selftest_commands {
	LNET_SELFTEST_CMD_UNSPEC	= 0,

	LNET_SELFTEST_CMD_SESSIONS	= 1,
	LNET_SELFTEST_CMD_GROUPS	= 2,

	__LNET_SELFTEST_CMD_MAX_PLUS_ONE,
};

#define LNET_SELFTEST_CMD_MAX (__LNET_SELFTEST_CMD_MAX_PLUS_ONE - 1)

#endif
