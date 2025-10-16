

/*
 * Copyright (c) 2007, 2010, Oracle and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 *
 * Copyright (c) 2012, 2017, Intel Corporation.
 */

/*
 * This file is part of Lustre, http:
 *
 * Author: Isaac Huang <isaac@clusterfs.com>
 */

#ifndef __SELFTEST_SELFTEST_H__
#define __SELFTEST_SELFTEST_H__

#define LNET_ONLY

#include <linux/refcount.h>
#include <linux/libcfs/libcfs.h>
#include <lnet/api.h>
#include <lnet/lib-lnet.h>
#include <lnet/lib-types.h>
#include <uapi/linux/lnet/lnetst.h>

#include "rpc.h"
#include "timer.h"

#ifndef MADE_WITHOUT_COMPROMISE
#define MADE_WITHOUT_COMPROMISE
#endif

/* enum lnet_selftest_session_attrs   - LNet selftest session Netlink
 *					attributes
 *
 *  @LNET_SELFTEST_SESSION_UNSPEC:	unspecified attribute to catch errors
 *  @LNET_SELFTEST_SESSION_PAD:		padding for 64-bit attributes, ignore
 *
 *  @LENT_SELFTEST_SESSION_HDR:		Netlink group this data is for
 *					(NLA_NUL_STRING)
 *  @LNET_SELFTEST_SESSION_NAME:	name of this session (NLA_STRING)
 *  @LNET_SELFTEST_SESSION_KEY:		key used to represent the session
 *					(NLA_U32)
 *  @LNET_SELFTEST_SESSION_TIMESTAMP:	timestamp when the session was created
 *					(NLA_S64)
 *  @LNET_SELFTEST_SESSION_NID:		NID of the node selftest ran on
 *					(NLA_STRING)
 *  @LNET_SELFTEST_SESSION_NODE_COUNT:	Number of nodes in use (NLA_U16)
 */
enum lnet_selftest_session_attrs {
	LNET_SELFTEST_SESSION_UNSPEC = 0,
	LNET_SELFTEST_SESSION_PAD = LNET_SELFTEST_SESSION_UNSPEC,

	LNET_SELFTEST_SESSION_HDR,
	LNET_SELFTEST_SESSION_NAME,
	LNET_SELFTEST_SESSION_KEY,
	LNET_SELFTEST_SESSION_TIMESTAMP,
	LNET_SELFTEST_SESSION_NID,
	LNET_SELFTEST_SESSION_NODE_COUNT,

	__LNET_SELFTEST_SESSION_MAX_PLUS_ONE,
};

#define LNET_SELFTEST_SESSION_MAX	(__LNET_SELFTEST_SESSION_MAX_PLUS_ONE - 1)

/* enum lnet_selftest_group_attrs     - LNet selftest group Netlink attributes
 *
 *  @LNET_SELFTEST_GROUP_ATTR_UNSPEC:	unspecified attribute to catch errors
 *
 *  @LENT_SELFTEST_GROUP_ATTR_HDR:	Netlink group this data is for
 *					(NLA_NUL_STRING)
 *  @LNET_SELFTEST_GROUP_ATTR_NAME:	name of this group (NLA_STRING)
 *  @LNET_SELFTEST_GROUP_ATTR_NODELIST:	List of nodes belonging to the group
 *					(NLA_NESTED)
 */
enum lnet_selftest_group_attrs {
	LNET_SELFTEST_GROUP_ATTR_UNSPEC = 0,

	LNET_SELFTEST_GROUP_ATTR_HDR,
	LNET_SELFTEST_GROUP_ATTR_NAME,
	LNET_SELFTEST_GROUP_ATTR_NODELIST,

	__LNET_SELFTEST_GROUP_MAX_PLUS_ONE,
};

#define LNET_SELFTEST_GROUP_MAX		(__LNET_SELFTEST_GROUP_MAX_PLUS_ONE - 1)

/* enum lnet_selftest_group_nodelist_prop_attrs	      - Netlink attributes for
 *							the properties of the
 *							nodes that belong to a
 *							group
 *
 *  @LNET_SELFTEST_GROUP_NODELIST_PROP_ATTR_UNSPEC:	unspecified attribute
 *							to catch errors
 *
 *  @LENT_SELFTEST_GROUP_NODELIST_PROP_ATTR_NID:	Nodes's NID (NLA_STRING)
 *  @LNET_SELFTEST_GROUP_NODELIST_PROP_ATTR_STATUS:	Status of the node
 *							(NLA_STRING)
 */
