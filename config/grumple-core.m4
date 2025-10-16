AC_DEFUN([LC_CONFIG_SRCDIR], [
AC_CONFIG_SRCDIR([grumple/obdclass/obdo.c])
ldiskfs_is_ext4="yes"
])
AC_DEFUN([LC_PATH_DEFAULTS], [
LUSTRE="$PWD/grumple"
AC_SUBST(LUSTRE)
rootsbindir='/sbin'
AC_SUBST(rootsbindir)
demodir='$(docdir)/demo'
AC_SUBST(demodir)
pkgexampledir='${pkgdatadir}/examples'
AC_SUBST(pkgexampledir)
]) 
AC_DEFUN([LC_TARGET_SUPPORTED], [
case $target_os in
	linux*)
$1
		;;
	*)
$2
		;;
esac
]) 
AC_DEFUN([LC_GLIBC_SUPPORT_FHANDLES], [
AC_CHECK_FUNCS([name_to_handle_at],
	[AC_DEFINE(HAVE_FHANDLE_GLIBC_SUPPORT, 1,
		[file handle and related syscalls are supported])],
	[AC_MSG_WARN([file handle and related syscalls are not supported])])
]) 
AC_DEFUN([LC_GLIBC_SUPPORT_COPY_FILE_RANGE], [
AC_CHECK_FUNCS([copy_file_range],
	[AC_DEFINE(HAVE_COPY_FILE_RANGE, 1,
		[copy_file_range() is supported])],
	[AC_MSG_WARN([copy_file_range() is not supported])])
]) 
AC_DEFUN([LC_FID2PATH_ANON_UNION], [
saved_flags="$CFLAGS"
CFLAGS="-Werror"
AC_MSG_CHECKING([if 'struct getinfo_fid2path' has anonymous union])
AC_COMPILE_IFELSE([AC_LANG_SOURCE([
	int main(void) {
		struct getinfo_fid2path gf;
		struct lu_fid root_fid;
		*gf.gf_root_fid = root_fid;
		return 0;
	}
])],[
	AC_DEFINE(HAVE_FID2PATH_ANON_UNIONS, 1, [union is unnamed])
	AC_MSG_RESULT([yes])
],[
	AC_MSG_RESULT([no])
])
CFLAGS="$saved_flags"
]) 
AC_DEFUN([LC_SRC_STACK_SIZE], [
	LB2_LINUX_TEST_SRC([stack_size_8k], [
	], [
	])
])
AC_DEFUN([LC_STACK_SIZE], [
	LB2_MSG_LINUX_TEST_RESULT([if stack size is at least 8k],
	[stack_size_8k], [],[
		AC_MSG_ERROR(
		[Lustre requires that Linux is configured with at least a 8KB stack.])
	])
]) 
AC_DEFUN([LC_MDS_MAX_THREADS], [
AC_MSG_CHECKING([for maximum number of MDS threads])
AC_ARG_WITH([mds_max_threads],
	AS_HELP_STRING([--with-mds-max-threads=count],
		[maximum threads available on the MDS: (default=512)]),
	[AC_DEFINE_UNQUOTED(MDS_MAX_THREADS, $with_mds_max_threads,
		[maximum number of MDS threads])])
AC_MSG_RESULT([$with_mds_max_threads])
]) 
AC_DEFUN([LC_CONFIG_PINGER], [
AC_MSG_CHECKING([whether to enable Lustre pinger support])
AC_ARG_ENABLE([pinger],
	AS_HELP_STRING([--disable-pinger],
		[disable recovery pinger support]),
	[], [enable_pinger="yes"])
AC_MSG_RESULT([$enable_pinger])
AS_IF([test "x$enable_pinger" != xno], [
	AC_DEFINE(CONFIG_LUSTRE_FS_PINGER, 1, [Use the Pinger])
	AC_SUBST(ENABLE_PINGER, yes)
], [
	AC_SUBST(ENABLE_PINGER, no)
])
]) 
AC_DEFUN([LC_CONFIG_CHECKSUM], [
AC_MSG_CHECKING([whether to enable data checksum support])
AC_ARG_ENABLE([checksum],
	AS_HELP_STRING([--disable-checksum],
		[disable data checksum support]),
	[], [enable_checksum="yes"])
AC_MSG_RESULT([$enable_checksum])
AS_IF([test "x$enable_checksum" != xno], [
	AC_DEFINE(CONFIG_ENABLE_CHECKSUM, 1, [do data checksums])
	AC_SUBST(ENABLE_CHECKSUM, yes)
], [
	AC_SUBST(ENABLE_CHECKSUM, no)
])
]) 
AC_DEFUN([LC_CONFIG_FLOCK], [
AC_MSG_CHECKING([whether to enable flock by default])
AC_ARG_ENABLE([flock],
	AS_HELP_STRING([--disable-flock],
		[disable flock by default]),
	[], [enable_flock="yes"])
AC_MSG_RESULT([$enable_flock])
AS_IF([test "x$enable_flock" != xno], [
	AC_DEFINE(CONFIG_ENABLE_FLOCK, 1, [enable flock by default])
	AC_SUBST(ENABLE_FLOCK, yes)
], [
	AC_SUBST(ENABLE_FLOCK, no)
])
]) 
AC_DEFUN([LC_CONFIG_LRU_RESIZE], [
AC_MSG_CHECKING([whether to enable lru self-adjusting])
AC_ARG_ENABLE([lru_resize],
	AS_HELP_STRING([--enable-lru-resize],
		[enable lru resize support]),
	[], [enable_lru_resize="yes"])
AC_MSG_RESULT([$enable_lru_resize])
AS_IF([test "x$enable_lru_resize" != xno], [
	AC_DEFINE(HAVE_LRU_RESIZE_SUPPORT, 1, [Enable lru resize support])
	AC_SUBST(ENABLE_LRU_RESIZE, yes)
], [
	AC_SUBST(ENABLE_LRU_RESIZE, no)
])
]) 
AC_DEFUN([LC_SRC_CONFIG_QUOTA], [
	LB2_SRC_CHECK_CONFIG_IM([QUOTA])
])
AC_DEFUN([LC_CONFIG_QUOTA], [
	LB2_TEST_CHECK_CONFIG_IM([QUOTA],[],[AC_MSG_ERROR(
[Lustre quota requires that CONFIG_QUOTA is enabled in your kernel.])])
]) 
AC_DEFUN([LC_SRC_CONFIG_FHANDLE], [
	LB2_SRC_CHECK_CONFIG_IM([FHANDLE])
])
AC_DEFUN([LC_CONFIG_FHANDLE], [
	LB2_TEST_CHECK_CONFIG_IM([FHANDLE],[],[AC_MSG_ERROR(
[Lustre fid handling requires that CONFIG_FHANDLE is enabled in your kernel.])])
]) 
AC_DEFUN([LC_SRC_POSIX_ACL_CONFIG], [
	LB2_SRC_CHECK_CONFIG_IM([FS_POSIX_ACL])
])
AC_DEFUN([LC_POSIX_ACL_CONFIG], [
	LB2_TEST_CHECK_CONFIG_IM([FS_POSIX_ACL],
		[AC_DEFINE(CONFIG_LUSTRE_FS_POSIX_ACL, 1, [Enable POSIX acl])],
		[])
]) 
AC_DEFUN([LC_CONFIG_GSS_KEYRING], [
AC_MSG_CHECKING([whether to enable gss keyring backend])
AC_ARG_ENABLE([gss_keyring],
	[AS_HELP_STRING([--disable-gss-keyring],
		[disable gss keyring backend])],
	[], [AS_IF([test "x$enable_gss" != xno], [
			enable_gss_keyring="yes"], [
			enable_gss_keyring="auto"])])
AC_MSG_RESULT([$enable_gss_keyring])
AS_IF([test "x$enable_gss_keyring" != xno], [
	LB_CHECK_CONFIG_IM([KEYS], [], [
		gss_keyring_conf_test="fail"
		AC_MSG_WARN([GSS keyring backend requires that CONFIG_KEYS be enabled in your kernel.])])
	AC_CHECK_LIB([keyutils], [keyctl_search], [], [
		gss_keyring_conf_test="fail"
		AC_MSG_WARN([GSS keyring backend requires libkeyutils])])
	AS_IF([test "x$gss_keyring_conf_test" != xfail], [
		AC_DEFINE([HAVE_GSS_KEYRING], [1],
			[Define this if you enable gss keyring backend])
		enable_gss_keyring="yes"
	], [
		AS_IF([test "x$enable_gss_keyring" = xyes], [
			AC_MSG_ERROR([Cannot enable gss_keyring. See above for details.])
		])
		enable_ssk="no"
	])
], [
	enable_ssk="no"
])
]) 
AC_DEFUN([LC_SRC_KEY_TYPE_INSTANTIATE_2ARGS], [
	LB2_LINUX_TEST_SRC([key_type_instantiate_2args], [
	],[
		((struct key_type *)0)->instantiate(0, NULL);
	])
])
AC_DEFUN([LC_KEY_TYPE_INSTANTIATE_2ARGS], [
	LB2_MSG_LINUX_TEST_RESULT([if 'key_type->instantiate' has two args],
	[key_type_instantiate_2args], [
		AC_DEFINE(HAVE_KEY_TYPE_INSTANTIATE_2ARGS, 1,
			[key_type->instantiate has two args])
	])
]) 
AC_DEFUN([LC_CONFIG_SUNRPC], [
LB_CHECK_CONFIG_IM([SUNRPC], [], [
	AS_IF([test "x$sunrpc_required" = xyes], [
		AC_MSG_ERROR([
kernel SUNRPC support is required by using GSS.
])
	])])
]) 
AC_DEFUN([LC_CONFIG_GSS], [
AC_MSG_CHECKING([whether to enable gss support])
AC_ARG_ENABLE([gss],
	[AS_HELP_STRING([--enable-gss], [enable gss support])],
	[], [enable_gss="auto"])
AC_MSG_RESULT([$enable_gss])
AC_ARG_VAR([TEST_JOBS],
    [simultaneous jobs during configure (defaults to $(nproc))])
if test "x$ac_cv_env_TEST_JOBS_set" != "xset"; then
	TEST_JOBS=${TEST_JOBS:-$(nproc)}
fi
AC_SUBST(TEST_JOBS)
AC_ARG_VAR([TEST_DIR],
    [location of temporary parallel configure tests (defaults to $PWD/lb2)])
	TEST_DIR=${TEST_DIR:-${ac_pwd}/_lpb}
AC_SUBST(TEST_DIR)
AS_IF([test "x$enable_gss" != xno], [
	LC_CONFIG_GSS_KEYRING
	sunrpc_required=$enable_gss
	LC_CONFIG_SUNRPC
	sunrpc_required="no"
	require_krb5=$enable_gss
	AC_KERBEROS_V5
	require_krb5="no"
	AS_IF([test -n "$KRBDIR"], [
		gss_conf_test="success"
	], [
		gss_conf_test="failure"
	])
	AS_IF([test "x$gss_conf_test" = xsuccess && test "x$enable_gss" != xno], [
		AC_DEFINE([HAVE_GSS], [1], [Define this is if you enable gss])
		enable_gss="yes"
	], [
		enable_gss_keyring="no"
		enable_gss="no"
	])
	AS_IF([test "x$enable_ssk" != xno], [
		enable_ssk=$enable_gss
	])
], [
	enable_gss_keyring="no"
])
]) 
AC_DEFUN([LC_SRC_CONFIG_XARRAY_MULTI], [
	LB2_SRC_CHECK_CONFIG_IM([XARRAY_MULTI])
])
AC_DEFUN([LC_CONFIG_XARRAY_MULTI], [
	LB2_TEST_CHECK_CONFIG_IM([XARRAY_MULTI],[],[AC_MSG_ERROR(
[Lustre quota requires that CONFIG_XARRAY_MULTI is enabled in your kernel.])])
]) 
AC_DEFUN([LC_OPENSSL_HMAC], [
has_hmac_functions="no"
saved_flags="$CFLAGS"
CFLAGS="-Werror"
AC_MSG_CHECKING([whether OpenSSL has HMAC_Init_ex])
AS_IF([test "x$enable_ssk" != xno], [
AC_COMPILE_IFELSE([AC_LANG_SOURCE([
	int main(void) {
		int rc;
		rc = HMAC_Init_ex(NULL, "test", 4, EVP_md_null(), NULL);
		return rc;
	}
])],[
	has_hmac_functions="yes"
])
])
AC_MSG_RESULT([$has_hmac_functions])
CFLAGS="$saved_flags"
]) 
AC_DEFUN([LC_OPENSSL_FIPS], [
has_fips_support="no"
saved_flags="$CFLAGS"
CFLAGS="-Werror"
AC_MSG_CHECKING([whether OpenSSL has FIPS_mode])
AS_IF([test "x$enable_ssk" != xno], [
AC_COMPILE_IFELSE([AC_LANG_SOURCE([
	int main(void) {
		int rc;
		rc = FIPS_mode();
		return rc;
	}
])],[
	AC_DEFINE(HAVE_OPENSSL_FIPS, 1, [OpenSSL FIPS_mode])
	has_fips_support="yes"
])
])
AC_MSG_RESULT([$has_fips_support])
CFLAGS="$saved_flags"
]) 
AC_DEFUN([LC_OPENSSL_EVP_PKEY], [
has_evp_pkey="no"
saved_flags="$CFLAGS"
CFLAGS="-Werror"
AC_MSG_CHECKING([whether OpenSSL has EVP_PKEY_get_params])
AS_IF([test "x$enable_ssk" != xno], [
AC_COMPILE_IFELSE([AC_LANG_SOURCE([
	int main(void) {
		OSSL_PARAM *params;
		int rc = EVP_PKEY_get_params(NULL, params);
		return rc;
	}
])],[
	AC_DEFINE(HAVE_OPENSSL_EVP_PKEY, 1, [OpenSSL EVP_PKEY_get_params])
	has_evp_pkey="yes"
])
])
CFLAGS="$saved_flags"
AC_MSG_RESULT([$has_evp_pkey])
]) 
AC_DEFUN([LC_OPENSSL_SSK], [
AS_IF([test "x$enable_ssk" != xno], [
	LC_OPENSSL_HMAC
	LC_OPENSSL_FIPS
	LC_OPENSSL_EVP_PKEY
])
AS_IF([test "x$has_hmac_functions" = xyes -o "x$has_evp_pkey" = xyes], [
	AC_DEFINE(HAVE_OPENSSL_SSK, 1, [OpenSSL HMAC functions needed for SSK])
], [
	enable_ssk="no"
])
AC_MSG_CHECKING([whether OpenSSL has functions needed for SSK])
AC_MSG_RESULT([$enable_ssk])
]) 
AC_DEFUN([LC_OPENSSL_GETSEPOL], [
saved_flags="$CFLAGS"
CFLAGS="-Werror"
AC_MSG_CHECKING([whether openssl-devel is present])
AC_COMPILE_IFELSE([AC_LANG_SOURCE([
	int main(void) {
		EVP_MD_CTX *mdctx = EVP_MD_CTX_create();
		(void) mdctx;
	}
])],[
	AC_DEFINE(HAVE_OPENSSL_GETSEPOL, 1, [openssl-devel is present])
	enable_getsepol="yes"
],[
	enable_getsepol="no"
	AC_MSG_WARN([
No openssl-devel headers found, unable to build l_getsepol and SELinux status checking
])
])
AC_MSG_RESULT([$enable_getsepol])
CFLAGS="$saved_flags"
]) 
AC_DEFUN([LC_CONFIG_GETSEPOL], [
AC_ARG_ENABLE([l_getsepol], [AS_HELP_STRING([--disable-l_getsepol],
    [build the l_getsepol utility])], [config_getsepol="no"],
    [config_getsepol="yes"])
AC_MSG_CHECKING([whether to build l_getsepol])
AC_MSG_RESULT([$config_getsepol])
]) 
AC_DEFUN([LC_HAVE_LIBAIO], [
	AC_CHECK_HEADER([libaio.h],
		enable_libaio="yes",
		AC_MSG_WARN([libaio is not installed on the system]))
]) 
AC_DEFUN([LC_SRC_FOP_READDIR], [
	LB2_LINUX_TEST_SRC([fop_readdir], [
	],[
		struct file_operations fop;
		fop.readdir = NULL;
	])
])
AC_DEFUN([LC_FOP_READDIR], [
	LB2_MSG_LINUX_TEST_RESULT([if 'file_operations' has 'readdir'],
	[fop_readdir], [
		AC_DEFINE(HAVE_FOP_READDIR, 1,
			[file_operations has readdir])
	])
]) 
AC_DEFUN([LC_SRC_INVALIDATE_RANGE], [
	LB2_LINUX_TEST_SRC([address_space_ops_invalidatepage_3args], [
	],[
		struct address_space_operations a_ops;
		a_ops.invalidatepage(NULL, 0, 0);
	])
])
AC_DEFUN([LC_INVALIDATE_RANGE], [
	LB2_MSG_LINUX_TEST_RESULT(
	[if 'address_space_operations.invalidatepage' requires 3 arguments],
	[address_space_ops_invalidatepage_3args], [
		AC_DEFINE(HAVE_INVALIDATE_RANGE, 1,
			[address_space_operations.invalidatepage needs 3 arguments])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_DIR_CONTEXT], [
	LB2_LINUX_TEST_SRC([dir_context], [
	],[
		struct dir_context ctx;
		ctx.pos = 0;
	])
])
AC_DEFUN([LC_HAVE_DIR_CONTEXT], [
	LB2_MSG_LINUX_TEST_RESULT([if 'dir_context' exist],
	[dir_context], [
		AC_DEFINE(HAVE_DIR_CONTEXT, 1, [dir_context exist])
	])
]) 
AC_DEFUN([LC_SRC_PID_NS_FOR_CHILDREN], [
	LB2_LINUX_TEST_SRC([pid_ns_for_children], [
	],[
		struct nsproxy ns;
		ns.pid_ns_for_children = NULL;
	])
])
AC_DEFUN([LC_PID_NS_FOR_CHILDREN], [
	LB2_MSG_LINUX_TEST_RESULT([if 'struct nsproxy' has 'pid_ns_for_children'],
	[pid_ns_for_children], [
		AC_DEFINE(HAVE_PID_NS_FOR_CHILDREN, 1,
			  ['struct nsproxy' has 'pid_ns_for_children'])
	])
]) 
AC_DEFUN([LC_SRC_VFS_PRESSURE_RATIO], [
	LB2_LINUX_TEST_SRC([vfs_pressure_ratio], [
	],[
		(void)vfs_pressure_ratio(10);
	])
])
AC_DEFUN([LC_VFS_PRESSURE_RATIO], [
	LB2_MSG_LINUX_TEST_RESULT([if vfs_pressure_ratio() is available],
	[vfs_pressure_ratio], [
		AC_DEFINE(HAVE_VFS_PRESSURE_RATIO, 1,
			  [vfs_pressure_ratio() is available])
	], [
		AC_DEFINE([vfs_pressure_ratio(val)],
			  [mult_frac((unsigned long)(val), sysctl_vfs_cache_pressure, 100)],
			  [vfs_pressure_ratio() is not available])
	])
]) 
AC_DEFUN([LC_SRC_OLDSIZE_TRUNCATE_PAGECACHE], [
	LB2_LINUX_TEST_SRC([truncate_pagecache_old_size], [
	],[
		truncate_pagecache(NULL, 0, 0);
	])
])
AC_DEFUN([LC_OLDSIZE_TRUNCATE_PAGECACHE], [
	LB2_MSG_LINUX_TEST_RESULT([if 'truncate_pagecache' with 'old_size' parameter],
	[truncate_pagecache_old_size], [
		AC_DEFINE(HAVE_OLDSIZE_TRUNCATE_PAGECACHE, 1,
			[with oldsize])
	])
]) 
AC_DEFUN([LC_SRC_PTR_ERR_OR_ZERO_MISSING], [
	LB2_LINUX_TEST_SRC([is_err_or_null], [
	],[
		if (PTR_ERR_OR_ZERO(NULL)) return 0;
	])
])
AC_DEFUN([LC_PTR_ERR_OR_ZERO_MISSING], [
	LB2_MSG_LINUX_TEST_RESULT([if 'PTR_ERR_OR_ZERO' is missing],
	[is_err_or_null], [
		AC_DEFINE(HAVE_PTR_ERR_OR_ZERO, 1,
			['PTR_ERR_OR_ZERO' exist])
	])
]) 
AC_DEFUN([LC_SRC_KIOCB_KI_LEFT], [
	LB2_LINUX_TEST_SRC([kiocb_ki_left], [
	],[
		((struct kiocb*)0)->ki_left = 0;
	])
])
AC_DEFUN([LC_KIOCB_KI_LEFT], [
	LB2_MSG_LINUX_TEST_RESULT([if 'struct kiocb' with 'ki_left' member],
	[kiocb_ki_left], [
		AC_DEFINE(HAVE_KIOCB_KI_LEFT, 1,
			[ki_left exist])
	])
]) 
AC_DEFUN([LC_SRC_VFS_RENAME_5ARGS], [
	LB2_LINUX_TEST_SRC([vfs_rename_5args], [
	],[
		vfs_rename(NULL, NULL, NULL, NULL, NULL);
	])
])
AC_DEFUN([LC_VFS_RENAME_5ARGS], [
	LB2_MSG_LINUX_TEST_RESULT([if Linux kernel has 'vfs_rename' with 5 args],
	[vfs_rename_5args], [
		AC_DEFINE(HAVE_VFS_RENAME_5ARGS, 1,
			[kernel has vfs_rename with 5 args])
	])
]) 
AC_DEFUN([LC_SRC_VFS_UNLINK_3ARGS], [
	LB2_LINUX_TEST_SRC([vfs_unlink_3args], [
	],[
		vfs_unlink(NULL, NULL, NULL);
	])
])
AC_DEFUN([LC_VFS_UNLINK_3ARGS], [
	LB2_MSG_LINUX_TEST_RESULT([if Linux kernel has 'vfs_unlink' with 3 args],
	[vfs_unlink_3args], [
		AC_DEFINE(HAVE_VFS_UNLINK_3ARGS, 1,
			[kernel has vfs_unlink with 3 args])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_BIP_ITER_BIO_INTEGRITY_PAYLOAD], [
	LB2_LINUX_TEST_SRC([bio_integrity_payload_bip_iter], [
	],[
		((struct bio_integrity_payload *)0)->bip_iter.bi_size = 0;
	])
])
AC_DEFUN([LC_HAVE_BIP_ITER_BIO_INTEGRITY_PAYLOAD], [
	LB2_MSG_LINUX_TEST_RESULT([if 'bio_integrity_payload.bip_iter' exist],
	[bio_integrity_payload_bip_iter], [
		AC_DEFINE(HAVE_BIP_ITER_BIO_INTEGRITY_PAYLOAD, 1,
			[bio_integrity_payload.bip_iter exist])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_BVEC_ITER], [
	LB2_LINUX_TEST_SRC([have_bvec_iter], [
	],[
		struct bvec_iter iter;
		iter.bi_bvec_done = 0;
	])
])
AC_DEFUN([LC_HAVE_BVEC_ITER], [
	LB2_MSG_LINUX_TEST_RESULT([if Linux kernel has struct bvec_iter],
	[have_bvec_iter], [
		AC_DEFINE(HAVE_BVEC_ITER, 1,
			[kernel has struct bvec_iter])
	])
]) 
AC_DEFUN([LC_SRC_IOP_SET_ACL], [
	LB2_LINUX_TEST_SRC([inode_ops_set_acl], [
	],[
		struct inode_operations iop;
		iop.set_acl = NULL;
	])
])
AC_DEFUN([LC_IOP_SET_ACL], [
	LB2_MSG_LINUX_TEST_RESULT([if 'inode_operations' has '.set_acl' member function],
	[inode_ops_set_acl], [
		AC_DEFINE(HAVE_IOP_SET_ACL, 1,
			[inode_operations has .set_acl member function])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_TRUNCATE_IPAGES_FINAL], [
	LB2_LINUX_TEST_SRC([truncate_ipages_final], [
	],[
		truncate_inode_pages_final(NULL);
	])
])
AC_DEFUN([LC_HAVE_TRUNCATE_IPAGES_FINAL], [
	LB2_MSG_LINUX_TEST_RESULT([if Linux kernel has truncate_inode_pages_final],
	[truncate_ipages_final], [
		AC_DEFINE(HAVE_TRUNCATE_INODE_PAGES_FINAL, 1,
			[kernel has truncate_inode_pages_final])
	])
]) 
AC_DEFUN([LC_SRC_IOPS_RENAME_WITH_FLAGS], [
	LB2_LINUX_TEST_SRC([iops_rename_with_flags], [
	],[
		struct inode_operations *iops = NULL;
		struct inode *i1 = NULL, *i2 = NULL;
		struct dentry *d1 = NULL, *d2 = NULL;
		iops->rename(i1, d1, i2, d2, 0);
	])
]) 
AC_DEFUN([LC_IOPS_RENAME_WITH_FLAGS], [
	LB2_MSG_LINUX_TEST_RESULT([if 'inode_operations->rename' taken flags as argument],
	[iops_rename_with_flags], [
		AC_DEFINE(HAVE_IOPS_RENAME_WITH_FLAGS, 1,
			[inode_operations->rename need flags as argument])
	])
]) 
AC_DEFUN([LC_SRC_VFS_RENAME_6ARGS], [
	LB2_LINUX_TEST_SRC([vfs_rename_6args], [
	],[
		vfs_rename(NULL, NULL, NULL, NULL, NULL, NULL);
	])
])
AC_DEFUN([LC_VFS_RENAME_6ARGS], [
	LB2_MSG_LINUX_TEST_RESULT([if Linux kernel has 'vfs_rename' with 6 args],
	[vfs_rename_6args], [
		AC_DEFINE(HAVE_VFS_RENAME_6ARGS, 1,
			[kernel has vfs_rename with 6 args])
	])
]) 
AC_DEFUN([LC_SRC_PMQOS_RESUME_LATENCY], [
        LB2_LINUX_TEST_SRC([pmqos_resume_latency], [
	], [
			struct dev_pm_qos_request req;
			struct device dev;
			dev_pm_qos_add_request(&dev, &req, DEV_PM_QOS_LATENCY, 0);
	])
])
AC_DEFUN([LC_PMQOS_RESUME_LATENCY], [
saved_flags="$CFLAGS"
CFLAGS="-Werror"
LB2_MSG_LINUX_TEST_RESULT([if 'DEV_PM_QOS_LATENCY' vs 'DEV_PM_QOS_RESUME_LATENCY'],
	[pmqos_resume_latency], [
		AC_DEFINE(DEV_PM_QOS_RESUME_LATENCY, DEV_PM_QOS_LATENCY, [using 'DEV_PM_QOS_LATENCY'])
	], [])
CFLAGS="$saved_flags"
])
AC_DEFUN([LC_SRC_DIRECTIO_USE_ITER], [
	LB2_LINUX_TEST_SRC([direct_io_iter], [
	],[
		struct address_space_operations ops = { };
		struct iov_iter *iter = NULL;
		loff_t offset = 0;
		ops.direct_IO(0, NULL, iter, offset);
	])
])
AC_DEFUN([LC_DIRECTIO_USE_ITER], [
	LB2_MSG_LINUX_TEST_RESULT([if direct IO uses iov_iter],
	[direct_io_iter], [
		AC_DEFINE(HAVE_DIRECTIO_ITER, 1, [direct IO uses iov_iter])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_IOV_ITER_INIT_DIRECTION], [
	LB2_LINUX_TEST_SRC([iter_init], [
	],[
		const struct iovec *iov = NULL;
		iov_iter_init(NULL, READ, iov, 1, 0);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_IOV_ITER_INIT_DIRECTION], [
	LB2_MSG_LINUX_TEST_RESULT([if 'iov_iter_init' takes a tag],
	[iter_init], [
		AC_DEFINE(HAVE_IOV_ITER_INIT_DIRECTION, 1,
			[iov_iter_init handles directional tag])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_IOV_ITER_TRUNCATE], [
	LB2_LINUX_TEST_SRC([iter_truncate], [
	],[
		struct iov_iter *i = NULL;
		iov_iter_truncate(i, 0);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_IOV_ITER_TRUNCATE], [
	LB2_MSG_LINUX_TEST_RESULT([if 'iov_iter_truncate' exists],
	[iter_truncate], [
		AC_DEFINE(HAVE_IOV_ITER_TRUNCATE, 1, [iov_iter_truncate exists])
	])
]) 
AC_DEFUN([LC_SRC_PAGECACHE_GET_PAGE], [
	LB2_LINUX_TEST_SRC([pagecache_get_page], [
	],[
		pagecache_get_page(NULL, 0, 0, 0);
	])
])
AC_DEFUN([LC_PAGECACHE_GET_PAGE], [
	LB2_MSG_LINUX_TEST_RESULT([if 'pagecache_get_page' exists],
	[pagecache_get_page], [
		AC_DEFINE(HAVE_PAGECACHE_GET_PAGE, 1,
			['pagecache_get_page' is available])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_INTERVAL_BLK_INTEGRITY], [
	LB2_LINUX_TEST_SRC([interval_blk_integrity], [
	],[
		((struct blk_integrity *)0)->interval = 0;
	])
])
AC_DEFUN([LC_HAVE_INTERVAL_BLK_INTEGRITY], [
	LB2_MSG_LINUX_TEST_RESULT([if 'blk_integrity.interval' exist],
	[interval_blk_integrity], [
		AC_DEFINE(HAVE_INTERVAL_BLK_INTEGRITY, 1,
			[blk_integrity.interval exist])
	])
]) 
AC_DEFUN([LC_SRC_KEY_MATCH_DATA], [
	LB2_LINUX_TEST_SRC([key_match], [
	],[
		struct key_match_data data;
		data.raw_data = NULL;
	])
])
AC_DEFUN([LC_KEY_MATCH_DATA], [
	LB2_MSG_LINUX_TEST_RESULT([if struct key_match field exist],
	[key_match], [
		AC_DEFINE(HAVE_KEY_MATCH_DATA, 1, [struct key_match_data exist])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_LM_GRANT_2ARGS], [
	LB2_LINUX_TEST_SRC([lock_manager_operations_lm_grant], [
	],[
		((struct lock_manager_operations *)NULL)->lm_grant(NULL, 0);
	])
])
AC_DEFUN([LC_HAVE_LM_GRANT_2ARGS], [
	LB2_MSG_LINUX_TEST_RESULT([if 'lock_manager_operations.lm_grant' takes two args],
	[lock_manager_operations_lm_grant], [
		AC_DEFINE(HAVE_LM_GRANT_2ARGS, 1,
			[lock_manager_operations.lm_grant takes two args])
	])
]) 
AC_DEFUN([LC_SRC_NFS_FILLDIR_USE_CTX], [
	LB2_LINUX_TEST_SRC([filldir_ctx], [
		int filldir(struct dir_context *ctx, const char* name,
			    int i, loff_t off, u64 tmp, unsigned temp);
		int filldir(struct dir_context *ctx, const char* name,
			    int i, loff_t off, u64 tmp, unsigned temp)
		{
			return 0;
		}
	],[
		struct dir_context ctx = {
			.actor = filldir,
		};
		ctx.actor(NULL, "test", 0, (loff_t) 0, 0, 0);
	],[-Werror])
])
AC_DEFUN([LC_NFS_FILLDIR_USE_CTX], [
	LB2_MSG_LINUX_TEST_RESULT([if filldir_t uses struct dir_context],
	[filldir_ctx], [
		AC_DEFINE(HAVE_FILLDIR_USE_CTX, 1,
			[filldir_t needs struct dir_context as argument])
	])
]) 
AC_DEFUN([LC_SRC_PERCPU_COUNTER_INIT], [
	LB2_LINUX_TEST_SRC([percpu_counter_init], [
	],[
		percpu_counter_init(NULL, 0, GFP_KERNEL);
	])
])
AC_DEFUN([LC_PERCPU_COUNTER_INIT], [
	LB2_MSG_LINUX_TEST_RESULT([if percpu_counter_init uses GFP_* flag as argument],
	[percpu_counter_init], [
		AC_DEFINE(HAVE_PERCPU_COUNTER_INIT_GFP_FLAG, 1,
			[percpu_counter_init uses GFP_* flag])
	])
]) 
AC_DEFUN([LC_SRC_KIOCB_HAS_NBYTES], [
	LB2_LINUX_TEST_SRC([ki_nbytes], [
	],[
		struct kiocb iocb = { };
		iocb.ki_nbytes = 0;
	])
])
AC_DEFUN([LC_KIOCB_HAS_NBYTES], [
	LB2_MSG_LINUX_TEST_RESULT([if struct kiocb has ki_nbytes field],
	[ki_nbytes], [
		AC_DEFINE(HAVE_KI_NBYTES, 1, [ki_nbytes field exist])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_DQUOT_QC_DQBLK], [
	LB2_LINUX_TEST_SRC([qc_dqblk], [
	],[
			struct quotactl_ops *ops = NULL;
			struct kqid kqid = { .type = USRQUOTA };
			struct qc_dqblk *qc = NULL;
			ops->set_dqblk(NULL, kqid, qc);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_DQUOT_QC_DQBLK], [
	LB2_MSG_LINUX_TEST_RESULT([if 'quotactl_ops.set_dqblk' takes struct qc_dqblk],
	[qc_dqblk], [
		AC_DEFINE(HAVE_DQUOT_QC_DQBLK, 1,
			[quotactl_ops.set_dqblk takes struct qc_dqblk])
		AC_DEFINE(HAVE_DQUOT_KQID, 1,
			[quotactl_ops.set_dqblk takes struct kqid])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_AIO_COMPLETE], [
	LB2_LINUX_TEST_SRC([aio_complete], [
	],[
		aio_complete(NULL, 0, 0);
	])
])
AC_DEFUN([LC_HAVE_AIO_COMPLETE], [
	LB2_MSG_LINUX_TEST_RESULT([if kernel has exported aio_complete()],
	[aio_complete], [
		AC_DEFINE(HAVE_AIO_COMPLETE, 1, [aio_complete defined])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_IS_ROOT_INODE], [
	LB2_LINUX_TEST_SRC([is_root_inode], [
	],[
		is_root_inode(NULL);
	],[])
])
AC_DEFUN([LC_HAVE_IS_ROOT_INODE], [
	LB2_MSG_LINUX_TEST_RESULT([if kernel has is_root_inode()],
	[is_root_inode], [
		AC_DEFINE(HAVE_IS_ROOT_INODE, 1, [is_root_inode defined])
	])
]) 
AC_DEFUN([LC_SRC_BACKING_DEV_INFO_REMOVAL], [
	LB2_LINUX_TEST_SRC([backing_dev_info], [
	],[
		struct address_space mapping;
		mapping.backing_dev_info = NULL;
	])
])
AC_DEFUN([LC_BACKING_DEV_INFO_REMOVAL], [
	LB2_MSG_LINUX_TEST_RESULT([if struct address_space has backing_dev_info],
	[backing_dev_info], [
		AC_DEFINE(HAVE_BACKING_DEV_INFO, 1, [backing_dev_info exist])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_PROJECT_QUOTA], [
	LB2_LINUX_TEST_SRC([get_projid], [
		struct inode;
	],[
		struct dquot_operations ops = { };
		ops.get_projid(NULL, NULL);
	])
])
AC_DEFUN([LC_HAVE_PROJECT_QUOTA], [
	LB2_MSG_LINUX_TEST_RESULT([if get_projid exists],
	[get_projid], [
		AC_DEFINE(HAVE_PROJECT_QUOTA, 1,
			[get_projid function exists])
	])
]) 
AC_DEFUN([LC_SRC_IOV_ITER_RW], [
	LB2_LINUX_TEST_SRC([iov_iter_rw], [
	],[
		struct iov_iter *iter = NULL;
		iov_iter_rw(iter);
	])
])
AC_DEFUN([LC_IOV_ITER_RW], [
	LB2_MSG_LINUX_TEST_RESULT([if iov_iter_rw exists],
	[iov_iter_rw], [
		AC_DEFINE(HAVE_IOV_ITER_RW, 1, [iov_iter_rw exists])
	])
]) 
AC_DEFUN([LC_SRC_HAVE___BI_CNT], [
	LB2_LINUX_TEST_SRC([have___bi_cnt], [
	],[
		struct bio bio = { };
		int cnt;
		cnt = atomic_read(&bio.__bi_cnt);
	])
])
AC_DEFUN([LC_HAVE___BI_CNT], [
	LB2_MSG_LINUX_TEST_RESULT([if Linux kernel has __bi_cnt in struct bio],
	[have___bi_cnt], [
		AC_DEFINE(HAVE___BI_CNT, 1, [struct bio has __bi_cnt])
	])
]) 
AC_DEFUN([LC_SRC_SYMLINK_OPS_USE_NAMEIDATA], [
	LB2_LINUX_TEST_SRC([symlink_use_nameidata], [
	],[
		struct inode_operations *iops = NULL;
		struct nameidata *nd = NULL;
		iops->follow_link(NULL, nd);
		iops->put_link(NULL, nd, NULL);
	])
])
AC_DEFUN([LC_SYMLINK_OPS_USE_NAMEIDATA], [
	LB2_MSG_LINUX_TEST_RESULT(
	[if symlink inode operations have struct nameidata argument],
	[symlink_use_nameidata], [
		AC_DEFINE(HAVE_SYMLINK_OPS_USE_NAMEIDATA, 1,
			[symlink inode operations need struct nameidata argument])
	])
]) 
AC_DEFUN([LC_SRC_BIO_ENDIO_USES_ONE_ARG], [
	LB2_LINUX_TEST_SRC([bio_endio], [
	],[
		bio_endio(NULL);
	])
])
AC_DEFUN([LC_BIO_ENDIO_USES_ONE_ARG], [
	LB2_MSG_LINUX_TEST_RESULT([if 'bio_endio' with one argument exist],
	[bio_endio], [
		AC_DEFINE(HAVE_BIO_ENDIO_USES_ONE_ARG, 1,
			[bio_endio takes only one argument])
	])
]) 
AC_DEFUN([LC_SRC_ACCOUNT_PAGE_DIRTIED_3ARGS], [
	LB2_LINUX_TEST_SRC([account_page_dirtied_3a], [
	],[
		account_page_dirtied(NULL, NULL, NULL);
	])
])
AC_DEFUN([LC_ACCOUNT_PAGE_DIRTIED_3ARGS], [
	LB2_MSG_LINUX_TEST_RESULT([if 'account_page_dirtied' with 3 args exists],
	[account_page_dirtied_3a], [
		AC_DEFINE(HAVE_ACCOUNT_PAGE_DIRTIED_3ARGS, 1,
			[account_page_dirtied takes three arguments])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_CRYPTO_ALLOC_SKCIPHER], [
	LB2_LINUX_TEST_SRC([crypto_alloc_skcipher], [
	],[
		crypto_alloc_skcipher(NULL, 0, 0);
	])
])
AC_DEFUN([LC_HAVE_CRYPTO_ALLOC_SKCIPHER], [
	LB2_MSG_LINUX_TEST_RESULT([if crypto_alloc_skcipher is defined],
	[crypto_alloc_skcipher], [
		AC_DEFINE(HAVE_CRYPTO_ALLOC_SKCIPHER, 1,
			[crypto_alloc_skcipher is defined])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_INTERVAL_EXP_BLK_INTEGRITY], [
	LB2_LINUX_TEST_SRC([blk_integrity_interval_exp], [
	],[
		((struct blk_integrity *)0)->interval_exp = 0;
	])
])
AC_DEFUN([LC_HAVE_INTERVAL_EXP_BLK_INTEGRITY], [
	LB2_MSG_LINUX_TEST_RESULT([if 'blk_integrity.interval_exp' exist],
	[blk_integrity_interval_exp], [
		AC_DEFINE(HAVE_INTERVAL_EXP_BLK_INTEGRITY, 1,
			[blk_integrity.interval_exp exist])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_CACHE_HEAD_HLIST], [
	LB2_LINUX_TEST_SRC([cache_head_has_hlist], [
	],[
		do {} while(sizeof(((struct cache_head *)0)->cache_list));
	])
])
AC_DEFUN([LC_HAVE_CACHE_HEAD_HLIST], [
	LB2_MSG_LINUX_TEST_RESULT([if 'struct cache_head' has 'cache_list' field],
	[cache_head_has_hlist], [
		AC_DEFINE(HAVE_CACHE_HEAD_HLIST, 1,
			[cache_head has hlist cache_list])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_XATTR_HANDLER_SIMPLIFIED], [
	LB2_LINUX_TEST_SRC([xattr_handler_simplified], [
	],[
		struct xattr_handler handler;
		((struct xattr_handler *)0)->get(&handler, NULL, NULL, NULL, 0);
		((struct xattr_handler *)0)->set(&handler, NULL, NULL, NULL, 0, 0);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_XATTR_HANDLER_SIMPLIFIED], [
	LB2_MSG_LINUX_TEST_RESULT(
	[if 'struct xattr_handler' functions pass in handler pointer],
	[xattr_handler_simplified], [
		AC_DEFINE(HAVE_XATTR_HANDLER_SIMPLIFIED, 1,
			[handler pointer is parameter])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_BI_OPF], [
	LB2_LINUX_TEST_SRC([have_bi_opf], [
	],[
		struct bio bio;
		bio.bi_opf = 0;
	])
])
AC_DEFUN([LC_HAVE_BI_OPF], [
	LB2_MSG_LINUX_TEST_RESULT([if Linux kernel has bi_opf in struct bio],
	[have_bi_opf], [
		AC_DEFINE(HAVE_BI_OPF, 1, [struct bio has bi_opf])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_SUBMIT_BIO_2ARGS], [
	LB2_LINUX_TEST_SRC([have_submit_bio_2args], [
	],[
		struct bio bio;
		submit_bio(READ, &bio);
	])
])
AC_DEFUN([LC_HAVE_SUBMIT_BIO_2ARGS], [
	LB2_MSG_LINUX_TEST_RESULT([if submit_bio takes two arguments],
	[have_submit_bio_2args], [
		AC_DEFINE(HAVE_SUBMIT_BIO_2ARGS, 1,
			[submit_bio takes two arguments])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_CLEAN_BDEV_ALIASES], [
	LB2_LINUX_TEST_SRC([have_clean_bdev_aliases], [
	],[
		clean_bdev_aliases(NULL,1,1);
	])
])
AC_DEFUN([LC_HAVE_CLEAN_BDEV_ALIASES], [
	LB2_MSG_LINUX_TEST_RESULT([if kernel has clean_bdev_aliases],
	[have_clean_bdev_aliases], [
		AC_DEFINE(HAVE_CLEAN_BDEV_ALIASES, 1,
			[kernel has clean_bdev_aliases])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_LOCKS_LOCK_FILE_WAIT], [
	LB2_LINUX_TEST_SRC([locks_lock_file_wait], [
	],[
		locks_lock_file_wait(NULL, NULL);
	])
])
AC_DEFUN([LC_HAVE_LOCKS_LOCK_FILE_WAIT], [
	LB2_MSG_LINUX_TEST_RESULT([if 'locks_lock_file_wait' exists],
	[locks_lock_file_wait], [
		AC_DEFINE(HAVE_LOCKS_LOCK_FILE_WAIT, 1,
			[kernel has locks_lock_file_wait])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_KEY_PAYLOAD_DATA_ARRAY], [
	LB2_LINUX_TEST_SRC([key_payload_data_array], [
	],[
		struct key key = { };
		key.payload.data[0] = NULL;
	])
])
AC_DEFUN([LC_HAVE_KEY_PAYLOAD_DATA_ARRAY], [
	LB2_MSG_LINUX_TEST_RESULT([if 'struct key' has 'payload.data' as an array],
	[key_payload_data_array], [
		AC_DEFINE(HAVE_KEY_PAYLOAD_DATA_ARRAY, 1, [payload.data is an array])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_XATTR_HANDLER_NAME], [
	LB2_LINUX_TEST_SRC([xattr_handler_name], [
	],[
		((struct xattr_handler *)NULL)->name = NULL;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_XATTR_HANDLER_NAME], [
	LB2_MSG_LINUX_TEST_RESULT([if 'struct xattr_handler' has a name member],
	[xattr_handler_name], [
		AC_DEFINE(HAVE_XATTR_HANDLER_NAME, 1,
			[xattr_handler has a name member])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_FILE_DENTRY], [
	LB2_LINUX_TEST_SRC([file_dentry], [
	],[
		file_dentry(NULL);
	])
])
AC_DEFUN([LC_HAVE_FILE_DENTRY], [
	LB2_MSG_LINUX_TEST_RESULT([if Linux kernel has 'file_dentry'],
	[file_dentry], [
		AC_DEFINE(HAVE_FILE_DENTRY, 1, [kernel has file_dentry])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_INODE_LOCK], [
	LB2_LINUX_TEST_SRC([inode_lock], [
	],[
		inode_lock(NULL);
	])
])
AC_DEFUN([LC_HAVE_INODE_LOCK], [
	LB2_MSG_LINUX_TEST_RESULT([if 'inode_lock' is defined],
	[inode_lock], [
		AC_DEFINE(HAVE_INODE_LOCK, 1, [inode_lock is defined])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_IOP_GET_LINK], [
	LB2_LINUX_TEST_SRC([inode_ops_get_link], [
	],[
		struct inode_operations iop;
		iop.get_link = NULL;
	])
])
AC_DEFUN([LC_HAVE_IOP_GET_LINK], [
	LB2_MSG_LINUX_TEST_RESULT([if 'iop' has 'get_link'],
	[inode_ops_get_link], [
		AC_DEFINE(HAVE_IOP_GET_LINK, 1, [have iop get_link])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_IN_COMPAT_SYSCALL], [
	LB2_LINUX_TEST_SRC([in_compat_syscall], [
	],[
		in_compat_syscall();
	])
])
AC_DEFUN([LC_HAVE_IN_COMPAT_SYSCALL], [
	LB2_MSG_LINUX_TEST_RESULT([if 'in_compat_syscall' is defined],
	[in_compat_syscall], [
		AC_DEFINE(HAVE_IN_COMPAT_SYSCALL, 1, [have in_compat_syscall])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_XATTR_HANDLER_INODE_PARAM], [
	LB2_LINUX_TEST_SRC([xattr_handler_inode_param], [
	],[
		const struct xattr_handler handler;
		((struct xattr_handler *)0)->get(&handler, NULL, NULL, NULL, NULL, 0);
		((struct xattr_handler *)0)->set(&handler, NULL, NULL, NULL, NULL, 0, 0);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_XATTR_HANDLER_INODE_PARAM], [
	LB2_MSG_LINUX_TEST_RESULT([if 'struct xattr_handler' functions have inode parameter],
	[xattr_handler_inode_param], [
		AC_DEFINE(HAVE_XATTR_HANDLER_INODE_PARAM, 1, [needs inode parameter])
	])
]) 
AC_DEFUN([LC_SRC_D_IN_LOOKUP], [
	LB2_LINUX_TEST_SRC([d_in_lookup], [
	],[
		d_in_lookup(NULL);
	],[-Werror])
])
AC_DEFUN([LC_D_IN_LOOKUP], [
	LB2_MSG_LINUX_TEST_RESULT([if 'd_in_lookup' is defined],
	[d_in_lookup], [
		AC_DEFINE(HAVE_D_IN_LOOKUP, 1, [d_in_lookup is defined])
	])
]) 
AC_DEFUN([LC_SRC_LOCK_PAGE_MEMCG], [
	LB2_LINUX_TEST_SRC([lock_page_memcg], [
	],[
		lock_page_memcg(NULL);
	],[-Werror])
])
AC_DEFUN([LC_LOCK_PAGE_MEMCG], [
	LB2_MSG_LINUX_TEST_RESULT([if 'lock_page_memcg' is defined],
	[lock_page_memcg], [
		AC_DEFINE(HAVE_LOCK_PAGE_MEMCG, 1, [lock_page_memcg is defined])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_DOWN_WRITE_KILLABLE], [
	LB2_LINUX_TEST_SRC([down_write_killable], [
		struct rw_semaphore sem;
	],[
		int rc;
		rc = down_write_killable(&sem);
		(void)rc;
	])
])
AC_DEFUN([LC_HAVE_DOWN_WRITE_KILLABLE], [
	LB2_MSG_LINUX_TEST_RESULT([if down_write_killable exists],
	[down_write_killable], [
		AC_DEFINE(HAVE_DOWN_WRITE_KILLABLE, 1,
			[down_write_killable function exists])
	])
]) 
AC_DEFUN([LC_SRC_DIRECTIO_2ARGS], [
	LB2_LINUX_TEST_SRC([direct_io_2args], [
	],[
		struct address_space_operations ops = { };
		struct iov_iter *iter = NULL;
		struct kiocb *iocb = NULL;
		int rc;
		rc = ops.direct_IO(iocb, iter);
	])
])
AC_DEFUN([LC_DIRECTIO_2ARGS], [
	LB2_MSG_LINUX_TEST_RESULT([if '->direct_IO()' takes 2 arguments],
	[direct_io_2args], [
		AC_DEFINE(HAVE_DIRECTIO_2ARGS, 1, [direct_IO has 2 arguments])
	])
]) 
AC_DEFUN([LC_SRC_GENERIC_WRITE_SYNC_2ARGS], [
	LB2_LINUX_TEST_SRC([generic_write_sync_2args], [
	],[
		struct kiocb *iocb = NULL;
		ssize_t rc;
		rc = generic_write_sync(iocb, 0);
	])
])
AC_DEFUN([LC_GENERIC_WRITE_SYNC_2ARGS], [
	LB2_MSG_LINUX_TEST_RESULT([if 'generic_write_sync()' takes 2 arguments],
	[generic_write_sync_2args], [
		AC_DEFINE(HAVE_GENERIC_WRITE_SYNC_2ARGS, 1,
			[generic_write_sync has 2 arguments])
	])
]) 
AC_DEFUN([LC_SRC_FOP_ITERATE_SHARED], [
	LB2_LINUX_TEST_SRC([fop_iterate_shared], [
	],[
		struct file_operations fop;
		fop.iterate_shared = NULL;
	])
])
AC_DEFUN([LC_FOP_ITERATE_SHARED], [
	LB2_MSG_LINUX_TEST_RESULT([if 'file_operations' has 'iterate_shared'],
	[fop_iterate_shared], [
		AC_DEFINE(HAVE_FOP_ITERATE_SHARED, 1,
			[file_operations has iterate_shared])
	])
]) 
AC_DEFUN([LC_EXPORT_DEFAULT_FILE_SPLICE_READ], [
LB_CHECK_EXPORT([default_file_splice_read], [fs/splice.c],
	[AC_DEFINE(HAVE_DEFAULT_FILE_SPLICE_READ_EXPORT, 1,
			[default_file_splice_read is exported])])
]) 
AC_DEFUN([LC_SRC_HAVE_POSIX_ACL_VALID_USER_NS], [
	LB2_LINUX_TEST_SRC([posix_acl_valid], [
	],[
		posix_acl_valid((struct user_namespace*)NULL, (const struct posix_acl*)NULL);
	])
])
AC_DEFUN([LC_HAVE_POSIX_ACL_VALID_USER_NS], [
	LB2_MSG_LINUX_TEST_RESULT([if 'posix_acl_valid' takes 'struct user_namespace'],
	[posix_acl_valid], [
		AC_DEFINE(HAVE_POSIX_ACL_VALID_USER_NS, 1,
			[posix_acl_valid takes struct user_namespace])
	])
]) 
AC_DEFUN([LC_SRC_FULL_NAME_HASH_3ARGS], [
	LB2_LINUX_TEST_SRC([full_name_hash_3args], [
	],[
		unsigned int hash;
		hash = full_name_hash(NULL,NULL,0);
	])
])
AC_DEFUN([LC_FULL_NAME_HASH_3ARGS], [
	LB2_MSG_LINUX_TEST_RESULT([if 'full_name_hash' taken 3 arguments],
	[full_name_hash_3args], [
		AC_DEFINE(HAVE_FULL_NAME_HASH_3ARGS, 1,
			[full_name_hash need 3 arguments])
	])
]) 
AC_DEFUN([LC_SRC_STRUCT_POSIX_ACL_XATTR], [
	LB2_LINUX_TEST_SRC([struct_posix_acl_xattr], [
	],[
		struct posix_acl_xattr_header *h = NULL;
		struct posix_acl_xattr_entry  *e;
		e = (void *)(h + 1);
	])
])
AC_DEFUN([LC_STRUCT_POSIX_ACL_XATTR], [
	LB2_MSG_LINUX_TEST_RESULT([if 'struct posix_acl_xattr_{header,entry}' defined],
	[struct_posix_acl_xattr], [
		AC_DEFINE(HAVE_STRUCT_POSIX_ACL_XATTR, 1,
			[struct posix_acl_xattr_{header,entry} defined])
	])
]) 
AC_DEFUN([LC_SRC_IOP_XATTR], [
	LB2_LINUX_TEST_SRC([inode_ops_xattr], [
	],[
		struct inode_operations iop;
		iop.setxattr = NULL;
		iop.getxattr = NULL;
		iop.removexattr = NULL;
	])
])
AC_DEFUN([LC_IOP_XATTR], [
	LB2_MSG_LINUX_TEST_RESULT([if 'inode_operations' has {get,set,remove}xattr members],
	[inode_ops_xattr], [
		AC_DEFINE(HAVE_IOP_XATTR, 1,
			[inode_operations has {get,set,remove}xattr members])
	])
]) 
AC_DEFUN([LC_SRC_GROUP_INFO_GID], [
	LB2_LINUX_TEST_SRC([group_info_gid], [
	],[
		kgid_t *p;
		p = ((struct group_info *)0)->gid;
	])
])
AC_DEFUN([LC_GROUP_INFO_GID], [
	LB2_MSG_LINUX_TEST_RESULT([if 'struct group_info' has member 'gid'],
	[group_info_gid], [
		AC_DEFINE(HAVE_GROUP_INFO_GID, 1,
			[struct group_info has member gid])
	])
]) 
AC_DEFUN([LC_SRC_VFS_SETXATTR], [
	LB2_LINUX_TEST_SRC([vfs_setxattr], [
	],[
		__vfs_setxattr(NULL, NULL, NULL, NULL, 0, 0);
	])
])
AC_DEFUN([LC_VFS_SETXATTR], [
	LB2_MSG_LINUX_TEST_RESULT([if '__vfs_setxattr' helper is available],
	[vfs_setxattr], [
		AC_DEFINE(HAVE_VFS_SETXATTR, 1, ['__vfs_setxattr' is available])
	])
]) 
AC_DEFUN([LC_SRC_POSIX_ACL_UPDATE_MODE], [
	LB2_LINUX_TEST_SRC([posix_acl_update_mode], [
	],[
		posix_acl_update_mode(NULL, NULL, NULL);
	])
])
AC_DEFUN([LC_POSIX_ACL_UPDATE_MODE], [
	LB2_MSG_LINUX_TEST_RESULT([if 'posix_acl_update_mode' exists],
	[posix_acl_update_mode], [
		AC_DEFINE(HAVE_POSIX_ACL_UPDATE_MODE, 1,
			['posix_acl_update_mode' is available])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_BDI_IO_PAGES], [
	LB2_LINUX_TEST_SRC([bdi_has_io_pages], [
	],[
		struct backing_dev_info info;
		info.io_pages = 0;
	])
])
AC_DEFUN([LC_HAVE_BDI_IO_PAGES], [
	LB2_MSG_LINUX_TEST_RESULT([if 'struct backing_dev_info' has 'io_pages' field],
	[bdi_has_io_pages], [
		AC_DEFINE(HAVE_BDI_IO_PAGES, 1,
			[backing_dev_info has io_pages])
	])
]) 
AC_DEFUN([LC_SRC_RADIX_TREE_REPLACE_SLOT_3ARGS], [
	LB2_LINUX_TEST_SRC([radix_tree_replace_slot_3args], [
	],[
		radix_tree_replace_slot(NULL, NULL, NULL);
	])
])
AC_DEFUN([LC_RADIX_TREE_REPLACE_SLOT_3ARGS], [
	AC_MSG_CHECKING([if 'radix_tree_replace_slot' has 3 args])
	LB2_LINUX_TEST_RESULT([radix_tree_replace_slot_3args], [
		AC_DEFINE(HAVE_RADIX_TREE_REPLACE_SLOT_3ARGS, 1,
			[radix_tree_replace_slot has 3 args])
	])
]) 
AC_DEFUN([LC_SRC_IOP_GENERIC_READLINK], [
	LB2_LINUX_TEST_SRC([inode_ops_readlink], [
	],[
		struct inode_operations iop;
		iop.readlink = generic_readlink;
	])
])
AC_DEFUN([LC_IOP_GENERIC_READLINK], [
	LB2_MSG_LINUX_TEST_RESULT([if 'generic_readlink' still exist],
	[inode_ops_readlink], [
		AC_DEFINE(HAVE_IOP_GENERIC_READLINK, 1,
			[generic_readlink has been removed])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_VM_FAULT_ADDRESS], [
	LB2_LINUX_TEST_SRC([vm_fault_address], [
	],[
		struct vm_fault vmf = { 0 };
		unsigned long addr = (unsigned long)vmf.address;
		(void)addr;
	])
])
AC_DEFUN([LC_HAVE_VM_FAULT_ADDRESS], [
	LB2_MSG_LINUX_TEST_RESULT([if 'struct vm_fault' replaced virtual_address with address field],
	[vm_fault_address], [
		AC_DEFINE(HAVE_VM_FAULT_ADDRESS, 1,
			[virtual_address has been replaced by address field])
	])
]) 
AC_DEFUN([LC_SRC_INODEOPS_ENHANCED_GETATTR], [
	LB2_LINUX_TEST_SRC([getattr_path], [
	],[
		struct inode_operations *iops = NULL;
		struct path path;
		iops->getattr(&path, NULL, 0, 0);
	])
])
AC_DEFUN([LC_INODEOPS_ENHANCED_GETATTR], [
	LB2_MSG_LINUX_TEST_RESULT([if 'inode_operations' getattr member can gather advance stats],
	[getattr_path], [
		AC_DEFINE(HAVE_INODEOPS_ENHANCED_GETATTR, 1,
			[inode_operations .getattr member function can gather advance stats])
	])
]) 
AC_DEFUN([LC_SRC_VM_OPERATIONS_REMOVE_VMF_ARG], [
	LB2_LINUX_TEST_SRC([vm_operations_no_vm_area_struct], [
	],[
		struct vm_fault vmf;
		((struct vm_operations_struct *)0)->fault(&vmf);
		((struct vm_operations_struct *)0)->page_mkwrite(&vmf);
	])
])
AC_DEFUN([LC_VM_OPERATIONS_REMOVE_VMF_ARG], [
	LB2_MSG_LINUX_TEST_RESULT([if 'struct vm_operations' removed struct vm_area_struct],
	[vm_operations_no_vm_area_struct], [
		AC_DEFINE(HAVE_VM_OPS_USE_VM_FAULT_ONLY, 1,
			['struct vm_operations' remove struct vm_area_struct argument])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_KEY_USAGE_REFCOUNT], [
	LB2_LINUX_TEST_SRC([key_usage_refcount], [
	],[
		struct key key = { };
		refcount_read(&key.usage);
	])
])
AC_DEFUN([LC_HAVE_KEY_USAGE_REFCOUNT], [
	LB2_MSG_LINUX_TEST_RESULT([if 'key.usage' is refcount_t],
	[key_usage_refcount], [
		AC_DEFINE(HAVE_KEY_USAGE_REFCOUNT, 1,
			[key.usage is of type refcount_t])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_CRYPTO_MAX_ALG_NAME_128], [
	LB2_LINUX_TEST_SRC([crypto_max_alg_name], [
	],[
		exit(1);
	])
])
AC_DEFUN([LC_HAVE_CRYPTO_MAX_ALG_NAME_128], [
	LB2_MSG_LINUX_TEST_RESULT([if 'CRYPTO_MAX_ALG_NAME' is 128],
	[crypto_max_alg_name], [
		AC_DEFINE(HAVE_CRYPTO_MAX_ALG_NAME_128, 1,
			['CRYPTO_MAX_ALG_NAME' is 128])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_FSMAP_HEADER], [
	LB2_CHECK_LINUX_HEADER_SRC([linux/fsmap.h], [-Werror])
])
AC_DEFUN([LC_HAVE_FSMAP_HEADER], [
	LB2_CHECK_LINUX_HEADER_RESULT([linux/fsmap.h], [
		AC_DEFINE(HAVE_FSMAP_H, 1,
			[fsmap.h is present])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_PERCPU_COUNTER_ADD_BATCH], [
	LB2_LINUX_TEST_SRC([percpu_counter_add_batch_exists], [
	],[
		(void)percpu_counter_add_batch(NULL, 0, 0);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_PERCPU_COUNTER_ADD_BATCH], [
	LB2_MSG_LINUX_TEST_RESULT([if 'percpu_counter_add_batch()' exists],
	[percpu_counter_add_batch_exists], [
		AC_DEFINE(HAVE_PERCPU_COUNTER_ADD_BATCH, 1,
			['percpu_counter_add_batch()' exists])
	])
]) 
AC_DEFUN([LC_SRC_CURRENT_TIME], [
	LB2_LINUX_TEST_SRC([current_time], [
	],[
		struct iattr attr;
		attr.ia_atime = current_time(NULL);
	])
])
AC_DEFUN([LC_CURRENT_TIME], [
	LB2_MSG_LINUX_TEST_RESULT([if CURRENT_TIME has been replaced with current_time],
	[current_time], [
		AC_DEFINE(HAVE_CURRENT_TIME, 1,
			[current_time() has replaced CURRENT_TIME])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_GET_INODE_USAGE], [
	LB2_LINUX_TEST_SRC([get_inode_usage], [
		struct inode;
	],[
		struct dquot_operations ops = { };
		ops.get_inode_usage(NULL, NULL);
	])
])
AC_DEFUN([LC_HAVE_GET_INODE_USAGE], [
	LB2_MSG_LINUX_TEST_RESULT([if get_inode_usage exists],
	[get_inode_usage], [
		AC_DEFINE(HAVE_GET_INODE_USAGE, 1,
			[get_inode_usage function exists])
	])
]) 
AC_DEFUN([LC_SRC_SUPER_SETUP_BDI_NAME], [
	LB2_LINUX_TEST_SRC([super_setup_bdi_name], [
	],[
		super_setup_bdi_name(NULL, "grumple");
	])
])
AC_DEFUN([LC_SUPER_SETUP_BDI_NAME], [
	LB2_MSG_LINUX_TEST_RESULT([if 'super_setup_bdi_name' exist],
	[super_setup_bdi_name], [
		AC_DEFINE(HAVE_SUPER_SETUP_BDI_NAME, 1,
			['super_setup_bdi_name' is available])
	])
]) 
AC_DEFUN([LC_SRC_BI_STATUS], [
	LB2_LINUX_TEST_SRC([bi_status], [
	],[
		((struct bio *)0)->bi_status = 0;
	])
])
AC_DEFUN([LC_BI_STATUS], [
	LB2_MSG_LINUX_TEST_RESULT([if 'bi_status' exists],
	[bi_status], [
		AC_DEFINE(HAVE_BI_STATUS, 1, ['bi_status' is available])
	])
]) 
AC_DEFUN([LC_SRC_PAGEVEC_INIT_ONE_PARAM], [
	LB2_LINUX_TEST_SRC([pagevec_init], [
	],[
		pagevec_init(NULL);
	])
])
AC_DEFUN([LC_PAGEVEC_INIT_ONE_PARAM], [
	LB2_MSG_LINUX_TEST_RESULT([if 'pagevec_init' takes one parameter],
	[pagevec_init], [
		AC_DEFINE(HAVE_PAGEVEC_INIT_ONE_PARAM, 1,
			['pagevec_init' takes one parameter])
	])
]) 
AC_DEFUN([LC_SRC_PAGEVEC_LOOKUP_THREE_PARAM], [
	LB2_LINUX_TEST_SRC([pagevec_lookup_3args], [
	],[
		pagevec_lookup(NULL, NULL, NULL);
	])
])
AC_DEFUN([LC_PAGEVEC_LOOKUP_THREE_PARAM], [
	LB2_MSG_LINUX_TEST_RESULT([if 'pagevec_lookup' takes three parameter],
	[pagevec_lookup_3args], [
		AC_DEFINE(HAVE_PAGEVEC_LOOKUP_THREE_PARAM, 1,
			['pagevec_lookup' takes three parameters])
	])
]) 
AC_DEFUN([LC_SRC_BI_BDEV], [
	LB2_LINUX_TEST_SRC([bi_bdev], [
	],[
		((struct bio *)0)->bi_bdev = NULL;
	])
])
AC_DEFUN([LC_BI_BDEV], [
	LB2_MSG_LINUX_TEST_RESULT([if 'bi_bdev' exists],
	[bi_bdev], [
		AC_DEFINE(HAVE_BI_BDEV, 1, ['bi_bdev' is available])
	])
]) 
AC_DEFUN([LC_SRC_INTERVAL_TREE_CACHED], [
	LB2_LINUX_TEST_SRC([itree_cached], [
		struct foo { struct rb_node rb; int last; int a,b;};
		struct rb_root_cached tree;
		/* forward declare functions created by INTERVAL_TREE_DEFINE */
		void ftree_insert(struct foo *, struct rb_root_cached *);
		void ftree_remove(struct foo *, struct rb_root_cached *);
		struct foo *ftree_iter_first(struct rb_root_cached *, int, int);
		struct foo *ftree_iter_next(struct foo *, int, int);
		INTERVAL_TREE_DEFINE(struct foo, rb, int, last,
			START, LAST, , ftree);
	],[
		ftree_insert(NULL, &tree);
	],[-Werror])
])
AC_DEFUN([LC_INTERVAL_TREE_CACHED], [
	LB2_MSG_LINUX_TEST_RESULT([if interval_trees use rb_tree_cached],
	[itree_cached], [
		AC_DEFINE(HAVE_INTERVAL_TREE_CACHED, 1,
			[interval trees use rb_tree_cached])
	])
]) 
AC_DEFUN([LC_SRC_IS_ENCRYPTED], [
	LB2_LINUX_TEST_SRC([is_encrypted], [
	],[
		(void)IS_ENCRYPTED((struct inode *)1);
	])
])
AC_DEFUN([LC_IS_ENCRYPTED], [
	LB2_MSG_LINUX_TEST_RESULT([if IS_ENCRYPTED is defined],
	[is_encrypted], [
		has_is_encrypted="yes"
	])
]) 
AC_DEFUN([LC_SRC_I_PAGES], [
	LB2_LINUX_TEST_SRC([i_pages], [
	],[
		struct address_space mapping = {};
		void *i_pages;
		i_pages = &mapping.i_pages;
	])
])
AC_DEFUN([LC_I_PAGES], [
	LB2_MSG_LINUX_TEST_RESULT([if struct address_space has i_pages],
	[i_pages], [
		AC_DEFINE(HAVE_I_PAGES, 1, [struct address_space has i_pages])
	])
]) 
AC_DEFUN([LC_SRC_VM_FAULT_T], [
	LB2_LINUX_TEST_SRC([vm_fault_t], [
	],[
		vm_fault_t x = VM_FAULT_SIGBUS;
		(void)x
	])
])
AC_DEFUN([LC_VM_FAULT_T], [
	LB2_MSG_LINUX_TEST_RESULT([if vm_fault_t type exists],
	[vm_fault_t], [
		AC_DEFINE(HAVE_VM_FAULT_T, 1, [if vm_fault_t type exists])
	])
]) 
AC_DEFUN([LC_SRC_VM_FAULT_RETRY], [
	LB2_LINUX_TEST_SRC([VM_FAULT_RETRY], [
	],[
			vm_fault_t x;
			x = VM_FAULT_RETRY;
	])
])
AC_DEFUN([LC_VM_FAULT_RETRY], [
	LB2_MSG_LINUX_TEST_RESULT([if VM_FAULT_RETRY is defined],
	[VM_FAULT_RETRY], [
		AC_DEFINE(HAVE_VM_FAULT_RETRY, 1,
			[if VM_FAULT_RETRY is defined])
	])
]) 
AC_DEFUN([LC_SRC_ALLOC_FILE_PSEUDO], [
	LB2_LINUX_TEST_SRC([alloc_file_pseudo], [
	],[
		struct file *file;
		file = alloc_file_pseudo(NULL, NULL, "[test]",
					 00000002, NULL);
	])
])
AC_DEFUN([LC_ALLOC_FILE_PSEUDO], [
	LB2_MSG_LINUX_TEST_RESULT([if 'alloc_file_pseudo' is defined],
	[alloc_file_pseudo], [
		AC_DEFINE(HAVE_ALLOC_FILE_PSEUDO, 1,
			['alloc_file_pseudo' exist])
	])
]) 
AC_DEFUN([LC_SRC_INODE_TIMESPEC64], [
	LB2_LINUX_TEST_SRC([inode_timespec64], [
	],[
		struct inode *inode = NULL;
		struct timespec64 ts = {0, 1};
		inode->i_atime = ts;
		(void)inode;
	],[-Werror])
])
AC_DEFUN([LC_INODE_TIMESPEC64], [
	LB2_MSG_LINUX_TEST_RESULT([if inode timestamps are struct timespec64],
	[inode_timespec64], [
		AC_DEFINE(HAVE_INODE_TIMESPEC64, 1,
			[inode times are using timespec64])
	])
]) 
AC_DEFUN([LC_SRC_UAPI_LINUX_MOUNT_H], [
	LB2_LINUX_TEST_SRC([uapi_linux_mount], [
	],[
		int x = MS_RDONLY;
		(void)x;
	],[-Werror])
])
AC_DEFUN([LC_UAPI_LINUX_MOUNT_H], [
	LB2_MSG_LINUX_TEST_RESULT([if MS_RDONLY was moved to uapi/linux/mount.h],
	[uapi_linux_mount], [
		AC_DEFINE(HAVE_UAPI_LINUX_MOUNT_H, 1,
			[if MS_RDONLY was moved to uapi/linux/mount.h])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_SUNRPC_CACHE_HASH_LOCK_IS_A_SPINLOCK], [
	LB2_LINUX_TEST_SRC([hash_lock_isa_spinlock_t], [
	],[
		spinlock_t *lock = &(((struct cache_detail *)0)->hash_lock);
		spin_lock(lock);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_SUNRPC_CACHE_HASH_LOCK_IS_A_SPINLOCK], [
	LB2_MSG_LINUX_TEST_RESULT([if cache_detail->hash_lock is a spinlock],
	[hash_lock_isa_spinlock_t], [
		AC_DEFINE(HAVE_CACHE_HASH_SPINLOCK, 1,
			[if cache_detail->hash_lock is a spinlock])
	])
]) 
AC_DEFUN([LC_SRC_GENL_FAMILY_HAS_RESV_START_OP], [
	LB2_LINUX_TEST_SRC([genl_family_has_resv_start_op], [
	],[
		static const struct genl_family family = {
			.resv_start_op = 42,
		};
		(void)family;
	],[-Werror])
])
AC_DEFUN([LC_GENL_FAMILY_HAS_RESV_START_OP], [
	LB2_MSG_LINUX_TEST_RESULT([if struct genl_family has resv_start_op member],
	[genl_family_has_resv_start_op], [
		AC_DEFINE(GENL_FAMILY_HAS_RESV_START_OP, 1,
			[struct genl_family has resv_start_op member])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_FS_CONTEXT_HEADER], [
	LB2_CHECK_LINUX_HEADER_SRC([linux/fs_context.h], [-Werror])
])
AC_DEFUN([LC_HAVE_FS_CONTEXT_HEADER], [
	LB2_CHECK_LINUX_HEADER_RESULT([linux/fs_context.h], [
		AC_DEFINE(HAVE_FS_CONTEXT_H, 1,
			[fs_context.h is present])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_BVEC_ITER_ALL], [
	LB2_LINUX_TEST_SRC([struct_bvec_iter_all], [
	],[
		struct bvec_iter_all iter;
		(void)iter;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_BVEC_ITER_ALL], [
	LB2_MSG_LINUX_TEST_RESULT(
	[if bvec_iter_all exists for multi-page bvec iteration],
	[struct_bvec_iter_all], [
		AC_DEFINE(HAVE_BVEC_ITER_ALL, 1,
			[if bvec_iter_all exists for multi-page bvec iteration])
	])
]) 
AC_DEFUN([LC_ACCOUNT_PAGE_DIRTIED], [
LB_CHECK_EXPORT([account_page_dirtied], [mm/page-writeback.c],
	[AC_DEFINE(HAVE_ACCOUNT_PAGE_DIRTIED_EXPORT, 1,
			[account_page_dirtied is exported])])
]) 
AC_DEFUN([LC_SRC_KEYRING_SEARCH_4ARGS], [
	LB2_LINUX_TEST_SRC([keyring_search_4args], [
	],[
		key_ref_t keyring;
		keyring_search(keyring, NULL, NULL, false);
	])
])
AC_DEFUN([LC_KEYRING_SEARCH_4ARGS], [
	LB2_MSG_LINUX_TEST_RESULT([if 'keyring_search' has 4 args],
	[keyring_search_4args], [
		AC_DEFINE(HAVE_KEYRING_SEARCH_4ARGS, 1,
			[keyring_search has 4 args])
	])
]) 
AC_DEFUN([LC_SRC_BIO_BI_PHYS_SEGMENTS], [
	LB2_LINUX_TEST_SRC([bye_bio_bi_phys_segments], [
	],[
		struct bio *bio = NULL;
		bio->bi_phys_segments++;
	],[-Werror])
])
AC_DEFUN([LC_BIO_BI_PHYS_SEGMENTS], [
	LB2_MSG_LINUX_TEST_RESULT([if struct bio has bi_phys_segments member],
	[bye_bio_bi_phys_segments], [
		AC_DEFINE(HAVE_BIO_BI_PHYS_SEGMENTS, 1,
			[struct bio has bi_phys_segments member])
	])
]) 
AC_DEFUN([LC_HAVE_FLUSH_DELAYED_FPUT], [
LB_CHECK_EXPORT([flush_delayed_fput], [fs/file_table.c],
	[AC_DEFINE(HAVE_FLUSH_DELAYED_FPUT, 1,
			[flush_delayed_fput() is exported by the kernel])])
]) 
AC_DEFUN([LC_SRC_LM_COMPARE_OWNER_EXISTS], [
	LB2_LINUX_TEST_SRC([lock_manager_ops_lm_compare_owner], [
	],[
		struct lock_manager_operations lm_ops;
		lm_ops.lm_compare_owner = NULL;
	],[-Werror])
])
AC_DEFUN([LC_LM_COMPARE_OWNER_EXISTS], [
	LB2_MSG_LINUX_TEST_RESULT([if lock_manager_operations has lm_compare_owner],
	[lock_manager_ops_lm_compare_owner], [
		AC_DEFINE(HAVE_LM_COMPARE_OWNER, 1,
			[lock_manager_operations has lm_compare_owner])
	])
]) 
AC_DEFUN([LC_FSCRYPT_SUPPORT], [
saved_flags="$CFLAGS"
CFLAGS="-Werror"
AC_MSG_CHECKING([for fscrypt in-kernel support])
AC_COMPILE_IFELSE([AC_LANG_SOURCE([
	int main(void) {
		struct fscrypt_policy_v2 policy;
		bzero(&policy, sizeof(policy));
		return 0;
	}
])],[
	has_fscrypt_support="yes"
	AC_MSG_RESULT([yes])
],[
	AC_MSG_RESULT([no])
])
CFLAGS="$saved_flags"
]) 
AC_DEFUN([LC_SRC_FSCRYPT_DIGESTED_NAME], [
	LB2_LINUX_TEST_SRC([fscrypt_digested_name], [
	],[
		struct fscrypt_digested_name fname;
		fname.hash = 0;
	],[-Werror])
])
AC_DEFUN([LC_FSCRYPT_DIGESTED_NAME], [
	LB2_MSG_LINUX_TEST_RESULT([if fscrypt has 'struct fscrypt_digested_name'],
	[fscrypt_digested_name], [
		AC_DEFINE(HAVE_FSCRYPT_DIGESTED_NAME, 1,
			['struct fscrypt_digested_name' exists])
	])
]) 
AC_DEFUN([LC_SRC_FSCRYPT_DUMMY_CONTEXT_ENABLED], [
	LB2_LINUX_TEST_SRC([fscrypt_dummy_context_enabled], [
	],[
		fscrypt_dummy_context_enabled(NULL);
	],[-Werror])
])
AC_DEFUN([LC_FSCRYPT_DUMMY_CONTEXT_ENABLED], [
	LB2_MSG_LINUX_TEST_RESULT([if fscrypt_dummy_context_enabled() exists],
	[fscrypt_dummy_context_enabled], [
		AC_DEFINE(HAVE_FSCRYPT_DUMMY_CONTEXT_ENABLED, 1,
			[fscrypt_dummy_context_enabled() exists])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_PRANDOM_HEADER], [
	LB2_CHECK_LINUX_HEADER_SRC([linux/prandom.h], [-Werror])
])
AC_DEFUN([LC_HAVE_PRANDOM_HEADER], [
	LB2_CHECK_LINUX_HEADER_RESULT([linux/prandom.h], [
		AC_DEFINE(HAVE_PRANDOM_H, 1,
			[prandom.h is present])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_KTHREAD_USE_MM], [
	LB2_LINUX_TEST_SRC([kthread_use_mm], [
	],[
		kthread_use_mm(NULL);
	])
])
AC_DEFUN([LC_HAVE_KTHREAD_USE_MM], [
	LB2_MSG_LINUX_TEST_RESULT([if have kthread_use_mm], [kthread_use_mm], [
		AC_DEFINE(HAVE_KTHREAD_USE_MM, 1, ['kthread_use_mm' exists])
	])
]) 
AC_DEFUN([LC_SRC_FSCRYPT_FNAME_ALLOC_BUFFER], [
	LB2_LINUX_TEST_SRC([fscrypt_fname_alloc_buffer], [
	],[
		fscrypt_fname_alloc_buffer(0, NULL);
	],[-Werror])
])
AC_DEFUN([LC_FSCRYPT_FNAME_ALLOC_BUFFER], [
	LB2_MSG_LINUX_TEST_RESULT([if fscrypt_fname_alloc_buffer() removed inode parameter],
	[fscrypt_fname_alloc_buffer], [
	AC_DEFINE(HAVE_FSCRYPT_FNAME_ALLOC_BUFFER_NO_INODE, 1,
		[fscrypt_fname_alloc_buffer() does not have inode parameter])
	])
]) 
AC_DEFUN([LC_SRC_FSCRYPT_SET_CONTEXT], [
	LB2_LINUX_TEST_SRC([fscrypt_set_context], [
	],[
		fscrypt_set_context(NULL, NULL);
		fscrypt_prepare_new_inode(NULL, NULL, NULL);
	])
])
AC_DEFUN([LC_FSCRYPT_SET_CONTEXT], [
	LB2_MSG_LINUX_TEST_RESULT([if 'fscrypt_set_context()' exists],
	[fscrypt_set_context], [
		AC_DEFINE(HAVE_FSCRYPT_SET_CONTEXT, 1,
			[fscrypt_set_context() does exist])
	])
]) 
AC_DEFUN([LC_FSCRYPT_D_REVALIDATE], [
LB_CHECK_EXPORT([fscrypt_d_revalidate], [fs/crypto/fname.c],
	[AC_DEFINE(HAVE_FSCRYPT_D_REVALIDATE, 1,
		   [fscrypt_d_revalidate() is exported by the kernel])])
]) 
AC_DEFUN([LC_SRC_FSCRYPT_NOKEY_NAME], [
	LB2_LINUX_TEST_SRC([fname_is_nokey_name], [
	],[
		struct fscrypt_name fname;
		fname.is_nokey_name = true;
	],[-Werror])
])
AC_DEFUN([LC_FSCRYPT_NOKEY_NAME], [
	LB2_MSG_LINUX_TEST_RESULT([if struct fscrypt_name has is_nokey_name field],
	[fname_is_nokey_name], [
		AC_DEFINE(HAVE_FSCRYPT_NOKEY_NAME, 1,
			[struct fscrypt_name has is_nokey_name field])
	])
]) 
AC_DEFUN([LC_SRC_FSCRYPT_SET_TEST_DUMMY_ENC_CHAR_ARG], [
	LB2_LINUX_TEST_SRC([fscrypt_set_test_dummy_encryption], [
	],[
		char *arg = "arg";
		fscrypt_set_test_dummy_encryption(NULL, arg, NULL);
	],[-Werror])
])
AC_DEFUN([LC_FSCRYPT_SET_TEST_DUMMY_ENC_CHAR_ARG], [
	LB2_MSG_LINUX_TEST_RESULT([if fscrypt_set_test_dummy_encryption() take 'const char' parameter],
	[fscrypt_set_test_dummy_encryption], [
		AC_DEFINE(HAVE_FSCRYPT_SET_TEST_DUMMY_ENC_CHAR_ARG, 1,
			[fscrypt_set_test_dummy_encryption() take 'const char' parameter])
	])
]) 
AC_DEFUN([LC_SRC_FSCRYPT_DUMMY_POLICY], [
	LB2_LINUX_TEST_SRC([fscrypt_free_dummy_policy], [
	],[
		fscrypt_free_dummy_policy(NULL);
	],[-Werror])
])
AC_DEFUN([LC_FSCRYPT_DUMMY_POLICY], [
	LB2_MSG_LINUX_TEST_RESULT([if fscrypt_free_dummy_policy() exists],
	[fscrypt_free_dummy_policy], [
		AC_DEFINE(HAVE_FSCRYPT_DUMMY_POLICY, 1,
			[fscrypt_free_dummy_policy() exists])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_ITER_FILE_SPLICE_WRITE], [
	LB2_LINUX_TEST_SRC([iter_file_splice_write], [
	],[
		(void)iter_file_splice_write(NULL, NULL, NULL, 1, 0);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_ITER_FILE_SPLICE_WRITE], [
	LB2_MSG_LINUX_TEST_RESULT([if iter_file_splice_write() exists],
	[iter_file_splice_write], [
		AC_DEFINE(HAVE_ITER_FILE_SPLICE_WRITE, 1,
			['iter_file_splice_write' exists])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_BDI_DEBUG_STATS], [
	LB2_LINUX_TEST_SRC([bdi_has_debug_stats], [
	],[
		struct backing_dev_info info;
		info.debug_stats = NULL;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_BDI_DEBUG_STATS], [
	LB2_MSG_LINUX_TEST_RESULT(
	[if 'struct backing_dev_info' has 'debug_stats' field],
	[bdi_has_debug_stats], [
		AC_DEFINE(HAVE_BDI_DEBUG_STATS, 1,
			[backing_dev_info has debug_stats])
	])
]) 
AC_DEFUN([LC_SRC_FSCRYPT_IS_NOKEY_NAME], [
	LB2_LINUX_TEST_SRC([fscrypt_is_no_key_name], [
	],[
		fscrypt_is_nokey_name(NULL);
	],[-Werror])
])
AC_DEFUN([LC_FSCRYPT_IS_NOKEY_NAME], [
	LB2_MSG_LINUX_TEST_RESULT([if fscrypt_is_no_key_name() exists],
	[fscrypt_is_no_key_name], [
		AC_DEFINE(HAVE_FSCRYPT_IS_NOKEY_NAME, 1,
			[fscrypt_is_nokey_name() exists])
	])
]) 
AC_DEFUN([LC_SRC_FSCRYPT_PREPARE_READDIR], [
	LB2_LINUX_TEST_SRC([fscrypt_prepare_readdir], [
	],[
		fscrypt_prepare_readdir(NULL);
	],[-Werror])
])
AC_DEFUN([LC_FSCRYPT_PREPARE_READDIR], [
	LB2_MSG_LINUX_TEST_RESULT([if fscrypt_prepare_readdir() exists],
	[fscrypt_prepare_readdir], [
		AC_DEFINE(HAVE_FSCRYPT_PREPARE_READDIR, 1,
			[fscrypt_prepare_readdir() exists])
	])
]) 
AC_DEFUN([LC_SRC_BIO_SET_DEV], [
	LB2_LINUX_TEST_SRC([bio_set_dev], [
	],[
		struct bio *bio = NULL;
		struct block_device *bdev = NULL;
		bio_set_dev(bio, bdev);
	],[-Werror])
])
AC_DEFUN([LC_BIO_SET_DEV], [
	LB2_MSG_LINUX_TEST_RESULT([if 'bio_set_dev' is available],
	[bio_set_dev], [
		AC_DEFINE(HAVE_BIO_SET_DEV, 1, ['bio_set_dev' is available])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_USER_NAMESPACE_ARG], [
	LB2_LINUX_TEST_SRC([inode_ops_has_user_namespace_argument], [
	],[
		struct inode_operations *iops = NULL;
		struct user_namespace *user_ns = NULL;
		iops->getattr(user_ns, NULL, NULL, 0, 0);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_USER_NAMESPACE_ARG], [
	LB2_MSG_LINUX_TEST_RESULT(
	[if 'inode_operations' members have user namespace argument],
	[inode_ops_has_user_namespace_argument], [
		AC_DEFINE(HAVE_USER_NAMESPACE_ARG, 1,
			['inode_operations' members have user namespace argument])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_FILEATTR_GET], [
	LB2_LINUX_TEST_SRC([fileattr_set], [
	],[
		struct inode_operations *iops = NULL;
		iops->fileattr_get(NULL, NULL);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_FILEATTR_GET], [
	LB2_MSG_LINUX_TEST_RESULT(
	[if 'inode_operations' has fileattr_get (and fileattr_set)],
	[fileattr_set], [
		AC_DEFINE(HAVE_FILEATTR_GET, 1,
			['inode_operations' has fileattr_get and fileattr_set])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_COPY_PAGE_FROM_ITER_ATOMIC], [
	LB2_LINUX_TEST_SRC([copy_page_from_iter_atomic], [
	],[
		copy_page_from_iter_atomic(NULL, 0, 0, NULL);
	])
])
AC_DEFUN([LC_HAVE_COPY_PAGE_FROM_ITER_ATOMIC], [
	LB2_MSG_LINUX_TEST_RESULT([if have copy_page_from_iter_atomic],
	[copy_page_from_iter_atomic], [
		AC_DEFINE(HAVE_COPY_PAGE_FROM_ITER_ATOMIC, 1,
			['copy_page_from_iter_atomic' exists])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_GET_ACL_RCU_ARG], [
	LB2_LINUX_TEST_SRC([get_acl_rcu_argument], [
	],[
		struct inode_operations *iops = NULL;
		iops->get_acl((struct inode *)NULL, 0, false);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_GET_ACL_RCU_ARG], [
	LB2_MSG_LINUX_TEST_RESULT([if 'get_acl' has a rcu argument],
	[get_acl_rcu_argument], [
		AC_DEFINE(HAVE_GET_ACL_RCU_ARG, 1,
			['get_acl' has a rcu argument])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_FAULT_IN_IOV_ITER_READABLE], [
	LB2_LINUX_TEST_SRC([fault_in_iov_iter_readable], [
	],[
		fault_in_iov_iter_readable(NULL, 0);
	])
])
AC_DEFUN([LC_HAVE_FAULT_IN_IOV_ITER_READABLE], [
	LB2_MSG_LINUX_TEST_RESULT([if have fault_in_iov_iter_readable],
	[fault_in_iov_iter_readable], [
		AC_DEFINE(HAVE_FAULT_IN_IOV_ITER_READABLE, 1,
			['fault_in_iov_iter_readable' exists])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_INVALIDATE_LOCK], [
	LB2_LINUX_TEST_SRC([address_space_invalidate_lock], [
	],[
		struct address_space *mapping = NULL;
		filemap_invalidate_lock(mapping);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_INVALIDATE_LOCK], [
	LB2_MSG_LINUX_TEST_RESULT([if filemap_invalidate_lock() is available],
	[address_space_invalidate_lock], [
		AC_DEFINE(HAVE_INVALIDATE_LOCK, 1,
			[filemap_invalidate_lock() is available])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_SECURITY_DENTRY_INIT_WITH_XATTR_NAME_ARG], [
	LB2_LINUX_TEST_SRC([security_dentry_init_security_xattr_name_arg], [
	],[
		struct dentry *dentry = NULL;
		int mode = 0;
		const struct qstr *name = NULL;
		const char *xattr_name = NULL;
		void **ctx = NULL;
		u32 *ctxlen = 0;
		int rc = security_dentry_init_security(dentry, mode, name, &xattr_name,
						       ctx, ctxlen);
		(void)rc;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_SECURITY_DENTRY_INIT_WITH_XATTR_NAME_ARG], [
	LB2_MSG_LINUX_TEST_RESULT([if security_dentry_init_security() returns xattr name],
	[security_dentry_init_security_xattr_name_arg], [
		AC_DEFINE(HAVE_SECURITY_DENTRY_INIT_WITH_XATTR_NAME_ARG, 1,
			[security_dentry_init_security() returns xattr name])
	])
]) 
AC_DEFUN([LC_SRC_FOLIO_MEMCG_LOCK], [
	LB2_LINUX_TEST_SRC([folio_memcg_lock], [
	],[
		folio_memcg_lock(NULL);
	],[-Werror])
])
AC_DEFUN([LC_FOLIO_MEMCG_LOCK], [
	LB2_MSG_LINUX_TEST_RESULT([if 'folio_memcg_lock' is defined],
	[folio_memcg_lock], [
		AC_DEFINE(HAVE_FOLIO_MEMCG_LOCK, 1, [folio_memcg_lock is defined])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_KIOCB_COMPLETE_2ARGS], [
	LB2_LINUX_TEST_SRC([kiocb_ki_complete_2args], [
		static void complete_fn(struct kiocb *iocb, long ret)
		{
			(void)iocb;
			(void)ret;
		}
	],[
		struct kiocb *kio = NULL;
		kio->ki_complete = complete_fn;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_KIOCB_COMPLETE_2ARGS], [
	LB2_MSG_LINUX_TEST_RESULT([if kiocb->ki_complete() has 2 arguments],
	[kiocb_ki_complete_2args], [
		AC_DEFINE(HAVE_KIOCB_COMPLETE_2ARGS, 1,
			[kiocb->ki_complete() has 2 arguments])
	])
]) 
AC_DEFUN([LC_FOLIO_MEMCG_LOCK_EXPORTED], [
LB_CHECK_EXPORT([folio_memcg_lock], [mm/memcontrol.c],
	[AC_DEFINE(FOLIO_MEMCG_LOCK_EXPORTED, 1,
			[folio_memcg_{,un}lock are exported])])
]) 
AC_DEFUN([LC_EXPORTS_DELETE_FROM_PAGE_CACHE], [
LB_CHECK_EXPORT([delete_from_page_cache], [mm/filemap.c],
	[AC_DEFINE(HAVE_DELETE_FROM_PAGE_CACHE, 1,
			[delete_from_page_cache is exported])])
]) 
AC_DEFUN([LC_SRC_HAVE_WB_STAT_MOD], [
	LB2_LINUX_TEST_SRC([wb_stat_mode], [
	],[
		wb_stat_mod(NULL, WB_WRITEBACK, 1);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_WB_STAT_MOD], [
	LB2_MSG_LINUX_TEST_RESULT([if wb_stat_mod() exists], [wb_stat_mode], [
		AC_DEFINE(HAVE_WB_STAT_MOD, 1,
			[wb_stat_mod() exists])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_INVALIDATE_FOLIO], [
	LB2_LINUX_TEST_SRC([address_spaace_operaions_invalidate_folio], [
	],[
		struct address_space_operations *aops = NULL;
		struct folio *folio = NULL;
		aops->invalidate_folio(folio, 0, PAGE_SIZE);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_INVALIDATE_FOLIO], [
	LB2_MSG_LINUX_TEST_RESULT([if have address_spaace_operaions->invalidate_folio() member],
	[address_spaace_operaions_invalidate_folio], [
		AC_DEFINE(HAVE_INVALIDATE_FOLIO, 1,
			[address_spaace_operaions->invalidate_folio() member exists])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_DIRTY_FOLIO], [
	LB2_LINUX_TEST_SRC([address_spaace_operaions_dirty_folio], [
	],[
		struct address_space_operations *aops = NULL;
		struct address_space *mapping = NULL;
		struct folio *folio = NULL;
		bool dirty = aops->dirty_folio(mapping, folio);
		(void) dirty;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_DIRTY_FOLIO], [
	LB2_MSG_LINUX_TEST_RESULT([if have address_spaace_operaions->dirty_folio() member],
	[address_spaace_operaions_dirty_folio], [
		AC_DEFINE(HAVE_DIRTY_FOLIO, 1,
			[address_spaace_operaions->dirty_folio() member exists])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_ALLOC_INODE_SB], [
	LB2_LINUX_TEST_SRC([alloc_inode_sb], [
	],[
		struct super_block *sb = NULL;
		struct kmem_cache *cache = NULL;
		(void)alloc_inode_sb(sb, cache, GFP_NOFS);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_ALLOC_INODE_SB], [
	LB2_MSG_LINUX_TEST_RESULT([if alloc_inode_sb() exists],
	[alloc_inode_sb], [
		AC_DEFINE(HAVE_ALLOC_INODE_SB, 1,
			[alloc_inode_sb() exists])
	])
]) 
AC_DEFUN([LC_SRC_GRAB_CACHE_PAGE_WRITE_BEGIN_WITH_FLAGS], [
	LB2_LINUX_TEST_SRC([grab_cache_page_write_begin_with_flags], [
	],[
		struct address_space *mapping = NULL;
		(void)grab_cache_page_write_begin(mapping, 0, 1);
	],[-Werror])
]) 
AC_DEFUN([LC_GRAB_CACHE_PAGE_WRITE_BEGIN_WITH_FLAGS], [
	LB2_MSG_LINUX_TEST_RESULT([if grab_cache_page_write_begin() has flags argument],
	[grab_cache_page_write_begin_with_flags], [
		AC_DEFINE(HAVE_GRAB_CACHE_PAGE_WRITE_BEGIN_WITH_FLAGS, 1,
			[grab_cache_page_write_begin() has flags argument])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_ADDRESS_SPACE_OPERATIONS_READ_FOLIO], [
	LB2_LINUX_TEST_SRC([address_space_operations_read_folio], [
	],[
		struct address_space_operations *aops = NULL;
		struct file *file = NULL;
		struct folio *folio = NULL;
		int err = aops->read_folio(file, folio);
		(void)err;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_ADDRESS_SPACE_OPERATIONS_READ_FOLIO], [
	LB2_MSG_LINUX_TEST_RESULT([if struct address_space_operations() has read_folio()],
	[address_space_operations_read_folio], [
		AC_DEFINE(HAVE_AOPS_READ_FOLIO, 1,
			[struct address_space_operations() has read_folio()])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_READ_CACHE_PAGE_FILLER_WITH_FILE], [
	LB2_LINUX_TEST_SRC([read_cache_page_filler_with_file], [
		static inline int _filler(struct file *file, struct folio *f)
		{
			return 0;
		}
	],[
		struct address_space *mapping = NULL;
		struct file *file = NULL;
		struct page *page = read_cache_page(mapping, 0, _filler, file);
		(void)page;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_READ_CACHE_PAGE_FILLER_WITH_FILE], [
	LB2_MSG_LINUX_TEST_RESULT([if read_cache_page() filler_t needs struct file],
	[read_cache_page_filler_with_file], [
		AC_DEFINE(HAVE_READ_CACHE_PAGE_WANTS_FILE, 1,
			[read_cache_page() filler_t needs struct file])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_ADDRESS_SPACE_OPERATIONS_RELEASE_FOLIO], [
	LB2_LINUX_TEST_SRC([address_space_operations_release_folio], [
	],[
		struct address_space_operations *aops = NULL;
		struct folio *folio = NULL;
		int err = aops->release_folio(folio, GFP_KERNEL);
		(void)err;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_ADDRESS_SPACE_OPERATIONS_RELEASE_FOLIO], [
	LB2_MSG_LINUX_TEST_RESULT([if struct address_space_operations() has release_folio()],
	[address_space_operations_release_folio], [
		AC_DEFINE(HAVE_AOPS_RELEASE_FOLIO, 1,
			[struct address_space_operations() has release_folio()])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_LSMCONTEXT_INIT], [
	LB2_LINUX_TEST_SRC([lsmcontext_init], [
	],[
		struct lsm_context ctx = {};
		lsmcontext_init(&ctx, "", 0, 0);
	],[])
])
AC_DEFUN([LC_HAVE_LSMCONTEXT_INIT], [
	LB2_MSG_LINUX_TEST_RESULT([if lsmcontext_init is available],
	[lsmcontext_init], [
		AC_DEFINE(HAVE_LSMCONTEXT_INIT, 1,
			[lsmcontext_init is available])
	])
]) 
AC_DEFUN([LC_SRC_SECURITY_DENTRY_INIT_SECURTY_WITH_CTX], [
	LB2_LINUX_TEST_SRC([security_dentry_init_security_with_ctx], [
	],[
		struct dentry *dentry = NULL;
		const struct qstr *name = NULL;
		struct lsm_context *ctx = NULL;
		const char *xattr_name = "";
		(void)security_dentry_init_security(dentry, 0, name,
						    &xattr_name, ctx);
	],[-Werror])
])
AC_DEFUN([LC_SECURITY_DENTRY_INIT_SECURTY_WITH_CTX], [
	LB2_MSG_LINUX_TEST_RESULT([if security_dentry_init_security needs lsm_context],
	[security_dentry_init_security_with_ctx], [
		AC_DEFINE(HAVE_SECURITY_DENTRY_INIT_SECURTY_WITH_CTX, 1,
			[security_dentry_init_security needs lsm_context])
	])
]) 
AC_DEFUN([LC_SRC_LSMCONTEXT_HAS_ID], [
	LB2_LINUX_TEST_SRC([lsm_context_has_id], [
	],[
		((struct lsm_context *)1)->id = 0;
	],[-Werror])
])
AC_DEFUN([LC_LSMCONTEXT_HAS_ID], [
	LB2_MSG_LINUX_TEST_RESULT([if lsm_context has id],
	[lsm_context_has_id], [
		AC_DEFINE(HAVE_LSMCONTEXT_HAS_ID, 1,
			[lsm_context has id])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_NO_LLSEEK], [
	LB2_LINUX_TEST_SRC([no_llseek], [
	],[
		static const struct file_operations fops = {
			.llseek = &no_llseek,
		};
		(void)fops;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_NO_LLSEEK], [
	LB2_MSG_LINUX_TEST_RESULT([if no_llseek() is available],
	[no_llseek], [
		AC_DEFINE(HAVE_NO_LLSEEK, 1, [no_llseek() is available])
	])
]) 
AC_DEFUN([LC_SRC_DQUOT_TRANSFER_WITH_USER_NS], [
	LB2_LINUX_TEST_SRC([dquot_transfer], [
	],[
		struct user_namespace *userns = NULL;
		struct inode *inode = NULL;
		struct iattr *iattr = NULL;
		int err __attribute__ ((unused));
		err = dquot_transfer(userns, inode, iattr);
	],[-Werror])
])
AC_DEFUN([LC_DQUOT_TRANSFER_WITH_USER_NS], [
	LB2_MSG_LINUX_TEST_RESULT([if dquot_transfer() has user_ns argument],
	[dquot_transfer], [
		AC_DEFINE(HAVE_DQUOT_TRANSFER_WITH_USER_NS, 1,
			[dquot_transfer() has user_ns argument])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_FILEMAP_GET_FOLIOS], [
	LB2_LINUX_TEST_SRC([filemap_get_folios], [
	],[
		struct address_space *m = NULL;
		pgoff_t start = 0;
		struct folio_batch *fbatch = NULL;
		(void)filemap_get_folios(m, &start, ULONG_MAX, fbatch);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_FILEMAP_GET_FOLIOS], [
	AC_MSG_CHECKING([if filemap_get_folios() exists])
	LB2_LINUX_TEST_RESULT([filemap_get_folios], [
		AC_DEFINE(HAVE_FILEMAP_GET_FOLIOS, 1,
			[filemap_get_folios() exists])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_ADDRESS_SPACE_OPERATIONS_MIGRATE_FOLIO], [
	LB2_LINUX_TEST_SRC([address_space_operations_migrate_folio], [
	],[
		struct address_space_operations *aops = NULL;
		struct address_space *m = NULL;
		struct folio *src = NULL;
		struct folio *dst = NULL;
		int err = aops->migrate_folio(m, dst, src, MIGRATE_ASYNC);
		(void)err;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_ADDRESS_SPACE_OPERATIONS_MIGRATE_FOLIO], [
	LB2_MSG_LINUX_TEST_RESULT([if struct address_space_operations() has migrate_folio()],
	[address_space_operations_migrate_folio], [
		AC_DEFINE(HAVE_AOPS_MIGRATE_FOLIO, 1,
			[struct address_space_operations() has migrate_folio()])
	])
]) 
AC_DEFUN([LC_SRC_REGISTER_SHRINKER_FORMAT_NAMED], [
	LB2_LINUX_TEST_SRC([register_shrinker_format], [
	],[
		if (register_shrinker(NULL, "grumple-%ps", __func__))
			unregister_shrinker(NULL);
	],[-Werror])
])
AC_DEFUN([LC_REGISTER_SHRINKER_FORMAT_NAMED], [
	LB2_MSG_LINUX_TEST_RESULT([if register_shrinker() returns status],
	[register_shrinker_format], [
		AC_DEFINE(HAVE_REGISTER_SHRINKER_FORMAT_NAMED, 1,
			[register_shrinker() returns status])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_VFS_SETXATTR_NON_CONST_VALUE], [
	LB2_LINUX_TEST_SRC([vfs_setxattr_non_const_value_arg], [
	],[
		struct dentry *de = NULL;
		const char *name = "an.xattr";
		const void *value = NULL;
		int err = vfs_setxattr(&init_user_ns, de, name, value, 0, 0);
		(void)err;
	],[-Werror])
]) 
AC_DEFUN([LC_HAVE_VFS_SETXATTR_NON_CONST_VALUE], [
	LB2_MSG_LINUX_TEST_RESULT([if vfs_setxattr() value argument is non-const],
	[vfs_setxattr_non_const_value_arg], [
		AC_DEFINE([VFS_SETXATTR_VALUE(value)],
			  [(value)],
			  [vfs_setxattr() value argument is const void *])
	],[
		AC_DEFINE([VFS_SETXATTR_VALUE(value)],
			  [((void *)(value))],
			  [vfs_setxattr() value argument is non-const])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_IOV_ITER_GET_PAGES_ALLOC2], [
	LB2_LINUX_TEST_SRC([iov_iter_get_pages_alloc2], [
	],[
		struct iov_iter *iter = NULL;
		struct page ***pages = NULL;
		size_t maxsize = 1;
		size_t start;
		size_t result __attribute__ ((unused));
		result = iov_iter_get_pages_alloc2(iter, pages, maxsize, &start);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_IOV_ITER_GET_PAGES_ALLOC2], [
	LB2_MSG_LINUX_TEST_RESULT([if iov_iter_get_pages_alloc2() is available],
	[iov_iter_get_pages_alloc2], [
		AC_DEFINE(HAVE_IOV_ITER_GET_PAGES_ALLOC2, 1,
			[iov_iter_get_pages_alloc2() is available])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_USER_BACKED_ITER], [
	LB2_LINUX_TEST_SRC([user_backed_iter], [
	],[
		struct iov_iter *iter = NULL;
		bool result __attribute__ ((unused));
		result = user_backed_iter(iter);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_USER_BACKED_ITER], [
	LB2_MSG_LINUX_TEST_RESULT([if user_backed_iter() is available],
	[user_backed_iter], [
		AC_DEFINE(HAVE_USER_BACKED_ITER, 1,
			[user_backed_iter() is available])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_IOV_ITER_IS_ALIGNED], [
	LB2_LINUX_TEST_SRC([iov_iter_is_aligned], [
	],[
		struct iov_iter *iter = NULL;
		bool result __attribute__ ((unused));
		result = iov_iter_is_aligned(iter, ~PAGE_MASK, ~PAGE_MASK);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_IOV_ITER_IS_ALIGNED], [
	LB2_MSG_LINUX_TEST_RESULT([if iov_iter_is_aligned() is available],
	[iov_iter_is_aligned], [
		AC_DEFINE(HAVE_IOV_ITER_IS_ALIGNED, 1,
			[iov_iter_is_aligned() is available])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_GET_RANDOM_U32_AND_U64], [
	LB2_LINUX_TEST_SRC([get_random_u32_and_u64], [
	],[
		u32 rand32 = get_random_u32();
		u64 rand64 = get_random_u64();
		(void)rand32;
		(void)rand64;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_GET_RANDOM_U32_AND_U64], [
	LB2_MSG_LINUX_TEST_RESULT([if get_random_u32() and get_random_u64() are available],
	[get_random_u32_and_u64], [
		AC_DEFINE(HAVE_GET_RANDOM_U32_AND_U64, 1,
			[get_random_[u32|u64] are available])
	],[
		AC_DEFINE([get_random_u32()], [prandom_u32()],
			[get_random_u32() is not available, use prandom_u32])
	])
]) 
AC_DEFUN([LC_SRC_NFS_FILLDIR_USE_CTX_RETURN_BOOL], [
	LB2_LINUX_TEST_SRC([filldir_ctx_return_bool], [
		bool filldir(struct dir_context *ctx, const char* name,
			     int i, loff_t off, u64 tmp, unsigned temp);
		bool filldir(struct dir_context *ctx, const char* name,
			     int i, loff_t off, u64 tmp, unsigned temp)
		{
			return 0;
		}
	],[
		struct dir_context ctx = {
			.actor = filldir,
		};
		ctx.actor(NULL, "test", 0, (loff_t) 0, 0, 0);
	],[-Werror])
])
AC_DEFUN([LC_NFS_FILLDIR_USE_CTX_RETURN_BOOL], [
	LB2_MSG_LINUX_TEST_RESULT([if filldir_t uses struct dir_context and returns bool],
	[filldir_ctx_return_bool], [
		AC_DEFINE(HAVE_FILLDIR_USE_CTX_RETURN_BOOL, 1,
			[filldir_t needs struct dir_context and returns bool])
		AC_DEFINE(HAVE_FILLDIR_USE_CTX, 1,
			[filldir_t needs struct dir_context as argument])
		AC_DEFINE(FILLDIR_TYPE, bool,
			[filldir_t return type is bool or int])
	],[
		AC_DEFINE(FILLDIR_TYPE, int,
			[filldir_t return type is bool or int])
	])
]) 
AC_DEFUN([LC_HAVE_ADD_TO_PAGE_CACHE_LOCKED], [
LB_CHECK_EXPORT([add_to_page_cache_locked], [mm/filemap.c],
	[AC_DEFINE(HAVE_ADD_TO_PAGE_CACHE_LOCKED, 1,
			[add_to_page_cache_locked is exported by the kernel])])
]) 
AC_DEFUN([LC_SRC_HAVE_FILEMAP_GET_FOLIOS_CONTIG], [
	LB2_LINUX_TEST_SRC([filemap_get_folios_contig], [
	],[
		struct address_space *m = NULL;
		pgoff_t start = 0;
		struct folio_batch *fbatch = NULL;
		(void)filemap_get_folios_contig(m, &start, ULONG_MAX, fbatch);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_FILEMAP_GET_FOLIOS_CONTIG], [
	LB2_MSG_LINUX_TEST_RESULT([if filemap_get_folios_contig() is available],
	[filemap_get_folios_contig], [
		AC_DEFINE(HAVE_FILEMAP_GET_FOLIOS_CONTIG, 1,
			[filemap_get_folios_contig() is available])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_GET_RANDOM_U32_BELOW], [
	LB2_LINUX_TEST_SRC([get_random_u32_below], [
	],[
		u32 rand32 = get_random_u32_below(99);
		(void)rand32;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_GET_RANDOM_U32_BELOW], [
	LB2_MSG_LINUX_TEST_RESULT([if get_random_u32_below()is available],
	[get_random_u32_below], [
		AC_DEFINE(HAVE_GET_RANDOM_U32_BELOW, 1,
			[get_random_u32_below() is available])
	],[
		AC_DEFINE([get_random_u32_below(v)], [prandom_u32_max(v)],
			[get_random_u32_below() is not available])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_ACL_WITH_DENTRY], [
	LB2_LINUX_TEST_SRC([acl_with_dentry], [
	],[
		struct inode_operations *iops = NULL;
		struct dentry *dentry = NULL;
		iops->get_acl(NULL, dentry, 0);
		(void)dentry;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_ACL_WITH_DENTRY], [
	LB2_MSG_LINUX_TEST_RESULT([if 'get_acl' and 'set_acl' use dentry argument],
	[acl_with_dentry], [
		AC_DEFINE(HAVE_ACL_WITH_DENTRY, 1,
			['get_acl' and 'set_acl' use dentry argument])
	])
]) 
AC_DEFUN([LC_SRC_IOP_GET_INODE_ACL], [
	LB2_LINUX_TEST_SRC([inode_ops_get_inode_acl], [
	],[
		struct inode_operations iop;
		iop.get_inode_acl = NULL;
	])
])
AC_DEFUN([LC_IOP_GET_INODE_ACL], [
	LB2_MSG_LINUX_TEST_RESULT([if inode_operations has .get_inode_acl member function],
	[inode_ops_get_inode_acl], [
		AC_DEFINE(HAVE_IOP_GET_INODE_ACL, 1,
			[inode_operations has .get_inode_acl member function])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_FOLIO_MAPCOUNT], [
	LB2_LINUX_TEST_SRC([folio_mapcount], [
	],[
		(void)folio_mapcount((const struct folio *)NULL);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_FOLIO_MAPCOUNT], [
	LB2_MSG_LINUX_TEST_RESULT([if 'folio_mapcount()' is available],
	[folio_mapcount], [
		AC_DEFINE(HAVE_FOLIO_MAPCOUNT, 1,
			['folio_mapcount()' is available])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_U64_CAPABILITY], [
	LB2_LINUX_TEST_SRC([kernel_cap_t_has_u64_value], [
	],[
		kernel_cap_t cap __attribute__ ((unused));
		cap.val = 0xffffffffffffffffull;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_U64_CAPABILITY], [
	LB2_MSG_LINUX_TEST_RESULT([if 'kernel_cap_t' has u64 val],
	[kernel_cap_t_has_u64_value], [
		AC_DEFINE(HAVE_U64_CAPABILITY, 1,
			['kernel_cap_t' has u64 val])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_MNT_IDMAP_ARG], [
	LB2_LINUX_TEST_SRC([inode_ops_getattr_has_mnt_idmap_argument], [
	],[
		struct inode_operations *iops = NULL;
		iops->getattr((struct mnt_idmap *)NULL,	NULL, NULL, 0, 0);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_MNT_IDMAP_ARG], [
	LB2_MSG_LINUX_TEST_RESULT([if 'inode_operations' members have mnt_idmap argument],
	[inode_ops_getattr_has_mnt_idmap_argument], [
		AC_DEFINE(HAVE_MNT_IDMAP_ARG, 1,
			['inode_operations' members have mnt_idmap argument])
		AC_DEFINE(HAVE_USER_NAMESPACE_ARG, 1,
			[use mnt_idmap in place of user_namespace argument])
		AC_DEFINE(HAVE_DQUOT_TRANSFER_WITH_USER_NS, 1,
			[use mnt_idmap with dquot_transfer])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_LOCKS_LOCK_FILE_WAIT_IN_FILELOCK], [
	LB2_LINUX_TEST_SRC([locks_lock_file_wait_in_filelock], [
	],[
		locks_lock_file_wait(NULL, NULL);
	])
])
AC_DEFUN([LC_HAVE_LOCKS_LOCK_FILE_WAIT_IN_FILELOCK], [
	LB2_MSG_LINUX_TEST_RESULT([if 'locks_lock_file_wait' exists in filelock.h],
	[locks_lock_file_wait_in_filelock], [
		AC_DEFINE(HAVE_LOCKS_LOCK_FILE_WAIT, 1,
			[kernel has locks_lock_file_wait in filelock.h])
		AC_DEFINE(HAVE_LINUX_FILELOCK_HEADER, 1,
			[linux/filelock.h is present])
		AC_DEFINE(HAVE_LM_GRANT_2ARGS, 1,
			[lock_manager_operations.lm_grant takes two args])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_FOLIO_BATCH_REINIT], [
	LB2_LINUX_TEST_SRC([folio_batch_reinit_exists], [
	],[
		struct folio_batch fbatch __attribute__ ((unused));
		folio_batch_reinit(&fbatch);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_FOLIO_BATCH_REINIT], [
	LB2_MSG_LINUX_TEST_RESULT([if 'folio_batch_reinit' is available],
	[folio_batch_reinit_exists], [
		AC_DEFINE(HAVE_FOLIO_BATCH_REINIT, 1,
			['folio_batch_reinit' is available])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_IOV_ITER_IOVEC], [
	LB2_LINUX_TEST_SRC([iov_iter_iovec_exists], [
	],[
		struct iovec iov __attribute__ ((unused));
		struct iov_iter i = { };
		iov = iov_iter_iovec(&i);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_IOV_ITER_IOVEC], [
	LB2_MSG_LINUX_TEST_RESULT([if 'iov_iter_iovec' is available],
	[iov_iter_iovec_exists], [
		AC_DEFINE(HAVE_IOV_ITER_IOVEC, 1,
			['iov_iter_iovec' is available])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_IOVEC_WITH_IOV_MEMBER], [
	LB2_LINUX_TEST_SRC([iov_iter_has___iov_member], [
	],[
		struct iov_iter iter = { };
		size_t len __attribute__ ((unused));
		len = iter.__iov->iov_len;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_IOVEC_WITH_IOV_MEMBER], [
	LB2_MSG_LINUX_TEST_RESULT([if 'iov_iter()' is available],
	[iov_iter_has___iov_member], [
		AC_DEFINE(HAVE___IOV_MEMBER, __iov,
			['struct iov_iter' has '__iov' member])
		AC_DEFINE(HAVE_ITER_IOV, 1,
			[iter_iov() is available])
	],[
		AC_DEFINE(iter_iov(iter), (iter)->__iov,
			['iov_iter()' provides iov])
		AC_DEFINE(__iov, iov,
			['struct iov_iter' has 'iov' member])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_CLASS_CREATE_MODULE_ARG], [
	LB2_LINUX_TEST_SRC([class_create_without_module_arg], [
	],[
		struct class *class;
		class = class_create("empty");
		if (IS_ERR(class))
			return PTR_ERR(class);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_CLASS_CREATE_MODULE_ARG], [
	LB2_MSG_LINUX_TEST_RESULT([if 'class_create' does not have module arg],
	[class_create_without_module_arg], [
		AC_DEFINE([ll_class_create(name)],
			  [class_create((name))],
			  ['class_create' does not have module arg])
	],[
		AC_DEFINE([ll_class_create(name)],
			  [class_create(THIS_MODULE, (name))],
			  ['class_create' expects module arg])
	])
]) 
AC_DEFUN([LC_EXPORTS_FILEMAP_SPLICE_READ], [
LB_CHECK_EXPORT([filemap_splice_read], [mm/filemap.c],
	[AC_DEFINE(HAVE_FILEMAP_SPLICE_READ, 1,
			['filemap_splice_read' is exported])])
]) 
AC_DEFUN([LC_SRC_HAVE_ENUM_ITER_PIPE], [
	LB2_LINUX_TEST_SRC([enum_iter_type_iter_pipe], [
	],[
		enum iter_type iter_type = ITER_PIPE;
		(void)iter_type;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_ENUM_ITER_PIPE], [
	LB2_MSG_LINUX_TEST_RESULT([if enum iter_type has member 'iter_pipe'],
	[enum_iter_type_iter_pipe], [
		AC_DEFINE(HAVE_ENUM_ITER_PIPE, 1,
			[enum iter_type has member 'iter_pipe'])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_GET_USER_PAGES_WITHOUT_VMA], [
	LB2_LINUX_TEST_SRC([get_user_pages_without_vma], [
	],[
		struct page *pages __attribute__ ((unused));
		(void)get_user_pages(0, 0, 0, &pages);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_GET_USER_PAGES_WITHOUT_VMA], [
	LB2_MSG_LINUX_TEST_RESULT([if get_user_pages removed 'vma' parameter],
	[get_user_pages_without_vma], [
		AC_DEFINE(HAVE_GET_USER_PAGES_WITHOUT_VMA, 1,
			[get_user_pages removed 'vma' parameter])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_FOLIO_BATCH], [
	LB2_LINUX_TEST_SRC([struct_folio_batch_exists], [
	],[
		struct folio_batch fbatch __attribute__ ((unused));
		folio_batch_init(&fbatch);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_FOLIO_BATCH], [
	LB2_MSG_LINUX_TEST_RESULT([if 'struct folio_batch' is available],
	[struct_folio_batch_exists], [
		AC_DEFINE(HAVE_FOLIO_BATCH, 1,
			['struct folio_batch' is available])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_STRUCT_PAGEVEC], [
	LB2_LINUX_TEST_SRC([struct_pagevec_exists], [
	],[
		struct pagevec *pvec = NULL;
		(void)pvec;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_STRUCT_PAGEVEC], [
	LB2_MSG_LINUX_TEST_RESULT([if 'struct pagevec' is available],
	[struct_pagevec_exists], [
		AC_DEFINE(HAVE_PAGEVEC, 1,
			['struct pagevec' is available])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_FLUSH___WORKQUEUE], [
	LB2_LINUX_TEST_SRC([flush_scheduled_work_warning], [
	],[
		__flush_workqueue(system_wq);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_FLUSH___WORKQUEUE], [
	LB2_MSG_LINUX_TEST_RESULT([if 'flush_scheduled_work()' throws warning],
	[flush_scheduled_work_warning], [
		AC_DEFINE(HAVE_FLUSH___WORKQUEUE, 1,
			['__flush_workqueue(system_wq)' is available])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_INODE_GET_CTIME], [
	LB2_LINUX_TEST_SRC([inode_get_ctime_exists], [
	],[
		struct inode *inode = NULL;
		struct timespec64 ts __attribute__ ((unused));
		ts = inode_get_ctime(inode);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_INODE_GET_CTIME], [
	LB2_MSG_LINUX_TEST_RESULT([if 'inode_get_ctime()' exists],
	[inode_get_ctime_exists], [
		AC_DEFINE(HAVE_INODE_GET_CTIME, 1,
			['inode_get_ctime()' exists])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_MMAP_WRITE_TRYLOCK], [
	LB2_LINUX_TEST_SRC([mmap_write_trylock_removed], [
	],[
		struct mm_struct *mm = NULL;
		(void)mmap_write_trylock(mm);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_MMAP_WRITE_TRYLOCK], [
	LB2_MSG_LINUX_TEST_RESULT([if 'mmap_write_trylock()' is available],
	[mmap_write_trylock_removed], [
		AC_DEFINE(HAVE_MMAP_WRITE_TRYLOCK, 1,
			['mmap_write_trylock()' is available])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_GENERIC_FILEATTR_HAS_MASK_ARG], [
	LB2_LINUX_TEST_SRC([generic_fillattr_has_request_mask_arg], [
	],[
		struct inode *inode = NULL;
		struct mnt_idmap *map = NULL;
		struct kstat *kstat = NULL;
		generic_fillattr(map, 0, inode, kstat);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_GENERIC_FILEATTR_HAS_MASK_ARG], [
	LB2_MSG_LINUX_TEST_RESULT([if 'generic_fillattr()' has request_mask argument],
	[generic_fillattr_has_request_mask_arg], [
		AC_DEFINE(HAVE_GENERIC_FILEATTR_HAS_MASK_ARG, 1,
			['generic_fillattr()' has request_mask argument])
		AC_DEFINE([RQMASK_ARG], [0,], [default request_mask argument])
	], [
		AC_DEFINE([RQMASK_ARG], [], [no request_mask argument needed])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_GROUP_INFO_USAGE_AS_REFCOUNT], [
	LB2_LINUX_TEST_SRC([struct_group_info_usage_is_refcount_t], [
	],[
		struct group_info *group = NULL;
		refcount_dec(&group->usage);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_GROUP_INFO_USAGE_AS_REFCOUNT], [
	LB2_MSG_LINUX_TEST_RESULT([if 'struct group_info.usage' is refcount_t],
	[struct_group_info_usage_is_refcount_t], [
		AC_DEFINE(HAVE_GROUP_INFO_USAGE_AS_REFCOUNT, 1,
			['struct group_info.usage' is refcount_t])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_NSPROXY_COUNT_AS_REFCOUNT], [
	LB2_LINUX_TEST_SRC([struct_nsproxy_count_refcount_t], [
	],[
		struct nsproxy *nsproxy = NULL;
		refcount_dec(&nsproxy->count);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_NSPROXY_COUNT_AS_REFCOUNT], [
	LB2_MSG_LINUX_TEST_RESULT([if 'struct nsproxy.count' is refcount_t],
	[struct_nsproxy_count_refcount_t], [
		AC_DEFINE(HAVE_NSPROXY_COUNT_AS_REFCOUNT, 1,
			['struct nsproxy.count' is refcount_t])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_INODE_GET_MTIME_SEC], [
	LB2_LINUX_TEST_SRC([inode_get_mtime_exists], [
	],[
		struct inode *inode = NULL;
		time64_t sec __attribute__ ((unused));
		sec = inode_get_mtime_sec(inode);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_INODE_GET_MTIME_SEC], [
	LB2_MSG_LINUX_TEST_RESULT([if 'inode_get_mtime()' exists],
	[inode_get_mtime_exists], [
		AC_DEFINE(HAVE_INODE_GET_MTIME_SEC, 1,
			['inode_get_mtime()' exists])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_SHRINKER_ALLOC], [
	LB2_LINUX_TEST_SRC([shrinker_alloc_exists], [
	],[
		struct shrinker *shrink __attribute__ ((unused));
		shrink = shrinker_alloc(0, "%s", "whoami");
	],[-Werror])
])
AC_DEFUN([LC_HAVE_SHRINKER_ALLOC], [
	LB2_MSG_LINUX_TEST_RESULT([if 'shrinker_alloc()' exists],
	[shrinker_alloc_exists], [
		AC_DEFINE(HAVE_SHRINKER_ALLOC, 1,
			['shrinker_alloc()' exists])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_DENTRY_D_CHILDREN], [
	LB2_LINUX_TEST_SRC([dentry_d_children], [
	],[
		struct dentry *dentry = NULL;
		return hlist_empty(&dentry->d_children);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_DENTRY_D_CHILDREN], [
	LB2_MSG_LINUX_TEST_RESULT([if sruct dentry has d_children member],
	[dentry_d_children], [
		AC_DEFINE(HAVE_DENTRY_D_CHILDREN, 1,
			[sruct dentry has d_children member])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_GENERIC_ERROR_REMOVE_FOLIO], [
	LB2_LINUX_TEST_SRC([generic_error_remove_folio], [
	],[
		struct address_space *mapping = NULL;
		struct folio *folio = NULL;
		int err = generic_error_remove_folio(mapping, folio);
		(void) err;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_GENERIC_ERROR_REMOVE_FOLIO], [
	LB2_MSG_LINUX_TEST_RESULT([if generic_error_remove_folio() exists],
	[generic_error_remove_folio], [
		AC_DEFINE(HAVE_GENERIC_ERROR_REMOVE_FOLIO, 1,
			[generic_error_remove_folio() exists])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_STRUCT_FILE_LOCK_CORE], [
	LB2_LINUX_TEST_SRC([struct_file_lock_core], [
	],[
		struct file_lock_core *flc = NULL;
		flc->flc_flags = 0;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_STRUCT_FILE_LOCK_CORE], [
	LB2_MSG_LINUX_TEST_RESULT([if struct file_lock_core exists],
	[struct_file_lock_core], [
		AC_DEFINE(HAVE_STRUCT_FILE_LOCK_CORE, 1,
			[struct file_lock_core exists])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_CSUM_TYPE_BLK_INTEGRITY], [
	LB2_LINUX_TEST_SRC([csum_type_blk_integrity], [
	],[
		((struct blk_integrity *)0)->csum_type = 0;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_CSUM_TYPE_BLK_INTEGRITY], [
	LB2_MSG_LINUX_TEST_RESULT([if 'blk_integrity.csum_type' exists],
	[csum_type_blk_integrity], [
		AC_DEFINE(HAVE_CSUM_TYPE_BLK_INTEGRITY, 1,
			[struct blk_integrity has csum_type field])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_LINUX_UNALIGNED_HEADER],[
	LB2_LINUX_TEST_SRC([linux_unaligned_header], [
	],[
	],[])
])
AC_DEFUN([LC_HAVE_LINUX_UNALIGNED_HEADER],[
	LB2_MSG_LINUX_TEST_RESULT([if linux/unaligned.h header is available],
	[linux_unaligned_header], [
		AC_DEFINE(HAVE_LINUX_UNALIGNED_HEADER, 1,
			[linux/unaligned.h header is available])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_WRITE_BEGIN_FOLIO],[
	LB2_LINUX_TEST_SRC([write_begin_with_folio], [
		static
		int ll_write_begin(struct file *f, struct address_space *m,
				   loff_t pos, unsigned len,
				   struct folio **foliop, void **fsdata)
		{
			*foliop = NULL;
			*fsdata = NULL;
			return 0;
		}
		static
		int ll_write_end(struct file *f, struct address_space *m,
				 loff_t pos, unsigned len, unsigned copied,
				 struct folio *folio, void *fsdata)
		{
			return 0;
		}
		const struct address_space_operations ll_aops = {
			.write_begin	= ll_write_begin,
			.write_end	= ll_write_end,
		};
	],[
	],[-Werror])
])
AC_DEFUN([LC_HAVE_WRITE_BEGIN_FOLIO],[
	LB2_MSG_LINUX_TEST_RESULT([if write_begin() takes folio],
	[write_begin_with_folio], [
		AC_DEFINE(HAVE_WRITE_BEGIN_FOLIO, 1,
			[write_begin() takes folio])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_STRUCT_FILE_F_VERSION], [
	LB2_LINUX_TEST_SRC([struct_file_f_version], [
	],[
		struct file *file __attribute__ ((unused)) = NULL;
		file->f_version = 0;
	],[-Werror])
])
AC_DEFUN([LC_HAVE_STRUCT_FILE_F_VERSION], [
	LB2_MSG_LINUX_TEST_RESULT([if struct file has f_version],
	[struct_file_f_version], [
		AC_DEFINE(HAVE_STRUCT_FILE_F_VERSION, 1,
			[struct file has f_version])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_PG_ERROR], [
	LB2_LINUX_TEST_SRC([pg_error], [
	],[
		bool x __attribute__ ((unused)) = PageError(NULL);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_PG_ERROR], [
	LB2_MSG_LINUX_TEST_RESULT([if 'PageError()' is available],
	[pg_error], [
		AC_DEFINE(HAVE_PG_ERROR, 1,
			['PageError()()' is available])
	],[
		AC_DEFINE(PageError(pg), (0),
			  ['PageError()' replacement])
		AC_DEFINE(SetPageError(pg), ,
			  ['SetPageError()' replacement])
		AC_DEFINE(ClearPageError(pg), ,
			  ['ClearPageError()' replacement])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_FOLIO_TEST_MLOCKED], [
	LB2_LINUX_TEST_SRC([folio_test_mlocked], [
	],[
		bool x __attribute__ ((unused)) = folio_test_mlocked(NULL);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_FOLIO_TEST_MLOCKED], [
	LB2_MSG_LINUX_TEST_RESULT([if 'folio_test_mlocked()' is available],
	[folio_test_mlocked], [
		AC_DEFINE([folio_test_mlocked_page(pg)],
			  [folio_test_mlocked(page_folio((pg)))],
			  ['folio_test_mlocked()' is available])
	],[
		AC_DEFINE([folio_test_mlocked_page(pg)], [PageMlocked((pg))],
			  ['folio_test_mlocked()' replacement])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_PAGE_MAPCOUNT_IS_TYPE], [
	LB2_LINUX_TEST_SRC([page_mapcount_is_type], [
	],[
		bool x __attribute__ ((unused)) = page_mapcount_is_type(0);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_PAGE_MAPCOUNT_IS_TYPE], [
	LB2_MSG_LINUX_TEST_RESULT([if 'page_mapcount_is_type()' is available],
	[page_mapcount_is_type], [
		AC_DEFINE(HAVE_PAGE_MAPCOUNT_IS_TYPE, 1,
			['page_mapcount_is_type()' is available])
	],[
		AC_DEFINE(page_mapcount_is_type(count),
			  (count < PAGE_MAPCOUNT_RESERVE + 1),
			  [need 'page_mapcount_is_type()' replacement])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_MODULE_IMPORT_STRING_LITERAL], [
	LB2_LINUX_TEST_SRC([module_import_ns_uses_export_symbols], [
		MODULE_IMPORT_NS(CRYPTO_INTERNAL);
		u8 salt[16];
	],[
		(void)crypto_cipher_setkey(NULL, salt, sizeof(salt));
	],[-Werror])
])
AC_DEFUN([LC_HAVE_MODULE_IMPORT_STRING_LITERAL], [
	LB2_MSG_LINUX_TEST_RESULT([if MODULE_IMPORT_NS() uses export symbols],
	[module_import_ns_uses_export_symbols], [
		AC_DEFINE(HAVE_MODULE_IMPORT_USES_EXPORT_SYMBOLS, 1,
			[MODULE_IMPORT_NS() needs string literal])
	], [
		AC_DEFINE(CRYPTO_INTERNAL, __stringify(CRYPTO_INTERNAL),
			[MODULE_IMPORT_NS() needs string literal])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_PAGEPRIVATE2], [
	LB2_LINUX_TEST_SRC([folio_test_private_2], [
	],[
		struct page *page = NULL;
		ClearPagePrivate2(page);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_PAGEPRIVATE2], [
	LB2_MSG_LINUX_TEST_RESULT([if PagePrivate2() is available],
	[folio_test_private_2], [
		AC_DEFINE(HAVE_PAGE_PRIVATE_2, 1,
			[PagePrivate2() is available])
	])
]) 
AC_DEFUN([LC_SRC_STRUCT_LSM_CONTEXT_EARLY], [
	LB2_LINUX_TEST_SRC([struct_lsm_context], [
	],[
		struct lsm_context ctx = {};
		ctx.context = NULL;
	],[-Werror])
])
AC_DEFUN([LC_STRUCT_LSM_CONTEXT_EARLY], [
	LB2_MSG_LINUX_TEST_RESULT([if struct lsm_context is available],
	[struct_lsm_context], [
		AC_DEFINE(HAVE_STRUCT_LSM_CONTEXT, 1,
			[struct lsm_context is available])
	],[
		AC_DEFINE(lsm_context, lsmcontext,
			[struct lsm_context also known as struct lsmcontext in ubuntu kernels])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_D_REVALIDATE_WITH_INODE_NAME], [
	LB2_LINUX_TEST_SRC([dentry_ops_d_revalidate_inode_name], [
	],[
		struct dentry_operations *d_ops = NULL;
		struct inode *inode = NULL;
		struct qstr *qstr = NULL;
		struct dentry *dentry = NULL;
		(void)d_ops->d_revalidate(inode, qstr, dentry, 0);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_D_REVALIDATE_WITH_INODE_NAME], [
	LB2_MSG_LINUX_TEST_RESULT([if d_revalidate() takes inode, name],
	[dentry_ops_d_revalidate_inode_name], [
		AC_DEFINE(HAVE_D_REVALIDATE_WITH_INODE_NAME, 1,
			[dentry operations d_revalidate() takes inode, name])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_GRAB_CACHE_PAGE_WRITE_BEGIN], [
	LB2_LINUX_TEST_SRC([grab_cache_page_write_begin], [
	],[
		struct address_space *mapping = NULL;
		pgoff_t index = 0;
		(void)grab_cache_page_write_begin(mapping, index
			, 0
			);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_GRAB_CACHE_PAGE_WRITE_BEGIN], [
	LB2_MSG_LINUX_TEST_RESULT([if grab_cache_page_write_begin() is available],
	[grab_cache_page_write_begin], [
		AC_DEFINE(HAVE_GRAB_CACHE_PAGE_WRITE_BEGIN, 1,
			[grab_cache_page_write_begin() is available])
	], [
		AC_DEFINE([grab_cache_page_write_begin(m, i)],
			  [pagecache_get_page((m), (i), FGP_WRITEBEGIN, mapping_gfp_mask((m)))],
			  [grab_cache_page_write_begin() is unavailable])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_WAIT_ON_PAGE_LOCKED], [
	LB2_LINUX_TEST_SRC([wait_on_page_locked], [
	],[
		wait_on_page_locked((struct page *)NULL);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_WAIT_ON_PAGE_LOCKED], [
	LB2_MSG_LINUX_TEST_RESULT([if wait_on_page_locked() is available],
	[wait_on_page_locked], [
		AC_DEFINE(HAVE_WAIT_ON_PAGE_LOCKED, 1,
			[wait_on_page_locked() is available])
	], [
		AC_DEFINE([wait_on_page_locked(page)],
			[folio_wait_locked(page_folio((page)))],
			[wait_on_page_locked() is unavailable])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_HRTIMER_SETUP], [
	LB2_LINUX_TEST_SRC([hrtimer_setup], [
		static enum hrtimer_restart fn(struct hrtimer *timer)
		{ return HRTIMER_NORESTART; }
	],[
		struct hrtimer *timer = NULL;
		hrtimer_setup(timer, fn, CLOCK_MONOTONIC, HRTIMER_MODE_ABS);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_HRTIMER_SETUP], [
	LB2_MSG_LINUX_TEST_RESULT([if hrtimer_setup() is available],
	[hrtimer_setup], [
		AC_DEFINE(HAVE_HRTIMER_SETUP, 1,
			[hrtimer_setup() is available])
	], [
		AC_DEFINE([hrtimer_setup(t, f, c, m)],
			  [(hrtimer_init((t), (c), (m)), (t)->function = (f))],
			  [hrtimer_setup() is unavailable])
	])
]) 
AC_DEFUN([LC_SRC_HAVE_IOPS_MKDIR_RETURNS_DENTRY], [
	LB2_LINUX_TEST_SRC([iops_mkdir_returns_dentry], [
	],[
		struct inode_operations *iop = NULL;
		struct dentry *din = NULL;
		struct inode *parent = NULL;
		umode_t mode = 0700;
		struct dentry *dentry;
		dentry = iop->mkdir(&nop_mnt_idmap, parent, din, mode);
	],[-Werror])
])
AC_DEFUN([LC_HAVE_IOPS_MKDIR_RETURNS_DENTRY], [
	LB2_MSG_LINUX_TEST_RESULT([if inode_operations.mkdir() returns dentry],
	[iops_mkdir_returns_dentry], [
		AC_DEFINE(HAVE_IOPS_MKDIR_RETURNS_DENTRY, 1,
			[inode_operations.mkdir() returns dentry])
	])
]) 
AC_DEFUN([LC_PROG_LINUX_SRC], [
	AS_IF([test "x$enable_gss" != xno], [
		LC_SRC_KEY_TYPE_INSTANTIATE_2ARGS
		LB2_SRC_CHECK_CONFIG_IM([CRYPTO_MD5])
		LB2_SRC_CHECK_CONFIG_IM([CRYPTO_SHA1])
		LB2_SRC_CHECK_CONFIG_IM([CRYPTO_SHA256])
		LB2_SRC_CHECK_CONFIG_IM([CRYPTO_SHA512])
	])
	AS_IF([test "x$enable_server" != xno], [
		LC_SRC_CONFIG_QUOTA
		LC_SRC_STACK_SIZE
	])
	LC_SRC_CONFIG_FHANDLE
	LC_SRC_POSIX_ACL_CONFIG
	LC_SRC_HAVE_PROJECT_QUOTA
	LC_SRC_CONFIG_XARRAY_MULTI
	LC_SRC_INVALIDATE_RANGE
	LC_SRC_HAVE_DIR_CONTEXT
	LC_SRC_PID_NS_FOR_CHILDREN
	LC_SRC_FOP_READDIR
	LC_SRC_VFS_PRESSURE_RATIO
	LC_SRC_OLDSIZE_TRUNCATE_PAGECACHE
	LC_SRC_PTR_ERR_OR_ZERO_MISSING
	LC_SRC_KIOCB_KI_LEFT
	LC_SRC_VFS_RENAME_5ARGS
	LC_SRC_VFS_UNLINK_3ARGS
	LC_SRC_HAVE_BIP_ITER_BIO_INTEGRITY_PAYLOAD
	LC_SRC_HAVE_BVEC_ITER
	LC_SRC_HAVE_TRUNCATE_IPAGES_FINAL
	LC_SRC_IOPS_RENAME_WITH_FLAGS
	LC_SRC_IOP_SET_ACL
	LC_SRC_VFS_RENAME_6ARGS
	LC_SRC_PMQOS_RESUME_LATENCY
	LC_SRC_DIRECTIO_USE_ITER
	LC_SRC_HAVE_IOV_ITER_INIT_DIRECTION
	LC_SRC_HAVE_IOV_ITER_TRUNCATE
	LC_SRC_PAGECACHE_GET_PAGE
	LC_SRC_HAVE_INTERVAL_BLK_INTEGRITY
	LC_SRC_KEY_MATCH_DATA
	LC_SRC_NFS_FILLDIR_USE_CTX
	LC_SRC_PERCPU_COUNTER_INIT
	LC_SRC_KIOCB_HAS_NBYTES
	LC_SRC_HAVE_DQUOT_QC_DQBLK
	LC_SRC_HAVE_AIO_COMPLETE
	LC_SRC_HAVE_IS_ROOT_INODE
	LC_SRC_BACKING_DEV_INFO_REMOVAL
	LC_SRC_IOV_ITER_RW
	LC_SRC_HAVE___BI_CNT
	LC_SRC_BIO_ENDIO_USES_ONE_ARG
	LC_SRC_SYMLINK_OPS_USE_NAMEIDATA
	LC_SRC_ACCOUNT_PAGE_DIRTIED_3ARGS
	LC_SRC_HAVE_CRYPTO_ALLOC_SKCIPHER
	LC_SRC_HAVE_INTERVAL_EXP_BLK_INTEGRITY
	LC_SRC_HAVE_CACHE_HEAD_HLIST
	LC_SRC_HAVE_XATTR_HANDLER_SIMPLIFIED
	LC_SRC_HAVE_LOCKS_LOCK_FILE_WAIT
	LC_SRC_HAVE_KEY_PAYLOAD_DATA_ARRAY
	LC_SRC_HAVE_XATTR_HANDLER_NAME
	LC_SRC_HAVE_BI_OPF
	LC_SRC_HAVE_SUBMIT_BIO_2ARGS
	LC_SRC_HAVE_CLEAN_BDEV_ALIASES
	LC_SRC_HAVE_FILE_DENTRY
	LC_SRC_HAVE_INODE_LOCK
	LC_SRC_HAVE_IOP_GET_LINK
	LC_SRC_HAVE_IN_COMPAT_SYSCALL
	LC_SRC_HAVE_XATTR_HANDLER_INODE_PARAM
	LC_SRC_LOCK_PAGE_MEMCG
	LC_SRC_HAVE_DOWN_WRITE_KILLABLE
	LC_SRC_D_IN_LOOKUP
	LC_SRC_DIRECTIO_2ARGS
	LC_SRC_GENERIC_WRITE_SYNC_2ARGS
	LC_SRC_FOP_ITERATE_SHARED
	LC_SRC_HAVE_POSIX_ACL_VALID_USER_NS
	LC_SRC_FULL_NAME_HASH_3ARGS
	LC_SRC_STRUCT_POSIX_ACL_XATTR
	LC_SRC_IOP_XATTR
	LC_SRC_GROUP_INFO_GID
	LC_SRC_VFS_SETXATTR
	LC_SRC_POSIX_ACL_UPDATE_MODE
	LC_SRC_HAVE_BDI_IO_PAGES
	LC_SRC_RADIX_TREE_REPLACE_SLOT_3ARGS
	LC_SRC_IOP_GENERIC_READLINK
	LC_SRC_HAVE_VM_FAULT_ADDRESS
	LC_SRC_INODEOPS_ENHANCED_GETATTR
	LC_SRC_VM_OPERATIONS_REMOVE_VMF_ARG
	LC_SRC_HAVE_KEY_USAGE_REFCOUNT
	LC_SRC_HAVE_CRYPTO_MAX_ALG_NAME_128
	LC_SRC_HAVE_FSMAP_HEADER
	LC_SRC_HAVE_PERCPU_COUNTER_ADD_BATCH
	LC_SRC_CURRENT_TIME
	LC_SRC_SUPER_SETUP_BDI_NAME
	LC_SRC_BI_STATUS
	LC_SRC_HAVE_GET_INODE_USAGE
	LC_SRC_PAGEVEC_INIT_ONE_PARAM
	LC_SRC_BI_BDEV
	LC_SRC_INTERVAL_TREE_CACHED
	LC_SRC_VM_FAULT_T
	LC_SRC_VM_FAULT_RETRY
	LC_SRC_I_PAGES
	LC_SRC_INODE_TIMESPEC64
	LC_SRC_ALLOC_FILE_PSEUDO
	LC_SRC_UAPI_LINUX_MOUNT_H
	LC_SRC_HAVE_SUNRPC_CACHE_HASH_LOCK_IS_A_SPINLOCK
	LC_SRC_GENL_FAMILY_HAS_RESV_START_OP
	LC_SRC_HAVE_FS_CONTEXT_HEADER
	LC_SRC_HAVE_BVEC_ITER_ALL
	LC_SRC_KEYRING_SEARCH_4ARGS
	LC_SRC_BIO_BI_PHYS_SEGMENTS
	LC_SRC_LM_COMPARE_OWNER_EXISTS
	LC_SRC_FSCRYPT_DIGESTED_NAME
	LC_SRC_FSCRYPT_DUMMY_CONTEXT_ENABLED
	LC_SRC_HAVE_PRANDOM_HEADER
	LC_SRC_HAVE_KTHREAD_USE_MM
	LC_SRC_FSCRYPT_FNAME_ALLOC_BUFFER
	LC_SRC_FSCRYPT_SET_CONTEXT
	LC_SRC_FSCRYPT_NOKEY_NAME
	LC_SRC_FSCRYPT_SET_TEST_DUMMY_ENC_CHAR_ARG
	LC_SRC_FSCRYPT_DUMMY_POLICY
	LC_SRC_HAVE_ITER_FILE_SPLICE_WRITE
	LC_SRC_HAVE_BDI_DEBUG_STATS
	LC_SRC_FSCRYPT_IS_NOKEY_NAME
	LC_SRC_FSCRYPT_PREPARE_READDIR
	LC_SRC_BIO_SET_DEV
	LC_SRC_HAVE_USER_NAMESPACE_ARG
	LC_SRC_HAVE_COPY_PAGE_FROM_ITER_ATOMIC
	LC_SRC_HAVE_FILEATTR_GET
	LC_SRC_HAVE_GET_ACL_RCU_ARG
	LC_SRC_HAVE_FAULT_IN_IOV_ITER_READABLE
	LC_SRC_HAVE_SECURITY_DENTRY_INIT_WITH_XATTR_NAME_ARG
	LC_SRC_FOLIO_MEMCG_LOCK
	LC_SRC_HAVE_KIOCB_COMPLETE_2ARGS
	LC_SRC_HAVE_INVALIDATE_FOLIO
	LC_SRC_HAVE_DIRTY_FOLIO
	LC_SRC_HAVE_ALLOC_INODE_SB
	LC_SRC_HAVE_ADDRESS_SPACE_OPERATIONS_READ_FOLIO
	LC_SRC_HAVE_READ_CACHE_PAGE_FILLER_WITH_FILE
	LC_SRC_HAVE_ADDRESS_SPACE_OPERATIONS_RELEASE_FOLIO
	LC_SRC_HAVE_LSMCONTEXT_INIT
	LC_SRC_SECURITY_DENTRY_INIT_SECURTY_WITH_CTX
	LC_SRC_HAVE_FILEMAP_GET_FOLIOS
	LC_SRC_HAVE_NO_LLSEEK
	LC_SRC_DQUOT_TRANSFER_WITH_USER_NS
	LC_SRC_HAVE_ADDRESS_SPACE_OPERATIONS_MIGRATE_FOLIO
	LC_SRC_REGISTER_SHRINKER_FORMAT_NAMED
	LC_SRC_HAVE_VFS_SETXATTR_NON_CONST_VALUE
	LC_SRC_HAVE_IOV_ITER_GET_PAGES_ALLOC2
	LC_SRC_HAVE_USER_BACKED_ITER
	LC_SRC_HAVE_IOV_ITER_IS_ALIGNED
	LC_SRC_HAVE_GET_RANDOM_U32_AND_U64
	LC_SRC_NFS_FILLDIR_USE_CTX_RETURN_BOOL
	LC_SRC_HAVE_FILEMAP_GET_FOLIOS_CONTIG
	LC_SRC_IOP_GET_INODE_ACL
	LC_SRC_HAVE_GET_RANDOM_U32_BELOW
	LC_SRC_HAVE_ACL_WITH_DENTRY
	LC_SRC_HAVE_FOLIO_MAPCOUNT
	LC_SRC_HAVE_MNT_IDMAP_ARG
	LC_SRC_HAVE_LOCKS_LOCK_FILE_WAIT_IN_FILELOCK
	LC_SRC_HAVE_U64_CAPABILITY
	LC_SRC_HAVE_FOLIO_BATCH_REINIT
	LC_SRC_HAVE_IOV_ITER_IOVEC
	LC_SRC_HAVE_IOVEC_WITH_IOV_MEMBER
	LC_SRC_HAVE_CLASS_CREATE_MODULE_ARG
	LC_SRC_HAVE_ENUM_ITER_PIPE
	LC_SRC_HAVE_GET_USER_PAGES_WITHOUT_VMA
	LC_SRC_HAVE_FOLIO_BATCH
	LC_SRC_HAVE_STRUCT_PAGEVEC
	LC_SRC_HAVE_FLUSH___WORKQUEUE
	LC_SRC_HAVE_INODE_GET_CTIME
	LC_SRC_HAVE_MMAP_WRITE_TRYLOCK
	LC_SRC_HAVE_GENERIC_FILEATTR_HAS_MASK_ARG
	LC_SRC_HAVE_GROUP_INFO_USAGE_AS_REFCOUNT
	LC_SRC_HAVE_NSPROXY_COUNT_AS_REFCOUNT
	LC_SRC_HAVE_INODE_GET_MTIME_SEC
	LC_SRC_HAVE_SHRINKER_ALLOC
	LC_SRC_HAVE_DENTRY_D_CHILDREN
	LC_SRC_HAVE_GENERIC_ERROR_REMOVE_FOLIO
	LC_SRC_LSMCONTEXT_HAS_ID
	LC_SRC_HAVE_STRUCT_FILE_LOCK_CORE
	LC_SRC_HAVE_CSUM_TYPE_BLK_INTEGRITY
	LC_SRC_HAVE_LINUX_UNALIGNED_HEADER
	LC_SRC_HAVE_WRITE_BEGIN_FOLIO
	LC_SRC_HAVE_STRUCT_FILE_F_VERSION
	LC_SRC_HAVE_PG_ERROR
	LC_SRC_HAVE_FOLIO_TEST_MLOCKED
	LC_SRC_HAVE_PAGE_MAPCOUNT_IS_TYPE
	LC_SRC_HAVE_MODULE_IMPORT_STRING_LITERAL
	LC_SRC_HAVE_PAGEPRIVATE2
	LC_SRC_HAVE_D_REVALIDATE_WITH_INODE_NAME
	LC_SRC_HAVE_GRAB_CACHE_PAGE_WRITE_BEGIN
	LC_SRC_HAVE_WAIT_ON_PAGE_LOCKED
	LC_SRC_HAVE_HRTIMER_SETUP
	LC_SRC_HAVE_IOPS_MKDIR_RETURNS_DENTRY
])
AC_DEFUN([LC_PROG_LINUX_RESULTS], [
	AS_IF([test "x$enable_gss" != xno], [
		LC_KEY_TYPE_INSTANTIATE_2ARGS
		LB2_TEST_CHECK_CONFIG_IM([CRYPTO_MD5], [],
			[AC_MSG_WARN(
			[kernel MD5 support is recommended by using GSS.])])
		LB2_TEST_CHECK_CONFIG_IM([CRYPTO_SHA1], [],
			[AC_MSG_WARN(
			[kernel SHA1 support is recommended by using GSS.])])
		LB2_TEST_CHECK_CONFIG_IM([CRYPTO_SHA256], [],
			[AC_MSG_WARN(
			[kernel SHA256 support is recommended by using GSS.])])
		LB2_TEST_CHECK_CONFIG_IM([CRYPTO_SHA512], [],
			[AC_MSG_WARN(
			[kernel SHA512 support is recommended by using GSS.])])
	])
	AS_IF([test "x$enable_server" != xno], [
		LC_CONFIG_QUOTA
		LC_STACK_SIZE
	])
	LC_CONFIG_FHANDLE
	LC_POSIX_ACL_CONFIG
	LC_HAVE_PROJECT_QUOTA
	LC_CONFIG_XARRAY_MULTI
	LC_INVALIDATE_RANGE
	LC_HAVE_DIR_CONTEXT
	LC_PID_NS_FOR_CHILDREN
	LC_FOP_READDIR
	LC_VFS_PRESSURE_RATIO
	LC_OLDSIZE_TRUNCATE_PAGECACHE
	LC_PTR_ERR_OR_ZERO_MISSING
	LC_KIOCB_KI_LEFT
	LC_VFS_RENAME_5ARGS
	LC_VFS_UNLINK_3ARGS
	LC_HAVE_BIP_ITER_BIO_INTEGRITY_PAYLOAD
	LC_HAVE_BVEC_ITER
	LC_HAVE_TRUNCATE_IPAGES_FINAL
	LC_IOPS_RENAME_WITH_FLAGS
	LC_IOP_SET_ACL
	LC_VFS_RENAME_6ARGS
	LC_PMQOS_RESUME_LATENCY
	LC_DIRECTIO_USE_ITER
	LC_HAVE_IOV_ITER_INIT_DIRECTION
	LC_HAVE_IOV_ITER_TRUNCATE
	LC_PAGECACHE_GET_PAGE
	LC_HAVE_INTERVAL_BLK_INTEGRITY
	LC_KEY_MATCH_DATA
	LC_PERCPU_COUNTER_INIT
	LC_NFS_FILLDIR_USE_CTX
	LC_KIOCB_HAS_NBYTES
	LC_HAVE_DQUOT_QC_DQBLK
	LC_HAVE_AIO_COMPLETE
	LC_HAVE_IS_ROOT_INODE
	LC_BACKING_DEV_INFO_REMOVAL
	LC_IOV_ITER_RW
	LC_HAVE___BI_CNT
	LC_BIO_ENDIO_USES_ONE_ARG
	LC_SYMLINK_OPS_USE_NAMEIDATA
	LC_ACCOUNT_PAGE_DIRTIED_3ARGS
	LC_HAVE_CRYPTO_ALLOC_SKCIPHER
	LC_HAVE_INTERVAL_EXP_BLK_INTEGRITY
	LC_HAVE_CACHE_HEAD_HLIST
	LC_HAVE_XATTR_HANDLER_SIMPLIFIED
	LC_HAVE_LOCKS_LOCK_FILE_WAIT
	LC_HAVE_KEY_PAYLOAD_DATA_ARRAY
	LC_HAVE_XATTR_HANDLER_NAME
	LC_HAVE_BI_OPF
	LC_HAVE_SUBMIT_BIO_2ARGS
	LC_HAVE_CLEAN_BDEV_ALIASES
	LC_HAVE_FILE_DENTRY
	LC_HAVE_INODE_LOCK
	LC_HAVE_IOP_GET_LINK
	LC_HAVE_IN_COMPAT_SYSCALL
	LC_HAVE_XATTR_HANDLER_INODE_PARAM
	LC_LOCK_PAGE_MEMCG
	LC_HAVE_DOWN_WRITE_KILLABLE
	LC_D_IN_LOOKUP
	LC_DIRECTIO_2ARGS
	LC_GENERIC_WRITE_SYNC_2ARGS
	LC_FOP_ITERATE_SHARED
	LC_HAVE_POSIX_ACL_VALID_USER_NS
	LC_FULL_NAME_HASH_3ARGS
	LC_STRUCT_POSIX_ACL_XATTR
	LC_IOP_XATTR
	LC_GROUP_INFO_GID
	LC_VFS_SETXATTR
	LC_POSIX_ACL_UPDATE_MODE
	LC_HAVE_BDI_IO_PAGES
	LC_RADIX_TREE_REPLACE_SLOT_3ARGS
	LC_IOP_GENERIC_READLINK
	LC_HAVE_VM_FAULT_ADDRESS
	LC_INODEOPS_ENHANCED_GETATTR
	LC_VM_OPERATIONS_REMOVE_VMF_ARG
	LC_HAVE_KEY_USAGE_REFCOUNT
	LC_HAVE_CRYPTO_MAX_ALG_NAME_128
	LC_HAVE_FSMAP_HEADER
	LC_HAVE_PERCPU_COUNTER_ADD_BATCH
	LC_CURRENT_TIME
	LC_SUPER_SETUP_BDI_NAME
	LC_BI_STATUS
	LC_HAVE_GET_INODE_USAGE
	LC_PAGEVEC_INIT_ONE_PARAM
	LC_BI_BDEV
	LC_INTERVAL_TREE_CACHED
	LC_VM_FAULT_T
	LC_VM_FAULT_RETRY
	LC_I_PAGES
	LC_ALLOC_FILE_PSEUDO
	LC_INODE_TIMESPEC64
	LC_UAPI_LINUX_MOUNT_H
	LC_HAVE_SUNRPC_CACHE_HASH_LOCK_IS_A_SPINLOCK
	LC_GENL_FAMILY_HAS_RESV_START_OP
	LC_HAVE_FS_CONTEXT_HEADER
	LC_HAVE_BVEC_ITER_ALL
	LC_KEYRING_SEARCH_4ARGS
	LC_BIO_BI_PHYS_SEGMENTS
	LC_HAVE_FLUSH_DELAYED_FPUT
	LC_LM_COMPARE_OWNER_EXISTS
	LC_FSCRYPT_DIGESTED_NAME
	LC_FSCRYPT_DUMMY_CONTEXT_ENABLED
	LC_HAVE_PRANDOM_HEADER
	LC_HAVE_KTHREAD_USE_MM
	LC_HAVE_ITER_FILE_SPLICE_WRITE
	LC_FSCRYPT_FNAME_ALLOC_BUFFER
	LC_FSCRYPT_SET_CONTEXT
	LC_FSCRYPT_D_REVALIDATE
	LC_FSCRYPT_NOKEY_NAME
	LC_FSCRYPT_SET_TEST_DUMMY_ENC_CHAR_ARG
	LC_FSCRYPT_DUMMY_POLICY
	LC_HAVE_BDI_DEBUG_STATS
	LC_FSCRYPT_IS_NOKEY_NAME
	LC_FSCRYPT_PREPARE_READDIR
	LC_BIO_SET_DEV
	LC_HAVE_USER_NAMESPACE_ARG
	LC_HAVE_FILEATTR_GET
	LC_HAVE_COPY_PAGE_FROM_ITER_ATOMIC
	LC_HAVE_GET_ACL_RCU_ARG
	LC_HAVE_FAULT_IN_IOV_ITER_READABLE
	LC_HAVE_SECURITY_DENTRY_INIT_WITH_XATTR_NAME_ARG
	LC_FOLIO_MEMCG_LOCK
	LC_HAVE_KIOCB_COMPLETE_2ARGS
	LC_FOLIO_MEMCG_LOCK_EXPORTED
	LC_EXPORTS_DELETE_FROM_PAGE_CACHE
	LC_HAVE_INVALIDATE_FOLIO
	LC_HAVE_DIRTY_FOLIO
	LC_HAVE_ALLOC_INODE_SB
	LC_HAVE_ADDRESS_SPACE_OPERATIONS_READ_FOLIO
	LC_HAVE_READ_CACHE_PAGE_FILLER_WITH_FILE
	LC_HAVE_ADDRESS_SPACE_OPERATIONS_RELEASE_FOLIO
	LC_HAVE_LSMCONTEXT_INIT
	LC_SECURITY_DENTRY_INIT_SECURTY_WITH_CTX
	LC_HAVE_FILEMAP_GET_FOLIOS
	LC_HAVE_NO_LLSEEK
	LC_DQUOT_TRANSFER_WITH_USER_NS
	LC_HAVE_ADDRESS_SPACE_OPERATIONS_MIGRATE_FOLIO
	LC_REGISTER_SHRINKER_FORMAT_NAMED
	LC_HAVE_VFS_SETXATTR_NON_CONST_VALUE
	LC_HAVE_IOV_ITER_GET_PAGES_ALLOC2
	LC_HAVE_USER_BACKED_ITER
	LC_HAVE_IOV_ITER_IS_ALIGNED
	LC_HAVE_GET_RANDOM_U32_AND_U64
	LC_NFS_FILLDIR_USE_CTX_RETURN_BOOL
	LC_HAVE_FILEMAP_GET_FOLIOS_CONTIG
	LC_IOP_GET_INODE_ACL
	LC_HAVE_GET_RANDOM_U32_BELOW
	LC_HAVE_ACL_WITH_DENTRY
	LC_HAVE_FOLIO_MAPCOUNT
	LC_HAVE_MNT_IDMAP_ARG
	LC_HAVE_LOCKS_LOCK_FILE_WAIT_IN_FILELOCK
	LC_HAVE_U64_CAPABILITY
	LC_HAVE_FOLIO_BATCH_REINIT
	LC_HAVE_IOV_ITER_IOVEC
	LC_HAVE_IOVEC_WITH_IOV_MEMBER
	LC_HAVE_CLASS_CREATE_MODULE_ARG
	LC_HAVE_ENUM_ITER_PIPE
	LC_HAVE_GET_USER_PAGES_WITHOUT_VMA
	LC_HAVE_FOLIO_BATCH
	LC_HAVE_STRUCT_PAGEVEC
	LC_EXPORTS_FILEMAP_SPLICE_READ
	LC_HAVE_FLUSH___WORKQUEUE
	LC_HAVE_INODE_GET_CTIME
	LC_HAVE_MMAP_WRITE_TRYLOCK
	LC_HAVE_GENERIC_FILEATTR_HAS_MASK_ARG
	LC_HAVE_GROUP_INFO_USAGE_AS_REFCOUNT
	LC_HAVE_NSPROXY_COUNT_AS_REFCOUNT
	LC_HAVE_INODE_GET_MTIME_SEC
	LC_HAVE_SHRINKER_ALLOC
	LC_HAVE_DENTRY_D_CHILDREN
	LC_HAVE_GENERIC_ERROR_REMOVE_FOLIO
	LC_LSMCONTEXT_HAS_ID
	LC_HAVE_STRUCT_FILE_LOCK_CORE
	LC_HAVE_CSUM_TYPE_BLK_INTEGRITY
	LC_HAVE_LINUX_UNALIGNED_HEADER
	LC_HAVE_WRITE_BEGIN_FOLIO
	LC_HAVE_STRUCT_FILE_F_VERSION
	LC_HAVE_PG_ERROR
	LC_HAVE_FOLIO_TEST_MLOCKED
	LC_HAVE_PAGE_MAPCOUNT_IS_TYPE
	LC_HAVE_MODULE_IMPORT_STRING_LITERAL
	LC_HAVE_PAGEPRIVATE2
	LC_HAVE_D_REVALIDATE_WITH_INODE_NAME
	LC_HAVE_GRAB_CACHE_PAGE_WRITE_BEGIN
	LC_HAVE_WAIT_ON_PAGE_LOCKED
	LC_HAVE_HRTIMER_SETUP
	LC_HAVE_IOPS_MKDIR_RETURNS_DENTRY
])
AC_DEFUN([LC_PROG_LINUX], [
	AC_MSG_NOTICE([Lustre kernel checks
==============================================================================])
	LC_CONFIG_PINGER
	LC_CONFIG_CHECKSUM
	LC_CONFIG_FLOCK
	LC_CONFIG_LRU_RESIZE
	LC_CONFIG_GSS
	LC_GLIBC_SUPPORT_FHANDLES
	LC_GLIBC_SUPPORT_COPY_FILE_RANGE
	LC_OPENSSL_SSK
	LC_OPENSSL_GETSEPOL
	LC_EXPORT_DEFAULT_FILE_SPLICE_READ
	LC_ACCOUNT_PAGE_DIRTIED
	LC_HAVE_ADD_TO_PAGE_CACHE_LOCKED
]) 
AC_DEFUN([LC_CONFIG_CLIENT], [
AC_MSG_CHECKING([whether to build Lustre client support])
AC_ARG_ENABLE([client],
	AS_HELP_STRING([--disable-client],
		[disable Lustre client support]),
	[], [enable_client="yes"])
AC_MSG_RESULT([$enable_client])
]) 
AC_DEFUN([LB_CONFIG_MPITESTS], [
AC_ARG_ENABLE([mpitests],
	AS_HELP_STRING([--enable-mpitests=<yes|no|mpicc wrapper>],
		       [include mpi tests]), [
		enable_mpitests="yes"
		case $enableval in
		yes)
			MPICC_WRAPPER="mpicc"
			MPI_BIN=$(eval which $MPICC_WRAPPER 2>/dev/null | xargs -r dirname)
			;;
		no)
			enable_mpitests="no"
			MPI_BIN=""
			;;
		*)
			MPICC_WRAPPER=$enableval
			MPI_BIN=$(eval echo $MPICC_WRAPPER | xargs -r dirname)
			;;
		esac
	], [
		enable_mpitests="yes"
		MPICC_WRAPPER="mpicc"
		MPI_BIN=$(eval which $MPICC_WRAPPER 2>/dev/null | xargs -r dirname)
	])
	if test "x$enable_mpitests" != "xno"; then
		oldcc=$CC
		CC=$MPICC_WRAPPER
		AC_CACHE_CHECK([whether mpitests can be built],
		lb_cv_mpi_tests, [AC_COMPILE_IFELSE([AC_LANG_SOURCE([
			int main(void) {
				int flag;
				MPI_Initialized(&flag);
				return 0;
			}
		])], [lb_cv_mpi_tests="yes"], [lb_cv_mpi_tests="no"])
		])
		enable_mpitests=$lb_cv_mpi_tests
		CC=$oldcc
	fi
	AC_SUBST(MPI_BIN)
	AC_SUBST(MPICC_WRAPPER)
]) 
AC_DEFUN([LC_ENABLE_QUOTA], [
AC_MSG_CHECKING([whether to enable quota support global control])
AC_ARG_ENABLE([quota],
	AS_HELP_STRING([--enable-quota],
		[enable quota support]),
	[], [enable_quota="yes"])
AS_IF([test "x$enable_quota" = xyes],
	[AC_MSG_RESULT([yes])],
	[AC_MSG_RESULT([no])])
]) 
AC_DEFUN([LC_QUOTA], [
LC_ENABLE_QUOTA
AS_IF([test "x$enable_quota" != xno -a "x$enable_utils" != xno], [
	AC_CHECK_HEADER([sys/quota.h],
		[AC_DEFINE(HAVE_SYS_QUOTA_H, 1,
			[Define to 1 if you have <sys/quota.h>.])],
		[AC_MSG_ERROR([did not find <sys/quota.h> on your system])])
])
]) 
AC_DEFUN([LC_OSD_ADDON], [
AC_MSG_CHECKING([whether to use OSD addon])
AC_ARG_WITH([osd],
	AS_HELP_STRING([--with-osd=path],
		[set path to optional osd]),
	[
	case "$with_osd" in
	no)
		ENABLEOSDADDON=0
		;;
	*)
		OSDADDON="$with_osd"
		ENABLEOSDADDON=1
		;;
	esac
	], [
		ENABLEOSDADDON=0
	])
AS_IF([test $ENABLEOSDADDON -eq 0], [
	AC_MSG_RESULT([no])
	OSDADDON=""
], [
	OSDMODNAME=$(basename $OSDADDON)
	AS_IF([test -e $LUSTRE/$OSDMODNAME], [
		AC_MSG_RESULT([cannot link])
		OSDADDON=""
	], [ln -s $OSDADDON $LUSTRE/$OSDMODNAME], [
		AC_MSG_RESULT([$OSDMODNAME])
		OSDADDON="obj-m += $OSDMODNAME/"
	], [
		AC_MSG_RESULT([cannot link])
		OSDADDON=""
	])
])
AC_SUBST(OSDADDON)
]) 
AC_DEFUN([LC_CONFIG_CRYPTO], [
AC_MSG_CHECKING([whether to enable Lustre client crypto])
AC_ARG_ENABLE([crypto],
	AS_HELP_STRING([--enable-crypto=yes|no|in-kernel],
		[enable Lustre client crypto (default is yes), use 'in-kernel' to force use of in-kernel fscrypt instead of embedded llcrypt]),
	[], [enable_crypto="auto"])
AS_IF([test "x$enable_crypto" != xno -a "x$enable_dist" = xno], [
	AC_MSG_RESULT(
	)
	LC_IS_ENCRYPTED
	LC_FSCRYPT_SUPPORT])
AS_IF([test "x$enable_crypto" = xin-kernel -o "x$enable_modules" = xno -a "x$enable_dist" = xno], [
	AS_IF([test "x$has_fscrypt_support" = xyes], [
	      AC_DEFINE(HAVE_LUSTRE_CRYPTO, 1, [Enable Lustre client crypto via in-kernel fscrypt])], [
	      AC_MSG_ERROR([Lustre client crypto cannot be enabled via in-kernel fscrypt.])
	      enable_crypto=no])],
	[AS_IF([test "x$has_is_encrypted" = xyes], [
	      AC_DEFINE(HAVE_LUSTRE_CRYPTO, 1, [Enable Lustre client crypto via embedded llcrypt])
	      AC_DEFINE(CONFIG_LL_ENCRYPTION, 1, [embedded llcrypt])
	      AC_DEFINE(HAVE_FSCRYPT_DUMMY_CONTEXT_ENABLED, 1, [embedded llcrypt uses llcrypt_dummy_context_enabled()])
	      enable_crypto="embedded-llcrypt"
	      enable_llcrypt=yes], [
	      AS_IF([test "x$enable_crypto" = xyes],
	            [AC_MSG_ERROR([Lustre client crypto cannot be enabled because of lack of encryption support in your kernel.])])
	      AS_IF([test "x$enable_crypto" != xno -a "x$enable_dist" = xno],
	            [AC_MSG_WARN(Lustre client crypto cannot be enabled because of lack of encryption support in your kernel.)])
	      enable_crypto=no])])
AS_IF([test "x$enable_dist" != xno], [
	enable_crypto=yes
	enable_llcrypt=yes])
AC_MSG_RESULT([$enable_crypto])
]) 
AC_DEFUN([LC_CONFIGURE], [
AC_MSG_NOTICE([Lustre core checks
==============================================================================])
LC_MDS_MAX_THREADS
AC_CHECK_HEADERS([netdb.h endian.h])
AC_CHECK_HEADERS([ext2fs/ext2fs.h], [], [
	AS_IF([test "x$enable_utils" = xyes -a "x$enable_ldiskfs" = xyes], [
		AC_MSG_ERROR([
ext2fs.h not found. Please install e2fsprogs development package.
		])
	])
])
AC_CHECK_FUNCS([statx])
AS_IF([test "$enable_dist" = "no"], [
		AC_CHECK_LIB([z], [crc32], [
				 AC_CHECK_HEADER([zlib.h], [], [
						 AC_MSG_ERROR([zlib.h not found.])])
				 ], [
				 AC_MSG_ERROR([
		zlib library not found. Please install zlib development package.])
		])
])
SELINUX=""
AC_CHECK_LIB([selinux], [is_selinux_enabled],
	[AC_CHECK_HEADERS([selinux/selinux.h],
			[SELINUX="-lselinux"
			AC_DEFINE([HAVE_SELINUX], 1,
				[support for selinux ])],
			[AC_MSG_WARN([
No libselinux-devel package found, unable to build selinux enabled tools
])
])],
	[AC_MSG_WARN([
No selinux package found, unable to build selinux enabled tools
])
])
AC_SUBST(SELINUX)
AC_CHECK_LIB([keyutils], [add_key])
AC_MSG_CHECKING([whether to report minimum OST free space])
AC_ARG_ENABLE([mindf],
	AS_HELP_STRING([--enable-mindf],
		[Make statfs report the minimum available space on any single OST instead of the sum of free space on all OSTs]),
	[], [enable_mindf="no"])
AC_MSG_RESULT([$enable_mindf])
AS_IF([test "$enable_mindf" = "yes"], [
	AC_DEFINE([MIN_DF], 1, [Report minimum OST free space])
	AC_SUBST(ENABLE_MINDF, yes)
], [
	AC_SUBST(ENABLE_MINDF, no)
])
AC_MSG_CHECKING([whether to randomly failing memory alloc])
AC_ARG_ENABLE([fail_alloc],
	AS_HELP_STRING([--disable-fail-alloc],
		[disable randomly alloc failure]),
	[], [enable_fail_alloc="yes"])
AC_MSG_RESULT([$enable_fail_alloc])
AS_IF([test "x$enable_fail_alloc" != xno], [
	AC_DEFINE([RANDOM_FAIL_ALLOC], 1, [enable randomly alloc failure])
	AC_SUBST(ENABLE_FAIL_ALLOC, yes)
], [
	AC_SUBST(ENABLE_FAIL_ALLOC, no)
])
AC_MSG_CHECKING([whether to check invariants (expensive cpu-wise)])
AC_ARG_ENABLE([invariants],
	AS_HELP_STRING([--enable-invariants],
		[enable invariant checking (cpu intensive)]),
	[], [enable_invariants="no"])
AC_MSG_RESULT([$enable_invariants])
AS_IF([test "x$enable_invariants" = xyes], [
	AC_DEFINE([CONFIG_LUSTRE_DEBUG_EXPENSIVE_CHECK], 1,
		  [enable invariant checking])
	AC_SUBST(ENABLE_INVARIANTS, yes)
], [
	AC_SUBST(ENABLE_INVARIANTS, no)
])
AC_MSG_CHECKING([whether to enable page state tracking])
AC_ARG_ENABLE([pgstate-track],
	AS_HELP_STRING([--enable-pgstate-track],
		[enable page state tracking]),
	[], [enable_pgstat_track="no"])
AC_MSG_RESULT([$enable_pgstat_track])
AS_IF([test "x$enable_pgstat_track" = xyes], [
	AC_DEFINE([CONFIG_DEBUG_PAGESTATE_TRACKING], 1,
		  [enable page state tracking code])
	AC_SUBST(ENABLE_PGSTAT_TRACK, yes)
], [
	AC_SUBST(ENABLE_PGSTAT_TRACK, no)
])
PKG_PROG_PKG_CONFIG
AC_MSG_CHECKING([systemd unit file directory])
AC_ARG_WITH([systemdsystemunitdir],
	[AS_HELP_STRING([--with-systemdsystemunitdir=DIR],
		[Directory for systemd service files])],
	[], [with_systemdsystemunitdir=auto])
AS_IF([test "x$with_systemdsystemunitdir" = "xyes" -o "x$with_systemdsystemunitdir" = "xauto"],
	[def_systemdsystemunitdir=$($PKG_CONFIG --variable=systemdsystemunitdir systemd)
	AS_IF([test "x$def_systemdsystemunitdir" = "x"],
		[AS_IF([test "x$with_systemdsystemunitdir" = "xyes"],
		[AC_MSG_ERROR([systemd support requested but pkg-config unable to query systemd package])])
		with_systemdsystemunitdir=no],
	[with_systemdsystemunitdir="$def_systemdsystemunitdir"])])
AS_IF([test "x$with_systemdsystemunitdir" != "xno"],
	[AC_SUBST([systemdsystemunitdir], [$with_systemdsystemunitdir])])
AC_MSG_RESULT([$with_systemdsystemunitdir])
AC_MSG_CHECKING([bash-completion directory])
AC_ARG_WITH([bash-completion-dir],
	AS_HELP_STRING([--with-bash-completion-dir[=PATH]],
		[Install the bash auto-completion script in this directory.]),
	[],
	[with_bash_completion_dir=yes])
AS_IF([test "x$with_bash_completion_dir" = "xyes"], [
	BASH_COMPLETION_DIR="`pkg-config --variable=completionsdir bash-completion`"
	AS_IF([test "x$BASH_COMPLETION_DIR" = "x"], [
		[BASH_COMPLETION_DIR="/usr/share/bash-completion/completions"]
	])
], [
	BASH_COMPLETION_DIR="$with_bash_completion_dir"
])
AC_SUBST([BASH_COMPLETION_DIR])
AC_MSG_RESULT([$BASH_COMPLETION_DIR])
]) 
AC_DEFUN([LC_CONDITIONALS], [
AM_CONDITIONAL(MPITESTS, test x$enable_mpitests = xyes, Build MPI Tests)
AM_CONDITIONAL(CLIENT, test x$enable_client = xyes)
AM_CONDITIONAL(SERVER, test x$enable_server = xyes)
AM_CONDITIONAL(SPLIT, test x$enable_split = xyes)
AM_CONDITIONAL(EXT2FS_DEVEL, test x$ac_cv_header_ext2fs_ext2fs_h = xyes)
AM_CONDITIONAL(GSS, test x$enable_gss = xyes)
AM_CONDITIONAL(GSS_KEYRING, test x$enable_gss_keyring = xyes)
AM_CONDITIONAL(GSS_SSK, test x$enable_ssk = xyes)
AM_CONDITIONAL(LIBPTHREAD, test x$enable_libpthread = xyes)
AM_CONDITIONAL(HAVE_SYSTEMD, test "x$with_systemdsystemunitdir" != "xno")
AM_CONDITIONAL(ENABLE_BASH_COMPLETION, test "x$with_bash_completion_dir" != "xno")
AM_CONDITIONAL(XATTR_HANDLER, test "x$lb_cv_compile_xattr_handler_flags" = xyes)
AM_CONDITIONAL(SELINUX, test "$SELINUX" = "-lselinux")
AM_CONDITIONAL(GETSEPOL, test x$enable_getsepol = xyes &&
                         test x$config_getsepol = xyes)
AM_CONDITIONAL(LLCRYPT, test x$enable_llcrypt = xyes)
AM_CONDITIONAL(LIBAIO, test x$enable_libaio = xyes)
]) 
AC_DEFUN([LC_CONFIG_FILES],
[AC_CONFIG_FILES([
grumple/Makefile
grumple/autoMakefile
grumple/conf/Makefile
grumple/conf/resource/Makefile
grumple/doc/Makefile
grumple/include/Makefile
grumple/include/grumple/Makefile
grumple/include/uapi/linux/grumple/Makefile
grumple/kernel_patches/targets/5.14-rhel9.6.target
grumple/kernel_patches/targets/5.14-rhel9.5.target
grumple/kernel_patches/targets/5.14-rhel9.4.target
grumple/kernel_patches/targets/5.14-rhel9.3.target
grumple/kernel_patches/targets/5.14-rhel9.2.target
grumple/kernel_patches/targets/5.14-rhel9.1.target
grumple/kernel_patches/targets/5.14-rhel9.0.target
grumple/kernel_patches/targets/4.18-rhel8.10.target
grumple/kernel_patches/targets/4.18-rhel8.9.target
grumple/kernel_patches/targets/4.18-rhel8.8.target
grumple/kernel_patches/targets/4.18-rhel8.7.target
grumple/kernel_patches/targets/4.18-rhel8.6.target
grumple/kernel_patches/targets/4.18-rhel8.5.target
grumple/kernel_patches/targets/4.18-rhel8.4.target
grumple/kernel_patches/targets/4.18-rhel8.3.target
grumple/kernel_patches/targets/4.18-rhel8.2.target
grumple/kernel_patches/targets/4.18-rhel8.1.target
grumple/kernel_patches/targets/4.18-rhel8.target
grumple/kernel_patches/targets/3.10-rhel7.9.target
grumple/kernel_patches/targets/3.10-rhel7.8.target
grumple/kernel_patches/targets/3.10-rhel7.7.target
grumple/kernel_patches/targets/3.10-rhel7.6.target
grumple/kernel_patches/targets/3.10-rhel7.5.target
grumple/kernel_patches/targets/4.14-rhel7.5.target
grumple/kernel_patches/targets/4.14-rhel7.6.target
grumple/kernel_patches/targets/4.12-sles12sp4.target
grumple/kernel_patches/targets/4.12-sles12sp5.target
grumple/kernel_patches/targets/4.12-sles15sp1.target
grumple/kernel_patches/targets/5.3-sles15sp2.target
grumple/kernel_patches/targets/5.3-sles15sp3.target
grumple/kernel_patches/targets/5.14-sles15sp4.target
grumple/kernel_patches/targets/5.14-sles15sp5.target
grumple/kernel_patches/targets/6.4-sles15sp6.target
grumple/kernel_patches/targets/6.4-sles15sp7.target
grumple/kernel_patches/targets/3.x-fc18.target
grumple/kernel_patches/targets/5.10-oe2203.target
grumple/kernel_patches/targets/5.10-oe2203sp1.target
grumple/kernel_patches/targets/5.10-oe2203sp2.target
grumple/ldlm/Makefile
grumple/ldlm/autoMakefile
grumple/ec/autoMakefile
grumple/ec/Makefile
grumple/fid/Makefile
grumple/fid/autoMakefile
grumple/llite/Makefile
grumple/llite/autoMakefile
grumple/lov/Makefile
grumple/lov/autoMakefile
grumple/mdc/Makefile
grumple/mdc/autoMakefile
grumple/lmv/Makefile
grumple/lmv/autoMakefile
grumple/lfsck/Makefile
grumple/lfsck/autoMakefile
grumple/mdt/Makefile
grumple/mdt/autoMakefile
grumple/mdd/Makefile
grumple/mdd/autoMakefile
grumple/fld/Makefile
grumple/fld/autoMakefile
grumple/obdclass/Makefile
grumple/obdclass/autoMakefile
grumple/obdecho/Makefile
grumple/obdecho/autoMakefile
grumple/ofd/Makefile
grumple/ofd/autoMakefile
grumple/osc/Makefile
grumple/osc/autoMakefile
grumple/osd-ldiskfs/Makefile
grumple/osd-ldiskfs/autoMakefile
grumple/osd-zfs/Makefile
grumple/osd-zfs/autoMakefile
grumple/osd-wbcfs/Makefile
grumple/osd-wbcfs/autoMakefile
grumple/mgc/Makefile
grumple/mgc/autoMakefile
grumple/mgs/Makefile
grumple/mgs/autoMakefile
grumple/target/Makefile
grumple/target/autoMakefile
grumple/ptlrpc/Makefile
grumple/ptlrpc/autoMakefile
grumple/ptlrpc/gss/Makefile
grumple/ptlrpc/gss/autoMakefile
grumple/quota/Makefile
grumple/quota/autoMakefile
grumple/scripts/Makefile
grumple/scripts/systemd/Makefile
grumple/tests/Makefile
grumple/tests/mpi/Makefile
grumple/tests/iabf/Makefile
grumple/tests/lutf/Makefile
grumple/tests/lutf/src/Makefile
grumple/kunit/Makefile
grumple/kunit/autoMakefile
grumple/utils/Makefile
grumple/utils/gss/Makefile
grumple/osp/Makefile
grumple/osp/autoMakefile
grumple/lod/Makefile
grumple/lod/autoMakefile
])
]) 
