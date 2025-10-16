

/* Copyright (c) 2007, 2010, Oracle and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 *
 * Copyright (c) 2011, 2017, Intel Corporation.
 */

/* This file is part of Lustre, http:
 *
 * Author: Eric Barton <eric@bartonsoftware.com>
 */

#include <linux/module.h>
#include <linux/kernel.h>

#if defined(EXTERNAL_OFED_BUILD) && !defined(HAVE_OFED_IB_DMA_MAP_SG_SANE)
#undef CONFIG_INFINIBAND_VIRT_DMA
#endif

#if defined(NEED_LOCKDEP_IS_HELD_DISCARD_CONST) \
 && defined(CONFIG_LOCKDEP) \
 && defined(lockdep_is_held)
#undef lockdep_is_held
	#define lockdep_is_held(lock) \
		lock_is_held((struct lockdep_map *)&(lock)->dep_map)
#endif

#ifdef HAVE_OFED_COMPAT_RDMA
#include <linux/compat-2.6.h>

#ifdef LINUX_3_17_COMPAT_H
#undef NEED_KTIME_GET_REAL_NS
#endif

#define HAVE_NLA_PUT_U64_64BIT 1
#define HAVE_NLA_PARSE_6_PARAMS 1
#define HAVE_NETLINK_EXTACK 1


#define HAVE_BITMAP_ALLOC 1

#endif

#include <linux/kthread.h>
#include <linux/mm.h>
#include <linux/string.h>
#include <linux/stat.h>
#include <linux/errno.h>
#include <linux/unistd.h>
#include <linux/uio.h>

#include <asm/uaccess.h>
#include <asm/io.h>

#include <linux/init.h>
#include <linux/fs.h>
#include <linux/file.h>
#include <linux/stat.h>
#include <linux/list.h>
#include <linux/kmod.h>
#include <linux/sysctl.h>
#include <linux/pci.h>

#include <net/sock.h>
#include <linux/in.h>

#include <rdma/rdma_cm.h>
#include <rdma/ib_cm.h>
#include <rdma/ib_verbs.h>
#ifdef HAVE_OFED_FMR_POOL_API
#include <rdma/ib_fmr_pool.h>
#endif

#define DEBUG_SUBSYSTEM S_LND

#include <linux/libcfs/libcfs.h>
#include <lustre_compat/net/linux-net.h>

#include <lnet/lib-lnet.h>
#include <lnet/lnet_rdma.h>
#include "o2iblnd-idl.h"

enum kiblnd_ni_lnd_tunables_attr {
	LNET_NET_O2IBLND_TUNABLES_ATTR_UNSPEC = 0,

	LNET_NET_O2IBLND_TUNABLES_ATTR_HIW_PEER_CREDITS,
	LNET_NET_O2IBLND_TUNABLES_ATTR_CONCURRENT_SENDS,
	LNET_NET_O2IBLND_TUNABLES_ATTR_MAP_ON_DEMAND,
	LNET_NET_O2IBLND_TUNABLES_ATTR_FMR_POOL_SIZE,
	LNET_NET_O2IBLND_TUNABLES_ATTR_FMR_FLUSH_TRIGGER,
	LNET_NET_O2IBLND_TUNABLES_ATTR_FMR_CACHE,
	LNET_NET_O2IBLND_TUNABLES_ATTR_NTX,
	LNET_NET_O2IBLND_TUNABLES_ATTR_CONNS_PER_PEER,
	LNET_NET_O2IBLND_TUNABLES_ATTR_LND_TIMEOUT,
	LNET_NET_O2IBLND_TUNABLES_ATTR_LND_TOS,
	__LNET_NET_O2IBLND_TUNABLES_ATTR_MAX_PLUS_ONE,
};

#define LNET_NET_O2IBLND_TUNABLES_ATTR_MAX (__LNET_NET_O2IBLND_TUNABLES_ATTR_MAX_PLUS_ONE - 1)

#define IBLND_PEER_HASH_BITS		7	
#define IBLND_N_SCHED			2
#define IBLND_N_SCHED_HIGH		4

struct kib_tunables {
	int              *kib_dev_failover;     
	unsigned int     *kib_service;          
	int              *kib_cksum;            
	int              *kib_timeout;          
	int              *kib_keepalive;        
	char            **kib_default_ipif;     
	int              *kib_retry_count;
	int              *kib_rnr_retry_count;
	int		 *kib_ib_mtu;		
	int              *kib_require_priv_port;
	int              *kib_use_priv_port;    
	
	int		 *kib_nscheds;
	int		 *kib_wrq_sge;		
	int		 *kib_use_fastreg_gaps; 
};

extern struct kib_tunables  kiblnd_tunables;
extern struct lnet_ioctl_config_o2iblnd_tunables kib_default_tunables;

#define IBLND_MSG_QUEUE_SIZE_V1      8          
#define IBLND_CREDIT_HIGHWATER_V1    7          

#define IBLND_CREDITS_DEFAULT        8          
#define IBLND_CREDITS_MAX          ((typeof(((struct kib_msg *) 0)->ibm_credits)) - 1)  

#define IBLND_TIMEOUT_DEFAULT	50	