enum lnet_selftest_group_nodelist_prop_attrs {
	LNET_SELFTEST_GROUP_NODELIST_PROP_ATTR_UNSPEC = 0,

	LNET_SELFTEST_GROUP_NODELIST_PROP_ATTR_NID,
	LNET_SELFTEST_GROUP_NODELIST_PROP_ATTR_STATUS,
	__LNET_SELFTEST_GROUP_NODELIST_PROP_MAX_PLUS_ONE,
};

#define LNET_SELFTEST_GROUP_NODELIST_PROP_MAX	(__LNET_SELFTEST_GROUP_NODELIST_PROP_MAX_PLUS_ONE - 1)

enum lsr_swi_state {
	SWI_STATE_DONE = 0,
	SWI_STATE_NEWBORN,
	SWI_STATE_REPLY_SUBMITTED,
	SWI_STATE_REPLY_SENT,
	SWI_STATE_REQUEST_SUBMITTED,
	SWI_STATE_REQUEST_SENT,
	SWI_STATE_REPLY_RECEIVED,
	SWI_STATE_BULK_STARTED,
	SWI_STATE_RUNNING,
	SWI_STATE_PAUSE,
};


struct srpc_service;
struct srpc_service_cd;
struct sfw_test_unit;
struct sfw_test_instance;

#define SRPC_REQUEST_PORTAL             50

#define SRPC_FRAMEWORK_REQUEST_PORTAL   51

#define SRPC_RDMA_PORTAL                52

static inline enum srpc_msg_type
srpc_service2request(enum srpc_service_type service)
{
	switch (service) {
	case SRPC_SERVICE_DEBUG:
		return SRPC_MSG_DEBUG_REQST;

	case SRPC_SERVICE_MAKE_SESSION:
		return SRPC_MSG_MKSN_REQST;

	case SRPC_SERVICE_REMOVE_SESSION:
		return SRPC_MSG_RMSN_REQST;

	case SRPC_SERVICE_BATCH:
		return SRPC_MSG_BATCH_REQST;

	case SRPC_SERVICE_TEST:
		return SRPC_MSG_TEST_REQST;

	case SRPC_SERVICE_QUERY_STAT:
		return SRPC_MSG_STAT_REQST;

	case SRPC_SERVICE_JOIN:
		return SRPC_MSG_JOIN_REQST;

	case SRPC_FRAMEWORK_SERVICE_MAX_ID:
		break;

	case SRPC_SERVICE_BRW:
		return SRPC_MSG_BRW_REQST;

	case SRPC_SERVICE_PING:
		return SRPC_MSG_PING_REQST;

	case SRPC_SERVICE_MAX_ID:
		break;
	}

	LASSERTF(0, "service = %i\n", service);
	return SRPC_MSG_INVALID;
}

static inline enum srpc_msg_type
srpc_service2reply(enum srpc_service_type service)
{
	return srpc_service2request(service) + 1;
}

enum srpc_event_type {
	SRPC_BULK_REQ_RCVD   = 1, 
	SRPC_BULK_PUT_SENT   = 2, 
	SRPC_BULK_GET_RPLD   = 3, 
	SRPC_REPLY_RCVD      = 4, 
	SRPC_REPLY_SENT      = 5, 
	SRPC_REQUEST_RCVD    = 6, 
	SRPC_REQUEST_SENT    = 7, 
};


struct srpc_event {
	enum srpc_event_type	ev_type;   
	enum lnet_event_kind	ev_lnet;   
	int               ev_fired;  
	int               ev_status; 
	void             *ev_data;   
};


struct srpc_bulk {
	int			bk_len;  
	struct lnet_handle_md	bk_mdh;
	int			bk_sink; 
	int			bk_alloc; 
	int			bk_niov; 
	struct bio_vec		bk_iovs[];
};


struct srpc_buffer {
	struct list_head	buf_list; 
	struct srpc_msg		buf_msg;
	struct lnet_handle_md	buf_mdh;
	lnet_nid_t		buf_self;
	struct lnet_process_id	buf_peer;
};

