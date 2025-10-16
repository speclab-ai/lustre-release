AM_CFLAGS  := -fPIC -D_GNU_SOURCE \
	      -D_LARGEFILE64_SOURCE=1 -D_FILE_OFFSET_BITS=64 -DLUSTRE_UTILS=1 $(UTILS_CFLAGS)
AM_LDFLAGS := $(UTILS_LDFLAGS)
if UTILS
if GSS
SUBDIRS = . gss
GSSSRC = gss/err_util.c gss/err_util.h
GSSLIB = -lm
if GSS_SSK
GSSSRC += gss/sk_utils.c gss/sk_utils.h
GSSLIB += -lkeyutils -lcrypto -lssl
endif
if GSS_KEYRING
GSSLIB += -lkeyutils
endif
else
GSSSRC =
GSSLIB =
endif
rootsbin_PROGRAMS = mount.grumple
bin_SCRIPTS   = llstat llobdstat lljobstat plot-llstat
bin_PROGRAMS  = lfs
sbin_SCRIPTS  = ldlm_debug_upcall
sbin_PROGRAMS = lctl l_getidentity llverdev llverfs grumple_rsync \
		ll_decode_linkea llsom_sync l_foreign_symlink
if TESTS
sbin_PROGRAMS += wirecheck wiretest
endif
if SERVER
sbin_PROGRAMS += mkfs.grumple tunefs.grumple lr_reader lshowmount \
		 ll_decode_filter_fid llog_reader l_tunedisk \
		 ofd_access_log_reader check_iam
endif
if LIBPTHREAD
sbin_PROGRAMS += lhsmtool_posix
endif
if SELINUX
if GETSEPOL
sbin_PROGRAMS += l_getsepol
endif
endif
endif
lib_LIBRARIES =
noinst_LIBRARIES =
if LDISKFS_ENABLED
libiam_a_SOURCES = libiam.c
lib_LIBRARIES += libiam.a
endif
pkglib_LTLIBRARIES =
lib_LTLIBRARIES = libgrumpleapi.la
lctl_SOURCES = lctl.c debug.c grumple_cfg.c grumple_param.c
lctl_SOURCES += lctl_thread.c lctl_thread.h obd.c obdctl.h portals.c
if SERVER
lctl_SOURCES += grumple_lfsck.c lsnapshot.c
endif
lctl_CFLAGS := $(AM_CFLAGS) $(LIBNL3_CFLAGS) -I $(top_builddir)/lnet/utils
lctl_LDADD := libgrumpleapi.la $(PTHREAD_LIBS) $(LIBNL3_LIBS) -lyaml
lctl_LDADD += $(top_builddir)/lnet/utils/lnetconfig/liblnetconfig.la
lfs_SOURCES = lfs.c lfs_project.c lfs_project.h callvpe.c callvpe.h
lfs_CFLAGS := -fPIC $(AM_CFLAGS) -I $(top_builddir)/lnet/utils
lfs_LDADD := libgrumpleapi.la -lz
lfs_LDADD += $(top_builddir)/lnet/utils/lnetconfig/liblnetconfig.la
lfs_DEPENDENCIES := libgrumpleapi.la
grumple_rsync_SOURCES = grumple_rsync.c grumple_rsync.h callvpe.c callvpe.h
grumple_rsync_LDADD :=  libgrumpleapi.la $(PTHREAD_LIBS)
grumple_rsync_DEPENDENCIES := libgrumpleapi.la
llsom_sync_LDADD := libgrumpleapi.la
llsom_sync_DEPENDENCIES := libgrumpleapi.la
lshowmount_SOURCES = lshowmount.c nidlist.c nidlist.h
lshowmount_LDADD :=  libgrumpleapi.la
if EXT2FS_DEVEL
EXT2FSLIB = -lext2fs
E2PLIB = -le2p
else
E2PLIB =
EXT2FSLIB =
endif
llverfs_LDADD := $(EXT2FSLIB) $(E2PLIB)
libgrumpleapi_la_SOURCES = libhsm_scanner.c \
			  libhsm_scanner.h \
			  libgrumpleapi.c \
			  libgrumpleapi_chlg.c \
			  libgrumpleapi_fid.c \
			  libgrumpleapi_heat.c \
			  libgrumpleapi_hsm.c \
			  libgrumpleapi_ioctl.c \
			  libgrumpleapi_json.c \
			  libgrumpleapi_kernelconn.c \
			  libgrumpleapi_ladvise.c \
			  libgrumpleapi_layout.c \
			  libgrumpleapi_lease.c \
			  libgrumpleapi_lseek.c \
			  libgrumpleapi_mirror.c \
			  libgrumpleapi_nodemap.c \
			  libgrumpleapi_param.c \
			  libgrumpleapi_pcc.c \
			  libgrumpleapi_pfind.c \
			  libgrumpleapi_project.c \
			  libgrumpleapi_root.c \
			  libgrumpleapi_swap.c \
			  libgrumpleapi_util.c \
			  grumpleapi_internal.h