#ifdef HAVE_OFED_RDMA_CREATE_ID_5ARG
# define kiblnd_rdma_create_id(ns, cb, dev, ps, qpt) \
	 rdma_create_id((ns) ? (ns) : &init_net, cb, dev, ps, qpt)
#else
# ifdef HAVE_OFED_RDMA_CREATE_ID_4ARG
#  define kiblnd_rdma_create_id(ns, cb, dev, ps, qpt) \
	  rdma_create_id(cb, dev, ps, qpt)
# else
#  define kiblnd_rdma_create_id(ns, cb, dev, ps, qpt) \
	  rdma_create_id(cb, dev, ps)
# endif
#endif


#define IBLND_OOB_CAPABLE(v)       ((v) != IBLND_MSG_VERSION_1)
#define IBLND_OOB_MSGS(v)           (IBLND_OOB_CAPABLE(v) ? 2 : 0)


#define IBLND_MSG_SIZE              (4<<10)

#define IBLND_MAX_RDMA_FRAGS        (LNET_MAX_IOV + 1)





#define IBLND_TX_POOL			256
#define IBLND_FMR_POOL			256
#define IBLND_FMR_POOL_FLUSH		192


#define IBLND_RX_MSGS(c)	\
	((c->ibc_queue_depth) * 2 + IBLND_OOB_MSGS(c->ibc_version))
#define IBLND_RX_MSG_BYTES(c)       (IBLND_RX_MSGS(c) * IBLND_MSG_SIZE)
#define IBLND_RX_MSG_PAGES(c)	\
	((IBLND_RX_MSG_BYTES(c) + PAGE_SIZE - 1) / PAGE_SIZE)


#define IBLND_RECV_WRS(c)            IBLND_RX_MSGS(c)


#define IBLND_CQ_ENTRIES(c) (IBLND_RECV_WRS(c) + kiblnd_send_wrs(c))

struct kib_hca_dev;


#ifdef IFALIASZ
#define KIB_IFNAME_SIZE              IFALIASZ
#else
#define KIB_IFNAME_SIZE              256
#endif

enum kib_dev_caps {
	IBLND_DEV_CAPS_FASTREG_ENABLED		= BIT(0),
	IBLND_DEV_CAPS_FASTREG_GAPS_SUPPORT	= BIT(1),
#ifdef HAVE_OFED_FMR_POOL_API
	IBLND_DEV_CAPS_FMR_ENABLED		= BIT(2),
#endif
};

#define IS_FAST_REG_DEV(dev) \
	((dev)->ibd_dev_caps & IBLND_DEV_CAPS_FASTREG_ENABLED)


struct kib_dev {
	struct list_head	ibd_list;	
	struct list_head	ibd_fail_list;	
	struct sockaddr_storage	ibd_addr;	
	
	char			ibd_ifname[KIB_IFNAME_SIZE];
	int			ibd_nnets;	

	time64_t		ibd_next_failover;
	
	int			ibd_failed_failover;
	
	unsigned int		ibd_failover;
	
	unsigned int		ibd_can_failover;
	struct list_head	ibd_nets;
	struct kib_hca_dev	*ibd_hdev;
	enum kib_dev_caps	ibd_dev_caps;
};

struct kib_hca_dev {
	struct rdma_cm_id   *ibh_cmid;          
	struct ib_device    *ibh_ibdev;         
	int                  ibh_page_shift;    
	int                  ibh_page_size;     
	__u64                ibh_page_mask;     
	__u64                ibh_mr_size;       
	int		     ibh_max_qp_wr;     
	struct ib_pd        *ibh_pd;            
	u8                   ibh_port;          
	struct ib_event_handler
			     ibh_event_handler; 
	int                  ibh_state;         
#define IBLND_DEV_PORT_DOWN     0
#define IBLND_DEV_PORT_ACTIVE   1
#define IBLND_DEV_FATAL         2
	struct kib_dev           *ibh_dev;           
	atomic_t             ibh_ref;           
};


#define IBLND_POOL_DEADLINE     300

#define IBLND_POOL_RETRY        1

struct kib_pages {
	int                     ibp_npages;             
	struct page            *ibp_pages[];            
};

struct kib_pool;
struct kib_poolset;

typedef int  (*kib_ps_pool_create_t)(struct kib_poolset *ps,
				     int inc, struct kib_pool **pp_po);
typedef void (*kib_ps_pool_destroy_t)(struct kib_pool *po);
typedef void (*kib_ps_node_init_t)(struct kib_pool *po, struct list_head *node);
typedef void (*kib_ps_node_fini_t)(struct kib_pool *po, struct list_head *node);

struct kib_net;

#define IBLND_POOL_NAME_LEN     32

struct kib_poolset {
	
	spinlock_t		ps_lock;
	
	struct kib_net		*ps_net;
	
	char			ps_name[IBLND_POOL_NAME_LEN];
	
	struct list_head	ps_pool_list;
	
	struct list_head	ps_failed_pool_list;
	
	time64_t		ps_next_retry;
	
	int			ps_increasing;
	
	int			ps_pool_size;
	
	int			ps_cpt;

	
	kib_ps_pool_create_t	ps_pool_create;
	
	kib_ps_pool_destroy_t	ps_pool_destroy;
	
	kib_ps_node_init_t	ps_node_init;
	