struct swi_workitem;
typedef void (*swi_action_t)(struct swi_workitem *);

struct swi_workitem {
	struct workqueue_struct	*swi_wq;
	struct work_struct	swi_work;
	swi_action_t		swi_action;
	enum lsr_swi_state	swi_state;
};


struct srpc_server_rpc {
	
	struct list_head	srpc_list;
	struct srpc_service_cd *srpc_scd;
	struct swi_workitem	srpc_wi;
	struct srpc_event	srpc_ev;	
	lnet_nid_t		srpc_self;
	struct lnet_process_id	srpc_peer;
	struct srpc_msg		srpc_replymsg;
	struct lnet_handle_md	srpc_replymdh;
	struct srpc_buffer     *srpc_reqstbuf;
	struct srpc_bulk       *srpc_bulk;

	unsigned int	srpc_aborted; 
	int		srpc_status;
	void		(*srpc_done)(struct srpc_server_rpc *);
};


struct srpc_client_rpc {
	struct list_head	crpc_list;	
	spinlock_t		crpc_lock;	
	int			crpc_service;
	struct kref		crpc_refcount;
	
	int			crpc_timeout;
	struct stt_timer	crpc_timer;
	struct swi_workitem	crpc_wi;
	struct lnet_process_id	crpc_dest;

	void               (*crpc_done)(struct srpc_client_rpc *);
	void               (*crpc_fini)(struct srpc_client_rpc *);
	int                  crpc_status;    
	void                *crpc_priv;      

	
	unsigned int         crpc_aborted:1; 
	unsigned int         crpc_closed:1;  

	
	struct srpc_event	crpc_bulkev;	
	struct srpc_event	crpc_reqstev;	
	struct srpc_event	crpc_replyev;	

	
	struct srpc_msg		crpc_reqstmsg;
	struct srpc_msg		crpc_replymsg;
	struct lnet_handle_md	crpc_reqstmdh;
	struct lnet_handle_md	crpc_replymdh;
	struct srpc_bulk	crpc_bulk;
};

#define srpc_client_rpc_size(rpc)                                       \
offsetof(struct srpc_client_rpc, crpc_bulk.bk_iovs[(rpc)->crpc_bulk.bk_niov])

#define srpc_client_rpc_addref(rpc)                                     \
do {                                                                    \
	CDEBUG(D_NET, "RPC[%p] -> %s (%d)++\n",                         \
	       (rpc), libcfs_id2str((rpc)->crpc_dest),                  \
	       kref_read(&(rpc)->crpc_refcount));                       \
	kref_get(&(rpc)->crpc_refcount);                                \
} while (0)

#define srpc_client_rpc_decref(rpc)                                     \
do {                                                                    \
	CDEBUG(D_NET, "RPC[%p] -> %s (%d)--\n",                         \
	       (rpc), libcfs_id2str((rpc)->crpc_dest),                  \
	       kref_read(&(rpc)->crpc_refcount));                       \
	kref_put(&(rpc)->crpc_refcount, srpc_destroy_client_rpc);       \
} while (0)

#define srpc_event_pending(rpc)   ((rpc)->crpc_bulkev.ev_fired == 0 ||  \
				   (rpc)->crpc_reqstev.ev_fired == 0 || \
				   (rpc)->crpc_replyev.ev_fired == 0)


struct srpc_service_cd {
	
	spinlock_t		scd_lock;
	
	struct srpc_service	*scd_svc;
	
	struct srpc_event	scd_ev;
	
	struct list_head	scd_rpc_free;
	
	struct list_head	scd_rpc_active;
	
	struct swi_workitem	scd_buf_wi;
	
	int			scd_cpt;
	
	int			scd_buf_err;
	
	time64_t		scd_buf_err_stamp;
	
	int			scd_buf_total;
	
	int			scd_buf_nposted;
	
	int			scd_buf_posting;
	
	int			scd_buf_low;
	
	int			scd_buf_adjust;
	
	struct list_head	scd_buf_posted;
	
	struct list_head	scd_buf_blocked;
};


#define SFW_TEST_WI_MIN		256
#define SFW_TEST_WI_MAX		2048
/* extra buffers for tolerating buggy peers, or unbalanced number
 * of peers between partitions  */