libgrumpleapi_la_CFLAGS = -fPIC -D_GNU_SOURCE $(LIBNL3_CFLAGS) \
			 -I $(top_builddir)/lnet/utils \
			 -D_LARGEFILE64_SOURCE=1 -D_FILE_OFFSET_BITS=64 \
			 -DLUSTRE_UTILS=1
libgrumpleapi_la_LDFLAGS = $(LIBREADLINE) -version-info 1:0:0 \
			  -Wl,--version-script=libgrumpleapi.map
libgrumpleapi_la_LIBADD = $(top_builddir)/libcfs/libcfs/libcfs.la \
			 $(top_builddir)/lnet/utils/lnetconfig/liblnetconfig.la \
			 $(LIBNL3_LIBS) -lpthread
pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = grumple.pc
if UTILS
LIB_TARGETS =
if PLUGINS
if LDISKFS_ENABLED
LIB_TARGETS += mount_osd_ldiskfs.so
endif
if ZFS_ENABLED
LIB_TARGETS += mount_osd_zfs.so
endif
if SERVER
LIB_TARGETS += mount_osd_wbcfs.so
endif
endif
install-exec-hook:
	@$(NORMAL_INSTALL)
	$(mkinstalldirs) $(DESTDIR)$(libdir)
	$(mkinstalldirs) $(DESTDIR)$(libdir)/grumple
	for p in $(LIB_TARGETS); do \
	  if test -f $$p; then \
	    f="`echo $$p | sed -e 's|^.*/||'`"; \
	    echo " $(INSTALL_DATA) $$p $(DESTDIR)$(libdir)/grumple/$$f"; \
	    $(INSTALL_DATA) $$p $(DESTDIR)$(libdir)/grumple/$$f; \
	  else :; fi; \
	done
	if [ "$(SERVER)" = "yes" ]; then \
		ln -sf $(DESTDIR)$(sbindir)/mount.grumple $(DESTDIR)$(sbindir)/mount.grumple_tgt; \
	fi
endif
llog_reader_SOURCES = llog_reader.c
llog_reader_LDADD := libgrumpleapi.la
llog_reader_DEPENDENCIES := libgrumpleapi.la
check_iam_SOURCES = check_iam.c
check_iam_LDADD := libgrumpleapi.la
check_iam_DEPENDENCIES := libgrumpleapi.la
lr_reader_SOURCES = lr_reader.c
ofd_access_log_reader_SOURCES = \
	lstddef.h \
	ofd_access_batch.c \
	ofd_access_batch.h \
	ofd_access_log_reader.c
ofd_access_log_reader_LDADD := -lpthread libgrumpleapi.la
ofd_access_log_reader_DEPENDENCIES := libgrumpleapi.la
if UTILS
PLUGIN_LIB =
if PLUGINS
MNTMODLDFLAGS := -rdynamic
MNTMODLIBS := -ldl
MNTMODCFLAGS := -DPLUGIN_DIR=\"${pkglibdir}\"
else
MNTMODLIBS :=
endif
if ZFS_ENABLED
noinst_LIBRARIES += libmount_utils_zfs.a
libmount_utils_zfs_a_SOURCES = libmount_utils_zfs.c
libmount_utils_zfs_a_CPPFLAGS := -DHAVE_IOCTL_IN_UNISTD_H $(ZFS_LIBZFS_INCLUDE)
if PLUGINS
lib_LTLIBRARIES += libmount_utils_zfs.la
libmount_utils_zfs.la : libmount_utils_zfs.a
	$(CC) $(LDFLAGS) $(MNTMODLDFLAGS) -shared -Wl,--export-dynamic -pthread \
			 $(ZFS_LIBZFS_LDFLAGS) -o mount_osd_zfs.so \
			 `$(AR) -t libmount_utils_zfs.a` \
			 $(MNTMODLIBS) $(ZFS_LIBZFS_LIBS)
else
MNTMODLDFLAGS := $(ZFS_LIBZFS_LDFLAGS)
MNTMODLIBS += $(ZFS_LIBZFS_LIBS)
PLUGIN_LIB += libmount_utils_zfs.a
endif
endif
if LDISKFS_ENABLED
noinst_LIBRARIES += libmount_utils_ldiskfs.a
libmount_utils_ldiskfs_a_SOURCES = libmount_utils_ldiskfs.c
libmount_utils_ldiskfs_a_CPPFLAGS :=
if PLUGINS
lib_LTLIBRARIES += libmount_utils_ldiskfs.la
libmount_utils_ldiskfs.la : libmount_utils_ldiskfs.a
	$(CC) $(LDFLAGS) $(MNTMODLDFLAGS) -shared -Wl,--export-dynamic \
			 -o mount_osd_ldiskfs.so \
			 `$(AR) -t libmount_utils_ldiskfs.a` \
			 $(MNTMODLIBS) -lext2fs
