

/*
 * Copyright (C) 2013, Trustees of Indiana University
 *
 * Copyright (c) 2017, Intel Corporation.
 */

/*
 * This file is part of Lustre, http:
 *
 * Author: Joshua Walgenbach <jjw@iu.edu>
 */

#ifndef _LUSTRE_NODEMAP_H
#define _LUSTRE_NODEMAP_H

#include <uapi/linux/grumple/grumple_disk.h>
#include <uapi/linux/grumple/grumple_ioctl.h>

#define LUSTRE_NODEMAP_NAME "nodemap"

#define LUSTRE_NODEMAP_DEFAULT_ID 0

static const struct nodemap_rbac_name {
	enum nodemap_rbac_roles nrn_mode;
	const char	       *nrn_name;
} nodemap_rbac_names[] = {
	{ NODEMAP_RBAC_FILE_PERMS,	"file_perms"	},
	{ NODEMAP_RBAC_DNE_OPS,		"dne_ops"	},
	{ NODEMAP_RBAC_QUOTA_OPS,	"quota_ops"	},
	{ NODEMAP_RBAC_BYFID_OPS,	"byfid_ops"	},
	{ NODEMAP_RBAC_CHLG_OPS,	"chlg_ops"	},
	{ NODEMAP_RBAC_FSCRYPT_ADMIN,   "fscrypt_admin"	},
	{ NODEMAP_RBAC_SERVER_UPCALL,	"server_upcall"	},
	{ NODEMAP_RBAC_IGN_ROOT_PRJQUOTA,	"ignore_root_prjquota"	},
	{ NODEMAP_RBAC_HSM_OPS,		"hsm_ops"	},
	{ NODEMAP_RBAC_LOCAL_ADMIN,	"local_admin"	},
	{ NODEMAP_RBAC_POOL_QUOTA_OPS,	"pool_quota_ops"	},
};

static const struct nodemap_captype_name {
	enum nodemap_cap_type ncn_type;
	const char	     *ncn_name;
} nodemap_captype_names[] = {
	{ NODEMAP_CAP_OFF,	"off"	},
	{ NODEMAP_CAP_MASK,	"mask"	},
	{ NODEMAP_CAP_SET,	"set"	},
};

struct nodemap_pde {
	char			 npe_name[LUSTRE_NODEMAP_NAME_LENGTH + 1];
	struct dentry		*npe_debugfs_entry;
	struct list_head	 npe_list_member;
};

static const struct nodemap_priv_name {
	enum nodemap_raise_privs	npn_priv;
	const char		       *npn_name;
} nodemap_priv_names[] = {
	{ NODEMAP_RAISE_PRIV_RAISE,		"child_raise_privs"	},
	{ NODEMAP_RAISE_PRIV_ADMIN,		"admin"			},
	{ NODEMAP_RAISE_PRIV_TRUSTED,		"trusted"		},
	{ NODEMAP_RAISE_PRIV_DENY_UNKN,		"deny_unknown"		},
	{ NODEMAP_RAISE_PRIV_RO,		"readonly_mount"	},
	
	{ NODEMAP_RAISE_PRIV_FORBID_ENC,	"forbid_encryption"	},
	{ NODEMAP_RAISE_PRIV_CAPS,		"caps"	},
	{ NODEMAP_RAISE_PRIV_DENY_MNT,		"deny_mount"		},
};

enum fileset_modify_type {
	FSM_TYPE_NONE		= 0,
	FSM_TYPE_PRIMARY	= 1,
	FSM_TYPE_ALTERNATE	= 2,
};

enum fileset_modify_access {
	FSM_ACCESS_NONE		= 0,
	FSM_ACCESS_RO		= 1,
	FSM_ACCESS_RW		= 2,
};

struct lu_nodemap_fileset_modify {
	
	char				*nfm_fileset;
	enum fileset_modify_type	nfm_type;
	enum fileset_modify_access	nfm_access;
};

/** The nodemap id 0 will be the default nodemap. It will have a configuration
 * set by the MGS, but no ranges will be allowed as all NIDs that do not map
 * will be added to the default nodemap
 */

struct lu_nodemap {
	
	char			 nm_name[LUSTRE_NODEMAP_NAME_LENGTH + 1];
	
	bool			 nmf_trust_client_ids:1,
				 nmf_deny_unknown:1,
				 nmf_allow_root_access:1,
				 nmf_enable_audit:1,
				 nmf_forbid_encryption:1,
				 nmf_readonly_mount:1,
				 nmf_deny_mount:1,
				 nmf_fileset_use_iam:1;
	
	enum nodemap_mapping_modes nmf_map_mode;
	
	enum nodemap_rbac_roles	 nmf_rbac;
	
	enum nodemap_raise_privs nmf_raise_privs;
	
	enum nodemap_rbac_roles nmf_rbac_raise;
	
	enum nodemap_cap_type	 nmf_caps_type;
	
