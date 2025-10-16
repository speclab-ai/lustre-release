

/* Copyright (C) 2004 Cluster File Systems, Inc.
 *
 * Copyright (C) 2009-2012 Cray, Inc.
 *
 * Copyright (c) 2014, 2016, Intel Corporation.
 */

/* This file is part of Lustre, http:
 *
 * Derived from work by: Eric Barton <eric@bartonsoftware.com>
 * Author: Nic Henke <nic@cray.com>
 * Author: James Shimek <jshimek@cray.com>
 */

#ifndef _GNILND_GNILND_H_
#define _GNILND_GNILND_H_

#define DEBUG_SUBSYSTEM S_LND

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/mm.h>
#include <linux/string.h>
#include <linux/stat.h>
#include <linux/errno.h>
#ifdef HAVE_LINUX_KERNEL_LOCK
#include <linux/smp_lock.h>
#endif
#include <linux/unistd.h>
#include <linux/uio.h>
#include <linux/time.h>
#include <asm/timex.h>

#include <asm/uaccess.h>
#include <asm/io.h>

#include <linux/init.h>
#include <linux/fs.h>
#include <linux/file.h>
#include <linux/stat.h>
#include <linux/list.h>
#include <linux/kmod.h>
#include <linux/sysctl.h>
#include <linux/kthread.h>
#include <linux/nmi.h>

#include <net/sock.h>
#include <linux/in.h>
#include <linux/nmi.h>

#include <lnet/lib-lnet.h>

#include <gni_pub.h>

static inline time_t cfs_duration_sec(long duration_jiffies)
{
	return jiffies_to_msecs(duration_jiffies) / MSEC_PER_SEC;
}

#ifdef CONFIG_SLAB
#define GNILND_MBOX_SIZE	KMALLOC_MAX_SIZE
#else
#define GNILND_SHIFT_HIGH	((MAX_ORDER + PAGE_SHIFT - 1) <= 25 ? \
				(MAX_ORDER + PAGE_SHIFT - 1) : 25)
#define GNILND_SHIFT_MAX	GNILND_SHIFT_HIGH
#define GNILND_MBOX_SIZE	(1UL << GNILND_SHIFT_MAX)
#endif



#define GNILND_MIN_TIMEOUT	5		
#define GNILND_TO2KA(t)		(((t)-1)/2)	
#define GNILND_MIN_RECONNECT_TO	(GNILND_BASE_TIMEOUT/4)
#define GNILND_MAX_RECONNECT_TO	GNILND_BASE_TIMEOUT
#define GNILND_HARDWARE_TIMEOUT	15		
#define GNILND_MDD_TIMEOUT	15		
#define GNILND_SCHED_TIMEOUT       1
#define GNILND_DGRAM_TIMEOUT       2
#define GNILND_FAST_MAPPING_TRY   \
	*kgnilnd_tunables.kgn_max_retransmits   
#define GNILND_MAP_RETRY_RATE      1            


#define GNILND_MAP_TIMEOUT         \
	(cfs_time_seconds(*kgnilnd_tunables.kgn_timeout * \
	 *kgnilnd_tunables.kgn_timeout))


#define GNILND_VZALLOC_RETRY 0


#define GNILND_REAPER_THREAD_WAKE  1

#define GNILND_REAPER_NCHECKS      4


#define GNILND_MAXDEVS		1		
#define GNILND_MBOX_CREDITS	256		
#define GNILND_CONN_MAGIC         0xa100f       

#define GNILND_CHECKSUM_OFF		0	
#define GNILND_CHECKSUM_SMSG_HEADER	1	
#define GNILND_CHECKSUM_SMSG		2	
#define GNILND_CHECKSUM_SMSG_BTE	3	

/* tune down some COMPUTE options as they won't see the same number of connections and
 * don't need the throughput of multiple threads by default */
#if defined(CONFIG_CRAY_COMPUTE)
#ifdef CONFIG_MK1OM
#define GNILND_SCHED_THREADS      2             
#else
#define GNILND_SCHED_THREADS      1             
#endif
#define GNILND_FMABLK             64            
#define GNILND_SCHED_NICE         0		
#define GNILND_COMPUTE            1             
#define GNILND_FAST_RECONNECT     1             
#define GNILND_DEFAULT_CREDITS    64            
#else
#define GNILND_FMABLK             1024          
#define GNILND_SCHED_NICE         -20		
#define GNILND_COMPUTE            0             
#define GNILND_FAST_RECONNECT     0             
#define GNILND_DEFAULT_CREDITS    256           
#endif


#define GNILND_EXTRA_BITS         1

#define GNILND_CQID_NBITS         (21 - GNILND_EXTRA_BITS)
#define GNILND_MSGID_TX_NBITS     (32 - GNILND_CQID_NBITS)
#define GNILND_MAX_CQID           (1 << GNILND_CQID_NBITS)
#define GNILND_MAX_MSG_ID         (1 << GNILND_MSGID_TX_NBITS)
#define GNILND_MAX_MSG_SIZE       (*kgnilnd_tunables.kgn_max_immediate + sizeof(kgn_msg_t))


#define GNILND_MAX_IMMEDIATE      (64<<10)

#define GNILND_MAX_IOV            1024


#define GNILND_PURGATORY_MAX	  5

#define GNILND_NOPURG             222

/* payload size to add to the base mailbox size
 * This is subtracting 2 from the concurrent_sends as 4 messages are included in the size
 * gni_smsg_buff_size_needed calculates, the MAX_PAYLOAD is added to
 * the calculation return from that function.*/
#define GNILND_MBOX_PAYLOAD     \
	  (GNILND_MAX_MSG_SIZE * \
	  ((*kgnilnd_tunables.kgn_concurrent_sends - 2) * 2));


#define GNILND_TIMEOUT2DEADMAN   ((*kgnilnd_tunables.kgn_mdd_timeout) * 1000 * 60)


#define GNILND_TIMEOUTRX(t)     (t + cfs_time_seconds(*kgnilnd_tunables.kgn_hardware_timeout))


#define GNILND_PURG_RELEASE(t)   (GNILND_TIMEOUTRX(t) * 3)

/* Macro for finding last_rx 2 datapoints are compared
 * and the most recent one in jiffies is returned.
 */
#define GNILND_LASTRX(conn) (time_after(conn->gnc_last_rx, conn->gnc_last_rx_cq) \
				? conn->gnc_last_rx : conn->gnc_last_rx_cq)


#define GNILND_REGFAILTO_DISABLE  -1

/************************************************************************
 * Enum, flag and tag data
 */
#define GNILND_INIT_NOTHING         0
#define GNILND_INIT_DATA            1
#define GNILND_INIT_ALL             2


#define GNILND_BUF_NONE           0              
#define GNILND_BUF_IMMEDIATE      1              
#define GNILND_BUF_IMMEDIATE_KIOV 2              
#define GNILND_BUF_PHYS_UNMAPPED  3              
#define GNILND_BUF_PHYS_MAPPED    4              

#define GNILND_TX_WAITING_REPLY      (1<<1)     
#define GNILND_TX_WAITING_COMPLETION (1<<2)     
#define GNILND_TX_PENDING_RDMA       (1<<3)     
#define GNILND_TX_QUIET_ERROR        (1<<4)     
#define GNILND_TX_FAIL_SMSG          (1<<5)     


#define GNILND_MSGID_NOOP           (GNILND_MAX_CQID + 128)
#define GNILND_MSGID_CLOSE          (GNILND_MSGID_NOOP + 1)


#define GNILND_MSG_NONE              0x00        
#define GNILND_MSG_NOOP              0x01        
#define GNILND_MSG_IMMEDIATE         0x02        
#define GNILND_MSG_PUT_REQ           0x03        
#define GNILND_MSG_PUT_NAK           0x04        
#define GNILND_MSG_PUT_ACK           0x05        
#define GNILND_MSG_PUT_DONE          0x06        
#define GNILND_MSG_GET_REQ           0x07        
#define GNILND_MSG_GET_NAK           0x08        
#define GNILND_MSG_GET_DONE          0x09        
#define GNILND_MSG_CLOSE             0x0a        
#define GNILND_MSG_PUT_REQ_REV       0x0b	 
#define GNILND_MSG_PUT_DONE_REV      0x0c	 
#define GNILND_MSG_PUT_NAK_REV       0x0d        
#define GNILND_MSG_GET_REQ_REV       0x0e        
#define GNILND_MSG_GET_ACK_REV       0x0f        
#define GNILND_MSG_GET_DONE_REV      0x10	 
#define GNILND_MSG_GET_NAK_REV       0x11        


#define GNILND_CONN_IDLE             0
#define GNILND_CONN_SCHED            1
#define GNILND_CONN_WANTS_SCHED      2
#define GNILND_CONN_PROCESS          3

#define GNILND_DEV_IDLE              0
#define GNILND_DEV_IRQ               1
#define GNILND_DEV_LOOP              2

#define GNILND_DGRAM_IDLE            0
#define GNILND_DGRAM_SCHED           1
#define GNILND_DGRAM_PROCESS         2

#define GNILND_PEER_IDLE             0
#define GNILND_PEER_CONNECT          1
#define GNILND_PEER_POSTING          2
#define GNILND_PEER_POSTED           3
#define GNILND_PEER_NEEDS_DEATH      4
#define GNILND_PEER_KILL             5


#define GNILND_CLOSE_RX              1
#define GNILND_CLOSE_INJECT1         2
#define GNILND_CLOSE_INJECT2         3
#define GNILND_CLOSE_EARLY           4


#define GNILND_QUIESCE_IDLE          0
#define GNILND_QUIESCE_ADMIN         1
#define GNILND_QUIESCE_RESET         2
#define GNILND_QUIESCE_HW_QUIESCE    3

#define GNILND_PEER_CLEAN            0
#define GNILND_PEER_PERSISTING       1

#define GNILND_DEL_CONN              0
#define GNILND_DEL_PEER              1
#define GNILND_CLEAR_PURGATORY       2

#define GNILND_PEER_UP               0
#define GNILND_PEER_DOWN             1
#define GNILND_PEER_TIMED_OUT        2
#define GNILND_PEER_UNKNOWN          3


#define GNILND_REVERSE_NONE		0
#define GNILND_REVERSE_GET		1
#define GNILND_REVERSE_PUT		2
#define GNILND_REVERSE_BOTH		(GNILND_REVERSE_GET | GNILND_REVERSE_PUT)

