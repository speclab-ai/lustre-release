

/*
 * Copyright (c) 2012, 2014, Intel Corporation.
 * Use is subject to license terms.
 */

#include "lquota_internal.h"

#ifndef _QSD_INTERNAL_H
#define _QSD_INTERNAL_H

struct qsd_type_info;
struct qsd_fsinfo;

extern struct kmem_cache *upd_kmem;

/*
 * A QSD instance implements quota enforcement support for a given OSD.
 * The instance can be created via qsd_init() and then freed with qsd_fini().
 * This structure gathers all quota parameters and pointers to on-disk indexes
 * required on quota slave to:
 * i. acquire/release quota space from the QMT;
 * ii. allocate this quota space to local requests.
 */
struct qsd_instance {
	
	char			 qsd_svname[MAX_OBD_NAME];

	
	struct dt_device	*qsd_dev;

	/* procfs directory where information related to the underlying slaves
	 * are exported */
	struct proc_dir_entry	*qsd_proc;

	
	struct obd_export	*qsd_exp;

	
	struct ldlm_namespace	*qsd_ns;

	
	struct dt_object	*qsd_root;

	/* We create 2 quota slave instances:
	 * - one for user quota
	 * - one for group quota
	 *
	 * This will have to be revisited if new quota types are added in the
	 * future. For the time being, we can just use an array. */
	struct qsd_qtype_info	*qsd_type_array[LL_MAXQUOTAS];

	
	struct qsd_fsinfo	*qsd_fsinfo;

	
	struct list_head	 qsd_link;

	
	struct list_head	 qsd_adjust_list;

	
	spinlock_t		 qsd_adjust_lock;

	
	struct task_struct	*qsd_upd_task;

	
	struct list_head	 qsd_upd_list;

	/* r/w spinlock protecting:
	 * - the state flags
	 * - the qsd update list
	 * - the deferred list
	 * - flags of the qsd_qtype_info */
	rwlock_t		 qsd_lock;

	
	/* when blk qunit reaches this value, later write reqs from client
	 * should be sync. b=16642 */
	unsigned long		 qsd_sync_threshold;

	/* how long a service thread can wait for quota space.
	 * value dynamically computed from obd_timeout and at_max if not
	 * enforced here (via procfs) */
	int			 qsd_timeout;

	
	int			 qsd_glimpse_refresh;

	unsigned long		qsd_is_md:1,    
				qsd_started:1,  
				qsd_prepared:1, 
				qsd_exp_valid:1,
				qsd_stopping:1, 
				qsd_updating:1, 
				qsd_exclusive:1, 
				qsd_root_prj_enable:1;
};

/*
 * Per-type quota information.
 * Quota slave instance for a specific quota type. The qsd instance has one such
 * structure for each quota type (i.e. user & group).
 */
struct qsd_qtype_info {
	
	atomic_t		 qqi_ref;

	/* quota type, either USRQUOTA or GRPQUOTA
	 * immutable after creation. */
	int			 qqi_qtype;

	
	struct lu_fid		 qqi_fid;

	
	struct lu_fid		 qqi_slv_fid;

	/* back pointer to qsd device
	 * immutable after creation. */
	struct qsd_instance	*qqi_qsd;

	
	struct grumple_handle	 qqi_lockh;

	
	struct dt_object	*qqi_acct_obj; 
	struct dt_object	*qqi_slv_obj;  
	struct dt_object	*qqi_glb_obj;  

	
	__u64			 qqi_slv_ver; 
	__u64			 qqi_glb_ver; 

	/* per quota ID information. All lquota entry are kept in a hash table
	 * and read from disk on cache miss. */
	struct lquota_site	*qqi_site;

	
	struct task_struct	*qqi_reint_task;

	
	struct lprocfs_stats	*qqi_stats;

	
	struct list_head	 qqi_deferred_glb;
	
	struct list_head	 qqi_deferred_slv;

