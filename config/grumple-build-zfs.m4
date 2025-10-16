AC_DEFUN([LB_SPL], [
	AC_ARG_WITH([spl],
		AS_HELP_STRING([--with-spl=PATH],
		[Path to spl source]),
		[splsrc="$withval"])
	AC_ARG_WITH([spl-obj],
		AS_HELP_STRING([--with-spl-obj=PATH],
		[Path to spl build objects]),
		[splobj="$withval"])
	splver=$(ls -1 /usr/src/ | grep ^spl- | cut -f2 -d'-' |
		 sort -V | head -n1)
	spldkms="/var/lib/dkms/spl/${splver}"
	splsrc1="/usr/src/spl-${splver}/${LINUXRELEASE}"
	splsrc2="/usr/src/spl-${splver}"
	splsrc3="../spl/"
	splsrc4="$LINUX/spl"
	AC_MSG_CHECKING([spl source directory])
	AS_IF([test -z "${splsrc}"], [
		AS_IF([test -e "${spldkms}/source/spl.release.in"], [
			splsrc=${spldkms}/source
		], [test -e "${splsrc1}/spl.release.in"], [
			splsrc=${splsrc1}
		], [test -e "${splsrc2}/spl.release.in"], [
			splsrc=${splsrc2}
		], [test -e "${splsrc3}/spl.release.in"], [
			splsrc=$(readlink -f "${splsrc3}")
		], [test -e "${splsrc4}/spl.release.in"], [
			splsrc=${splsrc4}
		], [
			splsrc="[Not found]"
		])
	])
	AC_MSG_RESULT([$splsrc])
	AS_IF([test ! -e "$splsrc/spl.release" &&
	    test ! -e "$splsrc/spl.release.in"], [
		enable_zfs=no
	])
	AC_MSG_CHECKING([spl build directory])
	AS_IF([test -z "$splobj"], [
		last_spl_obj_dir=$(ls -d ${splsrc}/[[0-9]]*/  2> /dev/null | tail -n 1 | sed 's|/$||')
		AS_IF([test "${splsrc}" = "${spldkms}/source"], [
			AS_IF([test -e "${spldkms}/${LINUXRELEASE}/${target_cpu}/spl_config.h"], [
				splobj=${spldkms}/${LINUXRELEASE}/${target_cpu}
			], [
				splobj="[Not found]"
			])
		],[test -e "${splsrc}/${LINUXRELEASE}/spl_config.h"], [
			splobj="${splsrc}/${LINUXRELEASE}"
		], [test -e "${splsrc}/spl_config.h"], [
			splobj="${splsrc}"
		], [test -e "${last_spl_obj_dir}/spl_config.h"], [
			splobj="${last_spl_obj_dir}"
		], [
			splobj="[Not found]"
		])
	])
	AC_MSG_RESULT([$splobj])
	AS_IF([test ! -e "$splobj/spl_config.h"], [
		enable_zfs=no
	])
	AS_IF([test x$enable_zfs = xyes], [
		AC_MSG_CHECKING([spl source version])
		AS_IF([fgrep -q SPL_META_VERSION $splobj/spl_config.h], [
			splver=$((echo "
			    echo "splver=SPL_META_VERSION-SPL_META_RELEASE") |
			    cpp -I $splobj |
			    grep "^splver=" | tr -d \" | cut -d= -f2)
		], [
			splver="[Not found]"
			enable_zfs=no
		])
		AC_MSG_RESULT([$splver])
	])
	AS_IF([test x$enable_zfs = xyes], [
		AC_MSG_CHECKING([spl file name for module symbols])
		AS_IF([test -r $splobj/$SYMVERFILE], [
			splsym=$SYMVERFILE
			EXTRA_SYMBOLS="$EXTRA_SYMBOLS $splobj/$SYMVERFILE"
		], [test -r $splobj/module/$SYMVERFILE], [
			splsym=$SYMVERFILE
			EXTRA_SYMBOLS="$EXTRA_SYMBOLS $splobj/module/$SYMVERFILE"
		], [
			splsym="[Not found]"
			enable_zfs=no
		])
		AC_MSG_RESULT([$splsym])
	])
	AS_IF([test x$enable_zfs = xyes], [
		SPL=${splsrc}
		SPL_OBJ=${splobj}
		SPL_VERSION=${splver}
		AC_SUBST(SPL)
		AC_SUBST(SPL_OBJ)
		AC_SUBST(SPL_VERSION)
		AC_SUBST(EXTRA_SYMBOLS)
	])
]) 
AC_DEFUN([LB_ZFS], [
	AC_ARG_WITH([zfs-obj],
		AS_HELP_STRING([--with-zfs-obj=PATH],
		[Path to zfs build objects]),
		[zfsobj="$withval"])
	zfsver=$(ls -1 /usr/src/ | grep ^zfs- | cut -f2 -d'-' |
		 sort -V | head -n1)
	zfsdkms="/var/lib/dkms/zfs/${zfsver}"
	zfssrc1="/usr/src/zfs-${zfsver}/${LINUXRELEASE}"
	zfssrc2="/usr/src/zfs-${zfsver}"
	zfssrc3="../zfs/"
	zfssrc4="$LINUX/zfs"
	AC_MSG_CHECKING([zfs source directory])
	AS_IF([test -z "${zfssrc}"], [
		AS_IF([test -e "${zfsdkms}/source/zfs.release.in"], [
			zfssrc=${zfsdkms}/source
		], [test -e "${zfssrc1}/zfs.release.in"], [
			zfssrc=${zfssrc1}
		], [test -e "${zfssrc2}/zfs.release.in"], [
			zfssrc=${zfssrc2}
		], [test -e "${zfssrc3}/zfs.release.in"], [
			zfssrc=$(readlink -f "${zfssrc3}")
		], [test -e "${zfssrc4}/zfs.release.in"], [
			zfssrc=${zfssrc4}
		], [
			zfssrc="[Not found]"
		])
	])
	AC_MSG_RESULT([$zfssrc])
	AS_IF([test ! -e "$zfssrc/zfs.release.in" &&
	    test ! -e "$zfssrc/zfs.release"], [
		enable_zfs=no
	])
	AC_MSG_CHECKING([zfs build directory])
	AS_IF([test -z "$zfsobj"], [
		last_zfs_obj_dir=$(ls -d ${zfssrc}/[[0-9]]*/ 2> /dev/null | tail -n 1 | sed 's|/$||')
		AS_IF([test "${zfssrc}" = "${zfsdkms}/source"], [
			AS_IF([test -e "${zfsdkms}/${LINUXRELEASE}/${target_cpu}/zfs_config.h"], [
				zfsobj=${zfsdkms}/${LINUXRELEASE}/${target_cpu}
			], [
				zfsobj="[Not found]"
			])
		], [test -e "${zfssrc}/${LINUXRELEASE}/zfs_config.h"], [
			zfsobj="${zfssrc}/${LINUXRELEASE}"
		], [test -e "${zfssrc}/zfs_config.h"], [
			zfsobj="${zfssrc}"
		], [test -e "${last_zfs_obj_dir}/zfs_config.h"], [
			zfsobj="${last_zfs_obj_dir}"
		], [
			zfsobj="[Not found]"
		])
	])
	AC_MSG_RESULT([$zfsobj])
	AS_IF([test ! -e "$zfsobj/zfs_config.h"], [
		enable_zfs=no
	])
	AS_IF([test x$enable_zfs = xyes], [
		AC_MSG_CHECKING([zfs source version])
		AS_IF([fgrep -q ZFS_META_VERSION $zfsobj/zfs_config.h], [
			zfsver=$((echo "
			    echo "zfsver=ZFS_META_VERSION-ZFS_META_RELEASE") |
			    cpp -I $zfsobj |
			    grep "^zfsver=" | tr -d \" | cut -d= -f2)
		],[
			zfsver="[Not found]"
			enable_zfs=no
		])
		AC_MSG_RESULT([$zfsver])
	])
	AS_IF([test x$enable_zfs = xyes], [
		AC_MSG_CHECKING([zfs file name for module symbols])
		AS_IF([test -r $zfsobj/$SYMVERFILE], [
			zfssym=$SYMVERFILE
			EXTRA_SYMBOLS="$EXTRA_SYMBOLS $zfsobj/$SYMVERFILE"
		], [test -r $zfsobj/module/$SYMVERFILE], [
			zfssym=$SYMVERFILE
			EXTRA_SYMBOLS="$EXTRA_SYMBOLS $zfsobj/module/$SYMVERFILE"
		], [
			zfssym="[Not found]"
			enable_zfs=no
		])
		AC_MSG_RESULT([$zfssym])
	])
	AS_IF([test x$enable_zfs = xyes], [
		ZFS=${zfssrc}
		ZFS_OBJ=${zfsobj}
		ZFS_VERSION=${zfsver}
		AC_SUBST(ZFS)
		AC_SUBST(ZFS_OBJ)
		AC_SUBST(ZFS_VERSION)
		AC_SUBST(EXTRA_SYMBOLS)
	])
]) 
AC_DEFUN([LB_ZFS_DEVEL], [
	AC_ARG_WITH([zfs-devel],
		[AS_HELP_STRING([--with-zfs-devel=PATH],
		[Path to zfs development headers])],
		[zfsdevel="$withval"])
	AC_MSG_CHECKING([user provided zfs devel headers])
	AS_IF([test ! -z "${zfsdevel}"], [
		AS_IF([test -d "${zfsdevel}/usr/include/libspl" && test -d "${zfsdevel}/usr/include/libzfs"], [
			zfsinc="-I $zfsdevel/usr/include/libspl -I $zfsdevel/usr/include/libzfs"
			zfslib="-L$zfsdevel/usr/lib64 -L$zfsdevel/usr/lib -L$zfsdevel/lib64 -L$zfsdevel/lib"
		], [
			AC_MSG_ERROR([Path to development headers directory does not exist])
		])
	])
	AC_MSG_RESULT([$zfsinc])
]) 
AC_DEFUN([LB_ZFS_USER], [
	AC_MSG_CHECKING([zfs devel headers])
	AS_IF([test -z "${zfsinc}"], [
        	AS_IF([test -e "${zfssrc}/include/libzfs.h" && test -e "${zfssrc}/lib/libspl/include"], [
			zfsinc="-I $zfssrc/lib/libspl/include -I $zfssrc/lib/libspl/include/os/linux -I $zfssrc/include"
			zfslib="-L$zfssrc/.libs/ -L$zfssrc/lib/libzfs/.libs/ -L$zfssrc/lib/libnvpair/.libs/ -L$zfssrc/lib/libzpool/.libs/"
		], [test -d /usr/include/libzfs && test -d /usr/include/libspl], [
			zfsinc="-I/usr/include/libspl -I /usr/include/libzfs"
			zfslib=""
		], [
			zfsinc="[Not Found]"
			zfslib=""
			enable_zfs=no
		])
	])
	AC_MSG_RESULT([$zfsinc])
	ZFS_LIBZFS_INCLUDE=${zfsinc}
	ZFS_LIBZFS_LDFLAGS=${zfslib}
	ZFS_LIBZFS_LIBS="-lzfs -lnvpair -lzpool"
	AC_SUBST(ZFS_LIBZFS_INCLUDE)
	AC_SUBST(ZFS_LIBZFS_LDFLAGS)
	AC_SUBST(ZFS_LIBZFS_LIBS)
]) 
AC_DEFUN([LZ_KABI_ZFS], [
	AC_DEFUN([LZ_SRC_ZFS_NVLIST_CONST_INTERFACES], [
		LB2_LINUX_TEST_SRC([zfs_nvpair_const], [
		],[
			nvpair_t *nvp = NULL;
			nvlist_t *nvl = NULL;
			const char *name = nvpair_name(nvp);
			nvlist_lookup_string(nvl, name, &name);
			nvlist_lookup_nvlist(nvl, name, &nvl);
		],[-Werror],[],[])
	])
	AC_DEFUN([LZ_ZFS_NVLIST_CONST_INTERFACES], [
		LB2_MSG_LINUX_TEST_RESULT([if ZFS nvlist interfaces require const],
		    [zfs_nvpair_const], [
			AC_DEFINE(HAVE_ZFS_NVLIST_CONST_INTERFACES, 1,
			    [ZFS nvlist interfaces require const])
		])
	]) 
	AC_DEFUN([LZ_SRC_ZFS_ARC_PRUNE_FUNC_UINT64], [
		LB2_LINUX_TEST_SRC([zfs_arc_prune_func_uint64], [
		],[
			void arc_prune_func(uint64_t bytes, void *priv) {}
			arc_prune_t *arc_p __attribute__ ((unused)) =
				arc_add_prune_callback(arc_prune_func, NULL);
		],[-Werror],[],[])
	])
	AC_DEFUN([LZ_ZFS_ARC_PRUNE_FUNC_UINT64], [
		LB2_MSG_LINUX_TEST_RESULT([if ZFS arc_prune_func_t uses uint64_t],
		    [zfs_arc_prune_func_uint64], [
			AC_DEFINE(HAVE_ZFS_ARC_PRUNE_FUNC_UINT64, 1,
				[ZFS arc_prune_func_t uses uint64_t])
		])
	]) 
	AC_DEFUN([LZ_SRC_DMU_BUF_WILL_FILL_3ARGS], [
		LB2_LINUX_TEST_SRC([dmu_buf_will_fill_3args], [
		],[
			dmu_buf_t *db = NULL;
			dmu_tx_t *tx = NULL;
			dmu_buf_will_fill(db, tx, B_TRUE);
		],[-Werror],[],[])
	])
	AC_DEFUN([LZ_DMU_BUF_WILL_FILL_3ARGS], [
		LB2_MSG_LINUX_TEST_RESULT([if dmu_buf_will_fill() has 3 args],
		    [dmu_buf_will_fill_3args], [
			AC_DEFINE(HAVE_DMU_BUF_WILL_FILL_3ARGS, 1,
				 [dmu_buf_will_fill() has 3 args])
			AC_DEFINE(LL_BFILL, [, B_FALSE], [buf bool arg])
		],[
			AC_DEFINE(LL_BFILL, [], [buf bool arg])
		])
	]) 
	AC_DEFUN([LZ_KABI_ZFS_TESTS], [
		LZ_SRC_ZFS_NVLIST_CONST_INTERFACES
		LZ_SRC_ZFS_ARC_PRUNE_FUNC_UINT64
		LZ_SRC_DMU_BUF_WILL_FILL_3ARGS
	])
	AC_DEFUN([LZ_KABI_ZFS_CHECKS], [
		LZ_ZFS_NVLIST_CONST_INTERFACES
		LZ_ZFS_ARC_PRUNE_FUNC_UINT64
		LZ_DMU_BUF_WILL_FILL_3ARGS
	])
])
AC_DEFUN([LB_CONFIG_ZFS], [
	AC_ARG_WITH([zfs],
		[AS_HELP_STRING([--with-zfs=PATH], [Path to zfs source])],
		[
			AS_IF([test x$withval = xno], [
				enable_spl=no
				enable_zfs=no
				require_zfs=no
			], [test x$withval = xyes], [
				enable_spl=yes
				enable_zfs=yes
				require_zfs=yes
			], [
				enable_spl=yes
				enable_zfs=yes
				require_zfs=yes
				zfssrc="$withval"
			])
		], [
			AS_IF([test x$enable_server != xno], [
				enable_spl=yes
				require_zfs=no
				enable_zfs=yes
			], [
				enable_spl=no
				require_zfs=no
				enable_zfs=no
			])
		])
	AC_MSG_CHECKING([whether to enable zfs])
	AC_MSG_RESULT([$enable_zfs])
	AS_IF([test x$enable_zfs = xyes], [
		AS_IF([test x$enable_modules = xyes], [
			LB_ZFS
		])
		LB_ZFS_DEVEL
		LB_ZFS_USER
		ZFS_MAJOR=$(echo $zfsver | sed -re ['s/([0-9]+)\.([0-9]+)\.([0-9]+)(\.([0-9]+))?.*/\1/'])
		ZFS_MINOR=$(echo $zfsver | sed -re ['s/([0-9]+)\.([0-9]+)\.([0-9]+)(\.([0-9]+))?.*/\2/'])
		ZFS_PATCH=$(echo $zfsver | sed -re ['s/([0-9]+)\.([0-9]+)\.([0-9]+)(\.([0-9]+))?.*/\3/'])
		ZFS_FIX=$(echo $zfsver   | sed -re ['s/([0-9]+)\.([0-9]+)\.([0-9]+)(\.([0-9]+))?.*/\5/'])
		AS_IF([test -z "$ZFS_FIX"], [ZFS_FIX="0"])
		AC_DEFINE_UNQUOTED([ZFS_MAJOR], [$ZFS_MAJOR], [zfs major version])
		AC_DEFINE_UNQUOTED([ZFS_MINOR], [$ZFS_MINOR], [zfs minor version])
		AC_DEFINE_UNQUOTED([ZFS_PATCH], [$ZFS_PATCH], [zfs patch version])
		AC_DEFINE_UNQUOTED([ZFS_FIX],   [$ZFS_FIX],   [zfs fix version])
		AS_IF([test x$enable_modules = xyes && test -n "$ZFS_MAJOR" &&
			    test $ZFS_MAJOR -eq 0 && test $ZFS_MINOR -lt 8], [
			LB_SPL
		],[
			enable_spl=no
		])
		AS_IF([test x$enable_zfs = xyes], [
			AC_DEFINE(HAVE_ZFS_OSD, 1, Enable zfs osd)
		],[
			AS_IF([test x$require_zfs = xyes], [
				AC_MSG_ERROR([
Required zfs osd cannot be built due to missing zfs development headers.
Support for zfs can be enabled by downloading the required packages for your
distribution.  See http://zfsonlinux.org/ to determine is zfs is supported by
your distribution.
				])
			], [
				AC_MSG_WARN([
Disabling optional zfs osd due to missing development headers.
Support for zfs can be enabled by downloading the required packages for your
distribution.  See http://zfsonlinux.org/ to determine is zfs is supported by
your distribution.
				])
			])
		])
	])
	AS_IF([test "x$enable_zfs" = xyes], [
		AC_SUBST(ENABLE_ZFS, yes)
	], [
		AC_SUBST(ENABLE_ZFS, no)
	])
	AM_CONDITIONAL(ZFS_ENABLED, [test "x$enable_zfs" = xyes])
	AM_CONDITIONAL(SPL_ENABLED, [test "x$enable_spl" = xyes])
]) 
AC_DEFUN([LZ_ZFS_KABI_SERIAL], [
	LB_CHECK_COMPILE([if zfs defines dsl_pool_config_enter/exit],
	dsl_pool_config_enter, [
	],[
		dsl_pool_config_enter(NULL, FTAG);
	],[
		AC_DEFINE(HAVE_DSL_POOL_CONFIG, 1,
			[Have dsl_pool_config_enter/exit in ZFS])
	],[
		AC_MSG_ERROR([dsl_pool_config_enter/exit do not exist])
	])
	LB_CHECK_COMPILE([if zfs defines zio_buf_alloc/free],
	zio_buf_alloc, [
	],[
		void *ptr = zio_buf_alloc(1024);
		(void)ptr;
	],[
		AC_DEFINE(HAVE_ZIO_BUF_ALLOC, 1,
			[Have zio_buf_alloc/free in ZFS])
	],[
		AC_MSG_ERROR([zio_buf_alloc/free do not exist])
	])
	LB_CHECK_COMPILE([if zfs defines spa_maxblocksize],
	spa_maxblocksize, [
	],[
		spa_t *spa = NULL;
		int size = spa_maxblocksize(spa);
		(void)size;
	],[
		AC_DEFINE(HAVE_SPA_MAXBLOCKSIZE, 1,
			[Have spa_maxblocksize in ZFS])
	],[
		AC_MSG_ERROR([spa_maxblocksize does not exist])
	])
	LB_CHECK_COMPILE([if zfs defines dmu_object_alloc_dnsize],
	dmu_object_alloc_dnsize, [
	],[
		objset_t *os = NULL;
		dmu_object_type_t objtype = DMU_OT_NONE;
		int blocksize = 0;
		dmu_object_type_t bonustype = DMU_OT_SA;
		int dnodesize = DNODE_MIN_SIZE;
		dmu_tx_t *tx = NULL;
		uint64_t id;
		id = dmu_object_alloc_dnsize(os, objtype, blocksize,
					     bonustype,
					     DN_BONUS_SIZE(dnodesize),
					     dnodesize, tx);
	],[
		AC_DEFINE(HAVE_DMU_OBJECT_ALLOC_DNSIZE, 1,
			[Have dmu_object_alloc_dnsize in ZFS])
	],[
		AC_MSG_ERROR([dmu_object_alloc_dnsize does not exist])
	])
	LB_CHECK_COMPILE([if ZFS has 'dmu_prefetch' with 6 args],
	dmu_prefetch, [
	],[
		objset_t *os = NULL;
		uint64_t object = 0;
		int64_t level = 0;
		uint64_t offset = 0;
		uint64_t len = 0;
		enum zio_priority pri = ZIO_PRIORITY_SYNC_READ;
		dmu_prefetch(os, object, level, offset, len, pri);
	],[
		AC_DEFINE(HAVE_DMU_PREFETCH_6ARG, 1,
			[Have 6 argument dmu_pretch in ZFS])
	],[
		AC_MSG_ERROR([6 argument dmu_pretch does not exist])
	])
	LB_CHECK_COMPILE([if ZFS has native dnode accounting supported],
	dmu_objset_userobjused_enabled, [
	],[
		dmu_objset_userobjused_enabled(NULL);
	],[
		AC_DEFINE(HAVE_DMU_USEROBJ_ACCOUNTING, 1,
			[Have native dnode accounting in ZFS])
	],[
		AC_MSG_ERROR([native dnode accounting does not exist])
	])
	LB_CHECK_COMPILE([if ZFS has multihost protection],
	spa_multihost, [
	],[
		zpool_prop_t prop = ZPOOL_PROP_MULTIHOST;
		(void)prop;
	],[
		AC_DEFINE(HAVE_ZFS_MULTIHOST, 1,
			[Have multihost protection in ZFS])
	],[
		AC_MSG_ERROR([multihost protection does not exist])
	])
	LB_CHECK_COMPILE([if ZFS has 'zap_lookup_by_dnode'],
	zap_lookup_by_dnode, [
	],[
		dnode_t *dn = NULL;
		zap_lookup_by_dnode(dn, NULL, 1, 1, NULL);
	],[
		AC_DEFINE(HAVE_ZAP_LOOKUP_BY_DNODE, 1,
			[Have zap_lookup_by_dnode() in ZFS])
	],[
		AC_MSG_ERROR([zap_lookup_by_dnode does not exist])
	])
	LB_CHECK_COMPILE([if ZFS has 'zap_add_by_dnode'],
	zap_add_by_dnode, [
	],[
		dnode_t *dn = NULL;
		zap_add_by_dnode(dn, NULL, 1, 1, NULL, NULL);
	],[
		AC_DEFINE(HAVE_ZAP_ADD_BY_DNODE, 1,
			[Have zap_add_by_dnode() in ZFS])
	],[
		AC_MSG_ERROR([zap_add_by_dnode does not exist])
	])
	LB_CHECK_COMPILE([if ZFS has 'zap_remove_by_dnode'],
	zap_remove_by_dnode, [
	],[
		dnode_t *dn = NULL;
		zap_remove_by_dnode(dn, NULL, NULL);
	],[
		AC_DEFINE(HAVE_ZAP_REMOVE_ADD_BY_DNODE, 1,
			[Have zap_remove_by_dnode() in ZFS])
	],[
		AC_MSG_ERROR([zap_remove_by_dnode does not exist])
	])
	LB_CHECK_COMPILE([if ZFS has 'dmu_tx_hold_zap_by_dnode'],
	dmu_tx_hold_zap_by_dnode, [
	],[
		dnode_t *dn = NULL;
		dmu_tx_hold_zap_by_dnode(NULL, dn, TRUE, NULL);
	],[
		AC_DEFINE(HAVE_DMU_TX_HOLD_ZAP_BY_DNODE, 1,
			[Have dmu_tx_hold_zap_by_dnode() in ZFS])
	],[
		AC_MSG_ERROR([dmu_tx_hold_zap_by_dnode does not exist])
	])
	LB_CHECK_COMPILE([if ZFS has 'dmu_tx_hold_write_by_dnode'],
	dmu_tx_hold_write_by_dnode, [
	],[
		dnode_t *dn = NULL;
		dmu_tx_hold_write_by_dnode(NULL, dn, 0, 0);
	],[
		AC_DEFINE(HAVE_DMU_TX_HOLD_WRITE_BY_DNODE, 1,
			[Have dmu_tx_hold_write_by_dnode() in ZFS])
	],[
		AC_MSG_ERROR([dmu_tx_hold_write_by_dnode does not exist])
	])
	LB_CHECK_COMPILE([if ZFS has 'dmu_write_by_dnode'],
	dmu_write_by_dnode, [
	],[
		dnode_t *dn = NULL;
		dmu_write_by_dnode(dn, 0, 0, NULL, NULL);
	],[
		AC_DEFINE(HAVE_DMU_WRITE_BY_DNODE, 1,
			[Have dmu_write_by_dnode() in ZFS])
	],[
		AC_MSG_ERROR([dmu_write_by_dnode does not exist])
	])
	LB_CHECK_COMPILE([if ZFS has 'dmu_read_by_dnode'],
	dmu_read_by_dnode, [
	],[
		dnode_t *dn = NULL;
		dmu_read_by_dnode(dn, 0, 0, NULL, 0);
	],[
		AC_DEFINE(HAVE_DMU_READ_BY_DNODE, 1,
			[Have dmu_read_by_dnode() in ZFS])
	],[
		AC_MSG_ERROR([dmu_read_by_dnode does not exist])
	])
	LB_CHECK_COMPILE([if ZFS has 'dmu_tx_mark_netfree'],
	dmu_tx_mark_netfree, [
	],[
		dmu_tx_t *tx = NULL;
		dmu_tx_mark_netfree(tx);
	],[
		AC_DEFINE(HAVE_DMU_TX_MARK_NETFREE, 1,
			[Have dmu_tx_mark_netfree])
	])
	LB_CHECK_COMPILE([if SPL has 'inode_timespec_t'],
	zfs_have_inode_timespec, [
	],[
		inode_timespec_t now;
		gethrestime(&now);
	],[
		AC_DEFINE(HAVE_ZFS_INODE_TIMESPEC, 1,
			[Have inode_timespec_t])
	])
	LB_CHECK_COMPILE([if ZFS has 'zfs_refcount_add'],
	zfs_refcount_add, [
	],[
		zfs_refcount_add((zfs_refcount_t *) NULL, NULL);
	],[
		AC_DEFINE(HAVE_ZFS_REFCOUNT_ADD, 1,
			[Have zfs_refcount_add])
	])
	LB_CHECK_COMPILE([if ZFS has 'dmu_objset_own' with 6 args],
	dmu_objset_own, [
	],[
		objset_t *os = NULL;
		dmu_objset_type_t type = DMU_OST_ANY;
		dmu_objset_own(NULL, type, B_FALSE, B_TRUE, FTAG, &os);
	],[
		AC_DEFINE(HAVE_DMU_OBJSET_OWN_6ARG, 1,
			[Have dmu_objset_own() with 6 args])
	])
	LB_CHECK_COMPILE([if ZFS has 'dmu_objset_disown' with 3 args],
	dmu_objset_disown, [
	],[
		objset_t *os = NULL;
		dmu_objset_disown(os, B_TRUE, FTAG);
	],[
		AC_DEFINE(HAVE_DMU_OBJSET_DISOWN_3ARG, 1,
			[Have dmu_objset_disown() with 3 args])
	])
	AC_CACHE_CHECK([if ZFS exports 'dmu_offset_next'],
	[lb_cv_dmu_offset_next], [
	lb_cv_dmu_offset_next="no"
	AS_IF([grep -q -E "EXPORT_SYMBOL.*\(dmu_offset_next\)" "$zfssrc/module/zfs/dmu.c" 2>/dev/null],
		[lb_cv_dmu_offset_next="yes"])
	])
	AS_IF([test "x$lb_cv_dmu_offset_next" = "xyes"], [
		AC_DEFINE(HAVE_DMU_OFFSET_NEXT, 1,
			[Have dmu_offset_next() exported])
	])
	LB_CHECK_COMPILE([if ZFS has 'db_dirty_records' list_t],
	db_dirty_records, [
	],[
		dmu_buf_impl_t db;
		dbuf_dirty_record_t *dr;
		dr = list_head(&db.db_dirty_records);
	],[
		AC_DEFINE(HAVE_DB_DIRTY_RECORDS_LIST, 1,
			[Have db_dirty_records list_t])
	])
	LB_CHECK_COMPILE([if ZFS renamed sys/refcount to zfs_refcount.h],
	zfs_zfs_refcount, [
	],[
		zfs_refcount_add((zfs_refcount_t *) NULL, NULL);
	],[
		AC_DEFINE(HAVE_ZFS_REFCOUNT_HEADER, 1,
			[Have zfs_refcount.h])
	])
])