	kib_ps_node_fini_t	ps_node_fini;
};

struct kib_pool {
	
	struct list_head	po_list;
	
	struct list_head	po_free_list;
	
	struct kib_poolset     *po_owner;
	
	time64_t		po_deadline;
	
	int			po_allocated;
	
	int			po_failed;
	
	int			po_size;
};

struct kib_tx_poolset {
	struct kib_poolset	tps_poolset;		
        __u64                   tps_next_tx_cookie;     
};

struct kib_tx_pool {
	struct kib_pool		tpo_pool;		
        struct kib_hca_dev     *tpo_hdev;               
        struct kib_tx          *tpo_tx_descs;           
	struct kib_pages       *tpo_tx_pages;           
};

struct kib_fmr_poolset {
	spinlock_t		fps_lock;		
	struct kib_net	       *fps_net;		
	struct list_head	fps_pool_list;		
	struct list_head	fps_failed_pool_list;	
	__u64			fps_version;		
	int			fps_cpt;		
	int			fps_pool_size;
	int			fps_flush_trigger;
	int			fps_cache;
	
	int			fps_increasing;
	
	time64_t		fps_next_retry;
};

#ifndef HAVE_OFED_IB_RDMA_WR
struct ib_rdma_wr {
	struct ib_send_wr wr;
};
#endif

struct kib_fast_reg_descriptor { 
	struct list_head		 frd_list;
	struct ib_rdma_wr		 frd_inv_wr;
#ifdef HAVE_OFED_IB_MAP_MR_SG
	struct ib_reg_wr		 frd_fastreg_wr;
#else
	struct ib_rdma_wr		 frd_fastreg_wr;
	struct ib_fast_reg_page_list    *frd_frpl;
#endif
	struct ib_mr			*frd_mr;
	bool				 frd_valid;
	bool				 frd_posted;
};

struct kib_fmr_pool {
	struct list_head	fpo_list;	
	struct kib_hca_dev     *fpo_hdev;	
	struct kib_fmr_poolset      *fpo_owner;	
#ifdef HAVE_OFED_FMR_POOL_API
	union {
		struct {
			struct ib_fmr_pool *fpo_fmr_pool; 
		} fmr;
#endif
		struct { 
			struct list_head  fpo_pool_list;
			int		  fpo_pool_size;
		} fast_reg;
#ifdef HAVE_OFED_FMR_POOL_API
	};
	bool			fpo_is_fmr; 
#endif
	time64_t		fpo_deadline;	
	int			fpo_failed;	
	int			fpo_map_count;	
};

struct kib_fmr {
	struct kib_fmr_pool		*fmr_pool;	
#ifdef HAVE_OFED_FMR_POOL_API
	struct ib_pool_fmr		*fmr_pfmr;	
#endif 
	struct kib_fast_reg_descriptor	*fmr_frd;
	u32				 fmr_key;
};

#ifdef HAVE_OFED_FMR_POOL_API

#ifdef HAVE_ORACLE_OFED_EXTENSIONS
#define kib_fmr_pool_map(pool, pgs, n, iov) \
	ib_fmr_pool_map_phys((pool), (pgs), (n), (iov), NULL)
#else
#define kib_fmr_pool_map(pool, pgs, n, iov) \
	ib_fmr_pool_map_phys((pool), (pgs), (n), (iov))
#endif

#endif 

struct kib_net {
	
	struct list_head	ibn_list;
	__u64			ibn_incarnation;
	int			ibn_init;	
	int			ibn_shutdown;	

	atomic_t		ibn_npeers;	
	atomic_t		ibn_nconns;	

	struct kib_tx_poolset	**ibn_tx_ps;	
	struct kib_fmr_poolset	**ibn_fmr_ps;	

	struct kib_dev		*ibn_dev;	
	struct lnet_ni          *ibn_ni;        
};

#define KIB_THREAD_SHIFT		16
#define KIB_THREAD_ID(cpt, tid)		((cpt) << KIB_THREAD_SHIFT | (tid))
#define KIB_THREAD_CPT(id)		((id) >> KIB_THREAD_SHIFT)
#define KIB_THREAD_TID(id)		((id) & ((1UL << KIB_THREAD_SHIFT) - 1))

struct kib_sched_info {
	
	spinlock_t		ibs_lock;
	
	wait_queue_head_t	ibs_waitq;
	
	struct list_head	ibs_conns;
	
	int			ibs_nthreads;
	
	int			ibs_nthreads_max;
	int			ibs_cpt;	
};

struct kib_data {
	int			kib_init;	
	int			kib_shutdown;	
	struct list_head	kib_devs;	
	
	struct list_head	kib_failed_devs;
	
	wait_queue_head_t	kib_failover_waitq;
	atomic_t		kib_nthreads;	
	
	rwlock_t		kib_global_lock;
	
	DECLARE_HASHTABLE(kib_peers, IBLND_PEER_HASH_BITS);
	
	void			*kib_connd;
	
	struct list_head	kib_connd_conns;
	
	struct list_head	kib_connd_zombies;
	
	struct list_head	kib_reconn_list;
	
	struct list_head	kib_reconn_wait;
	/*
	 * The second that peers are pulled out from \a kib_reconn_wait
	 * for reconnection.
	 */
	time64_t		kib_reconn_sec;
	