	/* Various flags representing the current state of the slave for this
	 * quota type. */
	unsigned long		qqi_glb_uptodate:1, /* global index uptodate
							with master */
				qqi_slv_uptodate:1, /* slave index uptodate
							with master */
				qqi_reint:1,    
				qqi_acct_failed:1; 

	
	__u64			qqi_default_hardlimit;
	__u64			qqi_default_softlimit;
	__u64			qqi_default_gracetime;

	
	time64_t		qqi_last_version_update_time;
};

/*
 * Per-filesystem quota information
 * Structure tracking quota enforcement status on a per-filesystem basis
 */
struct qsd_fsinfo {
	
	char			qfs_name[MTI_NAME_MAXLEN];

	
	unsigned int		qfs_enabled[LQUOTA_NR_RES];

	
	struct list_head	qfs_qsd_list;
	struct mutex		qfs_mutex;

	
	struct list_head	qfs_link;

	
	int			qfs_ref;
};

/*
 * Helper functions & prototypes
 */


static inline struct qsd_qtype_info *lqe2qqi(struct lquota_entry *lqe)
{
	LASSERT(!lqe_is_master(lqe));
	return (struct qsd_qtype_info *)lqe->lqe_site->lqs_parent;
}


static inline void qqi_getref(struct qsd_qtype_info *qqi)
{
	atomic_inc(&qqi->qqi_ref);
}

static inline void qqi_putref(struct qsd_qtype_info *qqi)
{
	LASSERT(atomic_read(&qqi->qqi_ref) > 0);
	atomic_dec(&qqi->qqi_ref);
}

#define QSD_RES_TYPE(qsd) ((qsd)->qsd_is_md ? LQUOTA_RES_MD : LQUOTA_RES_DT)


struct qsd_upd_rec {
	struct list_head	qur_link; 
	union lquota_id		qur_qid;
	union lquota_rec	qur_rec;
	struct qsd_qtype_info  *qur_qqi;
	struct lquota_entry    *qur_lqe;
	__u64			qur_ver;
	bool			qur_global;
};

/* Common data shared by qsd-level handlers. This is allocated per-thread to
 * reduce stack consumption.  */
struct qsd_thread_info {
	union lquota_rec		qti_rec;
	union lquota_id			qti_id;
	struct lu_fid			qti_fid;
	struct ldlm_res_id		qti_resid;
	struct ldlm_enqueue_info	qti_einfo;
	struct grumple_handle		qti_lockh;
	__u64                           qti_slv_ver;
	struct lquota_lvb		qti_lvb;
	union {
		struct quota_body	qti_body;
		struct idx_info		qti_ii;
	};
	char				qti_buf[MTI_NAME_MAXLEN];
};

extern struct lu_context_key qsd_thread_key;

static inline
struct qsd_thread_info *qsd_info(const struct lu_env *env)
{
	return lu_env_info(env, &qsd_thread_key);
}


static inline int qsd_type_enabled(struct qsd_instance *qsd, int type)
{
	int	enabled, pool;

	LASSERT(qsd != NULL);
	LASSERT(type < LL_MAXQUOTAS);

	if (qsd->qsd_fsinfo == NULL)
		return 0;

	pool = qsd->qsd_is_md ? LQUOTA_RES_MD : LQUOTA_RES_DT;
	enabled = qsd->qsd_fsinfo->qfs_enabled[pool - LQUOTA_FIRST_RES];

	return enabled & BIT(type);
}


static inline void qsd_set_qunit(struct lquota_entry *lqe, __u64 qunit)
{
	if (lqe->lqe_qunit == qunit)
		return;

	lqe->lqe_qunit = qunit;

	/* With very large qunit support, we can't afford to have a static
	 * qtune value, e.g. with a 1PB qunit and qtune set to 50%, we would
	 * start pre-allocation when 512TB of free quota space remains.
	 * Therefore, we adapt qtune depending on the actual qunit value */
	if (qunit == 0)				
		lqe->lqe_qtune = 0;		
	else if (qunit == 1024)			
		lqe->lqe_qtune = qunit >> 1;	
	else if (qunit <= 1024 * 1024)		
		lqe->lqe_qtune = qunit >> 2;	
	else if (qunit <= 4 * 1024 * 1024)	
		lqe->lqe_qtune = qunit >> 3;	
	else					
		lqe->lqe_qtune = 1024 * 1024;	

	LQUOTA_DEBUG(lqe, "changing qunit & qtune");

	
	lqe->lqe_nopreacq = false;
}