#define SFW_TEST_WI_EXTRA	64


#define SFW_FRWK_WI_MIN		16
#define SFW_FRWK_WI_MAX		256

struct srpc_service {
	enum srpc_service_type	sv_id;		
	const char		*sv_name;	
	int			sv_wi_total;	
	int			sv_shuttingdown;
	int			sv_ncpts;
	
	struct srpc_service_cd	**sv_cpt_data;
	/* Service callbacks:
	 * - sv_handler: process incoming RPC request
	 * - sv_bulk_ready: notify bulk data
	 */
	int              (*sv_handler)(struct srpc_server_rpc *);
	int              (*sv_bulk_ready)(struct srpc_server_rpc *, int);

	/** Service side srpc constructor/destructor.
	 *  used for the bulk preallocation as usual.
	 */
	int              (*sv_srpc_init)(struct srpc_server_rpc *, int);
	void             (*sv_srpc_fini)(struct srpc_server_rpc *);
};

struct lst_session_id {
	s64			ses_stamp;	
	struct lnet_nid		ses_nid;	
};						

extern struct lst_session_id LST_INVALID_SID;

struct sfw_session {
	
	struct list_head	sn_list;
	struct lst_session_id	sn_id;		
	
	unsigned int		sn_timeout;
	int			sn_timer_active;
	unsigned int		sn_features;
	struct stt_timer	sn_timer;
	struct list_head	sn_batches;	
	char			sn_name[LST_NAME_SIZE];
	refcount_t		sn_refcount;
	atomic_t		sn_brw_errors;
	atomic_t		sn_ping_errors;
	ktime_t			sn_started;
};

static inline int sfw_sid_equal(struct lst_sid sid0,
				struct lst_session_id sid1)
{
	struct lnet_nid ses_nid;

	lnet_nid4_to_nid(sid0.ses_nid, &ses_nid);

	return ((sid0.ses_stamp == sid1.ses_stamp) &&
		nid_same(&ses_nid, &sid1.ses_nid));
}

struct sfw_batch {
	struct list_head	bat_list;	
	struct lst_bid		bat_id;		
	int			bat_error;	
	struct sfw_session	*bat_session;	
	atomic_t		bat_nactive;	
	struct list_head	bat_tests;	
};

struct sfw_test_client_ops {
	int  (*tso_init)(struct sfw_test_instance *tsi); 
	void (*tso_fini)(struct sfw_test_instance *tsi); 
	int  (*tso_prep_rpc)(struct sfw_test_unit *tsu,
			     struct lnet_process_id dest,
			     struct srpc_client_rpc **rpc); 
	void (*tso_done_rpc)(struct sfw_test_unit *tsu,
			     struct srpc_client_rpc *rpc);  
};

struct sfw_test_instance {
	struct list_head	tsi_list; 
	int			tsi_service; 
	struct sfw_batch	*tsi_batch; 
	struct sfw_test_client_ops	*tsi_ops; 

	
	unsigned int		tsi_is_client:1;     
	unsigned int		tsi_stoptsu_onerr:1; 
	int                     tsi_concur;          
	int                     tsi_loop;            

	
	spinlock_t		tsi_lock;	
	unsigned int		tsi_stopping:1;	
	atomic_t		tsi_nactive;	
	struct list_head	tsi_units;	
	struct list_head	tsi_free_rpcs;	
	struct list_head	tsi_active_rpcs;

	union {
		struct test_ping_req	ping;	  
		struct test_bulk_req	bulk_v0;  
		struct test_bulk_req_v1	bulk_v1;  
	} tsi_u;
};

/* XXX: trailing (PAGE_SIZE % sizeof(struct lnet_process_id)) bytes at
 * the end of pages are not used */
#define SFW_MAX_CONCUR     LST_MAX_CONCUR
#define SFW_ID_PER_PAGE    (PAGE_SIZE / sizeof(struct lnet_process_id_packed))
#define SFW_MAX_NDESTS     (LNET_MAX_IOV * SFW_ID_PER_PAGE)
#define sfw_id_pages(n)    (((n) + SFW_ID_PER_PAGE - 1) / SFW_ID_PER_PAGE)

