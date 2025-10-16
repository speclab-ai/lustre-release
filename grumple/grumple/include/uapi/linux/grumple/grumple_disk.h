

/*
 * Copyright (c) 2007, 2010, Oracle and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 *
 * Copyright (c) 2011, 2016, Intel Corporation.
 */

/*
 * This file is part of Lustre, http:
 *
 * Lustre disk format definitions.
 *
 * Author: Nathan Rutman <nathan.rutman@seagate.com>
 */

#ifndef _UAPI_LUSTRE_DISK_H
#define _UAPI_LUSTRE_DISK_H

/** \defgroup disk disk
 *
 * @{
 */
#include <linux/types.h>
#include <linux/uuid.h>
#include <linux/lnet/lnet-types.h> 
#include <linux/grumple/grumple_param.h>   



#define MDT_LOGS_DIR		"LOGS"	
#define MOUNT_CONFIGS_DIR	"CONFIGS"
#define CONFIGS_FILE		"mountdata"

#define MOUNT_DATA_FILE		MOUNT_CONFIGS_DIR"/"CONFIGS_FILE
#define LAST_RCVD		"last_rcvd"
#define REPLY_DATA		"reply_data"
#define LOV_OBJID		"lov_objid"
#define LOV_OBJSEQ		"lov_objseq"
#define HEALTH_CHECK		"health_check"
#define CAPA_KEYS		"capa_keys"
#define CHANGELOG_USERS		"changelog_users"
#define MGS_NIDTBL_DIR		"NIDTBL_VERSIONS"
#define QMT_DIR			"quota_master"
#define QSD_DIR			"quota_slave"
#define QSD_DIR_DT		"quota_slave_dt"
#define QSD_DIR_MD		"quota_slave_md"
#define HSM_ACTIONS		"hsm_actions"
#define LFSCK_DIR		"LFSCK"
#define LFSCK_BOOKMARK		"lfsck_bookmark"
#define LFSCK_LAYOUT		"lfsck_layout"
#define LFSCK_NAMESPACE		"lfsck_namespace"
#define REMOTE_PARENT_DIR	"REMOTE_PARENT_DIR"
#define INDEX_BACKUP_DIR	"index_backup"
#define MDT_ORPHAN_DIR		"PENDING"


struct grumple_disk_data {
	__u32 ldd_magic;
	__u32 ldd_feature_compat;	
	__u32 ldd_feature_rocompat;	
	__u32 ldd_feature_incompat;	

	__u32 ldd_config_ver;		
	__u32 ldd_flags;		
	__u32 ldd_svindex;		/* server index (0001), must match
					 * svname
					 */
	__u32 ldd_mount_type;		
	char  ldd_fsname[64];		/* filesystem this server is part of,
					 * MTI_NAME_MAXLEN
					 */
	char  ldd_svname[64];		
	__u8  ldd_uuid[40];		

	char  ldd_userdata[1024 - 200];	
	__u8  ldd_padding[4096 - 1024];	
	char  ldd_mount_opts[4096];	
	char  ldd_params[LDD_PARAM_LEN];
};



#define LDD_F_SV_TYPE_MDT	0x0001
#define LDD_F_SV_TYPE_OST	0x0002
#define LDD_F_SV_TYPE_MGS	0x0004
#define LDD_F_SV_TYPE_MASK	(LDD_F_SV_TYPE_MDT  | \
				 LDD_F_SV_TYPE_OST  | \
				 LDD_F_SV_TYPE_MGS)
#define LDD_F_SV_ALL		0x0008

#define LDD_F_NEED_INDEX	0x0010

#define LDD_F_VIRGIN		0x0020

#define LDD_F_UPDATE		0x0040

#define LDD_F_REWRITE_LDD	0x0080

#define LDD_F_WRITECONF		0x0100



#define LDD_F_PARAM		0x0400

#define LDD_F_NO_PRIMNODE	0x1000

#define LDD_F_IR_CAPABLE	0x2000

#define LDD_F_ERROR		0x4000

#define LDD_F_PARAM2		0x8000

#define LDD_F_NO_LOCAL_LOGS	0x10000

#define LDD_MAGIC 0x1dd00001

#define XATTR_TARGET_RENAME "trusted.rename_tgt"

enum ldd_mount_type {
	LDD_MT_EXT3 = 0,
	LDD_MT_LDISKFS = 1,
	LDD_MT_REISERFS = 3,
	LDD_MT_LDISKFS2 = 4,
	LDD_MT_ZFS = 5,
	LDD_MT_WBCFS = 6,
	LDD_MT_LAST
};



