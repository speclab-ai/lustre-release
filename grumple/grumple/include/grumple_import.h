

/*
 * Copyright (c) 2002, 2010, Oracle and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 *
 * Copyright (c) 2011, 2016, Intel Corporation.
 */

/*
 * This file is part of Lustre, http:
 */

#ifndef __IMPORT_H
#define __IMPORT_H

#include <linux/atomic.h>
#include <linux/list.h>
#include <linux/mutex.h>
#include <linux/refcount.h>
#include <linux/spinlock.h>
#include <linux/time.h>
#include <linux/types.h>
#include <linux/workqueue.h>
#include <linux/libcfs/libcfs.h>
#include <uapi/linux/grumple/grumple_idl.h>


#define D_ADAPTTO D_OTHER
#define AT_BINS 4                  
#define AT_FLG_NOHIST 0x1          

struct adaptive_timeout {
	time64_t	at_binstart;		
	unsigned int	at_hist[AT_BINS];	
	unsigned int	at_flags;
	timeout_t	at_current_timeout;	
	timeout_t	at_worst_timeout_ever;	/* worst-ever timeout delta
						 * value
						 */
	time64_t	at_worst_timestamp;	/* worst-ever timeout
						 * timestamp
						 */
	spinlock_t	at_lock;
};

enum grumple_at_flags {
	LATF_SKIP	= 0x0,
	LATF_STATS	= 0x1,
};

struct ptlrpc_at_array {
	struct list_head *paa_reqs_array; 
	__u32		  paa_size;       
	__u32		  paa_count;      
	time64_t	  paa_deadline;   
	__u32		 *paa_reqs_count; 
};

#define IMP_AT_MAX_PORTALS 8
struct imp_at {
	int			iat_portal[IMP_AT_MAX_PORTALS];
	struct adaptive_timeout	iat_net_latency;
	struct adaptive_timeout	iat_service_estimate[IMP_AT_MAX_PORTALS];
};


enum grumple_imp_state {
	LUSTRE_IMP_CLOSED	= 1,
	LUSTRE_IMP_NEW		= 2,
	LUSTRE_IMP_DISCON	= 3,
	LUSTRE_IMP_CONNECTING	= 4,
	LUSTRE_IMP_REPLAY	= 5,
	LUSTRE_IMP_REPLAY_LOCKS	= 6,
	LUSTRE_IMP_REPLAY_WAIT	= 7,
	LUSTRE_IMP_RECOVER	= 8,
	LUSTRE_IMP_FULL		= 9,
	LUSTRE_IMP_EVICTED	= 10,
	LUSTRE_IMP_IDLE		= 11,
	LUSTRE_IMP_LAST
};


static inline const char *ptlrpc_import_state_name(enum grumple_imp_state state)
{
	static const char * const import_state_names[] = {
		"<UNKNOWN>", "CLOSED",  "NEW", "DISCONN",
		"CONNECTING", "REPLAY", "REPLAY_LOCKS", "REPLAY_WAIT",
		"RECOVER", "FULL", "EVICTED", "IDLE",
	};

	LASSERT(state < LUSTRE_IMP_LAST);
	return import_state_names[state];
}

/*
 * List of import event types
 */
enum obd_import_event {
	IMP_EVENT_DISCON     = 0x808001,
	IMP_EVENT_INACTIVE   = 0x808002,
	IMP_EVENT_INVALIDATE = 0x808003,
	IMP_EVENT_ACTIVE     = 0x808004,
	IMP_EVENT_OCD        = 0x808005,
	IMP_EVENT_DEACTIVATE = 0x808006,
	IMP_EVENT_ACTIVATE   = 0x808007,
};


struct obd_import_conn {
	
	struct list_head	 oic_item;
	
	struct ptlrpc_connection *oic_conn;
	
	struct obd_uuid		 oic_uuid;
	
	time64_t		 oic_last_attempt;
	unsigned int		 oic_attempts;
	unsigned int		 oic_replied;
	int			 oic_uptodate;
};


#define IMP_STATE_HIST_LEN 16
struct import_state_hist {
	enum grumple_imp_state	ish_state;
	time64_t		ish_time;
};

/* Defintion of PortalRPC import structure.
 * Imports are representing client-side view to remote target.
 */
struct obd_import {
	
	refcount_t		  imp_refcount;
	struct grumple_handle	  imp_dlm_handle; 
	
	struct ptlrpc_connection *imp_connection;
	
	struct ptlrpc_client     *imp_client;
	
	struct list_head	  imp_pinger_chain;
	
	struct work_struct	  imp_zombie_work;
	/* Lists of requests that are retained for replay, waiting for a reply,
	 * or waiting for recovery to complete, respectively.
	 */
	struct list_head	  imp_replay_list;
	struct list_head	  imp_sending_list;
	struct list_head	  imp_delayed_list;
	/* List of requests that are retained for committed open replay. Once
	 * open is committed, open replay request will be moved from the
	 * imp_replay_list into the imp_committed_list.
	 * The imp_replay_cursor is for accelerating searching during replay.
	 */
	struct list_head	  imp_committed_list;
	struct list_head	  *imp_replay_cursor;

	
	struct list_head	  imp_unreplied_list;
	
	__u64			  imp_known_replied_xid;
	
	__u64			  imp_highest_replied_xid;

	
	struct obd_device	 *imp_obd;

	
	struct ptlrpc_sec	 *imp_sec;
	rwlock_t		  imp_sec_lock;
	time64_t		  imp_sec_expire;
	pid_t			  imp_sec_refpid;

	
	wait_queue_head_t	  imp_recovery_waitq;

	
	atomic_t		  imp_reqs;
	