typedef enum kgn_fmablk_state {
	GNILND_FMABLK_IDLE = 0, 
	GNILND_FMABLK_PHYS,     
	GNILND_FMABLK_VIRT,     
	GNILND_FMABLK_FREED,    
} kgn_fmablk_state_t;

typedef enum kgn_tx_list_state {
	GNILND_TX_IDLE = 0,     
	GNILND_TX_ALLOCD,       
	GNILND_TX_PEERQ,        
	GNILND_TX_MAPQ,         
	GNILND_TX_FMAQ,         
	GNILND_TX_LIVE_FMAQ,    
	GNILND_TX_RDMAQ,        
	GNILND_TX_LIVE_RDMAQ,   
	GNILND_TX_DYING,        
	GNILND_TX_FREED         
} kgn_tx_list_state_t;

typedef enum kgn_conn_state {
	
	GNILND_CONN_DUMMY = 0,
	GNILND_CONN_LISTEN,
	GNILND_CONN_CONNECTING,
	GNILND_CONN_ESTABLISHED,
	GNILND_CONN_CLOSING,
	GNILND_CONN_CLOSED,
	GNILND_CONN_DONE,
	GNILND_CONN_DESTROY_EP
} kgn_conn_state_t;

/* changing these requires a change to GNILND_CONNREQ_VERSION and
 * will result in dropped packets instead of NAKs. Adding to this is
 * acceptable without changing the CONNREQ_VERSION, but code should
 * be ready to handle NAKs on version mismatch  */
typedef enum kgn_connreq_type {
	GNILND_CONNREQ_REQ = 1,         
	GNILND_CONNREQ_NAK,             
	GNILND_CONNREQ_CLOSE,           
} kgn_connreq_type_t;

typedef enum kgn_dgram_state {
	
	GNILND_DGRAM_USED = 1,
	GNILND_DGRAM_POSTING,
	GNILND_DGRAM_POSTED,
	GNILND_DGRAM_PROCESSING,
	GNILND_DGRAM_CANCELED,
	GNILND_DGRAM_DONE,
} kgn_dgram_state_t;

typedef enum kgn_dgram_type {
	GNILND_DGRAM_REQ = 1,         
	GNILND_DGRAM_WC_REQ,          
	GNILND_DGRAM_NAK,             
	GNILND_DGRAM_CLOSE,           
} kgn_dgram_type_t;

/************************************************************************
 * Wire message structs.  These are sent in sender's byte order
 * (i.e. receiver checks magic and flips if required).
 */

#define GNILND_MSG_MAGIC     LNET_PROTO_GNI_MAGIC 
#define GNILND_DGRAM_MAGIC   0x0DDBA11

/*  kgn_msg_t - FMA/SMSG wire struct
  v2:
   * - added checksum to FMA
   * moved seq before paylod
   * __packed added for alignment
  v3:
   * added gnm_payload_len for FMA payload size
  v4:
   * added gncm_retval to completion, allowing return code transmission
     on RDMA NAKs
  v5:
   * changed how CQID and TX ids are assigned
  v6:
   * added retval on CLOSE
  v7:
   * added payload checksumming
  v8:
   * reworked checksumming a bit, changed payload checksums
*/
#define GNILND_MSG_VERSION              8
/* kgn_connreq_t connection request datagram wire struct
  v2:
   * added NAKs
*/

#define GNILND_CONNREQ_VERSION          2

typedef struct kgn_gniparams {
	__u32            gnpr_host_id;          
	__u32            gnpr_cqid;             
	gni_smsg_attr_t  gnpr_smsg_attr;        
} __packed kgn_gniparams_t;

typedef struct kgn_nak_data {
	__s32            gnnd_errno;            

} __packed kgn_nak_data_t;

/* the first bits of the connreq struct CANNOT CHANGE FORM EVER
 * without breaking the ability for us to properly NAK someone */
typedef struct kgn_connreq {                    
	__u32             gncr_magic;           
	__u32             gncr_cksum;           
	__u16             gncr_type;            
	__u16             gncr_version;         
	__u32             gncr_timeout;         
	__u64             gncr_srcnid;          
	__u64             gncr_dstnid;          
	__u64             gncr_peerstamp;       
	__u64             gncr_connstamp;       

	/* everything before this needs to stay static, adding after should
	 * result in a change to GNILND_CONNREQ_VERSION */

	union {
		kgn_gniparams_t   gncr_gnparams;        
		kgn_nak_data_t    gncr_nakdata;         
	};
} __packed kgn_connreq_t;

typedef struct {
	gni_mem_handle_t  gnrd_key;
	__u64             gnrd_addr;
	__u32             gnrd_nob;
} __packed kgn_rdma_desc_t;

typedef struct {
	struct lnet_hdr_nid4	gnim_hdr;	
	
} __packed kgn_immediate_msg_t;

typedef struct {
	struct lnet_hdr_nid4	gnprm_hdr;	
	__u64			gnprm_cookie;	
} __packed kgn_putreq_msg_t;

typedef struct {
	__u64             gnpam_src_cookie;     
	__u64             gnpam_dst_cookie;     
	__u16		  gnpam_payload_cksum;  
	kgn_rdma_desc_t   gnpam_desc;           
} __packed kgn_putack_msg_t;

typedef struct {
	struct lnet_hdr_nid4	gngm_hdr;	
	__u64			gngm_cookie;	
	__u16			gngm_payload_cksum; 
	kgn_rdma_desc_t		gngm_desc;	
} __packed kgn_get_msg_t;

typedef struct {
	int               gncm_retval;          
	__u64             gncm_cookie;          
} __packed kgn_completion_msg_t;

typedef struct {                                
	__u32             gnm_magic;            
	__u16             gnm_version;          
	__u16             gnm_type;             
	__u64             gnm_srcnid;           
	__u64             gnm_connstamp;        
	__u32             gnm_seq;              
	__u16             gnm_cksum;            
	__u16             gnm_payload_cksum;    
	__u32             gnm_payload_len;      
	union {
		kgn_immediate_msg_t   immediate;
		kgn_putreq_msg_t      putreq;
		kgn_putack_msg_t      putack;
		kgn_get_msg_t         get;
		kgn_completion_msg_t  completion;
	} gnm_u;
} __packed kgn_msg_t;

/************************************************************************
 * runtime tunable data
 */

typedef struct kgn_tunables {
	int              *kgn_min_reconnect_interval; 
	int              *kgn_max_reconnect_interval; 
	int              *kgn_credits;          
	int              *kgn_fma_cq_size;      
	int              *kgn_peer_credits;     
	int              *kgn_concurrent_sends; 
	int              *kgn_timeout;          
	int              *kgn_max_immediate;    
	int              *kgn_checksum;         
	int              *kgn_checksum_dump;    
	int		 *kgn_bte_put_dlvr_mode; 
	int              *kgn_bte_get_dlvr_mode; 
	int              *kgn_bte_relaxed_ordering; 
	int              *kgn_ptag;             
	int              *kgn_pkey;             
	int              *kgn_max_retransmits;  
	int              *kgn_nwildcard;        
	int              *kgn_nice;             
	int              *kgn_rdmaq_intervals;  
	int              *kgn_loops;            
	int              *kgn_peer_hash_size;   
	int              *kgn_peer_health;      
	int              *kgn_peer_timeout;     
	int              *kgn_vmap_cksum;       
	int              *kgn_mbox_per_block;   
	int              *kgn_nphys_mbox;       
	int              *kgn_mbox_credits;     
	int              *kgn_sched_threads;    
	int              *kgn_net_hash_size;    
	int              *kgn_hardware_timeout; 
	int              *kgn_mdd_timeout;      
	int		 *kgn_sched_timeout;    
	int              *kgn_dgram_timeout;    
	int		 *kgn_sched_nice;	
	int		 *kgn_reverse_rdma;	
	int		 *kgn_eager_credits;	
	int     *kgn_fast_reconn;      
	int     *kgn_efault_lbug;      
	int     *kgn_max_purgatory;    
	int     *kgn_reg_fail_timeout; 
	int     *kgn_thread_affinity;  
	int     *kgn_to_reconn_disable;
	int     *kgn_thread_safe;      
	int     *kgn_vzalloc_noretry;  
} kgn_tunables_t;

typedef struct kgn_mbox_info {
	lnet_nid_t mbx_prev_nid;
	lnet_nid_t mbx_prev_purg_nid;
	unsigned long mbx_create_conn_memset;
	unsigned long mbx_add_purgatory;
	unsigned long mbx_detach_of_purgatory;
	unsigned long mbx_release_from_purgatory;
	unsigned long mbx_release_purg_active_dgram;
	int           mbx_nallocs;
	int           mbx_nallocs_total;
} kgn_mbox_info_t;

typedef struct kgn_fma_memblock {
	struct list_head    gnm_bufflist;                          
	kgn_fmablk_state_t  gnm_state;                             
	int                 gnm_hold_timeout;                      
	int                 gnm_num_mboxs;                         
	int                 gnm_avail_mboxs;                       
	int                 gnm_held_mboxs;                        
	int                 gnm_mbox_size;                         
	int                 gnm_next_avail_mbox;                   
	long                gnm_max_timeout;                       
	unsigned int        gnm_blk_size;                          
	void               *gnm_block;                             
	gni_mem_handle_t    gnm_hndl;                              
	unsigned long      *gnm_bit_array;                         
	kgn_mbox_info_t    *gnm_mbox_info;                         
} kgn_fma_memblock_t;

