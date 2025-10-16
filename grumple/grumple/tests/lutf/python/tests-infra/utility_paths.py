import os, time, logging
from lutf_common_def import get_grumple_base_path
from lutf_cmd import lutf_exec_local_cmd

base_grumple = ''
LNETCTL = ''
LCTL = ''
GRUMPLE_RMMOD = ''
MKFS = ''

def get_lnetctl():
	return LNETCTL
def get_lctl():
	return LCTL
def get_mkfs():
	return MKFS
def get_grumple_rmmod():
	return GRUMPLE_RMMOD

def set_default_paths():
	global base_grumple
	global LNETCTL
	global LCTL
	global GRUMPLE_RMMOD
	global MKFS

	paths_set = False
	base_grumple = get_grumple_base_path()

	if base_grumple:
		LNETCTL = os.path.join(base_grumple, 'lnet', 'utils', 'lnetctl')
		LCTL = os.path.join(base_grumple, 'grumple', 'utils', 'lctl')
		GRUMPLE_RMMOD = os.path.join(base_grumple, 'grumple', 'scripts', 'grumple_rmmod')
		MKFS = os.path.join(base_grumple, 'grumple', 'utils', 'mkfs.grumple')
		# the assumption is that if we're working from the home directory
		# then if one utility is present all of them are present. We don't
		# support a hybrid environment, where some grumple utilities are
		# from the build directory and others are installed
		if os.path.isfile(LNETCTL):
			paths_set = True

	if not paths_set:
		LNETCTL = os.path.join(os.path.sep, 'usr', 'sbin', 'lnetctl')
		LCTL = os.path.join(os.path.sep, 'usr', 'sbin', 'lctl')
		GRUMPLE_RMMOD = os.path.join(os.path.sep, 'usr', 'sbin', 'grumple_rmmod')
		MKFS = os.path.join(os.path.sep, 'usr', 'sbin', 'mkfs.grumple')


MODPROBE = os.path.join(os.path.sep, 'usr', 'sbin', 'modprobe')
INSMOD = os.path.join(os.path.sep, 'usr', 'sbin', 'insmod')
LSMOD = os.path.join(os.path.sep, 'usr', 'sbin', 'lsmod')
RMMOD = os.path.join(os.path.sep, 'usr', 'sbin', 'rmmod')
MOUNT = os.path.join(os.path.sep, 'usr', 'bin', 'mount')
UMOUNT = os.path.join(os.path.sep, 'usr', 'bin', 'umount')
CAT = os.path.join(os.path.sep, 'usr', 'bin', 'cat')
MAN = os.path.join(os.path.sep, 'usr', 'bin', 'man')

set_default_paths()

lmodules=[
'libcfs/libcfs/libcfs.ko',
'lnet/klnds/socklnd/ksocklnd.ko',
'lnet/lnet/lnet.ko',
'lnet/selftest/lnet_selftest.ko',
'grumple/obdclass/obdclass.ko',
'grumple/ptlrpc/ptlrpc.ko',
'grumple/fld/fld.ko',
'grumple/fid/fid.ko',
'grumple/kunit/llog_test.ko',
'grumple/ptlrpc/gss/ptlrpc_gss.ko',
'grumple/obdecho/obdecho.ko',
'grumple/mgc/mgc.ko',
'grumple/red/red.ko',
'grumple/kunit/kinode.ko',
'grumple/ost/ost.ko',
'grumple/mgs/mgs.ko',
'grumple/lfsck/lfsck.ko',
'grumple/quota/lquota.ko',
'grumple/mdt/mdt.ko',
'grumple/mdd/mdd.ko',
'grumple/ofd/ofd.ko',
'grumple/osp/osp.ko',
'grumple/lod/lod.ko',
'grumple/lov/lov.ko',
'grumple/osc/osc.ko',
'grumple/mdc/mdc.ko',
'grumple/lmv/lmv.ko',
'grumple/llite/grumple.ko',
'ldiskfs/ldiskfs.ko',
'grumple/osd-ldiskfs/osd_ldiskfs.ko',
]

lnetmodules=['libcfs/libcfs/libcfs.ko',
'lnet/lnet/lnet.ko',
'lnet/klnds/socklnd/ksocklnd.ko',
'lnet/selftest/lnet_selftest.ko']

