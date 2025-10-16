

/*
 * Copyright (c) 2023-2025, Amazon and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 */

/*
 * This file is part of Lustre, http:
 *
 * Author: Yehuda Yitschak <yehuday@amazon.com>
 * Author: Yonatan Nachum <ynachum@amazon.com>
 */

#ifndef _EFALND_PROTO_H_
#define _EFALND_PROTO_H_

enum kefa_comp_status {
	
	KEFA_COMP_STATUS_OK				= 0,
	
	KEFA_COMP_STATUS_UNSUPPORTED_OP			= 1,
	
	KEFA_COMP_STATUS_NO_MEMORY			= 2,
	
	KEFA_COMP_STATUS_GENERAL_ERROR			= 3,

	
	KEFA_COMP_STATUS_COMM_FAILURE			= 20,
	
	KEFA_COMP_STATUS_NO_LNET_MSG			= 21,
	
	KEFA_COMP_STATUS_BAD_ADDRESS			= 22,
	
	KEFA_COMP_STATUS_DMA_FAILURE			= 23,
	
	KEFA_COMP_STATUS_UNSUPPORTED_PROTO		= 24,
};

struct kefa_nid_md_entry {
	lnet_nid_t nid;
	u8 gid[16];
	u16 qp_num;
	u32 qkey;
	u8 buffer[10];
} __packed;

struct kefa_qp_proto {
	u16 qp_num;
	u32 qkey;
} __packed;

struct kefa_rdma_desc {
	u32 key;			
	u64 addr;
	u32 nob;			
} __packed;

struct kefa_immediate_msg_v2 {
	struct lnet_hdr_nid16 hdr;	
	char payload[];			
} __packed;

struct kefa_putr_req_msg_v2 {
	struct lnet_hdr_nid16 hdr;	
	u64 cookie;			
	struct kefa_rdma_desc rdma_desc;
} __packed;

struct kefa_getr_req_msg_v2 {
	struct lnet_hdr_nid16 hdr;	
	u64 sink_cookie;		
} __packed;

struct kefa_getr_ack_msg {
	u64 sink_cookie;		
	u64 src_cookie;			
	struct kefa_rdma_desc rdma_desc;
} __packed;

struct kefa_completion_msg {
	u64 cookie;			
	s16 status;			
} __packed;

struct kefa_conn_probe_msg {
	u16 lnd_ver;			
	u8 src_gid[16];			
	u64 src_epoch;			
	struct kefa_qp_proto cm_qp;
	u64 caps;			
} __packed;

struct kefa_conn_probe_resp_msg {
	u16 lnd_ver;			
	s16 status;			
	u64 src_epoch;			
	u64 caps;			
	u8 min_proto_ver;		
	u8 max_proto_ver;		
} __packed;

struct kefa_conn_req_msg {
	
	u16 lnd_ver;			
	u8 src_gid[16];			
	u64 src_epoch;			
	struct kefa_qp_proto cm_qp;
	u64 caps;			
	u64 reserved;
	u64 requests;			
	u32 src_conn_id;		
	u32 nqps;			
	struct kefa_qp_proto data_qps[]; 
} __packed;

struct kefa_conn_req_ack {
	u16 lnd_ver;			
	u64 src_epoch;			
	u64 caps;			
	u64 reserved;
	s16 status;			
	u32 src_conn_id;		
	u32 nqps;			
	struct kefa_qp_proto data_qps[]; 
} __packed;

struct kefa_msg_v1 {
	lnet_nid_t srcnid;		
	lnet_nid_t dstnid;		
	u64 dst_epoch;			
	u32 dst_conn_id;		
	u8 credits;			

	union {
		struct kefa_conn_probe_msg conn_probe;
		struct kefa_conn_probe_resp_msg conn_probe_resp;
	} __packed u;
	
} __packed;

struct kefa_msg_v2 {
	struct lnet_nid srcnid;		
	struct lnet_nid dstnid;		
	u64 dst_epoch;			
	u32 dst_conn_id;		
	u8 credits;			

	union {
		struct kefa_immediate_msg_v2 immediate;
		struct kefa_putr_req_msg_v2 putr_req;
		struct kefa_getr_req_msg_v2 getr_req;
		struct kefa_getr_ack_msg getr_ack;
		struct kefa_completion_msg completion;
		struct kefa_conn_probe_msg conn_probe;
		struct kefa_conn_probe_resp_msg conn_probe_resp;
		struct kefa_conn_req_msg conn_request;
		struct kefa_conn_req_ack conn_request_ack;
	} __packed u;
	
} __packed;

struct kefa_hdr {
	
	u32 magic;			
	u8 proto_ver;			
	u8 type;			
	u16 nob;			
} __packed;

struct kefa_msg {
	struct kefa_hdr hdr;
	union {
		struct kefa_msg_v1 msg_v1;
		struct kefa_msg_v2 msg_v2;
	} __packed;
	
} __packed;

#define EFALND_MSG_MAGIC LNET_PROTO_EFA_MAGIC	

#define EFALND_PROTO_VER_1	0x81
#define EFALND_PROTO_VER_2	0x82
#define EFALND_MIN_PROTO_VER	EFALND_PROTO_VER_1
#define EFALND_MAX_PROTO_VER	EFALND_PROTO_VER_2

#define EFALND_MSG_RESERVED		0x00
#define EFALND_MSG_CONN_PROBE		0x01	
#define EFALND_MSG_CONN_PROBE_RESP	0x02	
#define EFALND_MSG_CONN_REQ		0x03	
#define EFALND_MSG_CONN_REQ_ACK		0x04	
#define EFALND_MSG_IMMEDIATE		0x05	
#define EFALND_MSG_NACK			0x06	
#define EFALND_MSG_PUTR_REQ		0x07	
#define EFALND_MSG_PUTR_DONE		0x08	
#define EFALND_MSG_GETR_REQ		0x09	
#define EFALND_MSG_GETR_ACK		0x0a	
#define EFALND_MSG_GETR_DONE		0x0b	
#define EFALND_MSG_MAX			0x0c

#endif