typedef struct kgn_device {
	gni_nic_handle_t        gnd_handle;       
	gni_cdm_handle_t        gnd_domain;       
	gni_err_handle_t        gnd_err_handle;   
	unsigned long           gnd_sched_alive;  
	gni_cq_handle_t         gnd_rcv_fma_cqh;  
	gni_cq_handle_t         gnd_snd_rdma_cqh; 
	gni_cq_handle_t         gnd_snd_fma_cqh;  
	struct mutex            gnd_cq_mutex;     
	__u32                   gnd_host_id;      
	int                     gnd_id;           
	__u32                   gnd_nid;          
	struct list_head        gnd_fma_buffs;    
	struct mutex            gnd_fmablk_mutex; 
	spinlock_t              gnd_fmablk_lock;  
	atomic_t                gnd_nfmablk;      
	atomic_t                gnd_fmablk_vers;  
	atomic_t                gnd_neps;         
	short                   gnd_ready;        
	struct list_head        gnd_ready_conns;  
	struct list_head        gnd_delay_conns;  
	struct list_head        gnd_map_tx;       
	wait_queue_head_t       gnd_waitq;        
	spinlock_t              gnd_lock;         
	struct list_head        gnd_connd_peers;  
	spinlock_t              gnd_connd_lock;   
	wait_queue_head_t       gnd_dgram_waitq;  
	wait_queue_head_t       gnd_dgping_waitq; 
	int                     gnd_dgram_ready;  
	struct list_head       *gnd_dgrams;       
	atomic_t                gnd_ndgrams;      
	atomic_t                gnd_nwcdgrams;    
	spinlock_t              gnd_dgram_lock;   
	struct list_head        gnd_map_list;     
	int                     gnd_map_version;  
	struct timer_list       gnd_map_timer;    
	atomic_t                gnd_n_mdd;        
	atomic_t                gnd_n_mdd_held;   
	atomic_t                gnd_nq_map;       
	atomic64_t              gnd_nbytes_map;   
	__u32                   gnd_map_nphys;    
	__u32                   gnd_map_physnop;  
	spinlock_t              gnd_map_lock;     
	unsigned long           gnd_next_map;     
	int                     gnd_map_attempt;  
	unsigned long           gnd_last_map;     
	struct list_head        gnd_rdmaq;        
	spinlock_t              gnd_rdmaq_lock;   
	atomic64_t              gnd_rdmaq_bytes_out; 
	atomic64_t              gnd_rdmaq_bytes_ok;  
	atomic_t                gnd_rdmaq_nstalls;   
	unsigned long           gnd_rdmaq_deadline;  
	struct timer_list       gnd_rdmaq_timer;     
	atomic_t                gnd_short_ntx;      
	atomic64_t              gnd_short_txbytes;  
	atomic_t                gnd_rdma_ntx;       
	atomic64_t              gnd_rdma_txbytes;   
	atomic_t                gnd_short_nrx;      
	atomic64_t              gnd_short_rxbytes;  
	atomic_t                gnd_rdma_nrx;       
	atomic64_t              gnd_rdma_rxbytes;   
	atomic_t                gnd_fast_try;       
	atomic_t                gnd_fast_ok;        
	atomic_t                gnd_fast_block;     
	unsigned long           gnd_mutex_delay;
	atomic_t                gnd_n_yield;
	atomic_t                gnd_n_schedule;
	atomic_t                gnd_canceled_dgrams; 
	struct rw_semaphore     gnd_conn_sem;       
	void                   *gnd_smdd_hold_buf;  
	gni_mem_handle_t        gnd_smdd_hold_hndl; 
} kgn_device_t;

typedef struct kgn_net {
	struct list_head    gnn_list;           
	kgn_device_t       *gnn_dev;            
	struct lnet_ni          *gnn_ni;             
	atomic_t            gnn_refcount;       
	int                 gnn_shutdown;       
	__u16               gnn_netnum;         
} kgn_net_t;

static inline lnet_nid_t
kgnilnd_lnd2lnetnid(lnet_nid_t ni_nid, lnet_nid_t kgnilnd_nid)
{
	return LNET_MKNID(LNET_NIDNET(ni_nid), LNET_NIDADDR(kgnilnd_nid));
}

static inline lnet_nid_t
kgnilnd_lnet2lndnid(lnet_nid_t lnet_nid, lnet_nid_t kgnilnd_nid)
{
	return LNET_MKNID(LNET_NIDNET(kgnilnd_nid), LNET_NIDADDR(lnet_nid));
}

/* The code for this is a bit ugly - but really  this just boils down to a __u64
 * that can have various parts accessed separately.
 *
 * The lower 32 bits is the ID
 * we give to SMSG for our completion event - it needs to be globally unique across
 * all TX currently in flight. We separate that out into the CQID so that we can
 * reference the connection (kgnilnd_cqid2conn_locked) and then the msg_id to pull
 * the actual TX out of the per-connection gnc_tx_ref_table.
 *
 * The upper 32 bits are just extra stuff we put into the cookie to ensure this TX
 * has a unique value we can send with RDMA setup messages to ensure the completion for
 * those is unique across the wire. The extra 32 bits are there to ensure that TX id
 * reuse is separated.
 */

typedef struct kgn_tx_ev_id {
	union {
		__u64             txe_cookie;    
		struct {
			__u32     txe_chips;     
			union {
				__u32     txe_smsg_id;      
				/* N.B: Never ever ever ever use the bit shifts directly,
				 * you are just asking for a world of pain and are at the
				 * mercy of the compiler layouts */
				struct {
					__u32     txe_cqid :GNILND_CQID_NBITS;
					__u32     txe_idx :GNILND_MSGID_TX_NBITS;
				};
			};
		};
	};
} kgn_tx_ev_id_t;

typedef struct kgn_dgram {
	struct list_head     gndg_list;          
	kgn_dgram_state_t    gndg_state;         
	kgn_dgram_type_t     gndg_type;          
	__u32                gndg_magic;         
	unsigned long        gndg_post_time;     
	struct kgn_conn     *gndg_conn;          
	kgn_connreq_t        gndg_conn_out;      
	kgn_connreq_t        gndg_conn_in;       
} kgn_dgram_t;

typedef struct kgn_tx {                         
	struct list_head          tx_list;      
	kgn_tx_list_state_t       tx_list_state;
	struct list_head         *tx_list_p;    
	struct kgn_conn          *tx_conn;      
	struct lnet_msg               *tx_lntmsg[2]; 
	unsigned long             tx_qtime;     
	unsigned long             tx_cred_wait; 
	struct list_head          tx_map_list;  
	unsigned int              tx_nob;       
	int                       tx_buftype;   
	int                       tx_phys_npages; 
	gni_mem_handle_t          tx_map_key;   
	gni_mem_handle_t	  tx_buffer_copy_map_key;  
	gni_mem_segment_t        *tx_phys;      
	kgn_msg_t                 tx_msg;       
	kgn_tx_ev_id_t            tx_id;        
	__u8                      tx_state;     
	int                       tx_retrans;   
	int                       tx_rc;        
	void                     *tx_buffer;    
	void			 *tx_buffer_copy;   
	unsigned int		  tx_nob_rdma;  
	unsigned int		  tx_offset;	
	union {
		gni_post_descriptor_t     tx_rdma_desc; 
		struct page              *tx_imm_pages[GNILND_MAX_IMMEDIATE/PAGE_SIZE];  
	};

	
	union {
		kgn_putack_msg_t  tx_putinfo;   
		kgn_get_msg_t     tx_getinfo;   
	};
} kgn_tx_t;

typedef struct kgn_conn {
	kgn_device_t       *gnc_device;         
	struct kgn_peer    *gnc_peer;           
	int                 gnc_magic;          
	struct list_head    gnc_list;           
	struct list_head    gnc_hashlist;       
	struct list_head    gnc_schedlist;      
	struct list_head    gnc_fmaq;           
	struct list_head    gnc_mdd_list;       
	struct list_head    gnc_delaylist;      
	__u64               gnc_peerstamp;      
	__u64               gnc_peer_connstamp; 
	__u64               gnc_my_connstamp;   
	unsigned long       gnc_first_rx;       
	unsigned long       gnc_last_tx;        
	unsigned long       gnc_last_rx;        
	unsigned long       gnc_last_tx_cq;     
	unsigned long       gnc_last_rx_cq;     
	unsigned long       gnc_last_noop_want; 
	unsigned long       gnc_last_noop_sent; 
	unsigned long       gnc_last_noop_cq;   
	unsigned long       gnc_last_sched_ask; 
	unsigned long       gnc_last_sched_do;  
	atomic_t            gnc_reaper_noop;    
	atomic_t            gnc_sched_noop;     
	unsigned int        gnc_timeout;        
	__u32               gnc_cqid;           
	atomic_t            gnc_tx_seq;         
	atomic_t            gnc_rx_seq;         
	struct mutex        gnc_smsg_mutex;     
	struct mutex        gnc_rdma_mutex;     
	__u64               gnc_tx_retrans;     
	atomic_t            gnc_nlive_fma;      
	atomic_t            gnc_nq_rdma;        
	atomic_t            gnc_nlive_rdma;     
	short               gnc_close_sent;     
	short               gnc_close_recvd;    
	short               gnc_in_purgatory;   
	int                 gnc_error;          
	int                 gnc_peer_error;     
	kgn_conn_state_t    gnc_state;          
	int                 gnc_scheduled;      
	char		    gnc_sched_caller[30]; 
	int		    gnc_sched_line;	
	atomic_t            gnc_refcount;       
	spinlock_t          gnc_list_lock;      
	gni_ep_handle_t     gnc_ephandle;       
	kgn_fma_memblock_t *gnc_fma_blk;        
	gni_smsg_attr_t     gnpr_smsg_attr;     
	spinlock_t          gnc_tx_lock;        
	unsigned long       gnc_tx_bits[(GNILND_MAX_MSG_ID/8)/sizeof(unsigned long)]; 
	int                 gnc_next_tx;        
	kgn_tx_t          **gnc_tx_ref_table;   
	int                 gnc_mbox_id;        
	short               gnc_needs_detach;   
	short               gnc_needs_closing;  
	atomic_t	    gnc_tx_in_use;	
	kgn_dgram_type_t    gnc_dgram_type;     
	void               *remote_mbox_addr;   
} kgn_conn_t;

typedef struct kgn_mdd_purgatory {
	gni_mem_handle_t    gmp_map_key;        
	struct list_head    gmp_list;           
} kgn_mdd_purgatory_t;

typedef struct kgn_peer {
	struct list_head    gnp_list;                   
	struct list_head    gnp_connd_list;             
	struct list_head    gnp_conns;                  
	struct list_head    gnp_tx_queue;               
	kgn_net_t          *gnp_net;                    
	lnet_nid_t          gnp_nid;                    
	atomic_t            gnp_refcount;               
	__u32               gnp_host_id;                
	short               gnp_connecting;             
	short               gnp_pending_unlink;         
	int                 gnp_last_errno;             
	time64_t	    gnp_last_alive;             
	int                 gnp_last_dgram_errno;       
	unsigned long       gnp_last_dgram_time;        
	unsigned long       gnp_reconnect_time;         
	unsigned long       gnp_reconnect_interval;     
	atomic_t            gnp_dirty_eps;              
	int                 gnp_state;                  
	unsigned long       gnp_down_event_time;        
	unsigned long       gnp_up_event_time;          
} kgn_peer_t;