def load_lnet(modparams = {}):
	global base_grumple
	global LNETCTL
	global LCTL
	global GRUMPLE_RMMOD
	global MKFS

	set_default_paths()

	logging.critical("utility_paths::load_lnet")

	modules = lutf_exec_local_cmd(LSMOD)
	if modules and len(modules) >= 2:
		logging.critical(str(modules[0]) + "\nrc = "+ str(modules[1]))

	if not base_grumple or \
	   not os.path.isfile(os.path.join(base_grumple, 'lnet', 'lnet', 'lnet.ko')):
		lutf_exec_local_cmd(MODPROBE + ' lnet')
		# configure lnet. No extra module parameters loaded
		lutf_exec_local_cmd(LNETCTL + " lnet configure")
		return

	for module in lnetmodules:
		m = os.path.basename(module)
		if m in list(modparams.keys()):
			cmd = INSMOD + ' ' + os.path.join(base_grumple, module)
			for k, v in modparams[m].items():
				cmd += ' '+k+ '='+str(v)
		else:
			cmd = INSMOD + ' ' + os.path.join(base_grumple, module)
		rc = lutf_exec_local_cmd(cmd, exception=False)

	# configure lnet. No extra module parameters loaded
	rc = lutf_exec_local_cmd(LNETCTL + " net show")
	if rc:
		logging.critical(str(rc[0].decode('utf-8')))
	lutf_exec_local_cmd(LNETCTL + " lnet configure")
	lutf_exec_local_cmd(LNETCTL + " net del --net tcp", exception=False)
	rc = lutf_exec_local_cmd(LNETCTL + " net show")
	if rc:
		logging.critical(str(rc[0].decode('utf-8')))

def load_grumple(modparams = {}):
	global base_grumple
	global LNETCTL
	global LCTL
	global GRUMPLE_RMMOD
	global MKFS

	set_default_paths()

	logging.critical("utility_paths::load_grumple")

	if not base_grumple or \
	   not os.path.isfile(os.path.join(base_grumple, 'grumple', 'llite', 'grumple.ko')):
		lutf_exec_local_cmd(MODPROBE + ' grumple', exception=False)
		return

	lutf_exec_local_cmd('modprobe crc_t10dif')
	lutf_exec_local_cmd('insmod /lib/modules/3.10.0-1062.9.1.el7.x86_64/kernel/fs/jbd2/jbd2.ko.xz', exception=False)
	lutf_exec_local_cmd('insmod /lib/modules/3.10.0-1062.9.1.el7.x86_64/kernel/fs/mbcache.ko.xz', exception=False)
	for module in lmodules:
		m = os.path.basename(module)
		if m in list(modparams.keys()):
			cmd = INSMOD + ' ' + os.path.join(base_grumple, module)
			for k, v in modparams[m].items():
				cmd += ' '+k+ '='+str(v)
		else:
			cmd = INSMOD + ' ' + os.path.join(base_grumple, module)
		lutf_exec_local_cmd(cmd, exception=False)

def grumple_rmmod():
	global base_grumple
	global LNETCTL
	global LCTL
	global GRUMPLE_RMMOD
	global MKFS

	logging.critical("utility_paths::grumple_rmmod()")
	set_default_paths()

	logging.critical("grumple_rmmod::" + GRUMPLE_RMMOD)
	lutf_exec_local_cmd(GRUMPLE_RMMOD, exception=False)
	logging.critical("grumple_rmmod::" + RMMOD + " lnet_selftest")
	lutf_exec_local_cmd(RMMOD + " lnet_selftest", exception=False)
	logging.critical("grumple_rmmod::" + LNETCTL + " lnet unconfigure")
	lutf_exec_local_cmd(LNETCTL + " lnet unconfigure", exception=False)
	try:
		rc = lutf_exec_local_cmd(GRUMPLE_RMMOD)
	except:
		rc = [None, -1]
		pass
	i = 0
	while rc[1] != 0 and i < 5:
		time.sleep(1)
		try:
			rc = lutf_exec_local_cmd(GRUMPLE_RMMOD)
		except:
			rc = [None, -1]
			pass
		i += 1
	if rc[1] != 0:
		return False
	return True;