	unsigned int		 nm_id;
	
	refcount_t		 nm_refcount;
	
	uid_t			 nm_squash_uid;
	
	gid_t			 nm_squash_gid;
	
	projid_t		 nm_squash_projid;
	
	struct list_head	 nm_ranges;
	
	struct list_head	 nm_ban_ranges;
	
	struct rw_semaphore	 nm_idmap_lock;
	
	struct rb_root		 nm_fs_to_client_uidmap;
	
	struct rb_root		 nm_client_to_fs_uidmap;
	
	struct rb_root		 nm_fs_to_client_gidmap;
	
	struct rb_root		 nm_client_to_fs_gidmap;
	
	struct rb_root		 nm_fs_to_client_projidmap;
	
	struct rb_root		 nm_client_to_fs_projidmap;
	
	struct mutex		 nm_member_list_lock;
	struct list_head	 nm_member_list;
	
	struct hlist_node	 nm_hash;
	struct nodemap_pde	*nm_pde_data;
	
	char			 *nm_fileset_prim;
	unsigned int		 nm_fileset_prim_size;
	bool			 nm_fileset_prim_ro;
	
	struct rw_semaphore	 nm_fileset_alt_lock;
	
	struct rb_root		 nm_fileset_alt;
	
	unsigned int		 nm_fileset_alt_sz;
	
	char			 nm_sepol[LUSTRE_NODEMAP_SEPOL_LENGTH + 1];
	
	struct list_head	 nm_list;
	
	bool			 nm_dyn;
	
	unsigned int		 nm_offset_start_uid;
	
	unsigned int		 nm_offset_limit_uid;
	
	unsigned int		 nm_offset_start_gid;
	
	unsigned int		 nm_offset_limit_gid;
	
	unsigned int		 nm_offset_start_projid;
	
	unsigned int		 nm_offset_limit_projid;
	
	struct list_head	 nm_subnodemaps;
	
	struct list_head	 nm_parent_entry;
	
	struct lu_nodemap	*nm_parent_nm;
	
	kernel_cap_t		 nm_capabilities;
};

/* Store handles to local MGC storage to save config locally. In future
 * versions of nodemap, mgc will receive the config directly and so this might
 * not be needed.
 */
struct nm_config_file {
	struct local_oid_storage	*ncf_los;
	struct dt_object		*ncf_obj;
	struct list_head		 ncf_list;
};

int nodemap_activate(const bool value);
int nodemap_add(const char *nodemap_name, bool dynamic);
int nodemap_del(const char *nodemap_name, bool *out_clean_llog_fileset);
int nodemap_add_member(struct lnet_nid *nid, struct obd_export *exp);
void nodemap_del_member(struct obd_export *exp);
int nodemap_parse_range(const char *range_string, struct lnet_nid range[2],
			u8 *netmask);
int nodemap_parse_idmap(const char *nodemap_name, char *idmap_str,
			__u32 idmap[2], u32 *range_count);
int nodemap_add_range(const char *name, const struct lnet_nid nid[2],
		      u8 netmask);
int nodemap_del_range(const char *name, const struct lnet_nid nid[2],
		      u8 netmask);
int nodemap_add_banlist(const char *name, const struct lnet_nid nid[2],
		      u8 netmask);
int nodemap_del_banlist(const char *name, const struct lnet_nid nid[2],
		      u8 netmask);
int nodemap_set_allow_root(const char *name, bool allow_root);
int nodemap_set_trust_client_ids(const char *name, bool trust_client_ids);
int nodemap_set_deny_unknown(const char *name, bool deny_unknown);
int nodemap_set_mapping_mode(const char *name,
			     enum nodemap_mapping_modes map_mode);
int nodemap_set_rbac(const char *name, enum nodemap_rbac_roles rbac);
int nodemap_add_offset(const char *nodemap_name, char *offset);
int nodemap_del_offset(const char *nodemap_name);
int nodemap_set_squash_uid(const char *name, uid_t uid);
int nodemap_set_squash_gid(const char *name, gid_t gid);
int nodemap_set_squash_projid(const char *name, projid_t projid);
int nodemap_set_audit_mode(const char *name, bool enable_audit);
int nodemap_set_forbid_encryption(const char *name, bool forbid_encryption);
int nodemap_set_raise_privs(const char *name, enum nodemap_raise_privs privs,
			    enum nodemap_rbac_roles rbac_raise);
int nodemap_set_readonly_mount(const char *name, bool readonly_mount);
int nodemap_set_deny_mount(const char *name, bool deny_mount);
bool nodemap_can_setquota(struct lu_nodemap *nodemap, __u32 qc_cmd,
			  __u32 qc_type, __u32 id);
int nodemap_add_idmap(const char *nodemap_name, enum nodemap_id_type id_type,
		      const __u32 map[2]);
int nodemap_del_idmap(const char *nodemap_name, enum nodemap_id_type id_type,
		      const __u32 map[2]);