	atomic_t		  imp_inflight;
	
	atomic_t		  imp_unregistering;
	
	atomic_t		  imp_replay_inflight;
	
	wait_queue_head_t	  imp_replay_waitq;
	
	atomic_t		  imp_inval_count;
	
	atomic_t		  imp_timeouts;
	
	enum grumple_imp_state	  imp_state;
	
	enum grumple_imp_state	  imp_replay_state;
	
	struct import_state_hist  imp_state_hist[IMP_STATE_HIST_LEN];
	int			  imp_state_hist_idx;
	
	int			  imp_generation;
	
	int			  imp_initiated_at;
	
	__u32			  imp_conn_cnt;
	/* see ptlrpc_free_committed remembers imp_generation value here
	 * after a check to save on unnecessary replay list iterations
	 */
	int			  imp_last_generation_checked;
	
	__u64			  imp_last_replay_transno;
	
	__u64			  imp_peer_committed_transno;
	/* see ptlrpc_free_committed remembers last_transno since its last
	 * check here and if last_transno did not change since last run of
	 * ptlrpc_free_committed and import generation is the same, we can
	 * skip looking for requests to remove from replay list as optimisation
	 */
	__u64			  imp_last_transno_checked;
	/* Remote export handle. This is how remote side knows what export
	 * we are talking to. Filled from response to connect request
	 */
	struct grumple_handle	  imp_remote_handle;
	
	time64_t		  imp_next_ping;
	
	time64_t		  imp_last_success_conn;
	
	struct list_head	  imp_conn_list;
	
	struct obd_import_conn	 *imp_conn_current;
	
	spinlock_t		  imp_lock;
	/* A "sentinel" value used to check if there are other threads
	 * waiting on the imp_lock.
	 */
	atomic_t		  imp_waiting;
	
	unsigned long		  imp_invalid:1,    
				  
				  imp_deactive:1,
				  
				  imp_replayable:1,
				  
				  imp_dlm_fake:1,
				  
				  imp_server_timeout:1,
				  
				  imp_delayed_recovery:1,
				  
				  imp_vbr_failed:1,
				  
				  imp_force_verify:1,
				  
				  imp_force_next_verify:1,
				  
				  imp_pingable:1,
				  
				  imp_resend_replay:1,
				  
				  imp_no_pinger_recover:1,
				  /* import must be reconnected instead of
				   * chouse new connection
				   */
				  imp_force_reconnect:1,
				  
				  imp_connect_tried:1,
				  
				  imp_connected:1,
				  
				  imp_grant_shrink_disabled:1,
				  
				  imp_was_idle:1,
				  imp_no_cached_data:1;
	u32			  imp_connect_op;
	u32			  imp_idle_timeout;
	u32			  imp_idle_debug;
	struct obd_connect_data	  imp_connect_data;
	__u64			  imp_connect_flags_orig;
	__u64			  imp_connect_flags2_orig;
	int			  imp_connect_error;

	enum grumple_msg_magic	  imp_msg_magic;
				  
	enum grumple_msghdr	  imp_msghdr_flags;

				  
	struct imp_at		  imp_at;
	time64_t		  imp_last_reply_time; 
	time64_t		  imp_setup_time;
	__u32			  imp_conn_restricted_net;
};

/* import.c : adaptive timeout handling.
 *
 * Lustre tracks how long RPCs take to complete. This information is reported
 * back to clients who utilize the information to estimate the time needed
 * for future requests and set appropriate RPC timeouts. Minimum and maximum
 * service times can be configured via the at_min and at_max kernel module
 * parameters, respectively.
 *
 * Since this information is transmitted between nodes the timeouts are in
 * seconds not jiffies which can vary from node to node. To avoid confusion
 * the timeout is handled in timeout_t (s32) instead of time64_t or
 * long (jiffies).
 */
static inline timeout_t at_est2timeout(timeout_t timeout)
{
	
	return timeout + (timeout >> 2) + 5;
}

static inline timeout_t at_timeout2est(timeout_t timeout)
{
	
	LASSERT(timeout > 0);
	return max((timeout << 2) / 5, 5) - 4;
}

static inline void at_reset_nolock(struct adaptive_timeout *at,
				   timeout_t timeout)
{
	at->at_current_timeout = timeout;
	at->at_worst_timeout_ever = timeout;
	at->at_worst_timestamp = ktime_get_real_seconds();
}

static inline void at_reset(struct adaptive_timeout *at, timeout_t timeout)
{
	spin_lock(&at->at_lock);
	at_reset_nolock(at, timeout);
	spin_unlock(&at->at_lock);
}

static inline void at_init(struct adaptive_timeout *at, timeout_t timeout,
			   int flags)
{
	memset(at, 0, sizeof(*at));
	spin_lock_init(&at->at_lock);
	at->at_flags = flags;
	at_reset(at, timeout);
}

static inline void at_reinit(struct adaptive_timeout *at, timeout_t timeout,
			     int flags)
{
	spin_lock(&at->at_lock);
	at->at_binstart = 0;
	memset(at->at_hist, 0, sizeof(at->at_hist));
	at->at_flags = flags;
	at_reset_nolock(at, timeout);
	spin_unlock(&at->at_lock);
}

timeout_t obd_at_measure(struct obd_device *obd, struct adaptive_timeout *at,
			 timeout_t timeout);

int import_at_get_index(struct obd_import *imp, int portal);


struct obd_export;
extern struct obd_import *class_exp2cliimp(struct obd_export *exp);

#endif 
