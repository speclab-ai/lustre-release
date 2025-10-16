SUBDIRS = resource
DIST_SUBDIRS = resource
EXTRA_DIST = lustre.xml 99-lustre.rules lustre ldev.conf ko2iblnd.conf \
             lsvcgss lnet_routes.conf lnet.conf lgssc.conf dkms-lustre \
             lnet-sysctl.conf 99-lustre-server.rules mount.client.params \
             projid
sysconf_DATA = lnet.conf
sysconfigdir = $(sysconfdir)/sysconfig
sysconfig_DATA = dkms-lustre
if UTILS
sysconf_DATA += lnet_routes.conf
lustredir = $(sysconfdir)/lustre
lustre_DATA = mount.client.params
projiddir = $(sysconfdir)
projid_DATA = projid
endif
firewallddir = ${prefix}/lib/firewalld/services
firewalld_DATA = lustre.xml
udevrulesdir = $(prefix)/lib/udev/rules.d
udevrules_DATA = 99-lustre.rules
if SERVER
udevrules_DATA += 99-lustre-server.rules
if ZFS_ENABLED
sysconf_DATA += ldev.conf
endif
if RHEL
sysconfig_DATA += lustre
if GSS_KEYRING
sysconfig_DATA += lsvcgss
endif
endif
endif
if GSS_KEYRING
requestkeydir = $(sysconfdir)/request-key.d
requestkey_DATA = lgssc.conf
endif
modprobedir = $(sysconfdir)/modprobe.d
modprobe_DATA = ko2iblnd.conf
sysctldir = $(sysconfdir)
sysctl_DATA = lnet-sysctl.conf