struct sfw_test_unit {
	struct list_head	tsu_list;	
	struct lnet_process_id	tsu_dest;	
	int			tsu_loop;	
	struct sfw_test_instance *tsu_instance;	
	void			*tsu_private;	
	struct swi_workitem	 tsu_worker;	
};

struct sfw_test_case {
	struct list_head		tsc_list; 
	struct srpc_service		*tsc_srv_service; 
	struct sfw_test_client_ops	*tsc_cli_ops; 
};

struct srpc_client_rpc *
sfw_create_rpc(struct lnet_process_id peer, int service,
	       unsigned int features, int nbulkiov, int bulklen,
	       void (*done)(struct srpc_client_rpc *), void *priv);
int sfw_create_test_rpc(struct sfw_test_unit *tsu,
			struct lnet_process_id peer, unsigned int features,
			int nblk, int blklen, struct srpc_client_rpc **rpc);
void sfw_abort_rpc(struct srpc_client_rpc *rpc);
void sfw_post_rpc(struct srpc_client_rpc *rpc);
void sfw_client_rpc_done(struct srpc_client_rpc *rpc);
void sfw_unpack_message(struct srpc_msg *msg);
void sfw_add_bulk_page(struct srpc_bulk *bk, struct page *pg, int i);
int sfw_alloc_pages(struct srpc_server_rpc *rpc, int cpt, int len,
		    int sink);
int sfw_make_session(struct srpc_mksn_reqst *request,
		     struct srpc_mksn_reply *reply);

struct srpc_client_rpc *
srpc_create_client_rpc(struct lnet_process_id peer, int service,
		       int nbulkiov, int bulklen,
		       void (*rpc_done)(struct srpc_client_rpc *),
		       void (*rpc_fini)(struct srpc_client_rpc *), void *priv);
void srpc_post_rpc(struct srpc_client_rpc *rpc);
void srpc_abort_rpc(struct srpc_client_rpc *rpc, int why);
void srpc_free_bulk(struct srpc_bulk *bk);

struct srpc_bulk *srpc_alloc_bulk(int cpt, unsigned int bulk_len);
void srpc_init_bulk(struct srpc_bulk *bk, unsigned int off,
		    unsigned int bulk_len, int sink);

void srpc_send_rpc(struct swi_workitem *wi);
int srpc_send_reply(struct srpc_server_rpc *rpc);
int srpc_add_service(struct srpc_service *sv);
int srpc_remove_service(struct srpc_service *sv);
void srpc_shutdown_service(struct srpc_service *sv);
void srpc_abort_service(struct srpc_service *sv);
int srpc_finish_service(struct srpc_service *sv);
int srpc_service_add_buffers(struct srpc_service *sv, int nbuffer);
void srpc_service_remove_buffers(struct srpc_service *sv, int nbuffer);
void srpc_get_counters(struct srpc_counters *cnt);

extern struct workqueue_struct *lst_serial_wq;
extern struct workqueue_struct **lst_test_wq;

static inline int
srpc_serv_is_framework(struct srpc_service *svc)
{
	return svc->sv_id < SRPC_FRAMEWORK_SERVICE_MAX_ID;
}

static void
swi_wi_action(struct work_struct *wi)
{
	struct swi_workitem *swi;

	swi = container_of(wi, struct swi_workitem, swi_work);
	swi->swi_action(swi);
}

static inline void
swi_init_workitem(struct swi_workitem *swi,
		  swi_action_t action, struct workqueue_struct *wq)
{
	swi->swi_wq = wq;
	swi->swi_action = action;
	swi->swi_state  = SWI_STATE_NEWBORN;
	INIT_WORK(&swi->swi_work, swi_wi_action);
}

static inline void
swi_schedule_workitem(struct swi_workitem *wi)
{
	queue_work(wi->swi_wq, &wi->swi_work);
}

static inline int
swi_cancel_workitem(struct swi_workitem *swi)
{
	swi->swi_state = SWI_STATE_DONE;
	return cancel_work_sync(&swi->swi_work);
}

int sfw_startup(void);
int srpc_startup(void);
void sfw_shutdown(void);
void srpc_shutdown(void);

