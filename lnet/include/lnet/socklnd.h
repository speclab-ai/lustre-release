

/* Copyright (c) 2003, 2010, Oracle and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 */



#ifndef __LNET_LNET_SOCKLND_H__
#define __LNET_LNET_SOCKLND_H__

#include <uapi/linux/lnet/lnet-types.h>
#include <uapi/linux/lnet/socklnd.h>

struct ksock_hello_msg {
	__u32			kshm_magic;	
	__u32			kshm_version;	
	struct lnet_nid		kshm_src_nid;	
	struct lnet_nid		kshm_dst_nid;	
	lnet_pid_t		kshm_src_pid;	
	lnet_pid_t		kshm_dst_pid;	
	__u64			kshm_src_incarnation; 
	__u64			kshm_dst_incarnation; 
	__u32			kshm_ctype;	
	__u32			kshm_nips;	
	__u32			kshm_ips[];	
} __packed;

struct ksock_hello_msg_nid4 {
	__u32			kshm_magic;	
	__u32			kshm_version;	
	lnet_nid_t		kshm_src_nid;	
	lnet_nid_t		kshm_dst_nid;	
	lnet_pid_t		kshm_src_pid;	
	lnet_pid_t		kshm_dst_pid;	
	__u64			kshm_src_incarnation; 
	__u64			kshm_dst_incarnation; 
	__u32			kshm_ctype;	
	__u32			kshm_nips;	
	__u32			kshm_ips[];	
} __packed;

struct ksock_msg_hdr {
	__u32			ksh_type;	
	__u32			ksh_csum;	
	__u64			ksh_zc_cookies[2]; /* Zero-Copy request/ACK
						    * cookie
						    */
} __packed;

#define KSOCK_MSG_NOOP		0xc0		
#define KSOCK_MSG_LNET		0xc1		

struct ksock_msg {
	struct ksock_msg_hdr	ksm_kh;
	union {
		
		
		
		struct lnet_hdr_nid4 lnetmsg_nid4;
		/* case ksm_kh.ksh_type == KSOCK_MSG_LNET &&
		 *      kshm_version >= KSOCK_PROTO_V4
		 */
		struct lnet_hdr_nid16 lnetmsg_nid16;
	} __packed ksm_u;
} __packed;
#define ksm_type ksm_kh.ksh_type
#define ksm_csum ksm_kh.ksh_csum
#define ksm_zc_cookies ksm_kh.ksh_zc_cookies

/* We need to know this number to parse hello msg from ksocklnd in
 * other LND (usocklnd, for example) */
#define KSOCK_PROTO_V2		2
#define KSOCK_PROTO_V3		3
#define KSOCK_PROTO_V4		4

#endif