/* the kgn_rx_t is a struct for handing to LNET as the private pointer for things
 * like lnet_parse. It allows a single pointer to let us get enough
 * information in _recv and friends */
typedef struct kgn_rx {
	kgn_conn_t              *grx_conn;      
	kgn_msg_t               *grx_msg;       
	struct lnet_msg              *grx_lntmsg;    
	int                      grx_eager;     
	struct timespec64        grx_received;  
} kgn_rx_t;

typedef struct kgn_data {
	int                     kgn_init;             
	int                     kgn_shutdown;         
	int                     kgn_wc_kill;          
	atomic_t                kgn_nthreads;         
	int                     kgn_nresets;          
	int                     kgn_in_reset;         

	__u64                   kgn_nid_trans_private;

	kgn_device_t            kgn_devices[GNILND_MAXDEVS]; 
	int                     kgn_ndevs;            

	int                     kgn_ruhroh_running;   
	int                     kgn_ruhroh_shutdown;  
	wait_queue_head_t       kgn_ruhroh_waitq;     
	int                     kgn_quiesce_trigger;  
	atomic_t                kgn_nquiesce;         
	struct mutex            kgn_quiesce_mutex;    
	int                     kgn_needs_reset;      

	/* These next three members implement communication from gnilnd into
	 * the ruhroh task.  To ensure correct operation of the task, code that
	 * writes into them must use memory barriers to ensure that the changes
	 * are visible to other cores in the order the members appear below.  */
	__u32                   kgn_quiesce_secs;     
	int                     kgn_bump_info_rdy;    
	int                     kgn_needs_pause;      

	struct list_head       *kgn_nets;             
	struct rw_semaphore     kgn_net_rw_sem;       

	rwlock_t                kgn_peer_conn_lock;   
	struct list_head       *kgn_peers;            
	atomic_t                kgn_npeers;           
	int                     kgn_peer_version;     

	struct list_head       *kgn_conns;            
	atomic_t                kgn_nconns;           
	atomic_t                kgn_neager_allocs;    
	__u64                   kgn_peerstamp;        
	__u64                   kgn_connstamp;        
	int                     kgn_conn_version;     
	int                     kgn_next_cqid;        

	long                    kgn_new_min_timeout;  
	wait_queue_head_t       kgn_reaper_waitq;     
	spinlock_t              kgn_reaper_lock;      

	struct kmem_cache      *kgn_rx_cache;         
	struct kmem_cache      *kgn_tx_cache;         
	struct kmem_cache      *kgn_tx_phys_cache;    
	atomic_t                kgn_ntx;              
	struct kmem_cache      *kgn_dgram_cache;      

	struct page          ***kgn_cksum_map_pages;  
	__u64                   kgn_cksum_npages;     
	atomic_t                kgn_nvmap_cksum;      
	atomic_t                kgn_nvmap_short;      

	atomic_t                kgn_nkmap_short;      
	long                    kgn_rdmaq_override;   

	struct kmem_cache      *kgn_mbox_cache;       

	atomic_t                kgn_npending_unlink;  
	atomic_t                kgn_npending_conns;   
	atomic_t                kgn_npending_detach;  
	unsigned long           kgn_last_scheduled;   
	unsigned long           kgn_last_condresched; 
	atomic_t                kgn_rev_offset;       
	atomic_t                kgn_rev_length;       
	atomic_t                kgn_rev_copy_buff;    
	unsigned long           free_pages_limit;     
	int                     kgn_enable_gl_mutex;  
} kgn_data_t;

extern kgn_data_t         kgnilnd_data;
extern kgn_tunables_t     kgnilnd_tunables;

extern void kgnilnd_destroy_peer(kgn_peer_t *peer);
extern void kgnilnd_destroy_conn(kgn_conn_t *conn);
extern int _kgnilnd_schedule_conn(kgn_conn_t *conn, const char *caller, int line, int refheld, int lock_held);
extern int _kgnilnd_schedule_delay_conn(kgn_conn_t *conn);

static inline int kgnilnd_timeout(void)
{
	return *kgnilnd_tunables.kgn_timeout ?: lnet_get_lnd_timeout();
}

/* Macro wrapper for _kgnilnd_schedule_conn. This will store the function
 * and the line of the calling function to allow us to debug problematic
 * schedule calls in the future without the programmer having to mark
 * the location manually.
 */
#define kgnilnd_schedule_conn(conn)					\
	_kgnilnd_schedule_conn(conn, __func__, __LINE__, 0, 0);

#define kgnilnd_schedule_conn_refheld(conn, refheld)			\
	_kgnilnd_schedule_conn(conn, __func__, __LINE__, refheld, 0);

#define kgnilnd_schedule_conn_nolock(conn)				\
	_kgnilnd_schedule_conn(conn, __func__, __LINE__, 0, 1);


/* Macro wrapper for _kgnilnd_schedule_delay_conn. This will allow us to store
 * extra data if we need to.
 */
#define kgnilnd_schedule_delay_conn(conn) \
	_kgnilnd_schedule_delay_conn(conn);

static inline void
kgnilnd_thread_fini(void)
{
	atomic_dec(&kgnilnd_data.kgn_nthreads);
}

static inline void kgnilnd_gl_mutex_lock(struct mutex *lock)
{
	if (kgnilnd_data.kgn_enable_gl_mutex)
		mutex_lock(lock);
}

static inline void kgnilnd_gl_mutex_unlock(struct mutex *lock)
{
	if (kgnilnd_data.kgn_enable_gl_mutex)
		mutex_unlock(lock);
}

static inline void kgnilnd_conn_mutex_lock(struct mutex *lock)
{
	if (!kgnilnd_data.kgn_enable_gl_mutex)
		mutex_lock(lock);
}

static inline void kgnilnd_conn_mutex_unlock(struct mutex *lock)
{
	if (!kgnilnd_data.kgn_enable_gl_mutex)
		mutex_unlock(lock);
}

/* like mutex_trylock but with a jiffies spinner. This is to allow certain
 * parts of the code to avoid a scheduler trip when the mutex is held
 *
 * Try to acquire the mutex atomically for 1 jiffie. Returns 1 if the mutex
 * has been acquired successfully, and 0 on contention.
 *
 * NOTE: this function follows the spin_trylock() convention, so
 * it is negated to the down_trylock() return values! Be careful
 * about this when converting semaphore users to mutexes.
 *
 * This function must not be used in interrupt context. The
 * mutex must be released by the same task that acquired it.
 */
static inline int __kgnilnd_mutex_trylock(struct mutex *lock)
{
	int             ret;
	unsigned long   timeout;

	LASSERT(!in_interrupt());

	for (timeout = jiffies + 1; time_before(jiffies, timeout);) {

		ret = mutex_trylock(lock);
		if (ret)
			return ret;
	}
	return 0;
}

static inline int kgnilnd_mutex_trylock(struct mutex *lock)
{
	if (!kgnilnd_data.kgn_enable_gl_mutex)
		return 1;

	return __kgnilnd_mutex_trylock(lock);
}

static inline int kgnilnd_trylock(struct mutex *cq_lock,
				  struct mutex *c_lock)
{
	if (kgnilnd_data.kgn_enable_gl_mutex)
		return __kgnilnd_mutex_trylock(cq_lock);
	else
		return __kgnilnd_mutex_trylock(c_lock);
}

static inline void *kgnilnd_vzalloc(int size)
{
	void *ret;
	if (*kgnilnd_tunables.kgn_vzalloc_noretry)
		ret = __ll_vmalloc(size, __GFP_HIGHMEM | GFP_NOIO | __GFP_ZERO |
				   __GFP_NORETRY);
	else
		ret = __ll_vmalloc(size, __GFP_HIGHMEM | GFP_NOIO | __GFP_ZERO);

	LIBCFS_ALLOC_POST(ret, size, "alloc");
	return ret;
}

static inline void kgnilnd_vfree(void *ptr, int size)
{
	LIBCFS_FREE_PRE(ptr, size, "vfree");
	vfree(ptr);
}


#ifndef set_mb
#define set_mb smp_store_mb
#endif



extern void
_kgnilnd_debug_msg(kgn_msg_t *msg,
		struct libcfs_debug_msg_data *data, const char *fmt, ... );