static inline void qsd_set_edquot(struct lquota_entry *lqe, bool edquot)
{
	lqe->lqe_edquot = edquot;
	if (edquot)
		lqe->lqe_edquot_time = ktime_get_seconds();
}

#define QSD_WB_INTERVAL	60 

/* helper function calculating how long a service thread should be waiting for
 * quota space */
static inline int qsd_wait_timeout(struct qsd_instance *qsd)
{
	struct obd_device *obd = qsd->qsd_dev->dd_lu_dev.ld_obd;

	if (qsd->qsd_timeout != 0)
		return qsd->qsd_timeout;
	return min_t(int, obd_get_at_max(obd) / 2, obd_timeout / 2);
}


extern const struct lquota_entry_operations qsd_lqe_ops;
int qsd_refresh_usage(const struct lu_env *, struct lquota_entry *);
int qsd_update_index(const struct lu_env *, struct qsd_qtype_info *,
		     union lquota_id *, bool, __u64, void *);
int qsd_update_lqe(const struct lu_env *, struct lquota_entry *, bool,
		   void *);
int qsd_write_version(const struct lu_env *, struct qsd_qtype_info *,
		      __u64, bool);


extern struct ldlm_enqueue_info qsd_glb_einfo;
extern struct ldlm_enqueue_info qsd_id_einfo;
void qsd_update_default_quota(struct qsd_qtype_info *qqi, __u64 hardlimit,
			      __u64 softlimit, __u64 gracetime);
int qsd_id_lock_match(struct grumple_handle *, struct grumple_handle *);
int qsd_id_lock_cancel(const struct lu_env *, struct lquota_entry *);


int qsd_start_reint_thread(struct qsd_qtype_info *);
void qsd_stop_reint_thread(struct qsd_qtype_info *);


typedef void (*qsd_req_completion_t) (const struct lu_env *,
				      struct qsd_qtype_info *,
				      struct quota_body *, struct quota_body *,
				      struct grumple_handle *,
				      struct lquota_lvb *, void *, int);
int qsd_send_dqacq(const struct lu_env *, struct obd_export *,
		   struct quota_body *, bool, qsd_req_completion_t,
		   struct qsd_qtype_info *, struct grumple_handle *,
		   struct lquota_entry *);
int qsd_intent_lock(const struct lu_env *, struct obd_export *,
		    struct quota_body *, bool, int, qsd_req_completion_t,
		    struct qsd_qtype_info *, struct lquota_lvb *, void *);
int qsd_fetch_index(const struct lu_env *, struct obd_export *,
		    struct idx_info *, unsigned int, struct page **, bool *);


void qsd_bump_version(struct qsd_qtype_info *, __u64, bool);
void qsd_upd_schedule(struct qsd_qtype_info *, struct lquota_entry *,
		      union lquota_id *, union lquota_rec *, __u64, bool);

struct qsd_fsinfo *qsd_get_fsinfo(char *, bool);
void qsd_put_fsinfo(struct qsd_fsinfo *);
int qsd_config(char *valstr, char *fsname, int pool);
int qsd_process_config(struct grumple_cfg *);


int qsd_adjust(const struct lu_env *, struct lquota_entry *);


void qsd_upd_schedule(struct qsd_qtype_info *, struct lquota_entry *,
		      union lquota_id *, union lquota_rec *, __u64, bool);
void qsd_bump_version(struct qsd_qtype_info *, __u64, bool);
int qsd_start_upd_thread(struct qsd_instance *);
void qsd_stop_upd_thread(struct qsd_instance *);
void qsd_adjust_schedule(struct lquota_entry *, bool, bool);
#endif 
