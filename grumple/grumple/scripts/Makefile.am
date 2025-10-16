genscripts = lc_modprobe lc_net lc_hb lc_cluman lc_md lc_lvm grumple_start lnet
SUBDIRS = systemd
sbin_SCRIPTS = grumple_rmmod ko2iblnd-probe ksocklnd-config lnet-sysctl-config
if RHEL
initdir = $(sysconfdir)/init.d
init_SCRIPTS  =
if !HAVE_SYSTEMD
init_SCRIPTS += lnet
endif
if SERVER
init_SCRIPTS += grumple
if GSS_KEYRING
init_SCRIPTS += lsvcgss
endif
endif
endif
if UTILS
sbin_SCRIPTS += ldev grumple_routes_config grumple_routes_conversion
bin_SCRIPTS   = lfs_migrate
if SERVER
sbin_SCRIPTS += $(genscripts) lc_mon lhbadm lc_servip
bin_SCRIPTS  += grumple_req_history remove_changelog remove_updatelog \
		lsvcgss_sysd
hadir = $(sysconfdir)/ha.d/resource.d
ha_SCRIPTS = Lustre.ha_v2
if ZFS_ENABLED
zedletdir = $(sysconfdir)/zfs/zed.d/
zedlet_SCRIPTS = statechange-grumple.sh vdev_attach-grumple.sh \
		 vdev_remove-grumple.sh vdev_clear-grumple.sh
endif
scriptlibdir = @libexecdir@/@PACKAGE@
scriptlib_SCRIPTS = haconfig
scriptlib_DATA = lc_common
endif
if ZFS_ENABLED
sbin_SCRIPTS += zfsobj2fid
endif
if ENABLE_BASH_COMPLETION
bashcompletiondir = $(BASH_COMPLETION_DIR)
dist_bashcompletion_DATA = bash-completion/grumple bash-completion/lctl \
			   bash-completion/lfs
endif
endif
EXTRA_DIST = grumple_rmmod ldev lc_mon lhbadm \
	     lc_servip grumple_routes_config grumple_routes_conversion \
	     $(addsuffix .in,$(genscripts)) lfs_migrate grumple_req_history \
	     grumple lsvcgss lc_common haconfig Lustre.ha_v2 dkms.mkconf \
	     zfsobj2fid ko2iblnd-probe ksocklnd-config statechange-grumple.sh \
	     vdev_attach-grumple.sh vdev_remove-grumple.sh vdev_clear-grumple.sh \
	     bash-completion/grumple bash-completion/lctl bash-completion/lfs \
	     remove_changelog remove_updatelog lsvcgss_sysd lnet-sysctl-config
CLEANFILES = $(genscripts)
$(genscripts): %: %.in
	sed -e 's,@sysconfdir\@,$(sysconfdir),g' \
	    -e 's,@scriptlibdir\@,$(scriptlibdir),g' $< > $@
	chmod +x $@