	wait_queue_head_t	kib_connd_waitq;
	spinlock_t		kib_connd_lock;	
	struct ib_qp_attr	kib_error_qpa;	
	
	struct kib_sched_info	**kib_scheds;
};

#define IBLND_INIT_NOTHING         0
#define IBLND_INIT_DATA            1
#define IBLND_INIT_ALL             2

struct kib_rx {					
	
	struct list_head	rx_list;
	
	struct kib_conn	       *rx_conn;
	
	int			rx_nob;
	
	struct kib_msg	       *rx_msg;
	
	__u64			rx_msgaddr;
	
	DEFINE_DMA_UNMAP_ADDR(rx_msgunmap);
};

#define IBLND_POSTRX_DONT_POST    0             
#define IBLND_POSTRX_NO_CREDIT    1             
#define IBLND_POSTRX_PEER_CREDIT  2             
#define IBLND_POSTRX_RSRVD_CREDIT 3             

struct kib_tx {					
	
	struct list_head	tx_list;
	
	struct kib_tx_pool	*tx_pool;
	
	struct kib_conn		*tx_conn;
	
	short			tx_sending;
	
	unsigned long		tx_queued:1,
	
				tx_waiting:1,
	
				tx_gpu:1;
	
	int			tx_status;
	
	enum lnet_msg_hstatus	tx_hstatus;
	
	ktime_t			tx_deadline;
	
	__u64			tx_cookie;
	
	struct lnet_msg		*tx_lntmsg[2];
	
	struct kib_msg		*tx_msg;
	
	__u64			tx_msgaddr;
	
	DEFINE_DMA_UNMAP_ADDR(tx_msgunmap);
	
	int			tx_nwrq;
	
	int			tx_nsge;
	
	struct ib_rdma_wr	*tx_wrq;
	
	struct ib_sge		*tx_sge;
	
	struct kib_rdma_desc	*tx_rd;
	
	int			tx_nfrags;
	
	struct scatterlist	*tx_frags;
	
	__u64			*tx_pages;
	
	bool			tx_gaps;
	
	struct kib_fmr		tx_fmr;
				
	int			tx_dmadir;
};

struct kib_connvars {
        
	struct kib_msg		cv_msg;
};

struct kib_conn {
	
	struct kib_sched_info	*ibc_sched;
	
	struct kib_peer_ni	*ibc_peer;
	
	struct kib_hca_dev	*ibc_hdev;
	
	struct list_head	ibc_list;
	
	struct list_head	ibc_sched_list;
	
	__u16			ibc_version;
	
	__u16			ibc_reconnect:1;
	
	__u64			ibc_incarnation;
	
	atomic_t		ibc_refcount;
	
	int			ibc_state;
	
	int			ibc_nsends_posted;
	
	int			ibc_noops_posted;
	
	int			ibc_credits;
	
	int			ibc_outstanding_credits;
	
	int			ibc_reserved_credits;
	
	int			ibc_comms_error;
	
	__u16			ibc_queue_depth;
	
	__u16			ibc_max_frags;
	
	unsigned int		ibc_nrx:16;
	
	unsigned int		ibc_scheduled:1;
	
	unsigned int		ibc_ready:1;
	
	ktime_t			ibc_last_send;
	
	struct list_head	ibc_connd_list;
	
	struct list_head	ibc_early_rxs;
	
	struct list_head	ibc_tx_noops;
	
	struct list_head	ibc_tx_queue;
	
	struct list_head	ibc_tx_queue_nocred;
	
	struct list_head	ibc_tx_queue_rsrvd;
	
	struct list_head	ibc_active_txs;
	
	struct list_head	ibc_zombie_txs;
	
	spinlock_t		ibc_lock;
	
	struct kib_rx		*ibc_rxs;
	
	struct kib_pages	*ibc_rx_pages;

	
	struct rdma_cm_id	*ibc_cmid;
	
	struct ib_cq		*ibc_cq;

	
	struct kib_connvars	*ibc_connvars;
};

#define IBLND_CONN_INIT               0         
#define IBLND_CONN_ACTIVE_CONNECT     1         
#define IBLND_CONN_PASSIVE_WAIT       2         
#define IBLND_CONN_ESTABLISHED        3         
#define IBLND_CONN_CLOSING            4         
#define IBLND_CONN_DISCONNECTED       5         

struct kib_peer_ni {
	
	struct hlist_node	ibp_list;
	
	struct lnet_nid		ibp_nid;
	
	struct lnet_ni		*ibp_ni;
	
	struct list_head	ibp_conns;
	
	struct list_head	ibp_connreqs;
	
	struct kib_conn		*ibp_next_conn;
	
	struct list_head	ibp_tx_queue;
	
	__u64			ibp_incarnation;
	
	time64_t		ibp_last_alive;
	
	struct kref		ibp_kref;
	
	__u16			ibp_version;
	
	unsigned short		ibp_accepting;
	
	unsigned short		ibp_connecting;
	
	unsigned char		ibp_reconnecting;
	
	unsigned char		ibp_races;
	
	unsigned int		ibp_reconnected;
	
	int			ibp_error;
	
	__u16			ibp_max_frags;
	
	__u16			ibp_queue_depth;
	
	__u16                   ibp_queue_depth_mod;
	