#define LR_EXPIRE_INTERVALS 16	
#define LR_SERVER_SIZE	512
#define LR_CLIENT_START	8192
#define LR_CLIENT_SIZE	128
#if LR_CLIENT_START < LR_SERVER_SIZE
#error "Can't have LR_CLIENT_START < LR_SERVER_SIZE"
#endif

/*
 * Data stored per server at the head of the last_rcvd file. In le32 order.
 */
struct lr_server_data {
	__u8  lsd_uuid[40];	   
	__u64 lsd_last_transno;    
	__u64 lsd_compat14;	   
	__u64 lsd_mount_count;	   
	__u32 lsd_feature_compat;  
	__u32 lsd_feature_rocompat;
	__u32 lsd_feature_incompat;
	__u32 lsd_server_size;	   
	__u32 lsd_client_start;    
	__u16 lsd_client_size;	   
	__u16 lsd_subdir_count;    
	__u64 lsd_catalog_oid;	   
	__u32 lsd_catalog_ogen;    
	__u8  lsd_peeruuid[40];    
	__u32 lsd_osd_index;	   
	__u32 lsd_padding1;	   
	__u32 lsd_start_epoch;	   
	
	__u64 lsd_trans_table[LR_EXPIRE_INTERVALS];
	
	__u32 lsd_trans_table_time; 
	__u32 lsd_expire_intervals; 
	__u8  lsd_padding[LR_SERVER_SIZE - 288];
};


struct lsd_client_data {
	__u8  lcd_uuid[40];		
	__u64 lcd_last_transno;		
	__u64 lcd_last_xid;		
	__u32 lcd_last_result;		
	__u32 lcd_last_data;		/* per-op data (disposition for
					 * open &c.)
					 */
	
	__u64 lcd_last_close_transno;	
	__u64 lcd_last_close_xid;	
	__u32 lcd_last_close_result;	
	__u32 lcd_last_close_data;	
	
	__u64 lcd_pre_versions[4];
	__u32 lcd_last_epoch;
	
	__u32 lcd_generation;
	__u8  lcd_padding[LR_CLIENT_SIZE - 128];
};

/* Data stored in each slot of the reply_data file.
 *
 * The lrd_client_gen field is assigned with lcd_generation value
 * to allow identify which client the reply data belongs to.
 */
struct lsd_reply_data_v1 {
	__u64 lrd_transno;	
	__u64 lrd_xid;		
	__u64 lrd_data;		
	__u32 lrd_result;	
	__u32 lrd_client_gen;	
};

struct lsd_reply_data_v2 {
	__u64 lrd_transno;	
	__u64 lrd_xid;		
	__u64 lrd_data;		
	__u32 lrd_result;	
	__u32 lrd_client_gen;	
	__u32 lrd_batch_idx;	
	__u32 lrd_padding[7];	
};

#define lsd_reply_data lsd_reply_data_v2


#define LRH_MAGIC_V1		0xbdabda01
#define LRH_MAGIC_V2		0xbdabda02
#define LRH_MAGIC		LRH_MAGIC_V1


struct lsd_reply_header {
	__u32	lrh_magic;
	__u32	lrh_header_size;
	__u32	lrh_reply_size;
	__u8	lrh_pad[sizeof(struct lsd_reply_data_v1) - 12];
};



enum nodemap_idx_type {
	NODEMAP_EMPTY_IDX = 0,		
	NODEMAP_CLUSTER_IDX = 1,	
	NODEMAP_RANGE_IDX = 2,		
	NODEMAP_UIDMAP_IDX = 3,		
	NODEMAP_GIDMAP_IDX = 4,		
	NODEMAP_PROJIDMAP_IDX = 5,	
	NODEMAP_NID_MASK_IDX = 6,	
	NODEMAP_GLOBAL_IDX = 15,	
};

/* This is needed for struct nodemap_cgrumple_rec. Please don't move
 * to grumple_idl.h which will break user land builds.
 */
#define LUSTRE_NODEMAP_NAME_LENGTH     16
#define LUSTRE_NODEMAP_GUESS	       "?"


