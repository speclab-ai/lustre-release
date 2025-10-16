

/*
 * Copyright (c) 2007, 2010, Oracle and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 *
 * Copyright (c) 2012, 2016, Intel Corporation.
 */

/*
 * This file is part of Lustre, http:
 */

#ifndef __SELFTEST_RPC_H__
#define __SELFTEST_RPC_H__

#include <uapi/linux/lnet/lnetst.h>

/* services below SRPC_FRAMEWORK_SERVICE_MAX_ID are framework
 * services, e.g. create/modify session.
 */
enum srpc_service_type {
	SRPC_SERVICE_DEBUG             = 0,
	SRPC_SERVICE_MAKE_SESSION      = 1,
	SRPC_SERVICE_REMOVE_SESSION    = 2,
	SRPC_SERVICE_BATCH             = 3,
	SRPC_SERVICE_TEST              = 4,
	SRPC_SERVICE_QUERY_STAT        = 5,
	SRPC_SERVICE_JOIN              = 6,
	SRPC_FRAMEWORK_SERVICE_MAX_ID  = 10,
	
	SRPC_SERVICE_BRW               = 11,
	SRPC_SERVICE_PING              = 12,
	SRPC_SERVICE_MAX_ID
};

/* LST wired structures
 *
 * XXX: *REPLY == *REQST + 1
 */
enum srpc_msg_type {
	SRPC_MSG_MKSN_REQST     = 0,
	SRPC_MSG_MKSN_REPLY     = 1,
	SRPC_MSG_RMSN_REQST     = 2,
	SRPC_MSG_RMSN_REPLY     = 3,
	SRPC_MSG_BATCH_REQST    = 4,
	SRPC_MSG_BATCH_REPLY    = 5,
	SRPC_MSG_STAT_REQST     = 6,
	SRPC_MSG_STAT_REPLY     = 7,
	SRPC_MSG_TEST_REQST     = 8,
	SRPC_MSG_TEST_REPLY     = 9,
	SRPC_MSG_DEBUG_REQST    = 10,
	SRPC_MSG_DEBUG_REPLY    = 11,
	SRPC_MSG_BRW_REQST      = 12,
	SRPC_MSG_BRW_REPLY      = 13,
	SRPC_MSG_PING_REQST     = 14,
	SRPC_MSG_PING_REPLY     = 15,
	SRPC_MSG_JOIN_REQST     = 16,
	SRPC_MSG_JOIN_REPLY     = 17,
	SRPC_MSG_INVALID
};

/* CAVEAT EMPTOR:
 * All struct srpc_*_reqst's 1st field must be matchbits of reply buffer,
 * and 2nd field matchbits of bulk buffer if any.
 *
 * All struct srpc_*_reply's 1st field must be a __u32 status, and 2nd field
 * session id if needed.
 */
struct srpc_generic_reqst {
	__u64		rpyid;		
	__u64		bulkid;		
} __packed;

struct srpc_generic_reply {
	__u32		status;
	struct lst_sid	sid;
} __packed;


struct srpc_mksn_reqst {
	__u64		mksn_rpyid;      
	struct lst_sid	mksn_sid;        
	__u32		mksn_force;      
	char		mksn_name[LST_NAME_SIZE];
} __packed;				

struct srpc_mksn_reply {
	__u32		mksn_status;      
	struct lst_sid	mksn_sid;         
	__u32		mksn_timeout;     
	char			mksn_name[LST_NAME_SIZE];
} __packed;					

struct srpc_rmsn_reqst {
	__u64		rmsn_rpyid;	
	struct lst_sid	rmsn_sid;	
} __packed;				

struct srpc_rmsn_reply {
	__u32			rmsn_status;
	struct lst_sid		rmsn_sid;	
} __packed;					

struct srpc_join_reqst {
	__u64			join_rpyid;     
	struct lst_sid		join_sid;       
	char			join_group[LST_NAME_SIZE]; 
} __packed;

struct srpc_join_reply {
	__u32		join_status;    
	struct lst_sid	join_sid;       
	__u32		join_timeout;   
	char		join_session[LST_NAME_SIZE]; 
} __packed;

struct srpc_debug_reqst {
	__u64		dbg_rpyid;      
	struct lst_sid	dbg_sid;        
	__u32		dbg_flags;      
} __packed;

struct srpc_debug_reply {
	__u32		dbg_status;     
	struct lst_sid	dbg_sid;        
	__u32		dbg_timeout;    
	__u32		dbg_nbatch;     
	char		dbg_name[LST_NAME_SIZE]; 
} __packed;

#define SRPC_BATCH_OPC_RUN      1
#define SRPC_BATCH_OPC_STOP     2
#define SRPC_BATCH_OPC_QUERY    3