	atomic_t		ibp_nconns;
};

#ifndef HAVE_OFED_IB_INC_RKEY
/**
 * ib_inc_rkey - increments the key portion of the given rkey. Can be used
 * for calculating a new rkey for type 2 memory windows.
 * @rkey - the rkey to increment.
 */
static inline u32 ib_inc_rkey(u32 rkey)
{
	const u32 mask = 0x000000ff;
	return ((rkey + 1) & mask) | (rkey & ~mask);
}
#endif

extern struct kib_data kiblnd_data;

extern void kiblnd_hdev_destroy(struct kib_hca_dev *hdev);

int kiblnd_msg_queue_size(int version, struct lnet_ni *ni);

#define RDMA_RESOLVE_TIMEOUT	(5 * MSEC_PER_SEC)	

static inline int kiblnd_timeout(void)
{
	return *kiblnd_tunables.kib_timeout ?: lnet_get_lnd_timeout();
}


static inline int kiblnd_connreq_timeout_ms(void)
{
	return max(RDMA_RESOLVE_TIMEOUT, kiblnd_timeout() * MSEC_PER_SEC / 4);
}

static inline int
kiblnd_concurrent_sends(int version, struct lnet_ni *ni)
{
	struct lnet_ioctl_config_o2iblnd_tunables *tunables;
	int concurrent_sends;

	tunables = &ni->ni_lnd_tunables.lnd_tun_u.lnd_o2ib;
	concurrent_sends = tunables->lnd_concurrent_sends;

	if (version == IBLND_MSG_VERSION_1) {
		if (concurrent_sends > IBLND_MSG_QUEUE_SIZE_V1 * 2)
			return IBLND_MSG_QUEUE_SIZE_V1 * 2;

		if (concurrent_sends < IBLND_MSG_QUEUE_SIZE_V1 / 2)
			return IBLND_MSG_QUEUE_SIZE_V1 / 2;
	}

	return concurrent_sends;
}

static inline void
kiblnd_hdev_addref_locked(struct kib_hca_dev *hdev)
{
	LASSERT(atomic_read(&hdev->ibh_ref) > 0);
	atomic_inc(&hdev->ibh_ref);
}

static inline void
kiblnd_hdev_decref(struct kib_hca_dev *hdev)
{
	LASSERT(atomic_read(&hdev->ibh_ref) > 0);
	if (atomic_dec_and_test(&hdev->ibh_ref))
		kiblnd_hdev_destroy(hdev);
}

static inline int
kiblnd_dev_can_failover(struct kib_dev *dev)
{
	if (!list_empty(&dev->ibd_fail_list)) 
                return 0;

        if (*kiblnd_tunables.kib_dev_failover == 0) 
                return 0;

        if (*kiblnd_tunables.kib_dev_failover > 1) 
                return 1;

        return dev->ibd_can_failover;
}

static inline void kiblnd_conn_addref(struct kib_conn *conn)
{
#ifdef O2IBLND_CONN_REFCOUNT_DEBUG
	CDEBUG(D_NET, "conn[%p] (%d)++\n",
	       (conn), atomic_read(&(conn)->ibc_refcount));
#endif
	atomic_inc(&(conn)->ibc_refcount);
}

static inline void kiblnd_conn_decref(struct kib_conn *conn)
{
	unsigned long flags;
#ifdef O2IBLND_CONN_REFCOUNT_DEBUG
	CDEBUG(D_NET, "conn[%p] (%d)--\n",
	       (conn), atomic_read(&(conn)->ibc_refcount));
#endif
	LASSERT(atomic_read(&(conn)->ibc_refcount) > 0);
	if (atomic_dec_and_test(&(conn)->ibc_refcount)) {
		spin_lock_irqsave(&kiblnd_data.kib_connd_lock, flags);
		list_add_tail(&(conn)->ibc_list,
			      &kiblnd_data.kib_connd_zombies);
		wake_up(&kiblnd_data.kib_connd_waitq);
		spin_unlock_irqrestore(&kiblnd_data.kib_connd_lock, flags);
	}
}

void kiblnd_destroy_peer(struct kref *kref);

static inline void kiblnd_peer_addref(struct kib_peer_ni *peer_ni)
{
	CDEBUG(D_NET, "peer_ni[%p] -> %s (%d)++\n",
	       peer_ni, libcfs_nidstr(&peer_ni->ibp_nid),
	       kref_read(&peer_ni->ibp_kref));
	kref_get(&(peer_ni)->ibp_kref);
}

static inline void kiblnd_peer_decref(struct kib_peer_ni *peer_ni)
{
	CDEBUG(D_NET, "peer_ni[%p] -> %s (%d)--\n",
	       peer_ni, libcfs_nidstr(&peer_ni->ibp_nid),
	       kref_read(&peer_ni->ibp_kref));
	kref_put(&peer_ni->ibp_kref, kiblnd_destroy_peer);
}

static inline bool
kiblnd_peer_connecting(struct kib_peer_ni *peer_ni)
{
	return peer_ni->ibp_connecting != 0 ||
	       peer_ni->ibp_reconnecting != 0 ||
	       peer_ni->ibp_accepting != 0;
}