enum nm_flag_bits {
	NM_FL_ALLOW_ROOT_ACCESS = 0x1,
	NM_FL_TRUST_CLIENT_IDS = 0x2,
	NM_FL_DENY_UNKNOWN = 0x4,
	NM_FL_MAP_UID = 0x8,
	NM_FL_MAP_GID = 0x10,
	NM_FL_ENABLE_AUDIT = 0x20,
	NM_FL_FORBID_ENCRYPT = 0x40,
	NM_FL_MAP_PROJID = 0x80,
};

enum nm_flag2_bits {
	NM_FL2_READONLY_MOUNT = 0x1,
	NM_FL2_DENY_MOUNT = 0x2,
	NM_FL2_FILESET_USE_IAM = 0x4,
	NM_FL2_GSS_IDENTIFY = 0x8,
};

/* Nodemap records, uses 32 byte record length.
 * New nodemap config records can be added into NODEMAP_CLUSTER_IDX
 * with a new nk_cluster_subid value, as long as the records are
 * kept at 32 bytes in size.  New global config records can be added
 * into NODEMAP_GLOBAL_IDX with a new nk_global_subid.  This avoids
 * breaking compatibility.  Do not change the record size.  If a
 * new ID type or range is needed, a new IDX type should be used.
 */
struct nodemap_cluster_rec {
	char			ncr_name[LUSTRE_NODEMAP_NAME_LENGTH + 1];
	enum nm_flag_bits	ncr_flags:8;
	enum nm_flag2_bits	ncr_flags2:8;
	__u8			ncr_padding1;	
	__u32			ncr_squash_projid;
	__u32			ncr_squash_uid;
	__u32			ncr_squash_gid;
};

enum nm_range_type_bits {
	NM_RANGE_FL_REG = 0x0,
	NM_RANGE_FL_BAN = 0x1,
};


struct nodemap_range_rec {
	lnet_nid_t	nrr_start_nid;
	lnet_nid_t	nrr_end_nid;
	__u64		nrr_padding1;	
	__u64		nrr_padding2;	
};

struct nodemap_range2_rec {
	struct lnet_nid	nrr_nid_prefix;
	__u32		nrr_padding1;	
	__u32		nrr_padding2;	
	__u16		nrr_padding3;	
	__u8		nrr_padding4;	
	__u8		nrr_netmask;
};

struct nodemap_id_rec {
	__u32	nir_id_fs;
	__u32	nir_padding1;		
	__u64	nir_padding2;		
	__u64	nir_padding3;		
	__u64	nir_padding4;		
};

struct nodemap_global_rec {
	__u8	ngr_is_active;
	__u8	ngr_padding1;		
	__u16	ngr_padding2;		
	__u32	ngr_padding3;		
	__u64	ngr_padding4;		
	__u64	ngr_padding5;		
	__u64	ngr_padding6;		
};

struct nodemap_cluster_roles_rec {
	__u64 ncrr_roles;		
	__u64 ncrr_privs;		
	__u64 ncrr_roles_raise;		
	__u64 ncrr_unused1;		
};

struct nodemap_offset_rec {
	__u32 nor_start_uid;
	__u32 nor_limit_uid;
	__u32 nor_start_gid;
	__u32 nor_limit_gid;
	__u32 nor_start_projid;
	__u32 nor_limit_projid;
	__u32 nor_padding1;
	__u32 nor_padding2;
};


#define LUSTRE_NODEMAP_FILESET_FRAGMENT_SIZE \
	(sizeof(struct nodemap_cluster_rec) - (2 * sizeof(__u16)))

#define LUSTRE_NODEMAP_FILESET_SUBID_RANGE 256

#define LUSTRE_NODEMAP_FILESET_NUM_MAX 256

enum nm_fileset_flag_bits {
	NM_FS_FL_READONLY = 0x1,
};

struct nodemap_fileset_header_rec {
	enum nm_fileset_flag_bits	nfhr_flags:8;
	__u8	nfr_padding1;		
	__u16	nfr_padding2;		
	__u32	nfr_padding3;		
	__u64	nfr_padding4;		
	__u64	nfr_padding5;		
	__u64	nfr_padding6;		
};

struct nodemap_fileset_rec {
	
	char	nfr_path_fragment[LUSTRE_NODEMAP_FILESET_FRAGMENT_SIZE];
	__u16	nfr_fragment_id;	
	__u16	nfr_padding1;		
};

struct nodemap_user_capabilities_rec {
	__u64	nucr_caps;
	__u8	nucr_type;		
	__u8	nucr_padding1;		
	__u16	nucr_padding2;		
	__u32	nucr_padding3;		
	__u64	nucr_padding4;		
	__u64	nucr_padding5;		
};

