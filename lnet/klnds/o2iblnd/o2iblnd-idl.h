

/* Copyright (c) 2007, 2010, Oracle and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 *
 * Copyright (c) 2011, 2017, Intel Corporation.
 */

/* This file is part of Lustre, http:
 *
 * Author: Eric Barton <eric@bartonsoftware.com>
 */

#ifndef __LNET_O2IBLND_IDL_H__
#define __LNET_O2IBLND_IDL_H__

#include <uapi/linux/lnet/lnet-idl.h>

/************************************************************************
 * IB Wire message format.
 * These are sent in sender's byte order (i.e. receiver flips).
 */

struct kib_connparams {
	u16			ibcp_queue_depth;
	u16			ibcp_max_frags;
	u32			ibcp_max_msg_size;
} __packed;

struct kib_immediate_msg {
	struct lnet_hdr_nid4	ibim_hdr;	
	char			ibim_payload[]; 
} __packed;

struct kib_rdma_frag {
	u32			rf_nob;		
	u64			rf_addr;	
} __packed;

struct kib_rdma_desc {
	u32			rd_key;		
	u32			rd_nfrags;	
	struct kib_rdma_frag	rd_frags[];	
} __packed;

struct kib_putreq_msg {
	struct lnet_hdr_nid4	ibprm_hdr;	
	u64			ibprm_cookie;	
} __packed;

struct kib_putack_msg {
	u64			ibpam_src_cookie;
	u64			ibpam_dst_cookie;
	struct kib_rdma_desc	ibpam_rd;	
} __packed;

struct kib_get_msg {
	struct lnet_hdr_nid4	ibgm_hdr;	
	u64			ibgm_cookie;	
	struct kib_rdma_desc	ibgm_rd;	
} __packed;

struct kib_completion_msg {
	u64			ibcm_cookie;	
	s32			ibcm_status;    
} __packed;

struct kib_msg {
	
	u32			ibm_magic;	
	u16			ibm_version;	

	u8			ibm_type;	
	u8			ibm_credits;	
	u32			ibm_nob;	
	u32			ibm_cksum;	
	u64			ibm_srcnid;	
	u64			ibm_srcstamp;	
	u64			ibm_dstnid;	
	u64			ibm_dststamp;	

	union {
		struct kib_connparams		connparams;
		struct kib_immediate_msg	immediate;
		struct kib_putreq_msg		putreq;
		struct kib_putack_msg		putack;
		struct kib_get_msg		get;
		struct kib_completion_msg	completion;
	} __packed ibm_u;
} __packed;

#define IBLND_MSG_MAGIC LNET_PROTO_IB_MAGIC     

#define IBLND_MSG_VERSION_1	0x11
#define IBLND_MSG_VERSION_2	0x12
#define IBLND_MSG_VERSION	IBLND_MSG_VERSION_2

#define IBLND_MSG_CONNREQ	0xc0	
#define IBLND_MSG_CONNACK	0xc1	
#define IBLND_MSG_NOOP		0xd0	
#define IBLND_MSG_IMMEDIATE	0xd1	
#define IBLND_MSG_PUT_REQ	0xd2	
#define IBLND_MSG_PUT_NAK	0xd3	
#define IBLND_MSG_PUT_ACK	0xd4	
#define IBLND_MSG_PUT_DONE	0xd5	
#define IBLND_MSG_GET_REQ	0xd6	
#define IBLND_MSG_GET_DONE	0xd7	

struct kib_rej {
	u32			ibr_magic;	
	u16			ibr_version;	
	u8			ibr_why;	
	u8			ibr_padding;	
	u64			ibr_incarnation;
	struct kib_connparams	ibr_cp;		
} __packed;


#define IBLND_REJECT_CONN_RACE       1          
#define IBLND_REJECT_NO_RESOURCES    2          
#define IBLND_REJECT_FATAL           3          

#define IBLND_REJECT_CONN_UNCOMPAT   4          
#define IBLND_REJECT_CONN_STALE      5          


#define IBLND_REJECT_RDMA_FRAGS      6

#define IBLND_REJECT_MSG_QUEUE_SIZE  7
#define IBLND_REJECT_INVALID_SRV_ID  8
#define IBLND_REJECT_EARLY	     9		



#endif 