#define kgnilnd_debug_msg(msgdata, mask, cdls, msg, fmt, a...)                \
do {                                                                          \
	if (((mask) & D_CANTMASK) != 0 ||                                     \
	    ((libcfs_debug & (mask)) != 0 &&                                  \
	     (libcfs_subsystem_debug & DEBUG_SUBSYSTEM) != 0))                \
		_kgnilnd_debug_msg((msg), msgdata, fmt, ##a);                 \
} while(0)


#define GNIDBG_MSG(level, msg, fmt, args...)                                  \
do {                                                                          \
	if ((level) & (D_ERROR | D_WARNING | D_NETERROR)) {                   \
	    static struct cfs_debug_limit_state cdls;                         \
	    LIBCFS_DEBUG_MSG_DATA_DECL(msgdata, level, &cdls);                \
	    kgnilnd_debug_msg(&msgdata, level, &cdls, msg,                    \
			      "$$ "fmt" from %s ", ## args,                   \
			      libcfs_nid2str((msg)->gnm_srcnid));             \
	} else {                                                              \
	    LIBCFS_DEBUG_MSG_DATA_DECL(msgdata, level, NULL);                 \
	    kgnilnd_debug_msg(&msgdata, level, NULL, msg,                     \
			      "$$ "fmt" from %s ", ## args,                   \
			      libcfs_nid2str((msg)->gnm_srcnid));             \
	}                                                                     \
} while (0)


#define GNIDBG_TOMSG(level, msg, fmt, args...)                                \
do {                                                                          \
	if ((level) & (D_ERROR | D_WARNING | D_NETERROR)) {                   \
	    static struct cfs_debug_limit_state cdls;                         \
	    LIBCFS_DEBUG_MSG_DATA_DECL(msgdata, level, &cdls);                \
	    kgnilnd_debug_msg(&msgdata, level, &cdls, msg,                    \
			      "$$ "fmt" ", ## args);                          \
	} else {                                                              \
	    LIBCFS_DEBUG_MSG_DATA_DECL(msgdata, level, NULL);                 \
	    kgnilnd_debug_msg(&msgdata, level, NULL, msg,                     \
			      "$$ "fmt" ", ## args);                          \
	}                                                                     \
} while (0)

extern void
_kgnilnd_debug_conn(kgn_conn_t *conn,
		struct libcfs_debug_msg_data *data, const char *fmt, ... );

#define kgnilnd_debug_conn(msgdata, mask, cdls, conn, fmt, a...)               \
do {                                                                           \
	if (((mask) & D_CANTMASK) != 0 ||                                      \
	    ((libcfs_debug & (mask)) != 0 &&                                   \
	     (libcfs_subsystem_debug & DEBUG_SUBSYSTEM) != 0))                 \
		_kgnilnd_debug_conn((conn), msgdata, fmt, ##a);                \
} while(0)


#define GNIDBG_CONN(level, conn, fmt, args...)                                  \
do {                                                                            \
	if ((level) & (D_ERROR | D_WARNING | D_NETERROR)) {                     \
	    static struct cfs_debug_limit_state cdls;                           \
	    LIBCFS_DEBUG_MSG_DATA_DECL(msgdata, level, &cdls);                  \
	    kgnilnd_debug_conn(&msgdata, level, &cdls, conn,                    \
			       "$$ "fmt" ", ## args);                           \
	} else {                                                                \
	    LIBCFS_DEBUG_MSG_DATA_DECL(msgdata, level, NULL);                   \
	    kgnilnd_debug_conn(&msgdata, level, NULL, conn,                     \
			       "$$ "fmt" ", ## args);                           \
	}                                                                       \
} while (0)

extern void
_kgnilnd_debug_tx(kgn_tx_t *tx,
		struct libcfs_debug_msg_data *data, const char *fmt, ... );

#define kgnilnd_debug_tx(msgdata, mask, cdls, tx, fmt, a...)                   \
do {                                                                           \
	if (((mask) & D_CANTMASK) != 0 ||                                      \
	    ((libcfs_debug & (mask)) != 0 &&                                   \
	     (libcfs_subsystem_debug & DEBUG_SUBSYSTEM) != 0))                 \
		_kgnilnd_debug_tx((tx), msgdata, fmt, ##a);                    \
} while(0)


#define GNIDBG_TX(level, tx, fmt, args...)                                      \
do {                                                                            \
	if ((level) & (D_ERROR | D_WARNING | D_NETERROR)) {                     \
	    static struct cfs_debug_limit_state cdls;                           \
	    LIBCFS_DEBUG_MSG_DATA_DECL(msgdata, level, &cdls);                  \
	    kgnilnd_debug_tx(&msgdata, level, &cdls, tx,                        \
			      "$$ "fmt" ", ## args);                            \
	} else {                                                                \
	    LIBCFS_DEBUG_MSG_DATA_DECL(msgdata, level, NULL);                   \
	    kgnilnd_debug_tx(&msgdata, level, NULL, tx,                         \
			      "$$ "fmt" ", ## args);                            \
	}                                                                       \
} while (0)

#define GNITX_ASSERTF(tx, cond, fmt, a...)                                      \
({                                                                              \
	if (unlikely(!(cond))) {                                                \
		GNIDBG_TX(D_EMERG, tx, "ASSERTION(" #cond ") failed:" fmt, a);  \
		LBUG();                                                         \
	}                                                                       \
})

#define GNILND_IS_QUIESCED                                                      \
	(atomic_read(&kgnilnd_data.kgn_nquiesce) ==                             \
		atomic_read(&kgnilnd_data.kgn_nthreads))

#define KGNILND_SPIN_QUIESCE						\
do {									\
							\
	atomic_inc(&kgnilnd_data.kgn_nquiesce);				\
	CDEBUG(D_NET, "Waiting for thread pause to be over...\n");	\
	while (kgnilnd_data.kgn_quiesce_trigger) {			\
		msleep_interruptible(MSEC_PER_SEC);			\
	}								\
						\
	CDEBUG(D_NET, "Waking up from thread pause\n");			\
	atomic_dec(&kgnilnd_data.kgn_nquiesce);				\
} while(0)


#ifndef LIBCFS_DEBUG
#error "this code uses actions inside LASSERT for ref counting"
#endif

#define kgnilnd_admin_addref(atomic)					\
do {									\
	int val = atomic_inc_return(&atomic);				\
	LASSERTF(val > 0,  #atomic " refcount %d\n", val);		\
	CDEBUG(D_NETTRACE, #atomic " refcount %d\n", val);		\
} while (0)

#define kgnilnd_admin_decref(atomic)					\
do {									\
	int val = atomic_dec_return(&atomic);				\
	LASSERTF(val >= 0,  #atomic " refcount %d\n", val);		\
	CDEBUG(D_NETTRACE, #atomic " refcount %d\n", val);		\
	if (!val)							\
		wake_up_var(&kgnilnd_data);				\
}while (0)

#define kgnilnd_net_addref(net)						\
do {									\
	int     val = atomic_inc_return(&net->gnn_refcount);		\
	LASSERTF(val > 1, "net %px refcount %d\n", net, val);		\
	CDEBUG(D_NETTRACE, "net %p->%s++ (%d)\n", net,			\
		libcfs_nidstr(&net->gnn_ni->ni_nid), val);		\
} while (0)

#define kgnilnd_net_decref(net)						\
do {									\
	int     val = atomic_dec_return(&net->gnn_refcount);		\
	LASSERTF(val >= 0, "net %px refcount %d\n", net, val);		\
	CDEBUG(D_NETTRACE, "net %p->%s-- (%d)\n", net,			\
	       libcfs_nidstr(&net->gnn_ni->ni_nid), val);		\
} while (0)

#define kgnilnd_peer_addref(peer)					\
do {									\
	int     val = atomic_inc_return(&peer->gnp_refcount);		\
	LASSERTF(val > 1, "peer %px refcount %d\n", peer, val);		\
	CDEBUG(D_NETTRACE, "peer %p->%s++ (%d)\n", peer,		\
	       libcfs_nid2str(peer->gnp_nid), val);			\
} while (0)

#define kgnilnd_peer_decref(peer)					\
do {									\
	int     val = atomic_dec_return(&peer->gnp_refcount);		\
	LASSERTF(val >= 0, "peer %px refcount %d\n", peer, val);	\
	CDEBUG(D_NETTRACE, "peer %p->%s--(%d)\n", peer,			\
	       libcfs_nid2str(peer->gnp_nid), val);			\
	if (val == 0)							\
		kgnilnd_destroy_peer(peer);				\
} while(0)

#define kgnilnd_conn_addref(conn)					\
do {									\
	int val;							\
									\
	smp_wmb();							\
	val = atomic_inc_return(&conn->gnc_refcount);			\
	LASSERTF(val > 1 && conn->gnc_magic == GNILND_CONN_MAGIC,	\
		"conn %px refc %d to %s\n",				\
		conn, val,						\
		conn->gnc_peer						\
			? libcfs_nid2str(conn->gnc_peer->gnp_nid)	\
			: "<?>");					\
	CDEBUG(D_NETTRACE, "conn %p->%s++ (%d)\n", conn,		\
		conn->gnc_peer						\
			? libcfs_nid2str(conn->gnc_peer->gnp_nid)	\
			: "<?>",					\
		val);							\
} while (0)

/* we hijack conn_decref && gnc_refcount = 1 to allow us to push the conn
 * through the scheduler thread to get the EP destroyed. This avoids some
 * messy semaphore business and allows us to reuse the connd_list and existing
 * linkage and avoid creating extra lists just for destroying EPs */

/* Safety Disclaimer:
 * Q: If we decrement the refcount and then check it again, is it possible that
 *    another caller could have passed through this macro concurrently? If so,
 *    then it is possible that both will attempt to call kgnilnd_destroy_conn().
 *
 * A: Yes, entirely possible in most cases, but we can't get concurrent users
 * once we are refcount <= 2. It hinges around gnc_state and membership of
 * gnc_hashlist. There are two ways to find a connection - either ask for
 * it from the peer, kgnilnd_find_conn_locked(peer) or from the CQ id,
 * kgnilnd_cqid2conn_locked(id). While a conn is live, we'll have at least
 * 4 refcounts
 *
 * - #1 from create (kgnilnd_create_conn)
 * - #2 for EP (kgnilnd_create_conn)
 * - #3 - living on peer (gnc_list, kgnilnd_finish_connect)
 * - #4 living in global hash (gnc_hashlist, kgnilnd_finish_connect).
 *
 * Actually, only 3 live, as at the end of kgnilnd_finish_connect, we drop:
 * - #1 - the ref the dgram inherited from kgnilnd_create_conn.
 *
 * There could be more from TX descriptors during the lifetime of a live
 * conn.
 *
 * If we nuke the conn before finish_connect, we won't have parallel paths
 * because nobody besides the dgram handler for the single outstanding
 * dgram can find the connection as it isn't in any searchable tables yet.
 *
 * This leaves connection close, we'll drop 2 refs (#4 and #3) but only
 * after calling kgnilnd_schedule_conn, which would add a new ref (#5). At
 * this point gnc_refcount=2 (#2, #5). We have a 'maybe' send of the CLOSE
 * now on the next scheduler loop, this could be #6 (schedule_conn again)
 * and #7 (TX on gnc_fmaq). Both would be cleared quickly as that TX is
 * sent. Now the gnc_state == CLOSED, so we hit
 * kgnilnd_complete_closed_conn. At this point, nobody can 'find' this conn
 * - we've nuked them from the peer and CQ id tables, so we own them and
 * are guaranteed serial access - hence the complete lack of conn list
 * locking in kgnilnd_complete_closed_conn. We are free then to mark the
 * conn DESTROY_EP (add #6 for schedule_conn), then lose #5 in
 * kgnilnd_process_conns. Then the next scheduler loop would call
 * kgnilnd_destroy_conn_ep (drop #2 for EP) and lose #6 (refcount=0) in
 * kgnilnd_process_conns.
 *
 * Clearly, we are totally safe. Clearly.
 */

#define kgnilnd_conn_decref(conn)					\
do {									\
	int val;							\
									\
	smp_wmb();							\
	val = atomic_dec_return(&conn->gnc_refcount);			\
	LASSERTF(val >= 0, "conn %px refc %d to %s\n",			\
		conn, val,						\
		conn->gnc_peer						\
			? libcfs_nid2str(conn->gnc_peer->gnp_nid)	\
			: "<?>");					\
	CDEBUG(D_NETTRACE, "conn %p->%s-- (%d)\n", conn,		\
		conn->gnc_peer						\
			? libcfs_nid2str(conn->gnc_peer->gnp_nid)	\
			: "<?>",					\
		val);							\
	smp_rmb();							\
	if ((val == 1) &&						\
	    (conn->gnc_ephandle != NULL) &&				\
	    (conn->gnc_state != GNILND_CONN_DESTROY_EP)) {		\
		set_mb(conn->gnc_state, GNILND_CONN_DESTROY_EP);	\
		kgnilnd_schedule_conn(conn);				\
	} else if (val == 0) {						\
		kgnilnd_destroy_conn(conn);				\
	}								\
} while (0)

static inline struct list_head *
kgnilnd_nid2peerlist(lnet_nid_t nid)
{
	unsigned int hash = ((unsigned int)LNET_NIDADDR(nid)) % *kgnilnd_tunables.kgn_peer_hash_size;

	RETURN(&kgnilnd_data.kgn_peers[hash]);
}

static inline struct list_head *
kgnilnd_netnum2netlist(__u16 netnum)
{
	unsigned int hash = ((unsigned int) netnum) % *kgnilnd_tunables.kgn_net_hash_size;

	RETURN(&kgnilnd_data.kgn_nets[hash]);
}

static inline int
kgnilnd_peer_active(kgn_peer_t *peer)
{
	
	return (!list_empty(&peer->gnp_list));
}


static inline int
kgnilnd_can_unlink_peer_locked(kgn_peer_t *peer)
{
	CDEBUG(D_NET, "peer 0x%p->%s conns? %d tx? %d\n",
		peer, libcfs_nid2str(peer->gnp_nid),
		!list_empty(&peer->gnp_conns),
		!list_empty(&peer->gnp_tx_queue));

	/* kgn_peer_conn_lock protects us from conflict with
	 * kgnilnd_peer_notify and gnp_persistent */
	RETURN ((list_empty(&peer->gnp_conns)) &&
		(list_empty(&peer->gnp_tx_queue)));
}


static inline int
kgnilnd_conn_clean_errno(int errno)
{
	/*  - ESHUTDOWN - LND is unloading
	 *  - EUCLEAN - admin requested via "lctl del_peer"
	 *  - ENETRESET - admin requested via "lctl disconnect" or rca event
	 *  - ENOTRECOVERABLE - stack reset
	 *  - EISCONN - cleared via "lctl push"
	 *  not doing ESTALE - that isn't clean */
	RETURN ((errno == 0) ||
		(errno == -ESHUTDOWN) ||
		(errno == -EUCLEAN) ||
		(errno == -ENETRESET) ||
		(errno == -EISCONN) ||
		(errno == -ENOTRECOVERABLE));
}


static inline int
kgnilnd_check_purgatory_errno(int errno)
{
	/* We don't want to save the purgatory lists these cases:
	 *  - EUCLEAN - admin requested via "lctl del_peer"
	 *  - ESHUTDOWN - LND is unloading
	 */
	RETURN ((errno != -ESHUTDOWN) &&
		(errno != -EUCLEAN));

}


static inline int
kgnilnd_check_purgatory_conn(kgn_conn_t *conn)
{
	int loopback = 0;

	if (conn->gnc_peer) {
		loopback = conn->gnc_peer->gnp_nid ==
			lnet_nid_to_nid4(&conn->gnc_peer->gnp_net->gnn_ni->ni_nid);
	} else {
		/* short circuit - a conn that didn't complete
		 * setup never needs a purgatory hold */
		RETURN(0);
	}
	CDEBUG(D_NETTRACE, "conn 0x%p->%s loopback %d close_recvd %d\n",
		conn, conn->gnc_peer ?
				libcfs_nid2str(conn->gnc_peer->gnp_nid) :
				"<?>",
		loopback, conn->gnc_close_recvd);

	/* we only use a purgatory hold if we've not received the CLOSE msg
	 * from our peer - without that message, we can't know the state of
	 * the other end of this connection and must put it into purgatory
	 * to prevent reuse and corruption.
	 * The theory is that a TX error can be communicated in all other cases
	 */
	RETURN(likely(!loopback) && !conn->gnc_close_recvd &&
		kgnilnd_check_purgatory_errno(conn->gnc_error));
}

static inline const char *
kgnilnd_tx_state2str(kgn_tx_list_state_t state);

static inline struct list_head *
kgnilnd_tx_state2list(kgn_peer_t *peer, kgn_conn_t *conn,
			kgn_tx_list_state_t to_state)
{
	switch (to_state) {
	case GNILND_TX_PEERQ:
		return &peer->gnp_tx_queue;
	case GNILND_TX_FMAQ:
		return &conn->gnc_fmaq;
	case GNILND_TX_LIVE_FMAQ:
	case GNILND_TX_LIVE_RDMAQ:
	case GNILND_TX_DYING:
		return NULL;
	case GNILND_TX_MAPQ:
		return &conn->gnc_device->gnd_map_tx;
	case GNILND_TX_RDMAQ:
		return &conn->gnc_device->gnd_rdmaq;
	default:
		
		CERROR("invalid state requested: %s\n",
			kgnilnd_tx_state2str(to_state));
		LBUG();
		break;
	}
}


static inline void
kgnilnd_tx_add_state_locked(kgn_tx_t *tx, kgn_peer_t *peer,
			kgn_conn_t *conn, kgn_tx_list_state_t state,
			int add_tail)
{
	struct list_head        *list = NULL;

	
	GNITX_ASSERTF(tx, (tx->tx_list_p == NULL &&
		  tx->tx_list_state == GNILND_TX_ALLOCD) &&
		list_empty(&tx->tx_list),
		"bad state with tx_list %s",
		list_empty(&tx->tx_list) ? "empty" : "not empty");

	
	GNITX_ASSERTF(tx, state != tx->tx_list_state,
		      "already at %s", kgnilnd_tx_state2str(state));

	
	list = kgnilnd_tx_state2list(peer, conn, state);

	
	switch (state) {
	case GNILND_TX_PEERQ:
		kgnilnd_peer_addref(peer);
		break;
	case GNILND_TX_ALLOCD:
		
		break;
	case GNILND_TX_FMAQ:
		kgnilnd_conn_addref(conn);
		break;
	case GNILND_TX_MAPQ:
		atomic_inc(&conn->gnc_device->gnd_nq_map);
		kgnilnd_conn_addref(conn);
		break;
	case GNILND_TX_LIVE_FMAQ:
		atomic_inc(&conn->gnc_nlive_fma);
		kgnilnd_conn_addref(conn);
		break;
	case GNILND_TX_LIVE_RDMAQ:
		atomic_inc(&conn->gnc_nlive_rdma);
		kgnilnd_conn_addref(conn);
		break;
	case GNILND_TX_RDMAQ:
		atomic_inc(&conn->gnc_nq_rdma);
		kgnilnd_conn_addref(conn);
		break;
	case GNILND_TX_DYING:
		kgnilnd_conn_addref(conn);
		break;
	default:
		CERROR("invalid state requested: %s\n",
			kgnilnd_tx_state2str(state));
		LBUG();
		break;;
	}

	
	tx->tx_list_state = state;

	/* some states don't have lists - we track them in the per conn
	 * TX table instead. Waste not, want not! */
	if (list != NULL) {
		tx->tx_list_p = list;
		if (add_tail)
			list_add_tail(&tx->tx_list, list);
		else
			list_add(&tx->tx_list, list);
	} else {
		/* set dummy list_p to make book keeping happy and let debugging
		 * be a hair easier */
		tx->tx_list_p = (void *)state;
	}

	GNIDBG_TX(D_NET, tx, "onto %s->0x%p",
		  kgnilnd_tx_state2str(state), list);
}

static inline void
kgnilnd_tx_del_state_locked(kgn_tx_t *tx, kgn_peer_t *peer,
			kgn_conn_t *conn, kgn_tx_list_state_t new_state)
{
	
	GNITX_ASSERTF(tx, new_state == GNILND_TX_ALLOCD,
		      "invalid new_state %s", kgnilnd_tx_state2str(new_state));

	/* new_state == ALLOCD means we are deallocating this tx,
	 * so make sure it was on a valid list to start with */
	GNITX_ASSERTF(tx, (tx->tx_list_p != NULL) &&
		      (((tx->tx_list_state == GNILND_TX_LIVE_FMAQ) ||
			(tx->tx_list_state == GNILND_TX_LIVE_RDMAQ) ||
			(tx->tx_list_state == GNILND_TX_DYING)) == list_empty(&tx->tx_list)),
		      "bad state", NULL);

	GNIDBG_TX(D_NET, tx, "off %p", tx->tx_list_p);

	
	switch (tx->tx_list_state) {
	case GNILND_TX_PEERQ:
		kgnilnd_peer_decref(peer);
		break;
	case GNILND_TX_FREED:
	case GNILND_TX_IDLE:
	case GNILND_TX_ALLOCD:
		
		break;
	case GNILND_TX_DYING:
		kgnilnd_conn_decref(conn);
		break;
	case GNILND_TX_FMAQ:
		kgnilnd_conn_decref(conn);
		break;
	case GNILND_TX_MAPQ:
		atomic_dec(&conn->gnc_device->gnd_nq_map);
		kgnilnd_conn_decref(conn);
		break;
	case GNILND_TX_LIVE_FMAQ:
		atomic_dec(&conn->gnc_nlive_fma);
		kgnilnd_conn_decref(conn);
		break;
	case GNILND_TX_LIVE_RDMAQ:
		atomic_dec(&conn->gnc_nlive_rdma);
		kgnilnd_conn_decref(conn);
		break;
	case GNILND_TX_RDMAQ:
		atomic_dec(&conn->gnc_nq_rdma);
		kgnilnd_conn_decref(conn);
	
	}

	
	list_del_init(&tx->tx_list);
	tx->tx_list_p = NULL;
	tx->tx_list_state = new_state;
}

static inline int
kgnilnd_tx_mapped(kgn_tx_t *tx)
{
	return tx->tx_buftype == GNILND_BUF_PHYS_MAPPED;
}

static inline struct list_head *
kgnilnd_cqid2connlist(__u32 cqid)
{
	unsigned int hash = cqid % *kgnilnd_tunables.kgn_peer_hash_size;

	return (&kgnilnd_data.kgn_conns [hash]);
}

static inline kgn_conn_t *
kgnilnd_cqid2conn_locked(__u32 cqid)
{
	struct list_head *conns = kgnilnd_cqid2connlist(cqid);
	struct list_head *tmp;
	kgn_conn_t       *conn;

	list_for_each(tmp, conns) {
		conn = list_entry(tmp, kgn_conn_t, gnc_hashlist);

		if (conn->gnc_cqid == cqid)
			return conn;
	}

	return NULL;
}


static inline __u32
kgnilnd_get_cqid_locked(void)
{
	int     looped = 0;
	__u32   cqid;

	do {
		cqid = kgnilnd_data.kgn_next_cqid++;
		if (kgnilnd_data.kgn_next_cqid >= GNILND_MAX_CQID) {
			if (looped) {
				return 0;
			}
			kgnilnd_data.kgn_next_cqid = 1;
			looped = 1;
		}
	} while (kgnilnd_cqid2conn_locked(cqid) != NULL);

	return cqid;
}

static inline void
kgnilnd_validate_tx_ev_id(kgn_tx_ev_id_t *ev_id, kgn_tx_t **txp, kgn_conn_t **connp)
{
	kgn_tx_t        *tx = NULL;
	kgn_conn_t      *conn = NULL;

	
	*txp = NULL;
	*connp = NULL;

	LASSERTF((ev_id->txe_idx > 0) &&
		 (ev_id->txe_idx < GNILND_MAX_MSG_ID),
		"bogus txe_idx %d >= %d\n",
		ev_id->txe_idx, GNILND_MAX_MSG_ID);

	LASSERTF((ev_id->txe_cqid > 0) &&
		 (ev_id->txe_cqid < GNILND_MAX_CQID),
		"bogus txe_cqid %d >= %d\n",
		ev_id->txe_cqid, GNILND_MAX_CQID);

	read_lock(&kgnilnd_data.kgn_peer_conn_lock);
	conn = kgnilnd_cqid2conn_locked(ev_id->txe_cqid);

	if (conn == NULL) {
		
		read_unlock(&kgnilnd_data.kgn_peer_conn_lock);
		CDEBUG(D_NET, "CQID %d lookup failed\n", ev_id->txe_cqid);
		return;
	}
	
	kgnilnd_conn_addref(conn);
	kgnilnd_admin_addref(conn->gnc_tx_in_use);
	read_unlock(&kgnilnd_data.kgn_peer_conn_lock);

	/* we know this is safe - as the TX won't be reused until AFTER
	 * the conn is unlinked from the cqid hash, so we can use the TX
	 * (serializing to avoid any cache oddness) freely from the conn tx ref table */

	spin_lock(&conn->gnc_tx_lock);
	tx = conn->gnc_tx_ref_table[ev_id->txe_idx];
	spin_unlock(&conn->gnc_tx_lock);

	/* We could have a tx that was cleared out by other forces
	 * lctl disconnect or del_peer. */
	if (tx == NULL) {
		CNETERR("txe_idx %d is gone, ignoring event\n", ev_id->txe_idx);
		kgnilnd_admin_decref(conn->gnc_tx_in_use);
		kgnilnd_conn_decref(conn);
		return;
	}

	
	GNITX_ASSERTF(tx, tx->tx_msg.gnm_magic == GNILND_MSG_MAGIC,
		      "came back from kgni with bad magic %x", tx->tx_msg.gnm_magic);

	GNITX_ASSERTF(tx, tx->tx_id.txe_idx == ev_id->txe_idx,
		      "conn 0x%p->%s tx_ref_table hosed: wanted txe_idx %d "
		      "found tx %px txe_idx %d",
		      conn, libcfs_nid2str(conn->gnc_peer->gnp_nid),
		      ev_id->txe_idx, tx, tx->tx_id.txe_idx);

	GNITX_ASSERTF(tx, tx->tx_conn != NULL, "tx with NULL connection", NULL);

	GNITX_ASSERTF(tx, tx->tx_conn == conn, "tx conn does not equal conn", NULL);

	*txp = tx;
	*connp = conn;

	GNIDBG_TX(D_NET, tx, "validated to 0x%p", conn);
}

/* set_normalized_timepsec isn't exported from the kernel, so
 * we need to do the same thing inline */
static inline struct timespec
kgnilnd_ts_sub(struct timespec lhs, struct timespec rhs)
{
	time_t                  sec;
	long                    nsec;
	struct timespec         ts;

	sec = lhs.tv_sec - rhs.tv_sec;
	nsec = lhs.tv_nsec - rhs.tv_nsec;

	while (nsec >= NSEC_PER_SEC) {
		nsec -= NSEC_PER_SEC;
		++sec;
	}
	while (nsec < 0) {
		nsec += NSEC_PER_SEC;
		--sec;
	}
	ts.tv_sec = sec;
	ts.tv_nsec = nsec;
	return ts;
}

static inline int
kgnilnd_count_list(struct list_head *q)
{
	struct list_head *e;
	int               n = 0;

	list_for_each(e, q) {
		n++;
	}

	return n;
}

/* kgnilnd_find_net adds a reference to the net it finds
 * this is so the net will not be removed before the calling function
 * has time to use the data returned. This reference needs to be released
 * by the calling function once it has finished using the returned net
 */

static inline int
kgnilnd_find_net(lnet_nid_t nid, kgn_net_t **netp)
{
	kgn_net_t *net;
	int rc;

	rc = down_read_trylock(&kgnilnd_data.kgn_net_rw_sem);

	if (!rc) {
		return -ESHUTDOWN;
	}

	list_for_each_entry(net,
			    kgnilnd_netnum2netlist(LNET_NETNUM(LNET_NIDNET(nid))),
			    gnn_list) {
		if (!net->gnn_shutdown &&
		    LNET_NID_NET(&net->gnn_ni->ni_nid) == LNET_NIDNET(nid)) {
			kgnilnd_net_addref(net);
			up_read(&kgnilnd_data.kgn_net_rw_sem);
			*netp = net;
			return 0;
		}
	}

	up_read(&kgnilnd_data.kgn_net_rw_sem);

	return -ENONET;
}

#ifdef CONFIG_DEBUG_SLAB
#define KGNILND_POISON(ptr, c, s) do {} while(0)
#else
#define KGNILND_POISON(ptr, c, s) memset(ptr, c, s)
#endif

#define CURRENT_LND_VERSION 1

enum kgnilnd_ni_lnd_tunables_attr {
	LNET_NET_GNILND_TUNABLES_ATTR_UNSPEC = 0,

	LNET_NET_GNILND_TUNABLES_ATTR_LND_TIMEOUT,
	__LNET_NET_GNILND_TUNABLES_ATTR_MAX_PLUS_ONE,
};

#define LNET_NET_GNILND_TUNABLES_ATTR_MAX (__LNET_NET_GNILND_TUNABLES_ATTR_MAX_PLUS_ONE - 1)

int kgnilnd_dev_init(kgn_device_t *dev);
void kgnilnd_dev_fini(kgn_device_t *dev);
int kgnilnd_startup(struct lnet_ni *ni);
void kgnilnd_shutdown(struct lnet_ni *ni);
int kgnilnd_base_startup(void);
void kgnilnd_base_shutdown(void);

int kgnilnd_allocate_phys_fmablk(kgn_device_t *device);
int kgnilnd_map_phys_fmablk(kgn_device_t *device);
void kgnilnd_unmap_fma_blocks(kgn_device_t *device);
void kgnilnd_free_phys_fmablk(kgn_device_t *device);

int kgnilnd_ctl(struct lnet_ni *ni, unsigned int cmd, void *arg);
int kgnilnd_send(struct lnet_ni *ni, void *private, struct lnet_msg *lntmsg);
int kgnilnd_eager_recv(struct lnet_ni *ni, void *private,
			struct lnet_msg *lntmsg, void **new_private);
int kgnilnd_recv(struct lnet_ni *ni, void *private, struct lnet_msg *lntmsg,
		int delayed, unsigned int niov,
		struct bio_vec *kiov,
		unsigned int offset, unsigned int mlen, unsigned int rlen);

__u16 kgnilnd_cksum_kiov(unsigned int nkiov, struct bio_vec *kiov,
			 unsigned int offset, unsigned int nob, int dump_blob);


void kgnilnd_add_purgatory_locked(kgn_conn_t *conn, kgn_peer_t *peer);
void kgnilnd_mark_for_detach_purgatory_all_locked(kgn_peer_t *peer);
void kgnilnd_detach_purgatory_locked(kgn_conn_t *conn, struct list_head *conn_list);
void kgnilnd_release_purgatory_list(struct list_head *conn_list);

void kgnilnd_update_reaper_timeout(long timeout);
void kgnilnd_unmap_buffer(kgn_tx_t *tx, int error);
kgn_tx_t *kgnilnd_new_tx_msg(int type, lnet_nid_t source);
void kgnilnd_tx_done(kgn_tx_t *tx, int completion);
void kgnilnd_txlist_done(struct list_head *txlist, int error);
void kgnilnd_unlink_peer_locked(kgn_peer_t *peer);
int _kgnilnd_schedule_conn(kgn_conn_t *conn, const char *caller, int line, int refheld, int lock_held);
int kgnilnd_schedule_process_conn(kgn_conn_t *conn, int sched_intent);

void kgnilnd_schedule_dgram(kgn_device_t *dev);
int kgnilnd_create_peer_safe(kgn_peer_t **peerp, lnet_nid_t nid, kgn_net_t *net, int node_state);
void kgnilnd_add_peer_locked(lnet_nid_t nid, kgn_peer_t *new_stub_peer, kgn_peer_t **peerp);
int kgnilnd_add_peer(kgn_net_t *net, lnet_nid_t nid, kgn_peer_t **peerp);

kgn_peer_t *kgnilnd_find_peer_locked(lnet_nid_t nid);
int kgnilnd_del_conn_or_peer(kgn_net_t *net, lnet_nid_t nid, int command, int error);
void kgnilnd_peer_increase_reconnect_locked(kgn_peer_t *peer);
void kgnilnd_queue_reply(kgn_conn_t *conn, kgn_tx_t *tx);
void kgnilnd_queue_tx(kgn_conn_t *conn, kgn_tx_t *tx);
void kgnilnd_launch_tx(kgn_tx_t *tx, kgn_net_t *net,
		       struct lnet_processid *target);
int kgnilnd_send_mapped_tx(kgn_tx_t *tx, int try_map_if_full);
void kgnilnd_consume_rx(kgn_rx_t *rx);

void kgnilnd_schedule_device(kgn_device_t *dev);
void kgnilnd_device_callback(__u32 devid, __u64 arg);
void kgnilnd_schedule_device_timer(cfs_timer_cb_arg_t data);
void kgnilnd_schedule_device_timer_rd(cfs_timer_cb_arg_t data);

int kgnilnd_reaper(void *arg);
int kgnilnd_scheduler(void *arg);
int kgnilnd_dgram_mover(void *arg);
int kgnilnd_rca(void *arg);
int kgnilnd_thread_start(int(*fn)(void *arg), void *arg, char *name, int id);

int kgnilnd_create_conn(kgn_conn_t **connp, kgn_device_t *dev);
int kgnilnd_conn_isdup_locked(kgn_peer_t *peer, kgn_conn_t *newconn);
kgn_conn_t *kgnilnd_find_conn_locked(kgn_peer_t *peer);
int kgnilnd_get_conn(kgn_conn_t **connp, kgn_peer_t);
kgn_conn_t *kgnilnd_find_or_create_conn_locked(kgn_peer_t *peer);
void kgnilnd_peer_cancel_tx_queue(kgn_peer_t *peer);
void kgnilnd_cancel_peer_connect_locked(kgn_peer_t *peer, struct list_head *zombies);
int kgnilnd_close_stale_conns_locked(kgn_peer_t *peer, kgn_conn_t *newconn);
void kgnilnd_peer_alive(kgn_peer_t *peer);
void kgnilnd_peer_notify(kgn_peer_t *peer, int error, int alive);
void kgnilnd_close_conn_locked(kgn_conn_t *conn, int error);
void kgnilnd_close_conn(kgn_conn_t *conn, int error);
void kgnilnd_complete_closed_conn(kgn_conn_t *conn);
void kgnilnd_destroy_conn_ep(kgn_conn_t *conn);

int kgnilnd_close_peer_conns_locked(kgn_peer_t *peer, int why);
int kgnilnd_report_node_state(lnet_nid_t nid, int down);
void kgnilnd_wakeup_rca_thread(void);
int kgnilnd_start_rca_thread(void);
int kgnilnd_get_node_state(__u32 nid);

int kgnilnd_tunables_setup(struct lnet_ni *ni);
int kgnilnd_tunables_init(void);

void kgnilnd_init_msg(kgn_msg_t *msg, int type, lnet_nid_t source);

void kgnilnd_bump_timeouts(__u32 nap_time, char *reason);
void kgnilnd_pause_threads(void);
int kgnilnd_hw_in_quiesce(void);
int kgnilnd_check_hw_quiesce(void);
void kgnilnd_quiesce_wait(char *reason);
void kgnilnd_quiesce_end_callback(gni_nic_handle_t nic_handle, uint64_t msecs);
int kgnilnd_ruhroh_thread(void *arg);
void kgnilnd_reset_stack(void);
void kgnilnd_critical_error(gni_err_handle_t err_handle);

void kgnilnd_insert_sysctl(void);
void kgnilnd_remove_sysctl(void);
void kgnilnd_proc_init(void);
void kgnilnd_proc_fini(void);


void kgnilnd_release_mbox(kgn_conn_t *conn, int purgatory_hold);

int kgnilnd_find_and_cancel_dgram(kgn_device_t *dev, lnet_nid_t dst_nid);
void kgnilnd_cancel_dgram_locked(kgn_dgram_t *dgram);
void kgnilnd_release_dgram(kgn_device_t *dev, kgn_dgram_t *dgram, int shutdown);

int kgnilnd_setup_wildcard_dgram(kgn_device_t *dev);
int kgnilnd_cancel_net_dgrams(kgn_net_t *net);
int kgnilnd_cancel_wc_dgrams(kgn_device_t *dev);
int kgnilnd_cancel_dgrams(kgn_device_t *dev);
void kgnilnd_wait_for_canceled_dgrams(kgn_device_t *dev);

int kgnilnd_dgram_waitq(void *arg);

int kgnilnd_set_conn_params(kgn_dgram_t *dgram);

/* struct2str functions - we don't use a default: case to cause the compile
 * to fail if there is a missing case. This allows us to hide these down here
 * out of the way but ensure we'll catch any updates to the enum/types
 * above */

static inline const char *
kgnilnd_fmablk_state2str(kgn_fmablk_state_t state)
{
	
	switch (state) {
	case GNILND_FMABLK_IDLE:
		return "I";
	case GNILND_FMABLK_PHYS:
		return "P";
	case GNILND_FMABLK_VIRT:
		return "V";
	case GNILND_FMABLK_FREED:
		return "F";
	}
	return "<unknown state>";
}

static inline const char *
kgnilnd_msgtype2str(int type)
{
	switch (type) {
		ENUM2STR(GNILND_MSG_NONE);
		ENUM2STR(GNILND_MSG_NOOP);
		ENUM2STR(GNILND_MSG_IMMEDIATE);
		ENUM2STR(GNILND_MSG_PUT_REQ);
		ENUM2STR(GNILND_MSG_PUT_NAK);
		ENUM2STR(GNILND_MSG_PUT_ACK);
		ENUM2STR(GNILND_MSG_PUT_DONE);
		ENUM2STR(GNILND_MSG_GET_REQ);
		ENUM2STR(GNILND_MSG_GET_NAK);
		ENUM2STR(GNILND_MSG_GET_DONE);
		ENUM2STR(GNILND_MSG_CLOSE);
		ENUM2STR(GNILND_MSG_PUT_REQ_REV);
		ENUM2STR(GNILND_MSG_PUT_DONE_REV);
		ENUM2STR(GNILND_MSG_PUT_NAK_REV);
		ENUM2STR(GNILND_MSG_GET_REQ_REV);
		ENUM2STR(GNILND_MSG_GET_ACK_REV);
		ENUM2STR(GNILND_MSG_GET_DONE_REV);
		ENUM2STR(GNILND_MSG_GET_NAK_REV);
	}
	return "<unknown msg type>";
}

static inline const char *
kgnilnd_tx_state2str(kgn_tx_list_state_t state)
{
	switch (state) {
		ENUM2STR(GNILND_TX_IDLE);
		ENUM2STR(GNILND_TX_ALLOCD);
		ENUM2STR(GNILND_TX_PEERQ);
		ENUM2STR(GNILND_TX_MAPQ);
		ENUM2STR(GNILND_TX_FMAQ);
		ENUM2STR(GNILND_TX_LIVE_FMAQ);
		ENUM2STR(GNILND_TX_RDMAQ);
		ENUM2STR(GNILND_TX_LIVE_RDMAQ);
		ENUM2STR(GNILND_TX_DYING);
		ENUM2STR(GNILND_TX_FREED);
	}
	return "<unknown state>";
}

static inline const char *
kgnilnd_conn_state2str(kgn_conn_t *conn)
{
	kgn_conn_state_t state = conn->gnc_state;
	switch (state) {
		ENUM2STR(GNILND_CONN_DUMMY);
		ENUM2STR(GNILND_CONN_LISTEN);
		ENUM2STR(GNILND_CONN_CONNECTING);
		ENUM2STR(GNILND_CONN_ESTABLISHED);
		ENUM2STR(GNILND_CONN_CLOSING);
		ENUM2STR(GNILND_CONN_CLOSED);
		ENUM2STR(GNILND_CONN_DONE);
		ENUM2STR(GNILND_CONN_DESTROY_EP);
	}
	return "<?state?>";
}

static inline const char *
kgnilnd_connreq_type2str(kgn_connreq_t *connreq)
{
	kgn_connreq_type_t type = connreq->gncr_type;

	switch (type) {
		ENUM2STR(GNILND_CONNREQ_REQ);
		ENUM2STR(GNILND_CONNREQ_NAK);
		ENUM2STR(GNILND_CONNREQ_CLOSE);
	}
	return "<?type?>";
}

static inline const char *
kgnilnd_dgram_state2str(kgn_dgram_t *dgram)
{
	kgn_dgram_state_t state = dgram->gndg_state;

	switch (state) {
		ENUM2STR(GNILND_DGRAM_USED);
		ENUM2STR(GNILND_DGRAM_POSTING);
		ENUM2STR(GNILND_DGRAM_POSTED);
		ENUM2STR(GNILND_DGRAM_PROCESSING);
		ENUM2STR(GNILND_DGRAM_DONE);
		ENUM2STR(GNILND_DGRAM_CANCELED);
	}
	return "<?state?>";
}

static inline const char *
kgnilnd_dgram_type2str(kgn_dgram_t *dgram)
{
	kgn_dgram_type_t type = dgram->gndg_type;

	switch (type) {
		ENUM2STR(GNILND_DGRAM_REQ);
		ENUM2STR(GNILND_DGRAM_WC_REQ);
		ENUM2STR(GNILND_DGRAM_NAK);
		ENUM2STR(GNILND_DGRAM_CLOSE);
	}
	return "<?type?>";
}

static inline const char *
kgnilnd_conn_dgram_type2str(kgn_dgram_type_t type)
{
	switch (type) {
		ENUM2STR(GNILND_DGRAM_REQ);
		ENUM2STR(GNILND_DGRAM_WC_REQ);
		ENUM2STR(GNILND_DGRAM_NAK);
		ENUM2STR(GNILND_DGRAM_CLOSE);
	}
	return "<?type?>";
}

/* pulls in tunables per platform and adds in nid/nic conversion
 * if RCA wasn't available at build time */
#include "gnilnd_hss_ops.h"

#include "gnilnd_api_wrap.h"

#if defined(CONFIG_CRAY_GEMINI)
 #include "gnilnd_gemini.h"
#elif defined(CONFIG_CRAY_ARIES)
 #include "gnilnd_aries.h"
#else
 #error "Undefined Network Hardware Type"
#endif

extern uint32_t kgni_driver_version;

static inline void
kgnilnd_check_kgni_version(void)
{
	uint32_t *kdv;

	kgnilnd_data.kgn_enable_gl_mutex = 1;
	kdv = symbol_get(kgni_driver_version);
	if (!kdv) {
		LCONSOLE_INFO("Not using thread safe locking -"
			" no symbol kgni_driver_version\n");
		return;
	}

	
	if (*kdv < GNI_VERSION_CHECK(0, GNILND_KGNI_TS_MINOR_VER, 0xb9)) {
		symbol_put(kgni_driver_version);
		LCONSOLE_INFO("Not using thread safe locking, gni version 0x%x,"
			" need >= 0x%x\n", *kdv,
			GNI_VERSION_CHECK(0, GNILND_KGNI_TS_MINOR_VER, 0xb9));
		return;
	}

	symbol_put(kgni_driver_version);

	if (!*kgnilnd_tunables.kgn_thread_safe) {
		return;
	}

	
	kgnilnd_data.kgn_enable_gl_mutex = 0;
}

#endif 
