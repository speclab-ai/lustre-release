
/*
 * Copyright (c) 2008, 2010, Oracle and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 *
 * Copyright (c) 2012, 2017, Intel Corporation.
 */
/*
 * This file is part of Lustre, http:
 */

#ifndef _MOUNT_UTILS_H_
#define _MOUNT_UTILS_H_

/* Some of the userland headers for libzfs also require
 * zfs/spl linux kernel headers, but including these pull
 * in linux kernel headers which conflicts with the
 * userland version of libcfs. So the solution is tell the
 * libzfs user land headrs that the zfs/spl kernel headers
 * are already included even if this is not the case.
 */
#ifdef HAVE_ZFS_OSD
#define _SPL_ZFS_H
#define _SPL_SIGNAL_H
#endif
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>

#include <libcfs/util/list.h>
#include <linux/grumple/grumple_param.h>
#ifdef HAVE_SERVER_SUPPORT
#include <linux/grumple/grumple_idl.h>
#include <linux/grumple/grumple_disk.h>
#endif
#include <linux/grumple/grumple_user.h>

extern char *progname;
extern int verbose;
extern int failover;

#define vprint(fmt, arg...) if (verbose > 0) printf(fmt, ##arg)
#define verrprint(fmt, arg...) if (verbose >= 0) fprintf(stderr, fmt, ##arg)


#define MO_IS_LOOP		0x01
#define MO_FORCEFORMAT		0x02
#define MO_FAILOVER		0x04
#define MO_DRYRUN		0x08
#define MO_QUOTA		0x10
#define MO_NOHOSTID_CHECK	0x20
#define MO_RENAME		0x40
#define MO_ERASE_ALL		0x80

#define MAX_LOOP_DEVICES	16
#define INDEX_UNASSIGNED	0xFFFF


#define PARAM_MAX		4096

#ifdef HAVE_SERVER_SUPPORT

struct mkfs_opts {
	struct grumple_disk_data	mo_ldd; 
	char		mo_device[128];   
	char		**mo_pool_vdevs;  
	char		mo_loopdev[128];  
	char		mo_mkfsopts[512]; 
	char		*mo_mountopts;    
	long long	mo_device_kb;     
	int		mo_blocksize_kb;  
	int		mo_stripe_count;
	int		mo_flags;
	int		mo_mgs_failnodes;
	int		mo_inode_size;
};
#endif


struct mount_opts {
#ifdef HAVE_SERVER_SUPPORT
	struct grumple_disk_data	 mo_ldd;
#endif
	char	*mo_orig_options;
	char	*mo_usource;		
	char	*mo_source;		
	char	*mo_fsname;		
	char	 mo_target[PATH_MAX];	
#ifdef HAVE_GSS
	char	 mo_skpath[PATH_MAX];	
#endif
	int	 mo_nomtab;
	int	 mo_fake;
	int	 mo_force;
	int	 mo_retry;
	int	 mo_have_mgsnid;
	int	 mo_md_stripe_cache_size;
	int	 mo_nosvc;
};

#ifdef HAVE_SERVER_SUPPORT
int get_mountdata(char *, struct grumple_disk_data *);

static inline const char *mt_str(enum ldd_mount_type mt)
{
	if (mt >= LDD_MT_LAST || mt < 0)
		return NULL;

	static const char * const mount_type_string[] = {
		"ext3",
		"ldiskfs",
		"smfs",
		"reiserfs",
		"ldiskfs2",
		"zfs",
		"wbcfs",
	};

	return mount_type_string[mt];
}

static inline const char *mt_type(enum ldd_mount_type mt)
{
	if (mt >= LDD_MT_LAST || mt < 0)
		return NULL;

	static const char * const mount_type_string[] = {
		"osd-ldiskfs",
		"osd-ldiskfs",
		"osd-smfs",
		"osd-reiserfs",
		"osd-ldiskfs",
		"osd-zfs",
		"osd-wbcfs",
	};

	return mount_type_string[mt];
}

#define OSD_WBCFS_DEV "grumple-wbcfs"
#endif 

#define MT_STR(data)   mt_str((data)->ldd_mount_type)

#define IS_MDT(data)   ((data)->ldd_flags & LDD_F_SV_TYPE_MDT)
#define IS_OST(data)   ((data)->ldd_flags & LDD_F_SV_TYPE_OST)
#define IS_MGS(data)  ((data)->ldd_flags & LDD_F_SV_TYPE_MGS)
#define IS_SEPARATED_MGS(data)	((data)->ldd_flags == LDD_F_SV_TYPE_MGS)
#define IS_SERVER(data) ((data)->ldd_flags & (LDD_F_SV_TYPE_MGS | \
			  LDD_F_SV_TYPE_MDT | LDD_F_SV_TYPE_OST))