static inline bool
kiblnd_peer_idle(struct kib_peer_ni *peer_ni)
{
	return !kiblnd_peer_connecting(peer_ni) && list_empty(&peer_ni->ibp_conns);
}

static inline int
kiblnd_peer_active(struct kib_peer_ni *peer_ni)
{
	
	return !hlist_unhashed(&peer_ni->ibp_list);
}

static inline struct kib_conn *
kiblnd_get_conn_locked(struct kib_peer_ni *peer_ni)
{
	struct list_head *next;

	LASSERT(!list_empty(&peer_ni->ibp_conns));

	
	if (!peer_ni->ibp_next_conn ||
	    peer_ni->ibp_next_conn->ibc_list.next == &peer_ni->ibp_conns)
		next = peer_ni->ibp_conns.next;
	else
		next = peer_ni->ibp_next_conn->ibc_list.next;
	peer_ni->ibp_next_conn = list_entry(next, struct kib_conn, ibc_list);

	return peer_ni->ibp_next_conn;
}

static inline int
kiblnd_send_keepalive(struct kib_conn *conn)
{
	s64 keepalive_ns = *kiblnd_tunables.kib_keepalive * NSEC_PER_SEC;

	return (*kiblnd_tunables.kib_keepalive > 0) &&
		ktime_after(ktime_get(),
			    ktime_add_ns(conn->ibc_last_send, keepalive_ns));
}


static inline int
kiblnd_credits_highwater(struct lnet_ioctl_config_o2iblnd_tunables *t,
			 struct lnet_ioctl_config_lnd_cmn_tunables *nt,
			 struct kib_conn *conn)
{
	int credits_hiw = IBLND_CREDIT_HIGHWATER_V1;

	if ((conn->ibc_version) == IBLND_MSG_VERSION_1)
		return credits_hiw;

	
	credits_hiw = (conn->ibc_queue_depth * t->lnd_peercredits_hiw) /
		       nt->lct_peer_tx_credits;

	return credits_hiw;
}

static inline int
kiblnd_need_noop(struct kib_conn *conn)
{
	struct lnet_ni *ni = conn->ibc_peer->ibp_ni;
	struct lnet_ioctl_config_o2iblnd_tunables *tunables;
	struct lnet_ioctl_config_lnd_cmn_tunables *net_tunables;

	LASSERT(conn->ibc_state >= IBLND_CONN_ESTABLISHED);
	tunables = &ni->ni_lnd_tunables.lnd_tun_u.lnd_o2ib;
	net_tunables = &ni->ni_net->net_tunables;

        if (conn->ibc_outstanding_credits <
	    kiblnd_credits_highwater(tunables, net_tunables, conn) &&
            !kiblnd_send_keepalive(conn))
                return 0; 

        if (IBLND_OOB_CAPABLE(conn->ibc_version)) {
		if (!list_empty(&conn->ibc_tx_queue_nocred))
                        return 0; 

                
		return (list_empty(&conn->ibc_tx_queue) ||
                        conn->ibc_credits == 0);
        }

	if (!list_empty(&conn->ibc_tx_noops) || 
	    !list_empty(&conn->ibc_tx_queue_nocred) || 
            conn->ibc_credits == 0)                    
                return 0;

        if (conn->ibc_credits == 1 &&      
            conn->ibc_outstanding_credits == 0) 
                return 0;

        
	return (list_empty(&conn->ibc_tx_queue) || conn->ibc_credits == 1);
}

static inline void
kiblnd_abort_receives(struct kib_conn *conn)
{
        ib_modify_qp(conn->ibc_cmid->qp,
                     &kiblnd_data.kib_error_qpa, IB_QP_STATE);
}

static inline const char *
kiblnd_queue2str(struct kib_conn *conn, struct list_head *q)
{
	if (q == &conn->ibc_tx_queue)
		return "tx_queue";

	if (q == &conn->ibc_tx_queue_rsrvd)
		return "tx_queue_rsrvd";

	if (q == &conn->ibc_tx_queue_nocred)
		return "tx_queue_nocred";

	if (q == &conn->ibc_active_txs)
		return "active_txs";

	LBUG();
	return NULL;
}

/* CAVEAT EMPTOR: We rely on descriptor alignment to allow us to use the
 * lowest bits of the work request id to stash the work item type. */

#define IBLND_WID_INVAL	0
#define IBLND_WID_TX	1
#define IBLND_WID_RX	2
#define IBLND_WID_RDMA	3
#define IBLND_WID_MR	4
#define IBLND_WID_MASK	7UL

static inline __u64
kiblnd_ptr2wreqid (void *ptr, int type)
{
        unsigned long lptr = (unsigned long)ptr;

        LASSERT ((lptr & IBLND_WID_MASK) == 0);
        LASSERT ((type & ~IBLND_WID_MASK) == 0);
        return (__u64)(lptr | type);
}

static inline void *
kiblnd_wreqid2ptr (__u64 wreqid)
{
        return (void *)(((unsigned long)wreqid) & ~IBLND_WID_MASK);
}

static inline int
kiblnd_wreqid2type (__u64 wreqid)
{
        return (wreqid & IBLND_WID_MASK);
}

static inline void
kiblnd_set_conn_state(struct kib_conn *conn, int state)
{
	conn->ibc_state = state;
	smp_mb();
}

