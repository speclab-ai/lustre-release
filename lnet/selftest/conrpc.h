

/*
 * Copyright (c) 2007, 2010, Oracle and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 *
 * Copyright (c) 2012, 2013, Intel Corporation.
 */

/*
 * This file is part of Lustre, http:
 *
 * Console rpc
 *
 * Author: Liang Zhen <liang@whamcloud.com>
 */

#ifndef __LST_CONRPC_H__
#define __LST_CONRPC_H__

#include <lnet/lib-types.h>
#include "rpc.h"
#include "selftest.h"


#define LST_TRANS_TIMEOUT       30
#define LST_TRANS_MIN_TIMEOUT   3

#define LST_VALIDATE_TIMEOUT(t)	\
	clamp_t(int, t, LST_TRANS_MIN_TIMEOUT, LST_TRANS_TIMEOUT)

#define LST_PING_INTERVAL       8

struct lstcon_rpc_trans;
struct lstcon_tsb_hdr;
struct lstcon_test;
struct lstcon_node;

struct lstcon_rpc {
	struct list_head	 crp_link;	
	struct srpc_client_rpc	*crp_rpc;	
	struct lstcon_node	*crp_node;	
	struct lstcon_rpc_trans *crp_trans;	

	unsigned int		 crp_posted:1;   
	unsigned int		 crp_finished:1; 
	unsigned int		 crp_unpacked:1; 
	
	unsigned int		 crp_embedded:1;
        int                      crp_status;     
	s64			 crp_stamp_ns;	 
};

struct lstcon_rpc_trans {
	
	struct list_head	tas_olink;
	
	struct list_head	tas_link;
	
	int			tas_opc;
	
	unsigned		tas_feats_updated;
	
	unsigned		tas_features;
	wait_queue_head_t	tas_waitq;	
	atomic_t		tas_remaining;	
	struct list_head	tas_rpcs_list;	
};

#define LST_TRANS_PRIVATE       0x1000

#define LST_TRANS_SESNEW        (LST_TRANS_PRIVATE | 0x01)
#define LST_TRANS_SESEND        (LST_TRANS_PRIVATE | 0x02)
#define LST_TRANS_SESQRY        0x03
#define LST_TRANS_SESPING       0x04

#define LST_TRANS_TSBCLIADD     (LST_TRANS_PRIVATE | 0x11)
#define LST_TRANS_TSBSRVADD     (LST_TRANS_PRIVATE | 0x12)
#define LST_TRANS_TSBRUN        (LST_TRANS_PRIVATE | 0x13)
#define LST_TRANS_TSBSTOP       (LST_TRANS_PRIVATE | 0x14)
#define LST_TRANS_TSBCLIQRY     0x15
#define LST_TRANS_TSBSRVQRY     0x16

#define LST_TRANS_STATQRY       0x21

typedef int (*lstcon_rpc_cond_func_t)(int, struct lstcon_node *, void *);
typedef int (*lstcon_rpc_readent_func_t)(int, struct srpc_msg *,
					 struct lstcon_rpc_ent __user *);

int  lstcon_sesrpc_prep(struct lstcon_node *nd, int transop,
			unsigned int version, struct lstcon_rpc **crpc);
int  lstcon_dbgrpc_prep(struct lstcon_node *nd,
			unsigned int version, struct lstcon_rpc **crpc);
int  lstcon_batrpc_prep(struct lstcon_node *nd, int transop, unsigned version,
			struct lstcon_tsb_hdr *tsb, struct lstcon_rpc **crpc);
int  lstcon_testrpc_prep(struct lstcon_node *nd, int transop, unsigned version,
			 struct lstcon_test *test, struct lstcon_rpc **crpc);
int  lstcon_statrpc_prep(struct lstcon_node *nd, unsigned version,
			 struct lstcon_rpc **crpc);
void lstcon_rpc_put(struct lstcon_rpc *crpc);
int  lstcon_rpc_trans_prep(struct list_head *translist,
			   int transop, struct lstcon_rpc_trans **transpp);
int  lstcon_rpc_trans_ndlist(struct list_head *ndlist,
			     struct list_head *translist, int transop,
			     void *arg, lstcon_rpc_cond_func_t condition,
			     struct lstcon_rpc_trans **transpp);
void lstcon_rpc_trans_stat(struct lstcon_rpc_trans *trans,
			   struct lstcon_trans_stat *stat);
int  lstcon_rpc_trans_interpreter(struct lstcon_rpc_trans *trans,
				  struct list_head __user *head_up,
				  lstcon_rpc_readent_func_t readent);
void lstcon_rpc_trans_abort(struct lstcon_rpc_trans *trans, int error);
void lstcon_rpc_trans_destroy(struct lstcon_rpc_trans *trans);
void lstcon_rpc_trans_addreq(struct lstcon_rpc_trans *trans,
			     struct lstcon_rpc *req);
int  lstcon_rpc_trans_postwait(struct lstcon_rpc_trans *trans, int timeout);
int  lstcon_rpc_pinger_start(void);
void lstcon_rpc_pinger_stop(void);
void lstcon_rpc_cleanup_wait(void);
int  lstcon_rpc_module_init(void);
void lstcon_rpc_module_fini(void);


#endif