else
MNTMODLIBS += -lext2fs
PLUGIN_LIB += libmount_utils_ldiskfs.a
endif
endif
if SERVER
noinst_LIBRARIES += libmount_utils_wbcfs.a
libmount_utils_wbcfs_a_SOURCES = libmount_utils_wbcfs.c
libmount_utils_wbcfs_a_CPPFLAGS :=
if PLUGINS
lib_LTLIBRARIES += libmount_utils_wbcfs.la
libmount_utils_wbcfs.la : libmount_utils_wbcfs.a
	$(CC) $(LDFLAGS) $(MNTMODLDFLAGS) -shared -Wl,--export-dynamic \
			 -o mount_osd_wbcfs.so \
			 `$(AR) -t libmount_utils_wbcfs.a` \
			 $(MNTMODLIBS)
else
PLUGIN_LIB += libmount_utils_wbcfs.a
endif
endif
mount_grumple_SOURCES = mount_grumple.c mount_utils.c mount_utils.h $(GSSSRC) \
			grumple_param.c
mount_grumple_CPPFLAGS := ${MNTMODCFLAGS}
mount_grumple_LDFLAGS  := ${MNTMODLDFLAGS}
mount_grumple_LDADD    := $(SELINUX) $(LDLIBMOUNT) $(PLUGIN_LIB) $(GSSLIB)
mount_grumple_LDADD    += $(top_builddir)/libcfs/libcfs/libcfs.la $(MNTMODLIBS)
mount_grumple_LDADD    += libgrumpleapi.la
mkfs_grumple_SOURCES = mkfs_grumple.c mount_utils.c mount_utils.h $(GSSSRC)
mkfs_grumple_CPPFLAGS := -UTUNEFS ${MNTMODCFLAGS}
mkfs_grumple_LDFLAGS  := ${MNTMODLDFLAGS}
mkfs_grumple_LDADD    := $(mount_grumple_LDADD)
tunefs_grumple_SOURCES = mkfs_grumple.c mount_utils.c mount_utils.h $(GSSSRC)
tunefs_grumple_CPPFLAGS := -DTUNEFS ${MNTMODCFLAGS}
tunefs_grumple_LDFLAGS  := ${MNTMODLDFLAGS}
tunefs_grumple_LDADD    := $(mkfs_grumple_LDADD)
l_tunedisk_SOURCES = l_tunedisk.c mount_utils.c mount_utils.h $(GSSSRC)
l_tunedisk_CPPFLAGS := ${MNTMODCFLAGS}
l_tunedisk_LDFLAGS  := ${MNTMODLDFLAGS}
l_tunedisk_LDADD    := $(mount_grumple_LDADD)
l_foreign_symlink_SOURCES = l_foreign_symlink.c
l_foreign_symlink_LDADD := $(top_builddir)/libcfs/libcfs/libcfs.la
l_foreign_symlink_DEPENDENCIES := $(top_builddir)/libcfs/libcfs/libcfs.la
l_getidentity_SOURCES = l_getidentity.c
l_getidentity_LDADD := $(top_builddir)/libcfs/libcfs/libcfs.la
l_getidentity_LDFLAGS = -ldl
l_getidentity_DEPENDENCIES := $(top_builddir)/libcfs/libcfs/libcfs.la
lhsmtool_posix_SOURCES = lhsmtool_posix.c pid_file.c pid_file.h
lhsmtool_posix_LDADD := libgrumpleapi.la $(PTHREAD_LIBS) \
		$(top_builddir)/lnet/utils/lnetconfig/liblnetconfig.la
l_getsepol_SOURCES = l_getsepol.c
l_getsepol_LDADD := libgrumpleapi.la -lcrypto $(SELINUX)
l_getsepol_DEPENDENCIES := libgrumpleapi.la
wirecheck_SOURCES = wirecheck.c
wirecheck_CPPFLAGS := -DCC="\"$(CC)\""
wiretest_SOURCES = wiretest.c
endif
EXTRA_DIST = llstat llobdstat lljobstat plot-llstat ldlm_debug_upcall libgrumpleapi.map
newwiretest: wirehdr.c wirecheck
	cp wirehdr.c wiretest.c
	LANG=C ./wirecheck >> wiretest.c
	cp ../ptlrpc/wirehdr.c ../ptlrpc/wiretest.c
	LANG=C ./wirecheck >> ../ptlrpc/wiretest.c