static inline void
kiblnd_init_msg(struct kib_msg *msg, int type, int body_nob)
{
        msg->ibm_type = type;
	msg->ibm_nob = offsetof(struct kib_msg, ibm_u) + body_nob;
}

static inline int
kiblnd_rd_size(struct kib_rdma_desc *rd)
{
        int   i;
        int   size;

        for (i = size = 0; i < rd->rd_nfrags; i++)
                size += rd->rd_frags[i].rf_nob;

        return size;
}

static inline __u64
kiblnd_rd_frag_addr(struct kib_rdma_desc *rd, int index)
{
        return rd->rd_frags[index].rf_addr;
}

static inline int
kiblnd_rd_frag_size(struct kib_rdma_desc *rd, int index)
{
        return rd->rd_frags[index].rf_nob;
}

static inline __u32
kiblnd_rd_frag_key(struct kib_rdma_desc *rd, int index)
{
        return rd->rd_key;
}

static inline int
kiblnd_rd_consume_frag(struct kib_rdma_desc *rd, int index, __u32 nob)
{
        if (nob < rd->rd_frags[index].rf_nob) {
                rd->rd_frags[index].rf_addr += nob;
                rd->rd_frags[index].rf_nob  -= nob;
        } else {
                index ++;
        }

        return index;
}

static inline int
kiblnd_rd_msg_size(struct kib_rdma_desc *rd, int msgtype, int n)
{
        return msgtype == IBLND_MSG_GET_REQ ?
	       offsetof(struct kib_get_msg, ibgm_rd.rd_frags[n]) :
	       offsetof(struct kib_putack_msg, ibpam_rd.rd_frags[n]);
}

static inline __u64
kiblnd_dma_mapping_error(struct ib_device *dev, u64 dma_addr)
{
        return ib_dma_mapping_error(dev, dma_addr);
}

static inline __u64 kiblnd_dma_map_single(struct ib_device *dev,
                                          void *msg, size_t size,
                                          enum dma_data_direction direction)
{
        return ib_dma_map_single(dev, msg, size, direction);
}

static inline void kiblnd_dma_unmap_single(struct ib_device *dev,
                                           __u64 addr, size_t size,
                                          enum dma_data_direction direction)
{
        ib_dma_unmap_single(dev, addr, size, direction);
}

#define KIBLND_UNMAP_ADDR_SET(p, m, a)  do {} while (0)
#define KIBLND_UNMAP_ADDR(p, m, a)      (a)

static inline
int kiblnd_dma_map_sg(struct kib_hca_dev *hdev, struct kib_tx *tx)
{
	struct scatterlist *sg = tx->tx_frags;
	int nents = tx->tx_nfrags;
	enum dma_data_direction direction = tx->tx_dmadir;

	if (tx->tx_gpu)
		return lnet_rdma_map_sg_attrs(hdev->ibh_ibdev->dma_device,
					      sg, nents, direction);

	return ib_dma_map_sg(hdev->ibh_ibdev, sg, nents, direction);
}

static inline
void kiblnd_dma_unmap_sg(struct kib_hca_dev *hdev, struct kib_tx *tx)
{
	struct scatterlist *sg = tx->tx_frags;
	int nents = tx->tx_nfrags;
	enum dma_data_direction direction = tx->tx_dmadir;

	if (tx->tx_gpu)
		lnet_rdma_unmap_sg(hdev->ibh_ibdev->dma_device,
					  sg, nents, direction);
	else
		ib_dma_unmap_sg(hdev->ibh_ibdev, sg, nents, direction);
}

#ifndef HAVE_OFED_IB_SG_DMA_ADDRESS
#include <linux/scatterlist.h>
#define ib_sg_dma_address(dev, sg)	sg_dma_address(sg)
#define ib_sg_dma_len(dev, sg)		sg_dma_len(sg)
#endif

static inline __u64 kiblnd_sg_dma_address(struct ib_device *dev,
                                          struct scatterlist *sg)
{
        return ib_sg_dma_address(dev, sg);
}

static inline unsigned int kiblnd_sg_dma_len(struct ib_device *dev,
                                             struct scatterlist *sg)
{
        return ib_sg_dma_len(dev, sg);
}

#ifndef HAVE_OFED_RDMA_CONNECT_LOCKED
#define rdma_connect_locked(cmid, cpp)	rdma_connect(cmid, cpp)
#endif

/* XXX We use KIBLND_CONN_PARAM(e) as writable buffer, it's not strictly
 * right because OFED1.2 defines it as const, to use it we have to add
 * (void *) cast to overcome "const" */

#define KIBLND_CONN_PARAM(e)            ((e)->param.conn.private_data)
#define KIBLND_CONN_PARAM_LEN(e)        ((e)->param.conn.private_data_len)

void kiblnd_abort_txs(struct kib_conn *conn, struct list_head *txs);
void kiblnd_map_rx_descs(struct kib_conn *conn);
void kiblnd_unmap_rx_descs(struct kib_conn *conn);
void kiblnd_pool_free_node(struct kib_pool *pool, struct list_head *node);
struct list_head *kiblnd_pool_alloc_node(struct kib_poolset *ps);