static inline void
srpc_destroy_client_rpc(struct kref *kref)
{
	struct srpc_client_rpc *rpc = container_of(kref, struct srpc_client_rpc,
						   crpc_refcount);

	LASSERT(rpc != NULL);
	LASSERT(!srpc_event_pending(rpc));

	if (rpc->crpc_fini == NULL)
		LIBCFS_FREE(rpc, srpc_client_rpc_size(rpc));
	else
		(*rpc->crpc_fini) (rpc);
}

static inline void
srpc_init_client_rpc(struct srpc_client_rpc *rpc, struct lnet_process_id peer,
		     int service, int nbulkiov, int bulklen,
		     void (*rpc_done)(struct srpc_client_rpc *),
		     void (*rpc_fini)(struct srpc_client_rpc *), void *priv)
{
	LASSERT(nbulkiov <= LNET_MAX_IOV);

	memset(rpc, 0, offsetof(struct srpc_client_rpc,
				crpc_bulk.bk_iovs[nbulkiov]));

	INIT_LIST_HEAD(&rpc->crpc_list);
	swi_init_workitem(&rpc->crpc_wi, srpc_send_rpc,
			  lst_test_wq[lnet_cpt_of_nid(peer.nid, NULL)]);
	spin_lock_init(&rpc->crpc_lock);
	kref_init(&rpc->crpc_refcount); 

	rpc->crpc_dest         = peer;
	rpc->crpc_priv         = priv;
	rpc->crpc_service      = service;
	rpc->crpc_bulk.bk_len  = bulklen;
	rpc->crpc_bulk.bk_niov = nbulkiov;
	rpc->crpc_done         = rpc_done;
	rpc->crpc_fini         = rpc_fini;
	LNetInvalidateMDHandle(&rpc->crpc_reqstmdh);
	LNetInvalidateMDHandle(&rpc->crpc_replymdh);
	LNetInvalidateMDHandle(&rpc->crpc_bulk.bk_mdh);

	
	rpc->crpc_bulkev.ev_fired  =
	rpc->crpc_reqstev.ev_fired =
	rpc->crpc_replyev.ev_fired = 1;

	rpc->crpc_reqstmsg.msg_magic   = SRPC_MSG_MAGIC;
	rpc->crpc_reqstmsg.msg_version = SRPC_MSG_VERSION;
	rpc->crpc_reqstmsg.msg_type    = srpc_service2request(service);
}

static inline const char *
swi_state2str(int state)
{
	switch (state) {
	ENUM2STR(SWI_STATE_NEWBORN);
	ENUM2STR(SWI_STATE_REPLY_SUBMITTED);
	ENUM2STR(SWI_STATE_REPLY_SENT);
	ENUM2STR(SWI_STATE_REQUEST_SUBMITTED);
	ENUM2STR(SWI_STATE_REQUEST_SENT);
	ENUM2STR(SWI_STATE_REPLY_RECEIVED);
	ENUM2STR(SWI_STATE_BULK_STARTED);
	ENUM2STR(SWI_STATE_DONE);
	default:
		LASSERTF(0, "state bad %u\n", state);
		return NULL;
	}
}

#define lst_wait_until(cond, lock, fmt, ...)				\
do {									\
	int __I = 2;							\
	while (!(cond)) {						\
		CDEBUG(is_power_of_2(++__I) ? D_WARNING : D_NET,	\
		       fmt, ## __VA_ARGS__);				\
		spin_unlock(&(lock));					\
									\
		schedule_timeout_uninterruptible(			\
			cfs_time_seconds(1) / 10);			\
									\
		spin_lock(&(lock));					\
	}								\
} while (0)

static inline void
srpc_wait_service_shutdown(struct srpc_service *sv)
{
	int i = 2;

	LASSERT(sv->sv_shuttingdown);

	while (srpc_finish_service(sv) == 0) {
		i++;
		CDEBUG(((i & -i) == i) ? D_WARNING : D_NET,
		       "Waiting for %s service to shutdown...\n",
		       sv->sv_name);
		schedule_timeout_uninterruptible(cfs_time_seconds(1) / 10);
	}
}

extern struct sfw_test_client_ops ping_test_client;
extern struct srpc_service ping_test_service;
void ping_init_test_client(void);
void ping_init_test_service(void);

extern struct sfw_test_client_ops brw_test_client;
extern struct srpc_service brw_test_service;
void brw_init_test_service(void);

#endif 