struct srpc_batch_reqst {
	__u64		bar_rpyid;      
	struct lst_sid	bar_sid;        
	struct lst_bid	bar_bid;        
	__u32		bar_opc;        
	__u32		bar_testidx;    
	__u32		bar_arg;        
} __packed;

struct srpc_batch_reply {
	__u32		bar_status;     
	struct lst_sid	bar_sid;	
	__u32		bar_active;     
	__u32		bar_time;       
} __packed;

struct srpc_stat_reqst {
	__u64		str_rpyid;      
	struct lst_sid	str_sid;	
	__u32		str_type;       
} __packed;

struct srpc_stat_reply {
	__u32				str_status;
	struct lst_sid			str_sid;
	struct sfw_counters		str_fw;
	struct srpc_counters		str_rpc;
	struct lnet_counters_common	str_lnet;
} __packed;

struct test_bulk_req {
	__u32		blk_opc;        
	__u32		blk_npg;        
	__u32		blk_flags;      
} __packed;

struct test_bulk_req_v1 {
	
	__u16		blk_opc;
	
	__u16		blk_flags;
	
	__u32		blk_len;
	
	__u32		blk_offset;
} __packed;

struct test_ping_req {
	__u32			png_size;       
	__u32			png_flags;      
} __packed;

struct srpc_test_reqst {
	__u64			tsr_rpyid;      
	__u64			tsr_bulkid;     
	struct lst_sid		tsr_sid;        
	struct lst_bid		tsr_bid;        
	enum srpc_service_type	tsr_service;    
	
	__u32			tsr_loop;
	__u32			tsr_concur;     
	__u8			tsr_is_client;  
	__u8			tsr_stop_onerr; 
	__u32			tsr_ndest;      

	union {
		struct test_ping_req	ping;
		struct test_bulk_req	bulk_v0;
		struct test_bulk_req_v1	bulk_v1;
	} tsr_u;
} __packed;

struct srpc_test_reply {
	__u32			tsr_status;     
	struct lst_sid		tsr_sid;
} __packed;


struct srpc_ping_reqst {
	__u64		pnr_rpyid;
	__u32		pnr_magic;
	__u32		pnr_seq;
	__u64		pnr_time_sec;
	__u64		pnr_time_nsec;
} __packed;

struct srpc_ping_reply {
	__u32		pnr_status;
	__u32		pnr_magic;
	__u32		pnr_seq;
} __packed;

struct srpc_brw_reqst {
	__u64		brw_rpyid;      
	__u64		brw_bulkid;     
	__u32		brw_rw;         
	__u32		brw_len;        
	__u32		brw_flags;      
} __packed;					

struct srpc_brw_reply {
	__u32                   brw_status;
} __packed; 

#define SRPC_MSG_MAGIC                  0xeeb0f00d
#define SRPC_MSG_VERSION                1

struct srpc_msg {
	
	__u32	msg_magic;
	
	__u32	msg_version;
	
	__u32	msg_type;
	__u32	msg_reserved0;
	__u32	msg_reserved1;
	
	__u32	msg_ses_feats;
	union {
		struct srpc_generic_reqst	reqst;
		struct srpc_generic_reply	reply;

		struct srpc_mksn_reqst		mksn_reqst;
		struct srpc_mksn_reply		mksn_reply;
		struct srpc_rmsn_reqst		rmsn_reqst;
		struct srpc_rmsn_reply		rmsn_reply;
		struct srpc_debug_reqst		dbg_reqst;
		struct srpc_debug_reply		dbg_reply;
		struct srpc_batch_reqst		bat_reqst;
		struct srpc_batch_reply		bat_reply;
		struct srpc_stat_reqst		stat_reqst;
		struct srpc_stat_reply		stat_reply;
		struct srpc_test_reqst		tes_reqst;
		struct srpc_test_reply		tes_reply;
		struct srpc_join_reqst		join_reqst;
		struct srpc_join_reply		join_reply;

		struct srpc_ping_reqst		ping_reqst;
		struct srpc_ping_reply		ping_reply;
		struct srpc_brw_reqst		brw_reqst;
		struct srpc_brw_reply		brw_reply;
	} msg_body;
} __packed;

static inline void
srpc_unpack_msg_hdr(struct srpc_msg *msg)
{
	if (msg->msg_magic == SRPC_MSG_MAGIC)
		return; 

	/* We do not swap the magic number here as it is needed to
	 * determine whether the body needs to be swapped.
	 */
	
	__swab32s(&msg->msg_type);
	__swab32s(&msg->msg_version);
	__swab32s(&msg->msg_ses_feats);
	__swab32s(&msg->msg_reserved0);
	__swab32s(&msg->msg_reserved1);
}

#endif 