union nodemap_rec {
	struct nodemap_cluster_rec ncr;
	struct nodemap_range_rec nrr;
	struct nodemap_range2_rec nrr2;
	struct nodemap_id_rec nir;
	struct nodemap_global_rec ngr;
	struct nodemap_cluster_roles_rec ncrr;
	struct nodemap_offset_rec nor;
	struct nodemap_fileset_header_rec nfhr;
	struct nodemap_fileset_rec nfr;
	struct nodemap_user_capabilities_rec nucr;
};


enum nodemap_cluster_rec_subid {
	NODEMAP_CLUSTER_REC = 0,   
	NODEMAP_CLUSTER_ROLES = 1, 
	NODEMAP_CLUSTER_OFFSET = 2, 
	NODEMAP_CLUSTER_CAPS = 3, 
	/*
	 * A fileset may consist of up to 256 consecutive subids. Each consists
	 * of a header (nodemap_fileset_header_rec) and up to 255 fragments
	 * (nodemap_fileset_rec).
	 */
	NODEMAP_FILESET = 512,
	/*
	 * Depending on its length, its fragments may use several subids
	 * in the range of 512 to 66,047 (assuming max 256 filesets). The first
	 * subid of each fileset range is its header.
	 */
};


struct nodemap_key {
	__u32 nk_nodemap_id;
	union {
		__u32 nk_cluster_subid;
		
		__u32 nk_range_id;
		__u32 nk_id_client;
		__u32 nk_unused;
	};
};

#define NM_TYPE_MASK 0x0FFFFFFF
#define NM_TYPE_SHIFT 28


#define OSD_OI_FID_OID_BITS_MAX	10
#define OSD_OI_FID_NR_MAX	(1UL << OSD_OI_FID_OID_BITS_MAX)
#define SCRUB_OI_BITMAP_SIZE	(OSD_OI_FID_NR_MAX >> 3)

#define SCRUB_MAGIC_V1			0x4C5FD252
#define SCRUB_MAGIC_V2			0x4C5FE253

enum scrub_flags {
	
	SF_RECREATED	= 0x0000000000000001ULL,

	
	SF_INCONSISTENT	= 0x0000000000000002ULL,

	
	SF_AUTO		= 0x0000000000000004ULL,

	
	SF_UPGRADE	= 0x0000000000000008ULL,
};

enum scrub_status {
	/* The scrub file is new created, for new MDT, upgrading from old disk,
	 * or re-creating the scrub file manually.
	 */
	SS_INIT		= 0,

	
	SS_SCANNING	= 1,

	
	SS_COMPLETED	= 2,

	
	SS_FAILED	= 3,

	
	SS_STOPPED	= 4,

	
	SS_PAUSED	= 5,

	
	SS_CRASHED	= 6,
};

enum scrub_param {
	
	SP_FAILOUT	= 0x0001,

	
	SP_DRYRUN	= 0x0002,
};

#ifdef __KERNEL__

#define uuid_le        guid_t
#endif

struct scrub_file {
	uuid_le	sf_uuid;		    
	__u64	sf_flags;		    
	__u32	sf_magic;		    
	__u16	sf_status;		    
	__u16	sf_param;		    
	__s64	sf_time_last_complete;      
	__s64	sf_time_latest_start;	    
	__s64   sf_time_last_checkpoint;    
	__u64	sf_pos_latest_start;	    
	__u64	sf_pos_last_checkpoint;     
	__u64	sf_pos_first_inconsistent;  
	__u64	sf_items_checked;	    
	__u64	sf_items_updated;           
	__u64	sf_items_failed;	    
	__u64	sf_items_updated_prior;     
	__u64	sf_items_noscrub;	    /* number of objects skipped due to
					     * LDISKFS_STATE_LUSTRE_NOSCRUB
					     */
	__u64   sf_items_igif;		    
	__u32	sf_run_time;		    
	__u32	sf_success_count;	    
	__u16	sf_oi_count;		    
	__u16	sf_internal_flags;	    /* flags to keep after reset, see
					     * 'enum scrub_internal_flags'
					     */
	__u32	sf_reserved_1;
	__u64	sf_reserved_2[16];
	__u8    sf_oi_bitmap[SCRUB_OI_BITMAP_SIZE]; 
};



#endif 
