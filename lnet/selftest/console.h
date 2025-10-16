

/*
 * Copyright (c) 2007, 2010, Oracle and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 *
 * Copyright (c) 2012, 2013, Intel Corporation.
 */

/*
 * This file is part of Lustre, http:
 *
 * kernel structure for LST console
 *
 * Author: Liang Zhen <liangzhen@clusterfs.com>
 */

#ifndef __LST_CONSOLE_H__
#define __LST_CONSOLE_H__

#include <linux/uaccess.h>
#include <linux/libcfs/libcfs.h>
#include <lnet/lib-types.h>

#include "selftest.h"
#include "conrpc.h"


struct lstcon_node {
	struct lnet_process_id		nd_id;    
	int				nd_ref;   
	int				nd_state; 
	int				nd_timeout; 
	ktime_t				nd_stamp; 
	struct lstcon_rpc		nd_ping;  
};


struct lstcon_ndlink {
	struct list_head	ndl_link;	
	struct list_head	ndl_hlink;	
	struct lstcon_node	*ndl_node;	
};


struct lstcon_group {
	struct list_head	grp_link;	
	int			grp_ref;	
	int			grp_userland;	
	int			grp_nnode;	
	char			grp_name[LST_NAME_SIZE];	

	struct list_head	grp_trans_list;	
	struct list_head	grp_ndl_list;	
	struct list_head	grp_ndl_hash[]; 
};

#define LST_BATCH_IDLE          0xB0            
#define LST_BATCH_RUNNING       0xB1            

struct lstcon_tsb_hdr {
	struct lst_bid		tsb_id;         
	int			tsb_index;      
};


struct lstcon_batch {
	
	struct lstcon_tsb_hdr	bat_hdr;
	
	struct list_head	bat_link;
	
	int			bat_ntest;
	
	int			bat_state;
	
	int			bat_arg;
	
	char			bat_name[LST_NAME_SIZE];

	
	struct list_head	bat_test_list;
	
	struct list_head	bat_trans_list;
	
	struct list_head	bat_cli_list;
	
	struct list_head	*bat_cli_hash;
	
	struct list_head	bat_srv_list;
	
	struct list_head	*bat_srv_hash;
};


struct lstcon_test {
	
	struct lstcon_tsb_hdr	tes_hdr;
	
	struct list_head	tes_link;
	
	struct lstcon_batch	*tes_batch;
	int			tes_type;       
	int			tes_stop_onerr; 
	int			tes_oneside;    
	int			tes_concur;     
	int			tes_loop;       
	int			tes_dist;       
	int			tes_span;       
	int			tes_cliidx;     
	struct list_head	tes_trans_list; 
	struct lstcon_group	*tes_src_grp;   
	struct lstcon_group	*tes_dst_grp;   
	int			tes_paramlen;   
	char			tes_param[];    
};

#define LST_GLOBAL_HASHSIZE     503   
#define LST_NODE_HASHSIZE       239   

#define LST_SESSION_NONE        0x0   
#define LST_SESSION_ACTIVE      0x1   

#define LST_CONSOLE_TIMEOUT     300   

struct lstcon_session {
	struct mutex		ses_mutex;      
	struct lst_session_id	ses_id;         
	u32			ses_key;        
	int			ses_state;      
	int			ses_timeout;    
	time64_t		ses_laststamp;  
	
	unsigned int		ses_features;
	
	unsigned int		ses_feats_updated:1;
	
	unsigned int		ses_force:1;
	
	unsigned int		ses_shutdown:1;
	
	unsigned int		ses_expired:1;
	__u64			ses_id_cookie;  
	char			ses_name[LST_NAME_SIZE];  
	struct lstcon_rpc_trans	*ses_ping;      
	struct stt_timer	ses_ping_timer; 
	struct lstcon_trans_stat ses_trans_stat;

	struct list_head	ses_trans_list; 
	struct list_head	ses_grp_list;   
	struct list_head	ses_bat_list;   
	struct list_head	ses_ndl_list;   
	struct list_head	*ses_ndl_hash;  

	spinlock_t		ses_rpc_lock;   
	atomic_t		ses_rpc_counter;
	struct list_head	ses_rpc_freelist;
}; 

extern struct lstcon_session console_session;

static inline struct lstcon_trans_stat *
lstcon_trans_stat(void)
{
	return &console_session.ses_trans_stat;
}

static inline struct list_head *
lstcon_id2hash(struct lnet_process_id id, struct list_head *hash)
{
	unsigned int idx = LNET_NIDADDR(id.nid) % LST_NODE_HASHSIZE;

	return &hash[idx];
}

extern int lstcon_session_match(struct lst_sid sid);
extern int lstcon_session_new(char *name, int key, unsigned int version,
			      int timeout, int flags);
extern int lstcon_session_end(void);
extern int lstcon_session_debug(int timeout,
				struct list_head __user *result_up);
extern int lstcon_session_feats_check(unsigned int feats);
extern int lstcon_batch_debug(int timeout, char *name,
			      int client, struct list_head __user *result_up);
extern int lstcon_group_debug(int timeout, char *name,
			      struct list_head __user *result_up);
extern int lstcon_nodes_debug(int timeout, int nnd,
			      struct lnet_process_id __user *nds_up,
			      struct list_head __user *result_up);
extern int lstcon_group_add(char *name);
extern int lstcon_group_del(char *name);
void lstcon_group_addref(struct lstcon_group *grp);
void lstcon_group_decref(struct lstcon_group *grp);
int lstcon_group_find(const char *name, struct lstcon_group **grpp);
extern int lstcon_group_clean(char *name, int args);
extern int lstcon_group_refresh(char *name, struct list_head __user *result_up);
extern int lstcon_nodes_add(char *name, int nnd,
			    struct lnet_process_id __user *nds_up,
			    unsigned int *featp,
			    struct list_head __user *result_up);
extern int lstcon_nodes_remove(char *name, int nnd,
			       struct lnet_process_id __user *nds_up,
			       struct list_head __user *result_up);
extern int lstcon_group_info(char *name,
			     struct lstcon_ndlist_ent __user *gent_up,
			     int *index_p, int *ndent_p,
			     struct lstcon_node_ent __user *ndents_up);
extern int lstcon_batch_add(char *name);
extern int lstcon_batch_run(char *name, int timeout,
			    struct list_head __user *result_up);
extern int lstcon_batch_stop(char *name, int force,
			     struct list_head __user *result_up);
extern int lstcon_test_batch_query(char *name, int testidx,
				   int client, int timeout,
				   struct list_head __user *result_up);
extern int lstcon_batch_del(char *name);
extern int lstcon_batch_list(int idx, int namelen, char __user *name_up);
extern int lstcon_batch_info(char *name,
			     struct lstcon_test_batch_ent __user *ent_up,
			     int server, int testidx, int *index_p,
			     int *ndent_p,
			     struct lstcon_node_ent __user *dents_up);
extern int lstcon_group_stat(char *grp_name, int timeout,
			     struct list_head __user *result_up);
extern int lstcon_nodes_stat(int count, struct lnet_process_id __user *ids_up,
			     int timeout, struct list_head __user *result_up);
extern int lstcon_test_add(char *batch_name, int type, int loop,
			   int concur, int dist, int span,
			   char *src_name, char *dst_name,
			   void *param, int paramlen, int *retp,
			   struct list_head __user *result_up);

int lstcon_ioctl_entry(struct notifier_block *nb,
		       unsigned long cmd, void *vdata);

int lstcon_console_init(void);
int lstcon_console_fini(void);

int lstcon_init_netlink(void);
void lstcon_fini_netlink(void);

#endif