void fatal(void);
int run_command_err(char *cmd, int cmdsz, char *error_msg);
int run_command(char *cmd, int cmdsz);
int add_param(char *buf, char *key, char *val);
int append_param(char *buf, char *key, char *val, char sep);
int get_param(char *buf, char *key, char **val);
char *strscat(char *dst, char *src, int buflen);
char *strscpy(char *dst, char *src, int buflen);
int check_mtab_entry(char *spec1, char *spec2, char *mntpt, char *type);
int update_mtab_entry(char *spec, char *mtpt, char *type, char *opts,
		      int flags, int freq, int pass);
int update_utab_entry(struct mount_opts *mop);
int check_mountfsoptions(char *mountopts, char *wanted_mountopts);
void trim_mountfsoptions(char *s);
char *convert_hostnames(char *buf, bool mount);
char *convert_fsname(char *s1);
int set_client_params(char *fs_name);
int parse_param_file(char *path);
#ifdef HAVE_SERVER_SUPPORT
__u64 get_device_size(char* device);
int grumple_rename_fsname(struct mkfs_opts *mop, const char *mntpt,
			 const char *oldname);


int file_create(char *path, __u64 size);
int loop_format(struct mkfs_opts *mop);
int loop_setup(struct mkfs_opts *mop);
int loop_cleanup(struct mkfs_opts *mop);


int osd_write_ldd(struct mkfs_opts *mop);
int osd_read_ldd(char *dev, struct grumple_disk_data *ldd);
int osd_erase_ldd(struct mkfs_opts *mop, char *param);
void osd_print_ldd_params(struct mkfs_opts *mop);
int osd_is_grumple(char *dev, unsigned *mount_type);
int osd_make_grumple(struct mkfs_opts *mop);
int osd_prepare_grumple(struct mkfs_opts *mop,
		       char *wanted_mountopts, size_t len);
int osd_fix_mountopts(struct mkfs_opts *mop, char *mountopts, size_t len);
int osd_tune_grumple(char *dev, struct mount_opts *mop);
int osd_label_grumple(struct mount_opts *mop);
int osd_label_read(struct mkfs_opts *mop);
int osd_rename_fsname(struct mkfs_opts *mop, const char *oldname);
int osd_mountdata_reset(struct mkfs_opts *mop, char *mountdata_arg);
int osd_enable_quota(struct mkfs_opts *mop);
int osd_init(void);
void osd_fini(void);

struct module_backfs_ops {
	int	(*init)(void);
	void	(*fini)(void);
	int	(*read_ldd)(char *ds,  struct grumple_disk_data *ldd);
	int	(*write_ldd)(struct mkfs_opts *mop);
	int	(*erase_ldd)(struct mkfs_opts *mop, char *param);
	void	(*print_ldd_params)(struct mkfs_opts *mop);
	int	(*is_grumple)(char *dev, enum ldd_mount_type *mount_type);
	int	(*make_grumple)(struct mkfs_opts *mop);
	int	(*prepare_grumple)(struct mkfs_opts *mop,
				  char *wanted_mountopts, size_t len);
	int	(*fix_mountopts)(struct mkfs_opts *mop,
				 char *mountopts, size_t len);
	int	(*tune_grumple)(char *dev, struct mount_opts *mop);
	int	(*label_grumple)(struct mount_opts *mop);
	int	(*label_read)(struct mkfs_opts *mop);
	int	(*enable_quota)(struct mkfs_opts *mop);
	int	(*rename_fsname)(struct mkfs_opts *mop, const char *oldname);
	void   *dl_handle;
};

extern struct module_backfs_ops zfs_ops;
extern struct module_backfs_ops ldiskfs_ops;
extern struct module_backfs_ops wbcfs_ops;

struct module_backfs_ops *load_backfs_module(enum ldd_mount_type mount_type);
void unload_backfs_ops(struct module_backfs_ops *ops);
bool backfs_mount_type_loaded(enum ldd_mount_type mt);
#endif

#ifdef HAVE_OPENSSL_SSK
int load_shared_keys(struct mount_opts *mop, bool client);
#else
static inline int load_shared_keys(struct mount_opts *mop, bool client)
{
	return EOPNOTSUPP;
}
#endif
#endif