int kiblnd_fmr_pool_map(struct kib_fmr_poolset *fps, struct kib_tx *tx,
			struct kib_rdma_desc *rd, u32 nob, u64 iov,
			struct kib_fmr *fmr);
void kiblnd_fmr_pool_unmap(struct kib_fmr *fmr, int status);

int kiblnd_tunables_setup(struct lnet_lnd_tunables *lnd_tunables,
			  struct lnet_ioctl_config_lnd_cmn_tunables *net_tunables);
int  kiblnd_tunables_init(void);

int  kiblnd_connd (void *arg);
int  kiblnd_scheduler(void *arg);
#define kiblnd_thread_start(fn, data, namefmt, arg...)			\
	({								\
		struct task_struct *__task = kthread_run(fn, data,	\
							 namefmt, ##arg); \
		if (!IS_ERR(__task))					\
			atomic_inc(&kiblnd_data.kib_nthreads);		\
		PTR_ERR_OR_ZERO(__task);				\
	})

int  kiblnd_failover_thread (void *arg);

int kiblnd_alloc_pages(struct kib_pages **pp, int cpt, int npages);

int  kiblnd_cm_callback(struct rdma_cm_id *cmid,
                        struct rdma_cm_event *event);
int  kiblnd_translate_mtu(int value);

int  kiblnd_dev_failover(struct kib_dev *dev, struct net *ns);
int kiblnd_create_peer(struct lnet_ni *ni, struct kib_peer_ni **peerp,
		       struct lnet_nid *nid);
bool kiblnd_reconnect_peer(struct kib_peer_ni *peer);
void kiblnd_destroy_dev(struct kib_dev *dev);
void kiblnd_unlink_peer_locked(struct kib_peer_ni *peer_ni);
struct kib_peer_ni *kiblnd_find_peer_locked(struct lnet_ni *ni,
					    struct lnet_nid *nid);
int  kiblnd_close_stale_conns_locked(struct kib_peer_ni *peer_ni,
				     int version, u64 incarnation);
int  kiblnd_close_peer_conns_locked(struct kib_peer_ni *peer_ni, int why);

struct kib_conn *kiblnd_create_conn(struct kib_peer_ni *peer_ni,
				    struct rdma_cm_id *cmid,
				    int state, int version);
void kiblnd_destroy_conn(struct kib_conn *conn);
void kiblnd_close_conn(struct kib_conn *conn, int error);
void kiblnd_close_conn_locked(struct kib_conn *conn, int error);

void kiblnd_launch_tx(struct lnet_ni *ni, struct kib_tx *tx,
		      struct lnet_nid *nid);
void kiblnd_txlist_done(struct list_head *txlist, int status,
			enum lnet_msg_hstatus hstatus);

void kiblnd_qp_event(struct ib_event *event, void *arg);
void kiblnd_cq_event(struct ib_event *event, void *arg);
void kiblnd_cq_completion(struct ib_cq *cq, void *arg);

void kiblnd_pack_msg(struct lnet_ni *ni, struct kib_msg *msg, int version,
		     int credits, struct lnet_nid *dstnid, u64 dststamp);
int kiblnd_unpack_msg(struct kib_msg *msg, int nob);
int kiblnd_post_rx(struct kib_rx *rx, int credit);

int kiblnd_send(struct lnet_ni *ni, void *private, struct lnet_msg *lntmsg);
int kiblnd_recv(struct lnet_ni *ni, void *private, struct lnet_msg *lntmsg,
		int delayed, unsigned int niov,
		struct bio_vec *kiov, unsigned int offset, unsigned int mlen,
		unsigned int rlen);
unsigned int kiblnd_get_dev_prio(struct lnet_ni *ni, unsigned int dev_idx);

#if LINUX_VERSION_CODE < KERNEL_VERSION(3, 11, 0)
#undef netdev_notifier_info_to_dev
#define netdev_notifier_info_to_dev(ndev) ndev
#endif

#define kiblnd_dump_conn_dbg(conn)			\
({							\
	if (conn && conn->ibc_cmid)			\
		CDEBUG(D_NET, "conn %p state %d nposted %d/%d c/o/r %d/%d/%d ce %d : cm_id %p qp_num 0x%x device_name %s\n",	\
			conn,				\
			conn->ibc_state,		\
			conn->ibc_noops_posted,		\
			conn->ibc_nsends_posted,	\
			conn->ibc_credits,		\
			conn->ibc_outstanding_credits,	\
			conn->ibc_reserved_credits,	\
			conn->ibc_comms_error,		\
			conn->ibc_cmid,			\
			conn->ibc_cmid->qp ? conn->ibc_cmid->qp->qp_num : 0,	\
			conn->ibc_cmid->qp ? (conn->ibc_cmid->qp->device ? dev_name(&conn->ibc_cmid->qp->device->dev) : "NULL") : "NULL");	\
	else if (conn)					\
		CDEBUG(D_NET, "conn %p state %d nposted %d/%d c/o/r %d/%d/%d ce %d : cm_id NULL\n",	\
			conn,				\
			conn->ibc_state,		\
			conn->ibc_noops_posted,		\
			conn->ibc_nsends_posted,	\
			conn->ibc_credits,		\
			conn->ibc_outstanding_credits,	\
			conn->ibc_reserved_credits,	\
			conn->ibc_comms_error		\
			);				\
})