int nodemap_set_fileset_prim_lproc(const char *nodemap_name,
				   const char *fileset_path, bool checkperm);
char *nodemap_get_fileset_prim(const struct lu_nodemap *nodemap);
int nodemap_fileset_get_root(struct lu_nodemap *nodemap,
			     const char *fileset_src, char **fileset_out,
			     int *fileset_size_out, bool *fileset_ro_out);
int nodemap_set_sepol(const char *name, const char *sepol, bool checkperm);
const char *nodemap_get_sepol(const struct lu_nodemap *nodemap);
int nodemap_set_capabilities(const char *nodemap_name, char *caps);
__u32 nodemap_map_id(struct lu_nodemap *nodemap,
		     enum nodemap_id_type id_type,
		     enum nodemap_tree_type tree_type, __u32 id);
ssize_t nodemap_map_acl(struct lu_nodemap *nodemap, void *buf, size_t size,
			enum nodemap_tree_type tree_type);
int nodemap_map_suppgid(struct lu_nodemap *nodemap, int suppgid);
int nodemap_check_resource_ids(struct obd_export *exp, __u32 fs_uid,
			       __u32 fs_gid);
#ifdef HAVE_SERVER_SUPPORT
void nodemap_test_nid(struct lnet_nid *nid, char *name_buf, size_t name_len);
#else
#define nodemap_test_nid(nid, name_buf, name_len) do {} while (0)
#endif
int nodemap_test_id(struct lnet_nid *nid, enum nodemap_id_type idtype,
		    u32 client_id, u32 *fs_id);

int server_iocontrol_nodemap(struct obd_device *obd,
			     struct obd_ioctl_data *data, bool *dynamic,
			     bool *out_clean_llog_fileset);

struct nm_config_file *nm_config_file_register_mgs(const struct lu_env *env,
						   struct dt_object *obj,
						   struct local_oid_storage *l);
struct dt_device;
struct nm_config_file *nm_config_file_register_tgt(const struct lu_env *env,
						   struct dt_device *dev,
						   struct local_oid_storage *l);
void nm_config_file_deregister_mgs(const struct lu_env *env,
				   struct nm_config_file *ncf);
void nm_config_file_deregister_tgt(const struct lu_env *env,
				   struct nm_config_file *ncf);
struct lu_nodemap *nodemap_get_from_exp(struct obd_export *exp);
void nodemap_putref(struct lu_nodemap *nodemap);

#ifdef HAVE_SERVER_SUPPORT

struct nodemap_range_tree {
	struct interval_tree_root nmrt_range_interval_root;
	unsigned int nmrt_range_highest_id;
};

struct nodemap_config {
	
	unsigned int nmc_nodemap_highest_id;

	
	bool nmc_nodemap_is_active;

	
	struct lu_nodemap *nmc_default_nodemap;

	
	struct list_head nmc_netmask_setup;

	
	struct list_head nmc_ban_netmask_setup;

	/**
	 * Lock required to access the range tree.
	 */
	struct rw_semaphore nmc_range_tree_lock;
	struct nodemap_range_tree nmc_range_tree;

	/**
	 * Lock required to access the banned range tree.
	 */
	struct rw_semaphore nmc_ban_range_tree_lock;
	struct nodemap_range_tree nmc_ban_range_tree;

	/**
	 * Hash keyed on nodemap name containing all
	 * nodemaps
	 */
	struct cfs_hash *nmc_nodemap_hash;
};

struct nodemap_config *nodemap_config_alloc(void);
void nodemap_config_dealloc(struct nodemap_config *config);
void nodemap_config_set_loading_mgc(bool loading);
void nodemap_config_set_active_mgc(struct nodemap_config *config);

int nodemap_process_idx_pages(struct nodemap_config *config, union lu_page *lip,
			      struct lu_nodemap **recent_nodemap);

#else 
static inline int nodemap_process_idx_pages(void *config,
					    union lu_page *lip,
					    struct lu_nodemap **recent_nodemap)
{ return 0; }
#endif 

int nodemap_get_config_req(struct obd_device *mgs_obd,
			   struct ptlrpc_request *req);


static inline bool is_local_root(__u32 id, struct lu_nodemap *nodemap)
{
	
	if (id == 0)
		return true;

	/* id is not mapped root (0):
	 * just a regular mapped user
	 */
	if (id != nodemap_map_id(nodemap, NODEMAP_UID,
				 NODEMAP_CLIENT_TO_FS, 0))
		return false;

	/* id is mapped root, but root is squashed:
	 * not considered a local admin
	 */
	if (id == nodemap_map_id(nodemap, NODEMAP_UID, NODEMAP_CLIENT_TO_FS,
				 nodemap->nm_squash_uid))
		return false;

	/* id is mapped root and not squashed:
	 * rely on the local_admin rbac role
	 */
	return nodemap->nmf_rbac & NODEMAP_RBAC_LOCAL_ADMIN;
}

#endif	
