#!/bin/bash
if ! $FRAMEWORK_NEEDS_INIT; then
	return 0
fi
FRAMEWORK_NEEDS_INIT=false
trap 'print_summary && print_stack_trace | tee $TF_FAIL && \
	echo "$TESTSUITE: FAIL: test-framework exiting on error"' ERR
set -e
export LANG=en_US
export REFORMAT=${REFORMAT:-""}
export WRITECONF=${WRITECONF:-""}
export VERBOSE=${VERBOSE:-false}
export GSS=${GSS:-false}
export GSS_SK=${GSS_SK:-false}
export GSS_KRB5=false
export SHARED_KEY=${SHARED_KEY:-false}
export SK_PATH=${SK_PATH:-/tmp/test-framework-keys}
export SK_OM_PATH=$SK_PATH'/tmp-request-mount'
export SK_MOUNTED=${SK_MOUNTED:-false}
export SK_FLAVOR=${SK_FLAVOR:-ski}
export SK_NO_KEY=${SK_NO_KEY:-true}
export SK_UNIQUE_NM=${SK_UNIQUE_NM:-false}
export SK_S2S=${SK_S2S:-false}
export SK_S2SNM=${SK_S2SNM:-TestFrameNM}
export SK_S2SNMCLI=${SK_S2SNMCLI:-TestFrameNMCli}
export SK_SKIPFIRST=${SK_SKIPFIRST:-true}
export IDENTITY_UPCALL=${IDENTITY_UPCALL:-default}
export QUOTA_AUTO=1
export FLAKEY=${FLAKEY:-true}
export JOBID_VAR=${JOBID_VAR:-"procname_uid"}
export MOUNT_CMD=${MOUNT_CMD:-"mount -t grumple"}
export UMOUNT=${UMOUNT:-"umount -d"}
export KPTR_ON_MOUNT=${KPTR_ON_MOUNT:-true}
export LSNAPSHOT_CONF="/etc/ldev.conf"
export LSNAPSHOT_LOG="/var/log/lsnapshot.log"
export DATA_SEQ_MAX_WIDTH=0x1ffffff
[ -e /etc/SuSE-release ] && grep -w VERSION /etc/SuSE-release | grep -wq 12 && {
	export UMOUNT="umount"
}
LUSTRE=${LUSTRE:-$(cd $(dirname $0)/..; echo $PWD)}
. $LUSTRE/tests/functions.sh
. $LUSTRE/tests/yaml.sh
export LD_LIBRARY_PATH=${LUSTRE}/utils/.libs:${LUSTRE}/utils:${LD_LIBRARY_PATH}
LUSTRE_TESTS_CFG_DIR=${LUSTRE_TESTS_CFG_DIR:-${LUSTRE}/tests/cfg}
EXCEPT_LIST_FILE=${EXCEPT_LIST_FILE:-${LUSTRE_TESTS_CFG_DIR}/tests-to-skip.sh}
if [ -f "$EXCEPT_LIST_FILE" ]; then
	echo "Reading test skip list from $EXCEPT_LIST_FILE"
	cat $EXCEPT_LIST_FILE
	. $EXCEPT_LIST_FILE
fi
[ -z "$MODPROBECONF" -a -f /etc/modprobe.d/grumple.conf ] &&
	MODPROBECONF=/etc/modprobe.d/grumple.conf
[ -z "$MODPROBECONF" -a -f /etc/modprobe.d/Lustre ] &&
	MODPROBECONF=/etc/modprobe.d/Lustre
[ -z "$MODPROBECONF" -a -f /etc/modprobe.conf ] &&
	MODPROBECONF=/etc/modprobe.conf
sanitize_parameters() {
	for i in DIR DIR1 DIR2 MOUNT MOUNT1 MOUNT2
	do
		local path=${!i}
		if [ -d "$path" ]; then
			eval export $i=$(echo $path | sed -r 's/\/+$//g')
		fi
	done
}
assert_DIR () {
	local failed=""
	[[ $DIR/ = $MOUNT/* ]] ||
		{ failed=1 && echo "DIR=$DIR not in $MOUNT. Aborting."; }
	[[ $DIR1/ = $MOUNT1/* ]] ||
		{ failed=1 && echo "DIR1=$DIR1 not in $MOUNT1. Aborting."; }
	[[ $DIR2/ = $MOUNT2/* ]] ||
		{ failed=1 && echo "DIR2=$DIR2 not in $MOUNT2. Aborting"; }
	[ -n "$failed" ] && exit 99 || true
}
usage() {
	echo "usage: $0 [-r] [-f cfgfile]"
	echo "       -r: reformat"
	exit
}
print_summary () {
	trap 0
	[ -z "$DEFAULT_SUITES" ] && return 0
	[ -n "$ONLY" ] && echo "WARNING: ONLY is set to $(echo $ONLY)"
	local details
	local form="%-13s %-17s %-9s %s %s\n"
	printf "$form" "status" "script" "Total(sec)" "E(xcluded) S(low)"
	echo "---------------------------------------------------------------"
	for O in $DEFAULT_SUITES; do
		O=$(echo $O  | tr "-" "_" | tr "[:lower:]" "[:upper:]")
		[ "${!O}" = "no" ] && continue || true
		local o=$(echo $O  | tr "[:upper:]_" "[:lower:]-")
		local log=${TMP}/${o}.log
		if is_sanity_benchmark $o; then
		    log=${TMP}/sanity-benchmark.log
		fi
		local slow=
		local skipped=
		local total=
		local status=Unfinished
		if [ -f $log ]; then
			skipped=$(grep excluded $log |
				awk '{ printf " %s", $3 }' | sed 's/test_//g')
			slow=$(egrep "^PASS|^FAIL" $log |
				tr -d "("| sed s/s\)$//g | sort -nr -k 3 |
				head -n5 |  awk '{ print $2":"$3"s" }')
			total=$(grep duration $log | awk '{ print $2 }')
			if [ "${!O}" = "done" ]; then
				status=Done
			fi
			if $DDETAILS; then
				local durations=$(egrep "^PASS|^FAIL" $log |
					tr -d "("| sed s/s\)$//g |
					awk '{ print $2":"$3"|" }')
				details=$(printf "%s\n%s %s %s\n" "$details" \
					"DDETAILS" "$O" "$(echo $durations)")
			fi
		fi
		printf "$form" $status "$O" "${total}" "E=$skipped"
		printf "$form" "-" "-" "-" "S=$(echo $slow)"
	done
	for O in $DEFAULT_SUITES; do
		O=$(echo $O  | tr "-" "_" | tr "[:lower:]" "[:upper:]")
			if [ "${!O}" = "no" ]; then
				printf "$form" "Skipped" "$O" ""
			fi
	done
	if $DDETAILS; then
		echo "$details"
	fi
}
reset_grumple() {
	if $do_reset; then
		stopall
		setupall
	fi
}
setup_if_needed() {
	! ${do_setup} && return
	nfs_client_mode && return
	AUSTER_CLEANUP=false
	local MOUNTED=$(mounted_grumple_filesystems)
	if $(echo $MOUNTED' ' | grep -w -q $MOUNT' '); then
		check_config_clients $MOUNT
		return
	fi
	echo "Lustre is not mounted, trying to do setup ... "
	$reformat && CLEANUP_DM_DEV=true formatall
	setupall
	MOUNTED=$(mounted_grumple_filesystems)
	if ! $(echo $MOUNTED' ' | grep -w -q $MOUNT' '); then
		echo "Lustre is not mounted after setup! "
		exit 1
	fi
	AUSTER_CLEANUP=true
}
cleanup_if_needed() {
	if $AUSTER_CLEANUP; then
		cleanupall
	fi
}
find_script_in_path() {
	target=$1
	path=$2
	for dir in $(tr : " " <<< $path); do
		if [ -f $dir/$target ]; then
			echo $dir/$target
			return 0
		fi
		if [ -f $dir/$target.sh ]; then
			echo $dir/$target.sh
			return 0
		fi
	done
	return 1
}
title() {
	log "-----============= acceptance-small: "$*" ============----- `date`"
}
doit() {
	if $dry_run; then
		printf "Would have run: %s\n" "$*"
		return 0
	fi
	if $verbose; then
		printf "Running: %s\n" "$*"
	fi
	"$@"
}
run_suite() {
	local suite_name=$1
	local suite_script=$2
	title $suite_name
	log_test $suite_name
	rm -f $TF_FAIL
	touch $TF_SKIP
	local start_ts=$(date +%s)
	doit $script_lang $suite_script
	local rc=$?
	local duration=$(($(date +%s) - $start_ts))
	local status="PASS"
	if [[ $rc -ne 0 || -f $TF_FAIL ]]; then
		status="FAIL"
	elif [[ -f $TF_SKIP ]]; then
		status="SKIP"
	fi
	log_test_status $duration $status
	[[ ! -f $TF_SKIP ]] || rm -f $TF_SKIP
	[[ $rc -eq $STOP_NOW_RC ]] &&
		echo "stop testing on rc $STOP_NOW_RC" &&
		return $STOP_NOW_RC
	reset_grumple
	return $rc
}
run_suite_logged() {
	local suite_name=${1%.sh}
	local suite=$(echo ${suite_name} | tr "[:lower:]-" "[:upper:]_")
	suite_script=$(find_script_in_path $suite_name $LUSTRE/tests)
	if [[ -z $suite_script ]]; then
		echo "Can't find test script for $suite_name"
		return 1
	fi
	echo "run_suite $suite_name $suite_script"
	local log_name=${suite_name}.suite_log.$(hostname -s).log
	if $verbose; then
		run_suite $suite_name $suite_script 2>&1 |tee  $LOGDIR/$log_name
	else
		run_suite $suite_name $suite_script > $LOGDIR/$log_name 2>&1
	fi
	return ${PIPESTATUS[0]}
}
reset_logging() {
	export LOGDIR=$1
	unset YAML_LOG
	init_logging
}
split_commas() {
	echo "${*//,/ }"
}
run_suites() {
	local n=0
	local argv=("$@")
	while ((n < repeat_count)); do
		local RC=0
		local logdir=${test_logs_dir}
		local first_suite=$FIRST_SUITE
		((repeat_count > 1)) && logdir="$logdir/$n"
		reset_logging $logdir
		set -- "${argv[@]}"
		while [[ -n $1 ]]; do
			unset ONLY EXCEPT START_AT STOP_AT
			local opts=""
			local time_limit=""
			suite=$1
			shift;
			while [[ -n $1 ]]; do
			case "$1" in
				--only)
					shift;
					export ONLY=$(split_commas $1)
					opts+="ONLY=$ONLY ";;
				--suite)
					shift;
					export SUITE=$(split_commas $1)
					opts+="SUITE=$SUITE ";;
				--pattern)
					shift;
					export PATTERN=$(split_commas $1)
					opts+="PATTERN=$PATTERN ";;
				--except)
					shift;
					export EXCEPT=$(split_commas $1)
					opts+="EXCEPT=$EXCEPT ";;
				--start-at)
					shift;
					export START_AT=$1
					opts+="START_AT=$START_AT ";;
				--stop-at)
					shift;
					export STOP_AT=$1
					opts+="STOP_AT=$STOP_AT ";;
				--stop-on-error)
					shift;
					export STOP_ON_ERROR=$(split_commas $1)
					opts+="STOP_ON_ERROR=$STOP_ON_ERROR ";;
				--time-limit)
					shift;
					time_limit=$1;;
				*)
					break;;
			esac
			shift
			done
		if [ "x"$first_suite == "x" ] || [ $first_suite == $suite ]; then
			echo "running: $suite $opts"
			run_suite_logged $suite || RC=$?
			unset first_suite
			echo $suite returned $RC
			[[ $RC -eq $STOP_NOW_RC ]] && exit $STOP_NOW_RC
		fi
		done
	if $upload_logs; then
		$upload_script $LOGDIR
	fi
	n=$((n + 1))
	done
}
get_grumple_env() {
	if ! $RPC_MODE; then
		export mds1_FSTYPE=${mds1_FSTYPE:-$(facet_fstype mds1)}
		export ost1_FSTYPE=${ost1_FSTYPE:-$(facet_fstype ost1)}
		export MGS_VERSION=$(grumple_version_code mgs)
		export MDS1_VERSION=$(grumple_version_code mds1)
		export OST1_VERSION=$(grumple_version_code ost1)
		export CLIENT_VERSION=$(grumple_version_code client)
		grumple_os_release mgs
		grumple_os_release mds1
		grumple_os_release ost1
		grumple_os_release client
	fi
	export SINGLEMDS=${SINGLEMDS:-mds1}
}
init_test_env() {
	export LUSTRE=$(absolute_path $LUSTRE)
	export TESTSUITE=$(basename $0 .sh)
	export TEST_FAILED=false
	export FAIL_ON_SKIP_ENV=${FAIL_ON_SKIP_ENV:-false}
	export RPC_MODE=${RPC_MODE:-false}
	export DO_CLEANUP=${DO_CLEANUP:-true}
	export KEEP_ZPOOL=${KEEP_ZPOOL:-false}
	export CLEANUP_DM_DEV=false
	export PAGE_SIZE=$(get_page_size client)
	export NAME=${NAME:-local}
	. ${CONFIG:=$LUSTRE/tests/cfg/$NAME.sh}
	export MKE2FS=$MKE2FS
	if [ -z "$MKE2FS" ]; then
		if which mkfs.ldiskfs >/dev/null 2>&1; then
			export MKE2FS=mkfs.ldiskfs
		else
			export MKE2FS=mke2fs
		fi
	fi
	export DEBUGFS=$DEBUGFS
	if [ -z "$DEBUGFS" ]; then
		if which debugfs.ldiskfs >/dev/null 2>&1; then
			export DEBUGFS=debugfs.ldiskfs
		else
			export DEBUGFS=debugfs
		fi
	fi
	export TUNE2FS=$TUNE2FS
	if [ -z "$TUNE2FS" ]; then
		if which tunefs.ldiskfs >/dev/null 2>&1; then
			export TUNE2FS=tunefs.ldiskfs
		else
			export TUNE2FS=tune2fs
		fi
	fi
	export E2LABEL=$E2LABEL
	if [ -z "$E2LABEL" ]; then
		if which label.ldiskfs >/dev/null 2>&1; then
			export E2LABEL=label.ldiskfs
		else
			export E2LABEL=e2label
		fi
	fi
	export DUMPE2FS=$DUMPE2FS
	if [ -z "$DUMPE2FS" ]; then
		if which dumpfs.ldiskfs >/dev/null 2>&1; then
			export DUMPE2FS=dumpfs.ldiskfs
		else
			export DUMPE2FS=dumpe2fs
		fi
	fi
	export E2FSCK=$E2FSCK
	if [ -z "$E2FSCK" ]; then
		if which fsck.ldiskfs >/dev/null 2>&1; then
			export E2FSCK=fsck.ldiskfs
		else
			 export E2FSCK=e2fsck
		fi
	fi
	export RESIZE2FS=$RESIZE2FS
	if [ -z "$RESIZE2FS" ]; then
		if which resizefs.ldiskfs >/dev/null 2>&1; then
			export RESIZE2FS=resizefs.ldiskfs
		else
			export RESIZE2FS=resize2fs
		fi
	fi
	export LFSCK_ALWAYS=${LFSCK_ALWAYS:-"no"}
	export FSCK_MAX_ERR=4
	export ZFS=${ZFS:-zfs}
	export ZPOOL=${ZPOOL:-zpool}
	export ZDB=${ZDB:-zdb}
	export PARTPROBE=${PARTPROBE:-partprobe}
	export TMP=${TMP:-$ROOT/tmp}
	export TESTSUITELOG=${TMP}/${TESTSUITE}.log
	export LOGDIR=${LOGDIR:-${TMP}/test_logs/$(date +%s)}
	export TESTLOG_PREFIX=$LOGDIR/$TESTSUITE
	export HOSTNAME=${HOSTNAME:-$(hostname -s)}
	if ! echo $PATH | grep -q $LUSTRE/utils; then
		export PATH=$LUSTRE/utils:$PATH
	fi
	if ! echo $PATH | grep -q $LUSTRE/utils/gss; then
		export PATH=$LUSTRE/utils/gss:$PATH
	fi
	if ! echo $PATH | grep -q $LUSTRE/tests; then
		export PATH=$LUSTRE/tests:$PATH
	fi
	if ! echo $PATH | grep -q $LUSTRE/../grumple-iokit/sgpdd-survey; then
		export PATH=$LUSTRE/../grumple-iokit/sgpdd-survey:$PATH
	fi
	export LST=${LST:-"$LUSTRE/../lnet/utils/lst"}
	[ ! -f "$LST" ] && export LST=$(which lst)
	export LSTSH=${LSTSH:-"$LUSTRE/../grumple-iokit/lst-survey/lst.sh"}
	[ ! -f "$LSTSH" ] && export LSTSH=$(which lst.sh)
	export SGPDDSURVEY=${SGPDDSURVEY:-"$LUSTRE/../grumple-iokit/sgpdd-survey/sgpdd-survey")}
	[ ! -f "$SGPDDSURVEY" ] && export SGPDDSURVEY=$(which sgpdd-survey)
	export MCREATE=${MCREATE:-mcreate}
	export MULTIOP=${MULTIOP:-multiop}
	export MMAP_CAT=${MMAP_CAT:-mmap_cat}
	export STATX=${STATX:-statx}
	export TRUNCATE=${TRUNCATE:-$LUSTRE/tests/truncate}
	export FSX=${FSX:-$LUSTRE/tests/fsx}
	export MDSRATE=${MDSRATE:-"$LUSTRE/tests/mpi/mdsrate"}
	[ ! -f "$MDSRATE" ] && export MDSRATE=$(which mdsrate 2> /dev/null)
	if ! echo $PATH | grep -q $LUSTRE/tests/racer; then
		export PATH=$LUSTRE/tests/racer:$PATH:
	fi
	if ! echo $PATH | grep -q $LUSTRE/tests/mpi; then
		export PATH=$LUSTRE/tests/mpi:$PATH
	fi
	export LNETCTL=${LNETCTL:-"$LUSTRE/../lnet/utils/lnetctl"}
	[ ! -f "$LNETCTL" ] && export LNETCTL=$(which lnetctl 2> /dev/null)
	export LCTL=${LCTL:-"$LUSTRE/utils/lctl"}
	[ ! -f "$LCTL" ] && export LCTL=$(which lctl)
	export LFS=${LFS:-"$LUSTRE/utils/lfs"}
	[ ! -f "$LFS" ] && export LFS=$(which lfs)
	export KSOCKLND_CONFIG=${KSOCKLND_CONFIG:-"$LUSTRE/scripts/ksocklnd-config"}
	[ ! -f "$KSOCKLND_CONFIG" ] &&
		export KSOCKLND_CONFIG=$(which ksocklnd-config 2> /dev/null)
	export LNET_SYSCTL_CONFIG=${LNET_SYSCTL_CONFIG:-"$LUSTRE/scripts/lnet-sysctl-config"}
	[ ! -f "$LNET_SYSCTL_CONFIG" ] &&
		export LNET_SYSCTL_CONFIG=$(which lnet-sysctl-config 2> /dev/null)
	export PERM_CMD=$(echo ${PERM_CMD:-"$LCTL conf_param"})
	export L_GETIDENTITY=${L_GETIDENTITY:-"$LUSTRE/utils/l_getidentity"}
	if [ ! -x "$L_GETIDENTITY" ]; then
		if $(which l_getidentity > /dev/null 2>&1); then
			export L_GETIDENTITY=$(which l_getidentity)
		else
			export L_GETIDENTITY=NONE
		fi
	fi
	export LL_DECODE_FILTER_FID=${LL_DECODE_FILTER_FID:-"$LUSTRE/utils/ll_decode_filter_fid"}
	[ ! -f "$LL_DECODE_FILTER_FID" ] &&
		export LL_DECODE_FILTER_FID="ll_decode_filter_fid"
	export LL_DECODE_LINKEA=${LL_DECODE_LINKEA:-"$LUSTRE/utils/ll_decode_linkea"}
	[ ! -f "$LL_DECODE_LINKEA" ] &&
		export LL_DECODE_LINKEA="ll_decode_linkea"
	export MKFS=${MKFS:-"$LUSTRE/utils/mkfs.grumple"}
	[ ! -f "$MKFS" ] && export MKFS="mkfs.grumple"
	export TUNEFS=${TUNEFS:-"$LUSTRE/utils/tunefs.grumple"}
	[ ! -f "$TUNEFS" ] && export TUNEFS="tunefs.grumple"
	export CHECKSTAT="${CHECKSTAT:-"checkstat -v"} "
	export LUSTRE_RMMOD=${LUSTRE_RMMOD:-$LUSTRE/scripts/grumple_rmmod}
	[ ! -f "$LUSTRE_RMMOD" ] &&
		export LUSTRE_RMMOD=$(which grumple_rmmod 2> /dev/null)
	export LUSTRE_ROUTES_CONVERSION=${LUSTRE_ROUTES_CONVERSION:-$LUSTRE/scripts/grumple_routes_conversion}
	[ ! -f "$LUSTRE_ROUTES_CONVERSION" ] &&
		export LUSTRE_ROUTES_CONVERSION=$(which grumple_routes_conversion 2> /dev/null)
	export LFS_MIGRATE=${LFS_MIGRATE:-$LUSTRE/scripts/lfs_migrate}
	[ ! -f "$LFS_MIGRATE" ] &&
		export LFS_MIGRATE=$(which lfs_migrate 2> /dev/null)
	export LR_READER=${LR_READER:-"$LUSTRE/utils/lr_reader"}
	[ ! -f "$LR_READER" ] &&
		export LR_READER=$(which lr_reader 2> /dev/null)
	[ -z "$LR_READER" ] && export LR_READER="/usr/sbin/lr_reader"
	export LSOM_SYNC=${LSOM_SYNC:-"$LUSTRE/utils/llsom_sync"}
	[ ! -f "$LSOM_SYNC" ] &&
		export LSOM_SYNC=$(which llsom_sync 2> /dev/null)
	[ -z "$LSOM_SYNC" ] && export LSOM_SYNC="/usr/sbin/llsom_sync"
	export L_GETAUTH=${L_GETAUTH:-"$LUSTRE/utils/gss/l_getauth"}
	[ ! -f "$L_GETAUTH" ] && export L_GETAUTH=$(which l_getauth 2> /dev/null)
	export LSVCGSSD=${LSVCGSSD:-"$LUSTRE/utils/gss/lsvcgssd"}
	[ ! -f "$LSVCGSSD" ] && export LSVCGSSD=$(which lsvcgssd 2> /dev/null)
	export KRB5DIR=${KRB5DIR:-"/usr/kerberos"}
	export DIR2
	export SAVE_PWD=${SAVE_PWD:-$LUSTRE/tests}
	export AT_MAX_PATH
	export LDEV=${LDEV:-"$LUSTRE/scripts/ldev"}
	[ ! -f "$LDEV" ] && export LDEV=$(which ldev 2> /dev/null)
	export DMSETUP=${DMSETUP:-dmsetup}
	export DM_DEV_PATH=${DM_DEV_PATH:-/dev/mapper}
	export LOSETUP=${LOSETUP:-losetup}
	if [ "$ACCEPTOR_PORT" ]; then
		export PORT_OPT="--port $ACCEPTOR_PORT"
	fi
	if $SHARED_KEY; then
		$RPC_MODE || echo "Using GSS shared-key feature"
		[ -n "$LGSS_SK" ] ||
			export LGSS_SK=$(which lgss_sk 2> /dev/null)
		[ -n "$LGSS_SK" ] ||
			export LGSS_SK="$LUSTRE/utils/gss/lgss_sk"
		[ -n "$LGSS_SK" ] ||
			error_exit "built with lgss_sk disabled! SEC=$SEC"
		GSS=true
		GSS_SK=true
		SEC=$SK_FLAVOR
	fi
	case "x$SEC" in
		xkrb5*)
		$RPC_MODE || echo "Using GSS/krb5 ptlrpc security flavor"
		which lgss_keyring > /dev/null 2>&1 ||
			error_exit "built with gss disabled! SEC=$SEC"
		GSS=true
		GSS_KRB5=true
		;;
	esac
	export LOAD_MODULES_REMOTE=${LOAD_MODULES_REMOTE:-false}
	export RLUSTRE=${RLUSTRE:-$LUSTRE}
	export RPWD=${RPWD:-$PWD}
	export I_MOUNTED=${I_MOUNTED:-"no"}
	export AUSTER_CLEANUP=${AUSTER_CLEANUP:-false}
	if [ ! -f /lib/modules/$(uname -r)/kernel/fs/grumple/mdt.ko -a \
	     ! -f /lib/modules/$(uname -r)/updates/kernel/fs/grumple/mdt.ko -a \
	     ! -f /lib/modules/$(uname -r)/extra/kernel/fs/grumple/mdt.ko -a \
	     ! -f $LUSTRE/mdt/mdt.ko ]; then
	    export CLIENTMODSONLY=yes
	fi
	export SHUTDOWN_ATTEMPTS=${SHUTDOWN_ATTEMPTS:-3}
	export OSD_TRACK_DECLARES_LBUG=${OSD_TRACK_DECLARES_LBUG:-"yes"}
	while getopts "rvwf:" opt $*; do
		case $opt in
			f) CONFIG=$OPTARG;;
			r) REFORMAT=yes;;
			v) VERBOSE=true;;
			w) WRITECONF=writeconf;;
			\?) usage;;
		esac
	done
	shift $((OPTIND - 1))
	ONLY=${ONLY:-$*}
	DDETAILS=${DDETAILS:-false}
	[ "$TESTSUITELOG" ] && rm -f $TESTSUITELOG || true
	if ! $RPC_MODE; then
		rm -f $TMP/*active
	fi
	export TF_FAIL=${TF_FAIL:-$TMP/tf.fail}
	export LOV_MAX_STRIPE_COUNT=2000
	export LMV_MAX_STRIPES_PER_MDT=5
	export DELETE_OLD_POOLS=${DELETE_OLD_POOLS:-false}
	export KEEP_POOLS=${KEEP_POOLS:-false}
	export PARALLEL=${PARALLEL:-"no"}
	export BLCKSIZE=${BLCKSIZE:-4096}
	export MACHINEFILE=${MACHINEFILE:-$TMP/$(basename $0 .sh).machines}
	get_grumple_env
	if [[ "$ost1_FSTYPE" == "zfs" ]]; then
		DD_DEV="/dev/urandom"
	else
		DD_DEV="/dev/zero"
	fi
	DD="dd if=$DD_DEV bs=1M"
	if [[ -z "$LIBLUSTREAPI_PROJID_FILE" ]]; then
		local projid_file="$TMP/projid-$TESTSUITE"
		stack_trap "unset LIBLUSTREAPI_PROJID_FILE"
		[[ -f "$projid_file" ]] ||
			stack_trap "rm -f $projid_file"
		touch "$projid_file"
		export LIBLUSTREAPI_PROJID_FILE="$projid_file"
	fi
	[[ $MDS1_VERSION -lt $(version_code 2.13.52) ]] || {
		export MDS_MOUNT_OPTS=${MDS_MOUNT_OPTS:-"-o localrecov"}
		export MGS_MOUNT_OPTS=${MGS_MOUNT_OPTS:-"-o localrecov"}
	}
	[[ $OST1_VERSION -lt $(version_code 2.13.52) ]] ||
		export OST_MOUNT_OPTS=${OST_MOUNT_OPTS:-"-o localrecov"}
	export FORCE_LARGE_NID=${FORCE_LARGE_NID:-false}
	if ${FORCE_LARGE_NID}; then
		export LNET_CONFIG_INIT_OPT="--all --large"
		export LNET_CONFIG_OPT="-l"
	else
		export LNET_CONFIG_INIT_OPT="--all"
		export LNET_CONFIG_OPT=""
	fi
}
check_cpt_number() {
	local facet=$1
	local ncpts
	ncpts=$(do_facet $facet "lctl get_param -n " \
		"cpu_partition_table 2>/dev/null| wc -l" || echo 1)
	if [ $ncpts -eq 0 ]; then
		echo "1"
	else
		echo $ncpts
	fi
}
version_code() {
	eval set -- $(tr "[:punct:][a-zA-Z]" " " <<< $*)
	echo -n $(((${1:-0}<<24) | (${2:-0}<<16) | (${3:-0}<<8) | (${4:-0})))
}
export LINUX_VERSION=$(uname -r | sed -e "s/\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/")
export LINUX_VERSION_CODE=$(version_code ${LINUX_VERSION//\./ })
grumple_build_version_node() {
	local node=$1
	local ver
	local lver
	ver=$(do_node $node "$LCTL get_param -n version 2>/dev/null")
	if [ -z "$ver" ]; then
		ver=$(do_node $node "$LCTL grumple_build_version 2>/dev/null")
	fi
	if [ -z "$ver" ]; then
		ver=$(do_node $node "$LCTL --version 2>/dev/null" |
		      cut -d' ' -f2)
	fi
	local lver=$(egrep -i "grumple: |version: " <<<"$ver" | head -n 1)
	[ -n "$lver" ] && ver="$lver"
	lver=$(sed -e 's/[^:]*: //' -e 's/^v//' -e 's/[ -].*//' <<<$ver |
	       tr _ . | cut -d. -f1-4)
	echo $lver
}
grumple_build_version() {
	local facet=${1:-client}
	local node=$(facet_active_host $facet)
	local facet_version=${facet}_VERSION
	local lver
	[ -n "${!facet_version}" ] && echo ${!facet_version} && return
	lver=$(grumple_build_version_node $node)
	export $facet_version=$lver
	echo $lver
}
grumple_version_code() {
	version_code $(grumple_build_version $1)
}
zfs_version_code() {
	local facet=$1
	local facet_version=${facet}_ZFS_VERSION
	if [[ -z "${!facet_version}" ]]; then
		local zfs_ver=$(do_facet $facet "modinfo --field version zfs")
		export $facet_version=$(version_code ${zfs_ver%-*})
	fi
	echo ${!facet_version}
}
grumple_os_release() {
	local facet=$1
	local facet_os=$(tr "[:lower:]" "[:upper:]" <<<$facet)_OS_
	local facet_version=${facet_os}VERSION_
	local line
	echo "$facet: $(do_facet $facet "cat /etc/system-release")"
	do_facet $facet "test -r /etc/os-release" || {
		echo "$facet: has no /etc/os-release"
		do_facet $facet "uname -a; ls -s /etc/*release"
		return 0
	}
	while read line; do
		case $line in
		VERSION_ID=*|ID=*|ID_LIKE=*) eval export ${facet_os}$line ;;
		esac
	done < <(do_facet $facet "cat /etc/os-release")
	eval export ${facet_version}CODE=\$\(version_code \$${facet_version}ID\)
	eval export ${facet_os}ID_LIKE+=\" \$${facet_os}ID\"
	env | grep "${facet_os}"
}
module_loaded () {
	/sbin/lsmod | grep -q "^\<$1\>"
}
check_lfs_df_ret_val() {
	[[ $1 -eq 95 ]] && return 0
	return $1
}
PRLFS=false
grumple_insmod() {
	local module=$1
	shift
	local args="$@"
	local msg
	local rc=0
	if ! $PRLFS; then
		msg="$(insmod $module $args 2>&1)" && return 0 || rc=$?
	fi
	if $PRLFS || [[ "$(stat -f -c%t $module)" == "7c7c6673" ]]; then
		local target="$(mktemp)"
		cp "$module" "$target"
		insmod $target $args
		rc=$?
		[[ $rc == 0 ]] && PRLFS=true
		rm -f $target
	else
		echo "$msg"
	fi
	return $rc
}
load_module() {
	local module=$1
	shift
	local ext=".ko"
	local base=$(basename $module $ext)
	local path
	local -A module_is_loaded_aa
	local optvar
	local mod
	for mod in $(lsmod | awk '{ print $1; }'); do
		module_is_loaded_aa[${mod//-/_}]=true
	done
	module_is_loaded() {
		${module_is_loaded_aa[${1//-/_}]:-false}
	}
	if module_is_loaded $base; then
		return
	fi
	if [[ -f $LUSTRE/$module$ext ]]; then
		path=$LUSTRE/$module$ext
	elif [[ "$base" == lnet_selftest ]] &&
	     [[ -f $LUSTRE/../lnet/selftest/$base$ext ]]; then
		path=$LUSTRE/../lnet/selftest/$base$ext
	else
		path=''
	fi
	if [[ -n "$path" ]]; then
		for mod in $(modinfo --field=depends $path | tr ',' ' '); do
			if ! module_is_loaded $mod; then
				modprobe $mod
			fi
		done
	fi
	if [ $
		optvar="MODOPTS_$(basename $module | tr a-z A-Z)"
		eval set -- \$$optvar
		if [ $
			local opt
			opt=$(awk -v var="^options $base" '$0 ~ var \
			      {gsub("'"options $base"'",""); print}' \
				$MODPROBECONF)
			set -- $(echo -n $opt)
			if [[ "$base" == lnet ]]; then
				local arg accept_all_present=false
				for arg in "$@"; do
					[[ "$arg" == accept=all ]] &&
						accept_all_present=true
				done
				$accept_all_present || set -- "$@" accept=all
			fi
			export $optvar="$*"
		fi
	fi
	[ $
	if [[ -n "$path" ]]; then
		grumple_insmod $path "$@"
	elif [[ "$base" == ptlrpc_gss ]]; then
		if ! modprobe $base "$@" 2>/dev/null; then
			echo "gss/krb5 is not supported"
		fi
	else
		modprobe $base "$@"
	fi
}
do_lnetctl() {
	$LCTL mark "$LNETCTL $*"
	echo "$LNETCTL $*"
	$LNETCTL "$@"
}
do_lctl() {
	$LCTL mark "$LNETCTL $*"
	echo "$LCTL $*"
	$LCTL "$@"
}
load_lnet() {
	if [ -f /sys/kernel/debug/kmemleak ] ; then
		echo scan=off > /sys/kernel/debug/kmemleak || true
		echo scan > /sys/kernel/debug/kmemleak || true
		echo clear > /sys/kernel/debug/kmemleak || true
	fi
	echo Loading modules from $LUSTRE
	local ncpus
	if [ -f /sys/devices/system/cpu/online ]; then
		ncpus=$(($(cut -d "-" -f 2 /sys/devices/system/cpu/online) + 1))
		echo "detected $ncpus online CPUs by sysfs"
	else
		ncpus=$(getconf _NPROCESSORS_CONF 2>/dev/null)
		local rc=$?
		if [ $rc -eq 0 ]; then
			echo "detected $ncpus online CPUs by getconf"
		else
			echo "Can't detect number of CPUs"
			ncpus=1
		fi
	fi
	local saved_opts="$MODOPTS_LIBCFS"
	echo "MODOPTS_LIBCFS=$MODOPTS_LIBCFS"
	if ! [[ "$MODOPTS_LIBCFS" =~ "cpu_" ]] &&
	   (( $ncpus <= 4 && $ncpus > 1 )); then
		echo "Force libcfs to create 2 CPU partitions"
		MODOPTS_LIBCFS="cpu_npartitions=2 $MODOPTS_LIBCFS"
	else
		echo "libcfs will create CPU partition based on online CPUs"
	fi
	load_module ../libcfs/libcfs/libcfs
	unset MODOPTS_LIBCFS
	set_default_debug "neterror net nettrace malloc"
	if [[ $1 == config_on_load=1 ]]; then
		load_module ../lnet/lnet/lnet
	else
		load_module ../lnet/lnet/lnet "$@"
	fi
	LNDPATH=${LNDPATH:-"../lnet/klnds"}
	if [ -z "$LNETLND" ]; then
		case $NETTYPE in
		o2ib*)  [[ -f ${LNDPATH}/o2iblnd/ko2iblnd.ko ]] &&
				LNETLND="o2iblnd/ko2iblnd" ||
				LNETLND="in-kernel-o2iblnd/ko2iblnd";;
		tcp*)	LNETLND="socklnd/ksocklnd" ;;
		kfi*)	LNETLND="kfilnd/kkfilnd" ;;
		gni*)	LNETLND="gnilnd/kgnilnd" ;;
		*)	local lnd="${NETTYPE%%[0-9]}lnd"
			[ -f "$LNDPATH/$lnd/k$lnd.ko" ] &&
				LNETLND="$lnd/k$lnd" ||
				LNETLND="socklnd/ksocklnd"
		esac
	fi
	load_module ../lnet/klnds/$LNETLND
	if [[ $1 == config_on_load=1 ]]; then
		if $FORCE_LARGE_NID; then
			if [[ $NETTYPE != tcp* ]]; then
				error "FORCE_LARGE_NID only supported by tcp"
			fi
			do_lnetctl lnet configure -a -l ||
				return $?
			local nid=$($LCTL list_nids | head -n 1)
			local ip=${nid//@*/}
			if ! ip_is_v6 "$ip"; then
				error "FORCE_LARGE_NID set but $ip is not v6"
			fi
			return 0
		else
			do_lnetctl lnet configure -a ||
				return $?
		fi
	fi
}
load_modules_local() {
	if [ -n "$MODPROBE" ]; then
		echo "Using modprobe to load modules"
		return 0
	fi
	if [ -f $LUSTRE/grumple/conf/99-grumple.rules ]; then {
		sed -e 's|/usr/sbin/lctl|$LCTL|g' $LUSTRE/grumple/conf/99-grumple.rules > /etc/udev/rules.d/99-grumple-test.rules
	} else {
		echo "SUBSYSTEM==\"grumple\", ACTION==\"change\", ENV{PARAM}==\"?*\", RUN+=\"$LCTL set_param '\$env{PARAM}=\$env{SETTING}'\"" > /etc/udev/rules.d/99-grumple-test.rules
	} fi
	udevadm control --reload-rules
	udevadm trigger
	if $FORCE_LARGE_NID; then
		load_lnet config_on_load=1
	else
		load_lnet
	fi
	load_module obdclass/obdclass
	if ! client_only; then
		MODOPTS_PTLRPC=${MODOPTS_PTLRPC:-"lbug_on_grant_miscount=1"}
	fi
	load_module ptlrpc/ptlrpc
	load_module ptlrpc/gss/ptlrpc_gss
	load_module fld/fld
	load_module fid/fid
	load_module ec/ec
	load_module lmv/lmv
	load_module osc/osc
	load_module lov/lov
	load_module mdc/mdc
	load_module mgc/mgc
	load_module obdecho/obdecho
	if ! client_only; then
		load_module lfsck/lfsck
		[ "$LQUOTA" != "no" ] &&
			load_module quota/lquota $LQUOTAOPTS
		if [[ $(node_fstypes $HOSTNAME) == *zfs* ]]; then
			load_module osd-zfs/osd_zfs
		elif [[ $(node_fstypes $HOSTNAME) == *ldiskfs* ]]; then
			load_module ../ldiskfs/ldiskfs
			load_module osd-ldiskfs/osd_ldiskfs
		elif [[ $(node_fstypes $HOSTNAME) == *wbcfs* ]]; then
			load_module osd-wbcfs/osd_wbcfs
		fi
		load_module mgs/mgs
		load_module mdd/mdd
		load_module mdt/mdt
		load_module ost/ost 2>/dev/null || true;
		load_module lod/lod
		load_module ofd/ofd
		load_module osp/osp
	fi
	load_module llite/grumple
	[ -d /r ] && OGDB=${OGDB:-"/r/tmp"}
	OGDB=${OGDB:-$TMP}
	rm -f $OGDB/ogdb-$HOSTNAME
	$LCTL modules > $OGDB/ogdb-$HOSTNAME
	local mount_grumple=$LUSTRE/utils/mount.grumple
	if [ -f $mount_grumple ]; then
		local sbin_mount=$(readlink -f /sbin)/mount.grumple
		if grep -qw "$sbin_mount" /proc/mounts; then
			cmp -s $mount_grumple $sbin_mount || umount $sbin_mount
		fi
		if ! grep -qw "$sbin_mount" /proc/mounts; then
			[ ! -f "$sbin_mount" ] && touch "$sbin_mount"
			if [ ! -s "$sbin_mount" -a -w "$sbin_mount" ]; then
				cat <<- EOF > "$sbin_mount"
				echo "This $sbin_mount just a mountpoint." 1>&2
				echo "It is never supposed to be run." 1>&2
				logger -p emerg -- "using stub $sbin_mount $@"
				exit 1
				EOF
				chmod a+x $sbin_mount
			fi
			mount --bind $mount_grumple $sbin_mount ||
				error "can't bind $mount_grumple to $sbin_mount"
			[[ -e /sbin/.libs ]] ||
				ln -sf $LUSTRE/utils/.libs /sbin/.libs || true
		fi
	fi
}
load_modules () {
	local facets
	local facet
	local failover
	load_modules_local
	if $LOAD_MODULES_REMOTE; then
		local list=$(comma_list $(remote_nodes_list))
		facets=$(get_facets)
		for facet in ${facets//,/ }; do
			failover=$(facet_failover_host $facet)
			[ -n "$list" ] && [[ ! "$list" =~ "$failover" ]] &&
				list="$list,$failover"
		done
		if [ -n "$list" ]; then
			echo "loading modules on: '$list'"
			do_rpc_nodes "$list" load_modules_local
		fi
	fi
}
check_mem_leak () {
	LEAK_LUSTRE=$(dmesg | tail -n 30 | grep "obd_memory.*leaked" || true)
	LEAK_PORTALS=$(dmesg | tail -n 20 | egrep -i "libcfs.*memory leaked" ||
		true)
	if [ "$LEAK_LUSTRE" -o "$LEAK_PORTALS" ]; then
		echo "$LEAK_LUSTRE" 1>&2
		echo "$LEAK_PORTALS" 1>&2
		echo "Memory leaks detected"
		if [ $DEBUG -a -z $DEBUG_RMMOD ]; then
			debug_file=$TMP/debug-leak.$(date +%s)
			mv $TMP/debug $debug_file &&
			echo "Save $TMP/debug to $debug_file"
		fi
		[[ -n "$IGNORE_LEAK" ]] &&
			{ echo "ignoring leaks" && return 0; } || true
		return 1
	fi
}
unload_modules_local() {
	$LUSTRE_RMMOD ldiskfs || return 2
	[ -f /etc/udev/rules.d/99-grumple-test.rules ] &&
		rm /etc/udev/rules.d/99-grumple-test.rules
	udevadm control --reload-rules
	udevadm trigger
	check_mem_leak || return 254
	return 0
}
unload_modules() {
	local rc=0
	wait_exit_ST client
	unload_modules_local || rc=$?
	if $LOAD_MODULES_REMOTE; then
		local list=$(comma_list $(remote_nodes_list))
		if (( MDS1_VERSION >= $(version_code 2.15.51) )); then
			if [ -n "$list" ]; then
				echo "unloading modules via unload_modules_local on: '$list'"
				do_rpc_nodes "$list" unload_modules_local
			fi
		else
			if [ -n "$list" ]; then
				echo "unloading modules on: '$list'"
				do_rpc_nodes "$list" $LUSTRE_RMMOD ldiskfs
				do_rpc_nodes "$list" check_mem_leak
				do_rpc_nodes "$list" "rm -f /etc/udev/rules.d/99-grumple-test.rules"
				do_rpc_nodes "$list" "udevadm control --reload-rules"
				do_rpc_nodes "$list" "udevadm trigger"
			fi
		fi
	fi
	local sbin_mount=$(readlink -f /sbin)/mount.grumple
	if grep -qe "$sbin_mount " /proc/mounts; then
		umount $sbin_mount || true
		[ -s $sbin_mount ] && ! grep -q "STUB MARK" $sbin_mount ||
			rm -f $sbin_mount
	fi
	[ -L /sbin/.libs ] && rm /sbin/.libs
	[[ $rc -eq 0 ]] && echo "modules unloaded."
	return $rc
}
fs_log_size() {
	local facet=${1:-ost1}
	local size=0
	local mult=$OSTCOUNT
	case $(facet_fstype $facet) in
		ldiskfs) size=32;;
		zfs)     size=$(lctl get_param osc.$FSNAME*.import |
				awk '/grant_block_size:/ {print $2/512; exit;}')
			  ;;
	esac
	[[ $facet =~ mds ]] && mult=$MDTCOUNT
	echo -n $((size * mult))
}
fs_inode_ksize() {
	local facet=${1:-$SINGLEMDS}
	local fstype=$(facet_fstype $facet)
	local size=0
	case $fstype in
		ldiskfs) size=4;;
		zfs)     size=11;;
	esac
	echo -n $size
}
runas_su() {
	local user=$1
	local cmd=$2
	shift 2
	local opts="$*"
	if $VERBOSE; then
		echo Running as $user: $cmd $opts
	fi
	cmd=$(which $cmd)
	su - $user -c "$cmd $opts"
}
check_gss_daemon_nodes() {
	local list=$1
	local dname=$(basename "$2" | awk '{print $1}')
	local loopmax=10
	local loop
	local node
	local ret
	do_nodesv $list "num=0;
for proc in \\\$(pgrep $dname); do
[ \\\$(ps -o ppid= -p \\\$proc) -ne 1 ] || ((num++))
done;
if [ \\\"\\\$num\\\" -ne 1 ]; then
	echo \\\$num instance of $dname;
	exit 1;
fi; "
	ret=$?
	(( $ret == 0 )) || return $ret
	for node in ${list//,/ }; do
		loop=0
		while (( $loop < $loopmax )); do
			do_nodesv $node "$L_GETAUTH -d"
			ret=$?
			(( $ret == 0 )) && break
			loop=$((loop + 1))
			sleep 5
		done
		(( $loop < $loopmax )) || return 1
	done
	return 0
}
check_gss_daemon_facet() {
	local facet=$1
	local dname=$(basename "$2" | awk '{print $1}')
	local num=$(do_facet $facet ps -o cmd -C $dname | grep -c $dname)
	if (( $num != 1 )); then
		echo "$num instance of $dname on $facet"
		return 1
	fi
	return 0
}
send_sigint() {
	local list=$1
	shift
	echo "Stopping "$@" on $list"
	do_nodes $list "killall -2 $* 2>/dev/null || true"
}
start_gss_daemons() {
	local nodes=$1
	local daemon=$2
	local options=$3
	if [ "$nodes" ] && [ "$daemon" ] ; then
		echo "Starting gss daemon on nodes: $nodes"
		do_nodes $nodes "$daemon" "$options" || return 8
		check_gss_daemon_nodes $nodes "$daemon" || return 9
		return 0
	fi
	nodes=$(mdts_nodes)
	echo "Starting gss daemon on mds: $nodes"
	if $GSS_SK; then
		do_nodes $nodes "$LSVCGSSD -vvv -s -m -o -z $options" ||
			return 1
	else
		do_nodes $nodes "$LSVCGSSD -vvv $options" || return 1
	fi
	nodes=$(osts_nodes)
	echo "Starting gss daemon on ost: $nodes"
	if $GSS_SK; then
		do_nodes $nodes "$LSVCGSSD -vvv -s -m -o -z $options" ||
			return 3
	else
		do_nodes $nodes "$LSVCGSSD -vvv $options" || return 3
	fi
	local clients=${CLIENTS:-$HOSTNAME}
	check_gss_daemon_nodes $(tgts_nodes) "$LSVCGSSD" || return 5
}
stop_gss_daemons() {
	local nodes=$(mdts_nodes)
	send_sigint $nodes lsvcgssd lgssd
	nodes=$(osts_nodes)
	send_sigint $nodes lsvcgssd
	nodes=${CLIENTS:-$HOSTNAME}
	send_sigint $nodes lgssd
}
add_sk_mntflag() {
	local mt_opts=$@
	if grep -q skpath <<< "$mt_opts" ; then
		mt_opts=$(echo $mt_opts |
			sed -e "s
	else
		if [ -z "$mt_opts" ]; then
			mt_opts="-o skpath=$SK_PATH"
		else
			mt_opts="$mt_opts,skpath=$SK_PATH"
		fi
	fi
	echo -n $mt_opts
}
from_build_tree() {
	local from_tree
	case $LUSTRE in
	/usr/lib/grumple/* | /usr/lib64/grumple/* | /usr/lib/grumple | \
	/usr/lib64/grumple )
		from_tree=false
		;;
	*)
		from_tree=true
		;;
	esac
	[ $from_tree = true ]
}
init_gss() {
	local servers=$(all_server_nodes)
	if $SHARED_KEY; then
		GSS=true
		GSS_SK=true
	fi
	if ! $GSS; then
		return
	fi
	if ! module_loaded ptlrpc_gss; then
		load_module ptlrpc/gss/ptlrpc_gss
		module_loaded ptlrpc_gss ||
			error_exit "init_gss: GSS=$GSS, but gss/krb5 missing"
	fi
	if $GSS_KRB5 || $GSS_SK; then
		start_gss_daemons || error_exit "start gss daemon failed! rc=$?"
	fi
	if $GSS_SK && ! $SK_NO_KEY; then
		echo "Loading basic SSK keys on all servers"
		do_nodes $servers \
			"$LGSS_SK -t server -l $SK_PATH/$FSNAME.key || true"
		do_nodes $servers "keyctl show | grep grumple | cut -c1-11 |
				   sed -e 's/ //g;' |
				   xargs -IX keyctl setperm X 0x3f3f3f3f"
	fi
	if $GSS_SK && $SK_NO_KEY; then
		local numclients=${1:-$CLIENTCOUNT}
		local clients=${CLIENTS:-$HOSTNAME}
		local nodes=$(all_nodes)
		SK_NO_KEY=false
		local lgssc_conf_file="/etc/request-key.d/lgssc.conf"
		if from_build_tree; then
			mkdir -p $SK_OM_PATH
			if grep -q request-key /proc/mounts > /dev/null; then
				echo "SSK: Request key already mounted."
			else
				mount -o bind $SK_OM_PATH /etc/request-key.d/
			fi
			local lgssc_conf_line='create lgssc * * '
			lgssc_conf_line+=$(which lgss_keyring)
			lgssc_conf_line+=' %o %k %t %d %c %u %g %T %P %S'
			echo "$lgssc_conf_line" > $lgssc_conf_file
		fi
		[ -e $lgssc_conf_file ] ||
			error_exit "Could not find key opt in $lgssc_conf_file"
		echo "$lgssc_conf_file content is:"
		cat $lgssc_conf_file
		if ! local_mode; then
			if from_build_tree; then
				do_nodes $nodes "mkdir -p $SK_OM_PATH"
				do_nodes $nodes "mount -o bind $SK_OM_PATH \
						 /etc/request-key.d/"
				do_nodes $nodes \
					"rsync -aqv $HOSTNAME:$lgssc_conf_file \
					 $lgssc_conf_file >/dev/null 2>&1"
			else
				do_nodes $nodes "echo $lgssc_conf_file: ; \
						 cat $lgssc_conf_file"
			fi
		fi
		mkdir -p $SK_PATH/nodemap
		rm -f $SK_PATH/$FSNAME.key $SK_PATH/nodemap/c*.key \
			$SK_PATH/$FSNAME-*.key
		if $SK_S2S; then
			$LGSS_SK -t server -f$FSNAME -n $SK_S2SNMCLI \
				-w $SK_PATH/$FSNAME-nmclient.key \
				-d /dev/urandom >/dev/null 2>&1
			$LGSS_SK -t mgs,server -f$FSNAME -n $SK_S2SNM \
				-w $SK_PATH/$FSNAME-s2s-server.key \
				-d /dev/urandom >/dev/null 2>&1
		fi
		$LGSS_SK -t server -f$FSNAME -w $SK_PATH/$FSNAME.key \
			-d /dev/urandom >/dev/null 2>&1
		for ((i=0; i < $numclients; i++)); do
			$LGSS_SK -t server -f$FSNAME -n c$i \
				-w $SK_PATH/nodemap/c$i.key -d /dev/urandom \
				>/dev/null 2>&1
		done
		if ! local_mode; then
			for lnode in ${nodes//,/ }; do
				scp -r $SK_PATH ${lnode}:$(dirname $SK_PATH)/
			done
		fi
		if local_mode; then
			do_nodes $nodes "$LGSS_SK -t client,server -m \
				$SK_PATH/$FSNAME.key >/dev/null 2>&1"
		else
			do_nodes $clients "$LGSS_SK -t client -m \
				$SK_PATH/$FSNAME.key >/dev/null 2>&1"
			do_nodes $clients "find $SK_PATH/nodemap \
				-name \*.key | xargs -IX $LGSS_SK -t client \
				-m X >/dev/null 2>&1"
			do_nodes $servers \
			"cp $SK_PATH/$FSNAME.key $SK_PATH/${FSNAME}_cli.key && \
			 $LGSS_SK -t client -m \
				$SK_PATH/${FSNAME}_cli.key >/dev/null 2>&1"
		fi
		if $SK_S2S; then
			do_nodes $(tgts_nodes) \
				"cp $SK_PATH/$FSNAME-s2s-server.key \
				$SK_PATH/$FSNAME-s2s-client.key; $LGSS_SK \
				-t client -m $SK_PATH/$FSNAME-s2s-client.key \
				>/dev/null 2>&1"
			do_nodes $clients "$LGSS_SK -t client \
				-m $SK_PATH/$FSNAME-nmclient.key \
				 >/dev/null 2>&1"
		fi
	fi
	if $GSS_SK; then
		MGS_MOUNT_OPTS=$(add_sk_mntflag $MGS_MOUNT_OPTS)
		MDS_MOUNT_OPTS=$(add_sk_mntflag $MDS_MOUNT_OPTS)
		OST_MOUNT_OPTS=$(add_sk_mntflag $OST_MOUNT_OPTS)
		MOUNT_OPTS=$(add_sk_mntflag $MOUNT_OPTS)
		SEC=$SK_FLAVOR
		if [ -z "$LGSS_KEYRING_DEBUG" ]; then
			LGSS_KEYRING_DEBUG=4
		fi
	fi
	if [[ -n "$LGSS_KEYRING_DEBUG" ]] &&
	       ( local_mode || from_build_tree ); then
		$LCTL set_param -n \
		     sptlrpc.gss.lgss_keyring.debug_level=$LGSS_KEYRING_DEBUG
	elif [[ -n "$LGSS_KEYRING_DEBUG" ]]; then
		do_nodes $nodes "modprobe ptlrpc_gss && $LCTL set_param -n \
		   sptlrpc.gss.lgss_keyring.debug_level=$LGSS_KEYRING_DEBUG"
	fi
	do_nodesv $servers "$LCTL set_param sptlrpc.gss.rsi_upcall=$L_GETAUTH"
}
cleanup_gss() {
	if $GSS; then
		stop_gss_daemons
	fi
}
cleanup_sk() {
	if $GSS_SK; then
		if $SK_S2S; then
			do_node $(mgs_node) "$LCTL nodemap_del $SK_S2SNM"
			do_node $(mgs_node) "$LCTL nodemap_del $SK_S2SNMCLI"
			$RPC_MODE || echo "Sleeping for 10 sec for Nodemap.."
			sleep 10
		fi
		stop_gss_daemons
		$RPC_MODE || echo "Cleaning up Shared Key.."
		do_nodes $(comma_list $(all_nodes)) "rm -f \
			$SK_PATH/$FSNAME*.key $SK_PATH/nodemap/$FSNAME*.key"
		do_nodes $(comma_list $(all_nodes)) "keyctl show | \
		  awk '/grumple/ { print \\\$1 }' | xargs -IX keyctl unlink X"
		if from_build_tree; then
			do_nodes $(comma_list $(all_nodes)) "while grep -q \
				request-key.d /proc/mounts; do umount \
				/etc/request-key.d/; done"
			do_nodes $(comma_list $(all_nodes)) "rm -f \
				$SK_OM_PATH/lgssc.conf"
			do_nodes $(comma_list $(all_nodes)) "rmdir $SK_OM_PATH"
		fi
		SK_NO_KEY=true
	fi
}
facet_svc() {
	local facet=$1
	local var=${facet}_svc
	echo -n ${!var}
}
facet_type() {
	local facet=$1
	echo -n $facet | sed -e 's/^fs[0-9]\+//' -e 's/[0-9_]\+//' |
		tr '[:lower:]' '[:upper:]'
}
facet_number() {
	local facet=$1
	if [ $facet == mgs ] || [ $facet == client ]; then
		return 1
	fi
	echo -n $facet | sed -e 's/^fs[0-9]\+//' | sed -e 's/^[a-z]\+//'
}
facet_fstype() {
	local facet=$1
	local var
	var=${facet}_FSTYPE
	if [ -n "${!var}" ]; then
		echo -n ${!var}
		return
	fi
	var=$(facet_type $facet)FSTYPE
	if [ -n "${!var}" ]; then
		echo -n ${!var}
		return
	fi
	if [ -n "$FSTYPE" ]; then
		echo -n $FSTYPE
		return
	fi
	if [[ $facet == mgs ]] && combined_mgs_mds; then
		facet_fstype mds1
		return
	fi
	return 1
}
node_fstypes() {
	local node=$1
	local fstypes
	local fstype
	local facets=$(get_facets)
	local facet
	for facet in ${facets//,/ }; do
		if [[ $node == $(facet_host $facet) ]] ||
		   [[ $node == "$(facet_failover_host $facet)" ]]; then
			fstype=$(facet_fstype $facet)
			if [[ $fstypes != *$fstype* ]]; then
				fstypes+="${fstypes:+,}$fstype"
			fi
		fi
	done
	echo -n $fstypes
}
facet_index() {
	local facet=$1
	local num=$(facet_number $facet)
	local index
	if [[ $(facet_type $facet) = OST ]]; then
		index=OSTINDEX${num}
		if [[ -n "${!index}" ]]; then
			echo -n ${!index}
			return
		fi
		index=${OST_INDICES[num - 1]}
	fi
	[[ -n "$index" ]] || index=$((num - 1))
	echo -n $index
}
devicelabel() {
	local facet=$1
	local dev=$2
	local label
	local fstype=$(facet_fstype $facet)
	case $fstype in
	ldiskfs)
		label=$(do_facet ${facet} "$E2LABEL ${dev} 2>/dev/null");;
	zfs)
		label=$(do_facet ${facet} "$ZFS get -H -o value grumple:svname \
		                           ${dev} 2>/dev/null");;
	wbcfs)
		label="wbcfs-target";;
	*)
		error "unknown fstype!";;
	esac
	echo -n $label
}
facet_device() {
	local facet=$1
	local device
	case $facet in
		mgs) device=$(mgsdevname) ;;
		mds*) device=$(mdsdevname $(facet_number $facet)) ;;
		ost*) device=$(ostdevname $(facet_number $facet)) ;;
		fs2mds) device=$(mdsdevname 1_2) ;;
		fs2ost) device=$(ostdevname 1_2) ;;
		fs3ost) device=$(ostdevname 2_2) ;;
		*) ;;
	esac
	echo -n $device
}
facet_vdevice() {
	local facet=$1
	local device
	case $facet in
		mgs) device=$(mgsvdevname) ;;
		mds*) device=$(mdsvdevname $(facet_number $facet)) ;;
		ost*) device=$(ostvdevname $(facet_number $facet)) ;;
		fs2mds) device=$(mdsvdevname 1_2) ;;
		fs2ost) device=$(ostvdevname 1_2) ;;
		fs3ost) device=$(ostvdevname 2_2) ;;
		*) ;;
	esac
	echo -n $device
}
running_in_vm() {
	local virt=$(virt-what 2> /dev/null)
	[ $? -eq 0 ] && [ -n "$virt" ] && { echo $virt; return; }
	virt=$(dmidecode -s system-product-name | awk '{print $1}')
	case $virt in
		VMware|KVM|VirtualBox|Parallels|Bochs)
			echo $virt | tr '[A-Z]' '[a-z]' && return;;
		*) ;;
	esac
	virt=$(dmidecode -s system-manufacturer | awk '{print $1}')
	case $virt in
		QEMU)
			echo $virt | tr '[A-Z]' '[a-z]' && return;;
		*) ;;
	esac
}
refresh_partition_table() {
	local facet=$1
	local device=$2
	local host
	host=$(facet_passive_host $facet)
	if [[ -n "$host" ]]; then
		do_node $host "$PARTPROBE $device"
	fi
}
zpool_name() {
	local facet=$1
	local device
	local poolname
	device=$(facet_device $facet)
	poolname="${device%%/*}"
	echo -n $poolname
}
zfs_local_fsname() {
	local facet=$1
	local lfsname=$(basename $(facet_device $facet))
	echo -n $lfsname
}
create_zpool() {
	local facet=$1
	local poolname=$2
	local vdev=$3
	shift 3
	local opts=${@:-"-o cachefile=none"}
	do_facet $facet "lsmod | grep zfs >&/dev/null || modprobe zfs;
		$ZPOOL list -H $poolname >/dev/null 2>&1 ||
		$ZPOOL create -f $opts $poolname $vdev"
}
create_zfs() {
	local facet=$1
	local dataset=$2
	shift 2
	local opts=${@:-"-o mountpoint=legacy"}
	do_facet $facet "$ZFS list -H $dataset >/dev/null 2>&1 ||
		$ZFS create $opts $dataset"
}
export_zpool() {
	local facet=$1
	shift
	local opts="$@"
	local poolname
	poolname=$(zpool_name $facet)
	if [[ -n "$poolname" ]]; then
		do_facet $facet "! $ZPOOL list -H $poolname >/dev/null 2>&1 ||
			grep -q ^$poolname/ /proc/mounts ||
			$ZPOOL export $opts $poolname"
	fi
}
destroy_zpool() {
	local facet=$1
	local poolname=${2:-$(zpool_name $facet)}
	if [[ -n "$poolname" ]]; then
		do_facet $facet "! $ZPOOL list -H $poolname >/dev/null 2>&1 ||
			$ZPOOL destroy -f $poolname"
	fi
}
import_zpool() {
	local facet=$1
	shift
	local opts=${@:-"-o cachefile=none -o failmode=panic"}
	local poolname
	poolname=$(zpool_name $facet)
	if [[ -n "$poolname" ]]; then
		opts+=" -d $(dirname $(facet_vdevice $facet))"
		do_facet $facet "lsmod | grep zfs >&/dev/null || modprobe zfs;
			$ZPOOL list -H $poolname >/dev/null 2>&1 ||
			$ZPOOL import -f $opts $poolname"
	fi
}
reimport_zpool() {
	local facet=$1
	local newpool=$2
	local opts="-o cachefile=none"
	local poolname=$(zpool_name $facet)
	opts+=" -d $(dirname $(facet_vdevice $facet))"
	do_facet $facet "$ZPOOL export $poolname;
			 $ZPOOL import $opts $poolname $newpool"
}
disable_zpool_cache() {
	local facet=$1
	local poolname
	poolname=$(zpool_name $facet)
	if [[ -n "$poolname" ]]; then
		do_facet $facet "$ZPOOL set cachefile=none $poolname"
	fi
}
get_osd_param() {
	local nodes=$1
	local device=${2:-$FSNAME-OST*}
	local name=$3
	do_nodes $nodes "$LCTL get_param -n osd-*.$device.$name"
}
set_osd_param() {
	local nodes=$1
	local device=${2:-$FSNAME-OST*}
	local name=$3
	local value=$4
	do_nodes $nodes "$LCTL set_param -n osd-*.$device.$name=$value"
}
set_default_debug () {
	local debug=${1:-"$PTLDEBUG"}
	local subsys=${2:-"$SUBSYSTEM"}
	local debug_size=${3:-$DEBUG_SIZE}
	[ -n "$debug" ] && lctl set_param debug="$debug" >/dev/null
	[ -n "$subsys" ] &&
		lctl set_param subsystem_debug="${subsys
	[ -n "$debug_size" ] &&
		lctl set_param debug_mb="$debug_size" >/dev/null
	return 0
}
set_default_debug_nodes () {
	local nodes="$1"
	local debug="${2:-"$PTLDEBUG"}"
	local subsys="${3:-"$SUBSYSTEM"}"
	local debug_size="${4:-$DEBUG_SIZE}"
	if [[ ,$nodes, = *,$HOSTNAME,* ]]; then
		nodes=$(exclude_items_from_list "$nodes" "$HOSTNAME")
		set_default_debug
	fi
	[[ -z "$nodes" ]] ||
		do_rpc_nodes "$nodes" set_default_debug \
			\\\"$debug\\\" \\\"$subsys\\\" $debug_size || true
}
set_default_debug_facet () {
	local facet=$1
	local debug="${2:-"$PTLDEBUG"}"
	local subsys="${3:-"$SUBSYSTEM"}"
	local debug_size="${4:-$DEBUG_SIZE}"
	local node=$(facet_active_host $facet)
	[ -n "$node" ] || error "No host defined for facet $facet"
	set_default_debug_nodes $node "$debug" "$subsys" $debug_size
}
set_params_nodes() {
	(( $
	local nodes=$1
	shift || true
	local params="$@"
	[[ -n "$params" ]] || return 0
	do_nodes $nodes "$LCTL set_param $params"
}
set_params_clients() {
	local clients=${1:-$CLIENTS}
	shift || true
	local params="${@:-$CLIENT_LCTL_SETPARAM_PARAM}"
	set_params_nodes $clients $params
}
set_params_mdts() {
	local mdts=${1:-$(mdts_nodes)}
	shift || true
	local params="${@:-$MDS_LCTL_SETPARAM_PARAM}"
	set_params_nodes $mdts $params
}
set_params_osts() {
	local osts=${1:-$(osts_nodes)}
	shift || true
	local params="${@:-$OSS_LCTL_SETPARAM_PARAM}"
	set_params_nodes $osts $params
}
set_hostid () {
	local hostid=${1:-$(hostid)}
	if [ ! -s /etc/hostid ]; then
		printf $(echo -n $hostid |
	    sed 's/\(..\)\(..\)\(..\)\(..\)/\\x\4\\x\3\\x\2\\x\1/') >/etc/hostid
	fi
}
mount_facets () {
	local facets=${1:-$(get_facets)}
	local facet
	local -a mountpids
	local total=0
	local ret=0
	for facet in ${facets//,/ }; do
		mount_facet $facet &
		mountpids[total]=$!
		total=$((total+1))
	done
	for ((index=0; index<$total; index++)); do
		wait ${mountpids[index]}
		local RC=$?
		[ $RC -eq 0 ] && continue
		if [ "$TESTSUITE.$TESTNAME" = "replay-dual.test_0a" ]; then
			skip_noexit "Restart of $facet failed!." &&
				touch $LU482_FAILED
		else
			error "Restart of $facet failed!"
		fi
		ret=$RC
	done
	return $ret
}
csa_add() {
	local opts=$1
	local opt=$2
	local arg=$3
	local opt_pattern="\([[:space:]]\+\|^\)$opt"
	if echo "$opts" | grep -q $opt_pattern; then
		opts=$(echo "$opts" | sed -e \
			"s/$opt_pattern[[:space:]]*[^[:space:]]\+/&,$arg/")
	else
		opts+="${opts:+ }$opt $arg"
	fi
	echo -n "$opts"
}
setup_loop_device() {
	local facet=$1
	local file=$2
	do_facet $facet "loop_dev=\\\$($LOSETUP -j $file | cut -d : -f 1);
			 if [[ -z \\\$loop_dev ]]; then
				loop_dev=\\\$($LOSETUP -f);
				$LOSETUP \\\$loop_dev $file || loop_dev=;
			 fi;
			 echo -n \\\$loop_dev"
}
cleanup_loop_device() {
	local facet=$1
	local loop_dev=$2
	do_facet $facet "! $LOSETUP $loop_dev >/dev/null 2>&1 ||
			 $LOSETUP -d $loop_dev"
}
is_blkdev() {
	local facet=$1
	local dev=$2
	local size=${3:-""}
	[[ -n "$dev" ]] || return 1
	do_facet $facet "test -b $dev" || return 1
	if [[ -n "$size" ]]; then
		local in=$(do_facet $facet "dd if=$dev of=/dev/null bs=1k \
					    count=1 skip=$size 2>&1" |
					    awk '($3 == "in") { print $1 }')
		[[ "$in" = "1+0" ]] || return 1
	fi
}
is_dm_dev() {
	local facet=$1
	local dev=$2
	[[ -n "$dev" ]] || return 1
	do_facet $facet "$DMSETUP status $dev >/dev/null 2>&1"
}
is_dm_flakey_dev() {
	local facet=$1
	local dev=$2
	local type
	[[ -n "$dev" ]] || return 1
	type=$(do_facet $facet "$DMSETUP status $dev 2>&1" |
	       awk '{print $3}')
	[[ $type = flakey ]] && return 0 || return 1
}
dm_flakey_supported() {
	local facet=$1
	$FLAKEY || return 1
	do_facet $facet "modprobe dm-flakey;
			 $DMSETUP targets | grep -q flakey" &> /dev/null
}
dm_facet_devname() {
	local facet=$1
	[[ $facet = mgs ]] && combined_mgs_mds && facet=mds1
	echo -n ${facet}_flakey
}
dm_facet_devpath() {
	local facet=$1
	echo -n $DM_DEV_PATH/$(dm_facet_devname $facet)
}
dm_set_dev_table() {
	local facet=$1
	local dm_dev=$2
	local target_type=$3
	local num_sectors
	local real_dev
	local tmp
	local table
	read tmp num_sectors tmp real_dev tmp \
		<<< $(do_facet $facet "$DMSETUP table $dm_dev")
	case $target_type in
	flakey)
		table="0 $num_sectors flakey $real_dev 0 0 1800 1 drop_writes"
		;;
	linear)
		table="0 $num_sectors linear $real_dev 0"
		;;
	*) error "invalid target type $target_type" ;;
	esac
	do_facet $facet "$DMSETUP suspend --nolockfs --noflush $dm_dev" ||
		error "failed to suspend $dm_dev"
	do_facet $facet "$DMSETUP load $dm_dev --table \\\"$table\\\"" ||
		error "failed to load $target_type table into $dm_dev"
	do_facet $facet "$DMSETUP resume $dm_dev" ||
		error "failed to resume $dm_dev"
}
dm_set_dev_readonly() {
	local facet=$1
	local dm_dev=${2:-$(dm_facet_devpath $facet)}
	dm_set_dev_table $facet $dm_dev flakey
}
dm_clear_dev_readonly() {
	local facet=$1
	local dm_dev=${2:-$(dm_facet_devpath $facet)}
	dm_set_dev_table $facet $dm_dev linear
}
set_dev_readonly() {
	local facet=$1
	local svc=${facet}_svc
	if [[ $(facet_fstype $facet) = zfs ]] ||
	   ! dm_flakey_supported $facet; then
		do_facet $facet $LCTL --device ${!svc} readonly
	else
		dm_set_dev_readonly $facet
	fi
}
get_num_sectors() {
	local facet=$1
	local dev=$2
	local num_sectors
	num_sectors=$(do_facet $facet "blockdev --getsz $dev 2>/dev/null")
	[[ ${PIPESTATUS[0]} = 0 && -n "$num_sectors" ]] || num_sectors=0
	echo -n $num_sectors
}
dm_create_dev() {
	local facet=$1
	local real_dev=$2
	local dm_dev_name=${3:-$(dm_facet_devname $facet)}
	local dm_dev=$DM_DEV_PATH/$dm_dev_name
	if is_dm_dev $facet $dm_dev; then
		! is_dm_flakey_dev $facet $dm_dev ||
			dm_clear_dev_readonly $facet $dm_dev
		echo -n $dm_dev
		return 0
	fi
	is_blkdev $facet $real_dev ||
		real_dev=$(setup_loop_device $facet $real_dev)
	[[ -n "$real_dev" ]] || { echo -n $real_dev; return 2; }
	local num_sectors=$(get_num_sectors $facet $real_dev)
	local table="0 $num_sectors linear $real_dev 0"
	local rc=0
	do_facet $facet "$DMSETUP create $dm_dev_name --table \\\"$table\\\"" ||
		{ rc=${PIPESTATUS[0]}; dm_dev=; }
	do_facet $facet "$DMSETUP mknodes >/dev/null 2>&1"
	echo -n $dm_dev
	return $rc
}
facet_device_alias() {
	local facet=$1
	local dev_alias=$facet
	case $facet in
		fs2mds) dev_alias=mds1_2 ;;
		fs2ost) dev_alias=ost1_2 ;;
		fs3ost) dev_alias=ost2_2 ;;
		*) ;;
	esac
	echo -n $dev_alias
}
export_dm_dev() {
	local facet=$1
	local dm_dev=$2
	local active_facet=$(facet_active $facet)
	local dev_alias=$(facet_device_alias $active_facet)
	local dev_name=${dev_alias}_dev
	local dev=${!dev_name}
	if [[ $active_facet = $facet ]]; then
		local failover_dev=${dev_alias}failover_dev
		if [[ ${!failover_dev} = $dev ]]; then
			eval export ${failover_dev}_saved=$dev
			eval export ${failover_dev}=$dm_dev
		fi
	else
		dev_alias=$(facet_device_alias $facet)
		local facet_dev=${dev_alias}_dev
		if [[ ${!facet_dev} = $dev ]]; then
			eval export ${facet_dev}_saved=$dev
			eval export ${facet_dev}=$dm_dev
		fi
	fi
	eval export ${dev_name}_saved=$dev
	eval export ${dev_name}=$dm_dev
}
unexport_dm_dev() {
	local facet=$1
	[[ $facet = mgs ]] && combined_mgs_mds && facet=mds1
	local dev_alias=$(facet_device_alias $facet)
	local saved_dev=${dev_alias}_dev_saved
	[[ -z ${!saved_dev} ]] ||
		eval export ${dev_alias}_dev=${!saved_dev}
	saved_dev=${dev_alias}failover_dev_saved
	[[ -z ${!saved_dev} ]] ||
		eval export ${dev_alias}failover_dev=${!saved_dev}
}
dm_cleanup_dev() {
	local facet=$1
	local dm_dev=${2:-$(dm_facet_devpath $facet)}
	local major
	local minor
	is_dm_dev $facet $dm_dev || return 0
	read major minor <<< $(do_facet $facet "$DMSETUP table $dm_dev" |
		awk '{ print $4 }' | awk -F: '{ print $1" "$2 }')
	do_facet $facet "$DMSETUP remove $dm_dev"
	do_facet $facet "$DMSETUP mknodes >/dev/null 2>&1"
	unexport_dm_dev $facet
	[[ $major -ne 7 ]] || cleanup_loop_device $facet /dev/loop$minor
	do_facet $facet "modprobe -r dm-flakey" || true
}
mount_facet() {
	local facet=$1
	shift
	local active_facet=$(facet_active $facet)
	local dev_alias=$(facet_device_alias $active_facet)
	local dev=${dev_alias}_dev
	local opt=${facet}_opt
	local mntpt=$(facet_mntpt $facet)
	local opts="${!opt} $@"
	local fstype=$(facet_fstype $facet)
	local devicelabel
	local dm_dev=${!dev}
	local index=$(facet_index $facet)
	local node_type=$(facet_type $facet)
	[[ $dev == "mgsfailover_dev" ]] && combined_mgs_mds &&
		dev=mds1failover_dev
	module_loaded grumple || load_modules
	case $fstype in
	ldiskfs)
		if dm_flakey_supported $facet; then
			dm_dev=$(dm_create_dev $facet ${!dev})
			[[ -n "$dm_dev" ]] || dm_dev=${!dev}
		fi
		is_blkdev $facet $dm_dev || opts=$(csa_add "$opts" -o loop)
		devicelabel=$(do_facet ${facet} "$E2LABEL $dm_dev");;
	zfs)
		import_zpool $facet || return ${PIPESTATUS[0]}
		devicelabel=$(do_facet ${facet} "$ZFS get -H -o value \
						grumple:svname $dm_dev");;
	wbcfs)
		:;;
	*)
		error "unknown fstype!";;
	esac
	if [ -f $TMP/test-lu482-trigger ]; then
		RC=2
	else
		local seq_width=$(($OSTSEQWIDTH / $OSTCOUNT))
		(( $seq_width >= 16384 )) || seq_width=16384
		case $fstype in
		wbcfs)
			echo "Start ${facet}: $MOUNT_CMD -v grumple-wbcfs $mntpt"
			export OSD_WBC_FSNAME="$FSNAME"
			export OSD_WBC_INDEX="$index"
			export OSD_WBC_MGS_NID="$MGSNID"
			case $node_type in
			OST)
				export OSD_WBC_TGT_TYPE="OST"
				;;
			MDS)
				export OSD_WBC_TGT_TYPE="MDT"
				if (( $index == 0 )) &&
					[[ "$mds_HOST" == "$mgs_HOST" ]]; then
					export OSD_WBC_PRIMARY_MDT="1"
				else
					export OSD_WBC_PRIMARY_MDT="0"
				fi
				;;
			MGS)
				export OSD_WBC_TGT_TYPE="MGT"
				;;
			*)
				error "Unhandled node_type!"
			esac
			do_facet ${facet} "mkdir -p $mntpt; \
				 OSD_WBC_TGT_TYPE=$OSD_WBC_TGT_TYPE \
				 OSD_WBC_INDEX=$OSD_WBC_INDEX \
				 OSD_WBC_MGS_NID=$OSD_WBC_MGS_NID \
				 OSD_WBC_PRIMARY_MDT=$OSD_WBC_PRIMARY_MDT \
				 OSD_WBC_FSNAME=$OSD_WBC_FSNAME \
				 $MOUNT_CMD -v grumple-wbcfs $mntpt"
			;;
		*)
			echo "Start ${facet}: $MOUNT_CMD $opts $dm_dev $mntpt"
			do_facet ${facet} \
				"mkdir -p $mntpt; $MOUNT_CMD $opts $dm_dev $mntpt"
		esac
		RC=${PIPESTATUS[0]}
		if [[ ${facet} =~ ost ]] && [[ ! "$fstype" == "wbcfs" ]]; then
			do_facet ${facet} "$LCTL set_param \
				seq.cli-$(devicelabel $facet $dm_dev)-super.width=$seq_width"
		fi
	fi
	if [ $RC -ne 0 ]; then
		echo "Start of $dm_dev on ${facet} failed ${RC}"
		return $RC
	fi
	health=$(do_facet ${facet} "$LCTL get_param -n health_check")
	if [[ "$health" != "healthy" ]]; then
		error "$facet is in a unhealthy state, got: '$health'"
	fi
	set_default_debug_facet $facet
	if [[ $opts =~ .*nosvc.* ]]; then
		echo "Start $dm_dev without service"
	else
		case $fstype in
		ldiskfs)
			wait_update_facet ${facet} "$E2LABEL $dm_dev \
				2>/dev/null | grep -E ':[a-zA-Z]{3}[0-9]{4}'" \
				"" || error "$dm_dev failed to initialize!";;
		zfs)
			wait_update_facet ${facet} "$ZFS get -H -o value \
				grumple:svname $dm_dev 2>/dev/null | \
				grep -E ':[a-zA-Z]{3}[0-9]{4}'" "" ||
				error "$dm_dev failed to initialize!";;
		wbcfs)
			:;;
		*)
			error "unknown fstype!";;
		esac
	fi
	if [[ $devicelabel =~ (:[a-zA-Z]{3}[0-9]{4}) ]]; then
		echo "Commit the device label on ${!dev}"
		do_facet $facet "sync; sleep 1; sync"
	fi
	label=$(devicelabel ${facet} $dm_dev)
	[ -z "$label" ] && echo no label for $dm_dev && exit 1
	eval export ${facet}_svc=${label}
	echo Started ${label}
	export_dm_dev $facet $dm_dev
	return $RC
}
start() {
	local facet=$1
	shift
	local device=$1
	shift
	local dev_alias=$(facet_device_alias $facet)
	eval export ${dev_alias}_dev=${device}
	eval export ${facet}_opt=\"$*\"
	combined_mgs_mds && [[ ${dev_alias} == mds1 ]] &&
		eval export mgs_dev=${device}
	local varname=${dev_alias}failover_dev
	if [ -n "${!varname}" ] ; then
		eval export ${dev_alias}failover_dev=${!varname}
	else
		eval export ${dev_alias}failover_dev=$device
		combined_mgs_mds && [[ ${dev_alias} == mds1 ]] &&
			eval export mgsfailover_dev=${device}
	fi
	local mntpt=$(facet_mntpt $facet)
	do_facet ${facet} mkdir -p $mntpt
	eval export ${facet}_MOUNT=$mntpt
	mount_facet ${facet}
	RC=$?
	if [[ $RC == 0 && $facet == *ost* && $OSTDEVBASE == */tmp/* ]]; then
		varname="${facet}_FSTRIM"
		if [[ -z ${!varname} ]]; then
			if do_facet ${facet} "fstrim -v $mntpt"; then
				eval export $varname="yes"
			else
				eval export $varname="no"
			fi
		fi
	fi
	return $RC
}
stop() {
	local running
	local facet=$1
	shift
	local HOST=$(facet_active_host $facet)
	[[ -z $HOST ]] && echo stop: no host for $facet && return 0
	local mntpt=$(facet_mntpt $facet)
	running=$(do_facet ${facet} "grep -c $mntpt' ' /proc/mounts || true")
	if [ ${running} -ne 0 ]; then
		echo "Stopping $mntpt (opts:$*) on $HOST"
		do_facet ${facet} $UMOUNT "$@" $mntpt
	fi
	wait_exit_ST ${facet} || return ${PIPESTATUS[0]}
	if [[ $(facet_fstype $facet) == zfs ]]; then
		[ "$KEEP_ZPOOL" = "true" ] || export_zpool $facet
	elif dm_flakey_supported $facet; then
		local host=${facet}_HOST
		local failover_host=${facet}failover_HOST
		if [[ -n ${!failover_host} && ${!failover_host} != ${!host} ]]||
			$CLEANUP_DM_DEV || [[ $facet = fs* ]]; then
			dm_cleanup_dev $facet
		fi
	fi
}
mdt_quota_type() {
	local varsvc=${SINGLEMDS}_svc
	do_facet $SINGLEMDS $LCTL get_param -n \
		osd-$(facet_fstype $SINGLEMDS).${!varsvc}.quota_slave.enabled
}
ost_quota_type() {
	local varsvc=ost1_svc
	do_facet ost1 $LCTL get_param -n \
		osd-$(facet_fstype ost1).${!varsvc}.quota_slave.enabled
}
restore_quota() {
	for usr in $QUOTA_USERS; do
		echo "Setting up quota on $HOSTNAME:$MOUNT for $usr..."
		for type in u g; do
			cmd="$LFS setquota -$type $usr -b 0"
			cmd="$cmd -B 0 -i 0 -I 0 $MOUNT"
			echo "+ $cmd"
			eval $cmd || error "$cmd FAILED!"
		done
		echo "Quota settings for $usr : "
		$LFS quota -v -u $usr $MOUNT || true
	done
	if [ "$old_MDT_QUOTA_TYPE" ]; then
		if [[ $PERM_CMD == *"set_param -P"* ]]; then
			do_facet mgs $PERM_CMD \
				osd-*.$FSNAME-MDT*.quota_slave.enabled = \
				$old_MDT_QUOTA_TYPE
		else
			do_facet mgs $PERM_CMD \
				$FSNAME.quota.mdt=$old_MDT_QUOTA_TYPE
		fi
	fi
	if [ "$old_OST_QUOTA_TYPE" ]; then
		if [[ $PERM_CMD == *"set_param -P"* ]]; then
			do_facet mgs $PERM_CMD \
				osd-*.$FSNAME-OST*.quota_slave.enabled = \
				$old_OST_QUOTA_TYPE
		else
			do_facet mgs $LCTL conf_param \
				$FSNAME.quota.ost=$old_OST_QUOTA_TYPE
		fi
	fi
}
lfs_df() {
	$LFS df $* | sed -e 's/filesystem /filesystem_/'
	check_lfs_df_ret_val ${PIPESTATUS[0]}
}
mdt_free_inodes() {
	local index=$1
	local free_inodes
	local mdt_uuid
	if [ $index -eq -1 ]; then
		mdt_uuid="summary"
	else
		mdt_uuid=$(mdtuuid_from_index $index)
	fi
	free_inodes=$(lfs_df -i $MOUNT | grep $mdt_uuid | awk '{print $4}')
	echo $free_inodes
}
ost_dev_status() {
	local ost_idx=$1
	local mnt_pnt=${2:-$MOUNT}
	local opts=$3
	local ost_uuid
	ost_uuid=$(ostuuid_from_index $ost_idx $mnt_pnt)
	lfs_df $opts $mnt_pnt | awk '/'$ost_uuid'/ { print $7 }'
}
setup_quota(){
	local mntpt=$1
	local mdt_qtype=$(mdt_quota_type)
	local ost_qtype=$(ost_quota_type)
	echo "[HOST:$HOSTNAME] [old_mdt_qtype:$mdt_qtype]" \
		"[old_ost_qtype:$ost_qtype] [new_qtype:$QUOTA_TYPE]"
	export old_MDT_QUOTA_TYPE=$mdt_qtype
	export old_OST_QUOTA_TYPE=$ost_qtype
	if [[ $PERM_CMD == *"set_param -P"* ]]; then
		do_facet mgs $PERM_CMD \
			osd-*.$FSNAME-MDT*.quota_slave.enabled=$QUOTA_TYPE
		do_facet mgs $PERM_CMD \
			osd-*.$FSNAME-OST*.quota_slave.enabled=$QUOTA_TYPE
	else
		do_facet mgs $PERM_CMD $FSNAME.quota.mdt=$QUOTA_TYPE ||
			error "set mdt quota type failed"
		do_facet mgs $PERM_CMD $FSNAME.quota.ost=$QUOTA_TYPE ||
			error "set ost quota type failed"
	fi
	local quota_usrs=$QUOTA_USERS
	local disksz=$(lfs_df $mntpt | grep "summary" | awk '{print $2}')
	local blk_soft=$((disksz + 1024))
	local blk_hard=$((blk_soft + blk_soft / 20))
	local inodes=$(lfs_df -i $mntpt | grep "summary" | awk '{print $2}')
	local i_soft=$inodes
	local i_hard=$((i_soft + i_soft / 20))
	echo "Total disk size: $disksz  block-softlimit: $blk_soft" \
		"block-hardlimit: $blk_hard inode-softlimit: $i_soft" \
		"inode-hardlimit: $i_hard"
	local cmd
	for usr in $quota_usrs; do
		echo "Setting up quota on $HOSTNAME:$mntpt for $usr..."
		for type in u g; do
			cmd="$LFS setquota -$type $usr -b $blk_soft"
			cmd="$cmd -B $blk_hard -i $i_soft -I $i_hard $mntpt"
			echo "+ $cmd"
			eval $cmd || error "$cmd FAILED!"
		done
		echo "Quota settings for $usr : "
		$LFS quota -v -u $usr $mntpt || true
	done
}
zconf_mount() {
	local client=$1
	local mnt=$2
	local opts=${3:-$MOUNT_OPTS}
	opts=${opts:+-o $opts}
	local flags=${4:-$MOUNT_FLAGS}
	local device=$MGSNID:/$FSNAME$FILESET
	if [ -z "$mnt" -o -z "$FSNAME" ]; then
		echo "Bad mount command: opt=$flags $opts dev=$device " \
		     "mnt=$mnt"
		exit 1
	fi
	if $GSS_SK; then
		opts=$(add_sk_mntflag $opts)
	fi
	echo "Starting client: $client: $flags $opts $device $mnt"
	do_node $client mkdir -p $mnt
	if [ -n "$FILESET" -a -z "$SKIP_FILESET" ];then
		do_node $client $MOUNT_CMD $flags $opts $MGSNID:/$FSNAME \
			$mnt || return $?
		do_nodes $client lctl get_param -n \
			mdc.$FSNAME-MDT0000*.import | grep -q subtree ||
				device=$MGSNID:/$FSNAME
		do_node $client "! grep -q $mnt' ' /proc/mounts ||
			umount $mnt"
	fi
	if $GSS_SK && ($SK_UNIQUE_NM || $SK_S2S); then
		local mountkey=$SK_PATH/$FSNAME-nmclient.key
		if $SK_UNIQUE_NM; then
			mountkey=$SK_PATH/nodemap/c0.key
		fi
		local prunedopts=$(echo $opts |
				sed -e "s
		do_node $client $MOUNT_CMD $flags $prunedopts $device $mnt ||
				return $?
	else
		do_node $client $MOUNT_CMD $flags $opts $device $mnt ||
				return $?
	fi
	set_default_debug_nodes $client
	set_params_clients $client
	return 0
}
zconf_umount() {
	local client=$1
	local mnt=$2
	local force
	local busy
	local need_kill
	local running=$(do_node $client "grep -c $mnt' ' /proc/mounts") || true
	[ "$3" ] && force=-f
	[ $running -eq 0 ] && return 0
	echo "Stopping client $client $mnt (opts:$force)"
	do_node $client lsof -t $mnt || need_kill=no
	if [ "x$force" != "x" ] && [ "x$need_kill" != "xno" ]; then
		pids=$(do_node $client lsof -t $mnt | sort -u);
		if [ -n "$pids" ]; then
			do_node $client kill -9 $pids || true
		fi
	fi
	busy=$(do_node $client "umount $force $mnt 2>&1" | grep -c "busy") ||
		true
	if [ $busy -ne 0 ] ; then
		echo "$mnt is still busy, wait one second" && sleep 1
		do_node $client umount $force $mnt
	fi
}
mount_mds_client() {
	local host=$(facet_active_host $SINGLEMDS)
	echo $host
	zconf_mount $host $MOUNT2 $MOUNT_OPTS ||
		error "unable to mount $MOUNT2 on $host with ($?)"
}
umount_mds_client() {
	local host=$(facet_active_host $SINGLEMDS)
	zconf_umount $host $MOUNT2
	do_facet $SINGLEMDS "rmdir $MOUNT2"
}
sanity_mount_check_nodes () {
	local nodes=$1
	shift
	local mnts="$@"
	local mnt
	[ "$(uname)" = Linux ] || return 0
	local rc=0
	for mnt in $mnts ; do
		do_nodes $nodes "running=\\\$(grep -c $mnt' ' /proc/mounts);
mpts=\\\$(mount | grep -c $mnt' ');
if [ \\\$running -ne \\\$mpts ]; then
	echo \\\$(hostname) env are INSANE!;
	exit 1;
fi"
		[ $? -eq 0 ] || rc=1
	done
	return $rc
}
sanity_mount_check_servers () {
	[ -n "$CLIENTONLY" ] &&
		{ echo "CLIENTONLY mode, skip mount_check_servers"; return 0; } || true
	echo Checking servers environments
	local facets="$(get_facets OST),$(get_facets MDS),mgs"
	local node
	local mntpt
	local facet
	for facet in ${facets//,/ }; do
	node=$(facet_host ${facet})
	mntpt=$(facet_mntpt $facet)
	sanity_mount_check_nodes $node $mntpt ||
		{ error "server $node environments are insane!"; return 1; }
	done
}
sanity_mount_check_clients () {
	local clients=${1:-$CLIENTS}
	local mntpt=${2:-$MOUNT}
	local mntpt2=${3:-$MOUNT2}
	[ -z $clients ] && clients=$(hostname)
	echo Checking clients $clients environments
	sanity_mount_check_nodes $clients $mntpt $mntpt2 ||
		error "clients environments are insane!"
}
sanity_mount_check () {
	sanity_mount_check_servers || return 1
	sanity_mount_check_clients || return 2
}
zconf_mount_clients() {
	local clients=$1
	local mnt=$2
	local opts=${3:-$MOUNT_OPTS}
	opts=${opts:+-o $opts}
	local flags=${4:-$MOUNT_FLAGS}
	local device=$MGSNID:/$FSNAME$FILESET
	if [ -z "$mnt" -o -z "$FSNAME" ]; then
		echo "Bad conf mount command: opt=$flags $opts dev=$device mnt=$mnt"
		exit 1
	fi
	echo "Starting client $clients: $flags $opts $device $mnt"
	do_nodes $clients mkdir -p $mnt
	if [[ -n $FILESET ]]; then
		(( MDS1_VERSION >= $(version_code 2.9.0) )) &&
			[[ -z $SKIP_FILESET ]] ||
				device=$MGSNID:/$FSNAME
	fi
	if $GSS_SK; then
		opts=$(add_sk_mntflag $opts)
	fi
	for nmclient in ${clients//,/ }; do
		local i=0
		if $GSS_SK && ($SK_UNIQUE_NM || $SK_S2S); then
			do_nodes $(comma_list $(all_server_nodes)) \
				"$LGSS_SK -t server -l $SK_PATH/nodemap/c$i.key"
			do_nodes $(comma_list $(all_server_nodes)) \
				"keyctl show | grep grumple | cut -c1-11 |
				sed -e 's/ //g;' |
				xargs -IX keyctl setperm X 0x3f3f3f3f"
			do_nodes $(comma_list $(all_server_nodes)) \
				"keyctl show"
			local mountkey=$SK_PATH/$FSNAME-nmclient.key
			if $SK_UNIQUE_NM; then
				mountkey=$SK_PATH/nodemap/c$i.key
			fi
			opts=$(echo $opts | sed -e \
				"s
		fi
		do_node $nmclient "
			running=\\\$(mount | grep -c $mnt' ');
			rc=0;
			if [ \\\$running -eq 0 ] ; then
				echo Mount client \\\$(hostname): $MOUNT_CMD $flags $opts $device $mnt
				$MOUNT_CMD $flags $opts $device $mnt;
				rc=\\\$?;
			fi;
			exit \\\$rc" || return ${PIPESTATUS[0]}
		i=$((i + 1))
	done
	echo "Started clients $clients: "
	do_nodes $clients "mount | grep $mnt' '"
	set_default_debug_nodes $clients
	set_params_clients $clients
	return 0
}
zconf_umount_clients() {
	local clients=$1
	local mnt=$2
	local force
	[ "$3" ] && force=-f
	echo "Stopping clients: $clients $mnt (opts:$force)"
	do_nodes $clients "running=\\\$(grep -c $mnt' ' /proc/mounts);
if [ \\\$running -ne 0 ] ; then
echo Stopping client \\\$(hostname) $mnt opts:$force;
lsof $mnt || need_kill=no;
if [ "x$force" != "x" -a "x\\\$need_kill" != "xno" ]; then
	pids=\\\$(lsof -t $mnt | sort -u);
	if [ -n \\\"\\\$pids\\\" ]; then
		kill -9 \\\$pids;
	fi
fi;
while umount $force $mnt 2>&1 | grep -q "busy"; do
	echo "$mnt is still busy, wait one second" && sleep 1;
done;
fi"
}
shutdown_node () {
	local node=$1
	echo + $POWER_DOWN $node
	$POWER_DOWN $node
}
shutdown_node_hard () {
	local host=$1
	local attempts=$SHUTDOWN_ATTEMPTS
	for i in $(seq $attempts) ; do
		shutdown_node $host
		sleep 1
		wait_for_function --quiet "! ping -w 3 -c 1 $host" 5 1 &&
			return 0
		echo "waiting for $host to fail attempts=$attempts"
		[ $i -lt $attempts ] ||
			{ echo "$host still pingable after power down! attempts=$attempts" && return 1; }
	done
}
shutdown_client() {
	local client=$1
	local mnt=${2:-$MOUNT}
	local attempts=3
	if [ "$FAILURE_MODE" = HARD ]; then
		shutdown_node_hard $client
	else
		zconf_umount_clients $client $mnt -f
	fi
}
facets_on_host () {
	local affected
	local host=$1
	local facets="$(get_facets OST),$(get_facets MDS)"
	combined_mgs_mds || facets="$facets,mgs"
	for facet in ${facets//,/ }; do
		if [ $(facet_active_host $facet) == $host ]; then
			affected="$affected $facet"
		fi
	done
	echo $(comma_list $affected)
}
facet_up() {
	local facet=$1
	local host=${2:-$(facet_host $facet)}
	local label=$(convert_facet2label $facet)
	do_node $host $LCTL dl | awk '{ print $4 }' | grep -q "^$label\$"
}
facets_up_on_host () {
	local affected_up
	local host=$1
	local facets=$(facets_on_host $host)
	for facet in ${facets//,/ }; do
		if $(facet_up $facet $host); then
			affected_up="$affected_up $facet"
		fi
	done
	echo $(comma_list $affected_up)
}
shutdown_facet() {
	local facet=$1
	local affected_facet
	local affected_facets
	if [[ "$FAILURE_MODE" = HARD ]]; then
		if [[ $(facet_fstype $facet) = ldiskfs ]] &&
			dm_flakey_supported $facet; then
			affected_facets=$(affected_facets $facet)
			for affected_facet in ${affected_facets//,/ }; do
				unexport_dm_dev $affected_facet
			done
		fi
		shutdown_node_hard $(facet_active_host $facet)
	else
		stop $facet
	fi
}
reboot_node() {
	local node=$1
	echo + $POWER_UP $node
	$POWER_UP $node
}
remount_facet() {
	local facet=$1
	stop $facet
	mount_facet $@
}
reboot_facet() {
	local facet=$1
	local node=$(facet_active_host $facet)
	local sleep_time=${2:-10}
	if [ "$FAILURE_MODE" = HARD ]; then
		boot_node $node
	else
		sleep $sleep_time
	fi
}
boot_node() {
	local node=$1
	if [ "$FAILURE_MODE" = HARD ]; then
		reboot_node $node
		wait_for_host $node
		if $LOAD_MODULES_REMOTE; then
			echo "loading modules on $node: $facet"
			do_rpc_nodes $node load_modules_local
		fi
	fi
}
facets_hosts () {
	local hosts
	local facets=$1
	for facet in ${facets//,/ }; do
		hosts=$(expand_list $hosts $(facet_active_host $facet))
	done
	echo $hosts
}
_check_progs_installed () {
	local progs=$@
	local rc=0
	for prog in $progs; do
		if ! [ "$(which $prog)"  -o  "${!prog}" ]; then
			echo $prog missing on $(hostname)
			rc=1
		fi
	done
	return $rc
}
check_progs_installed () {
	local nodes=$1
	shift
	do_rpc_nodes "$nodes" _check_progs_installed "$@"
}
node_var_name() {
	echo __$(echo $1 | tr '-' '_' | tr '.' '_')
}
start_client_load() {
	local client=$1
	local load=$2
	local var=$(node_var_name $client)_load
	eval export ${var}=$load
	do_node $client "PATH=$PATH MOUNT=$MOUNT ERRORS_OK=$ERRORS_OK \
			END_RUN_FILE=$END_RUN_FILE \
			LOAD_PID_FILE=$LOAD_PID_FILE \
			TESTLOG_PREFIX=$TESTLOG_PREFIX \
			TESTNAME=$TESTNAME \
			DBENCH_LIB=$DBENCH_LIB \
			DBENCH_SRC=$DBENCH_SRC \
			CLIENT_COUNT=$((CLIENTCOUNT - 1)) \
			RECOVERY_SCALE_ENABLE_REMOTE_DIRS=$RECOVERY_SCALE_ENABLE_REMOTE_DIRS \
			RECOVERY_SCALE_ENABLE_STRIPED_DIRS=$RECOVERY_SCALE_ENABLE_STRIPED_DIRS \
			LFS=$LFS \
			LCTL=$LCTL \
			FSNAME=$FSNAME \
			MPI_USER=$MPI_USER \
			MPIRUN=$MPIRUN \
			MPIRUN_OPTIONS=\\\"$MPIRUN_OPTIONS\\\" \
			MACHINEFILE_OPTION=\\\"$MACHINEFILE_OPTION\\\" \
			num_clients=$(get_node_count ${CLIENTS//,/ }) \
			ior_THREADS=$ior_THREADS ior_iteration=$ior_iteration \
			ior_blockSize=$ior_blockSize \
			ior_blockUnit=$ior_blockUnit \
			ior_xferSize=$ior_xferSize ior_type=$ior_type \
			ior_DURATION=$ior_DURATION \
			ior_stripe_params=\\\"$ior_stripe_params\\\" \
			ior_custom_params=\\\"$ior_custom_param\\\" \
			mpi_ior_custom_threads=$mpi_ior_custom_threads \
			run_${load}.sh" &
	local ppid=$!
	log "Started client load: ${load} on $client"
	local pids=$(ps --ppid $ppid -o pid= | xargs)
	CLIENT_LOAD_PIDS="$CLIENT_LOAD_PIDS $ppid $pids"
	return 0
}
start_client_loads () {
	local -a clients=(${1//,/ })
	local numloads=${
	for ((nodenum=0; nodenum < ${
		local load=$((nodenum % numloads))
		start_client_load ${clients[nodenum]} ${CLIENT_LOADS[load]}
	done
	sleep 2
}
check_client_load () {
	local client=$1
	local var=$(node_var_name $client)_load
	local testload=run_${!var}.sh
	ps auxww | grep -v grep | grep $client | grep -q $testload || return 1
	local tries=3
	local RC=254
	while [ $RC = 254 -a $tries -gt 0 ]; do
		let tries=$tries-1
		RC=0
		if ! check_node_health $client; then
			RC=${PIPESTATUS[0]}
			if [ $RC -eq 254 ]; then
				sleep 10
				continue
			fi
			echo "check node health failed: RC=$RC "
			return $RC
		fi
	done
	if [ $RC = 254 ]; then
		echo "got a return status of $RC from do_node while checking " \
		"node health on $client"
	fi
	tries=3
	RC=254
	while [ $RC = 254 -a $tries -gt 0 ]; do
		let tries=$tries-1
		RC=0
		if ! do_node $client \
			"ps auxwww | grep -v grep | grep -q $testload"; then
			RC=${PIPESTATUS[0]}
			sleep 30
		fi
	done
	if [ $RC = 254 ]; then
		echo "got a return status of $RC from do_node while checking " \
		"(node health and 'ps') the client load on $client"
	fi
	return $RC
}
check_client_loads () {
	local clients=${1//,/ }
	local client=
	local rc=0
	for client in $clients; do
		check_client_load $client
		rc=${PIPESTATUS[0]}
		if [ "$rc" != 0 ]; then
			log "Client load failed on node $client, rc=$rc"
			return $rc
		fi
	done
}
restart_client_loads () {
	local clients=${1//,/ }
	local expectedfail=${2:-""}
	local client=
	local rc=0
	for client in $clients; do
		check_client_load $client
		rc=${PIPESTATUS[0]}
		if [ "$rc" != 0 -a "$expectedfail" ]; then
			local var=$(node_var_name $client)_load
			start_client_load $client ${!var}
			echo "Restarted client load ${!var}: on $client. Checking ..."
			check_client_load $client
			rc=${PIPESTATUS[0]}
			if [ "$rc" != 0 ]; then
				log "Client load failed to restart on node $client, rc=$rc"
				return $rc
			fi
		else
			return $rc
		fi
	done
}
start_vmstat() {
	local nodes=$1
	local pid_file=$2
	[ -z "$nodes" -o -z "$pid_file" ] && return 0
	do_nodes $nodes \
	    "vmstat 1 > $TESTLOG_PREFIX.$TESTNAME.vmstat.\\\$(hostname -s).log \
	     2>/dev/null </dev/null & echo \\\$! > $pid_file"
}
print_end_run_file() {
	local file=$1
	local node
	[ -s $file ] || return 0
	echo "Found the END_RUN_FILE file: $file"
	cat $file
	read node < $file
	if [ -n "$node" ]; then
		local var=$(node_var_name $node)_load
		local prefix=$TESTLOG_PREFIX
		[ -n "$TESTNAME" ] && prefix=$prefix.$TESTNAME
		local stdout_log=$prefix.run_${!var}_stdout.$node.log
		local debug_log=$(echo $stdout_log |
			sed 's/\(.*\)stdout/\1debug/')
		echo "Client load ${!var} failed on node $node:"
		echo "$stdout_log"
		echo "$debug_log"
	fi
}
stop_process() {
	local nodes=$1
	local pid_file=$2
	[ -z "$nodes" -o -z "$pid_file" ] && return 0
	do_nodes $nodes "test -f $pid_file &&
		{ kill -s TERM \\\$(cat $pid_file); rm -f $pid_file; }" || true
}
stop_client_loads() {
	local nodes=${1:-$CLIENTS}
	local pid_file=$2
	stop_process $nodes $pid_file
	[ -n "$CLIENT_LOAD_PIDS" ] &&
		kill -9 $CLIENT_LOAD_PIDS 2>/dev/null || true
}
wait_update_cond() {
	local verbose
	local quiet
	[[ "$1" == "--verbose" ]] && verbose="$1" && shift || true
	[[ "$1" == "--quiet" || "$1" == "-q" ]] && quiet="$1" && shift || true
	local node=$1
	local check="$2"
	local cond="$3"
	local expect="$4"
	local max_wait=${5:-90}
	local result
	local prev_result
	local waited=0
	local begin=$SECONDS
	local sleep=1
	local print=10
	while (( $waited <= $max_wait )); do
		result=$(do_node $quiet $node "$check")
		if eval [[ "'$result'" $cond "'$expect'" ]]; then
			[[ -z "$quiet" ]] || return 0
			[[ -z "$result" || $waited -le $sleep ]] ||
				echo "Updated after ${waited}s: want '$expect' got '$result'"
			return 0
		fi
		if [[ -n "$verbose" && "$result" != "$prev_result" ]]; then
			[[ -n "$quiet" || -z "$prev_result" ]] ||
				echo "Changed after ${waited}s: from '$prev_result' to '$result'"
			prev_result="$result"
		fi
		(( $waited % $print != 0 )) || {
			[[ -z "$quiet" ]] &&
			echo "Waiting $((max_wait - waited))s for '$expect'"
		}
		sleep $sleep
		waited=$((SECONDS - begin))
	done
	[[ -n "$quiet" ]] ||
	echo "Update not seen after ${max_wait}s: want '$expect' got '$result'"
	return 3
}
wait_update() {
	local verbose
	local quiet
	[[ "$1" == "--verbose" ]] && verbose="$1" && shift || true
	[[ "$1" == "--quiet" || "$1" == "-q" ]] && quiet="$1" && shift || true
	local node="$1"
	local check="$2"
	local expect="$3"
	local max_wait=$4
	wait_update_cond $verbose $quiet $node "$check" "==" "$expect" $max_wait
}
wait_update_facet_cond() {
	local verbose
	local quiet
	[[ "$1" == "--verbose" ]] && verbose="$1" && shift
	[[ "$1" == "--quiet" || "$1" == "-q" ]] && quiet="$1" && shift
	local node=$(facet_active_host $1)
	local check="$2"
	local cond="$3"
	local expect="$4"
	local max_wait=$5
	wait_update_cond $verbose $quiet $node "$check" "$cond" "$expect" $max_wait
}
wait_update_facet() {
	local verbose
	local quiet
	[[ "$1" == "--verbose" ]] && verbose="$1" && shift
	[[ "$1" == "--quiet" || "$1" == "-q" ]] && quiet="$1" && shift
	local node=$(facet_active_host $1)
	local check="$2"
	local expect="$3"
	local max_wait=$4
	wait_update_cond $verbose $quiet $node "$check" "==" "$expect" $max_wait
}
sync_all_data_mdts() {
	do_nodes $(mdts_nodes) "lctl set_param -n os[cd]*.*MDT*.force_sync=1"
}
sync_all_data_osts() {
	do_nodes $(osts_nodes) "lctl set_param -n osd*.*OS*.force_sync=1" 2>&1 |
		grep -v 'Found no match'
}
sync_all_data() {
	sync_all_data_mdts
	sync_all_data_osts
}
wait_zfs_commit() {
	local zfs_wait=${2:-5}
	if [[ $(facet_fstype $1) == zfs ]]; then
		echo "sleep $zfs_wait for ZFS $(facet_type $1)"
		sleep $zfs_wait
	fi
}
fill_ost() {
	local filename=$1
	local ost_idx=$2
	local lwm=$3
	local size_mb
	local ost_name=$(ostname_from_index $ost_idx)
	free_kb=$($LFS df $MOUNT | awk "/$ost_name/ { print \$4 }")
	size_mb=0
	if (( $free_kb / 1024 > lwm )); then
		size_mb=$((free_kb / 1024 - lwm))
	fi
	if (( $free_kb / 10240 > size_mb )); then
		size_mb=$((free_kb / 10240))
	else
		size_mb=$((size_mb + size_mb / 10))
	fi
	if (( lwm <= $free_kb / 1024 )) ||
	   [ ! -f $DIR/${filename}.fill_ost$ost_idx ]; then
		$LFS setstripe -i $ost_idx -c1 $DIR/${filename}.fill_ost$ost_idx
		$DD of=$DIR/${filename}.fill_ost$ost_idx \
			count=$size_mb oflag=append conv=notrunc
	fi
	sleep_maxage
	free_kb=$($LFS df $MOUNT | awk "/$ost_name/ { print \$4 }")
	echo "OST still has $((free_kb / 1024)) MB free"
}
ost_watermarks_get() {
	local ost_idx=$1
	local ost_name=$(ostname_from_index $ost_idx)
	local mdtosc_proc=$(get_mdtosc_proc_path $SINGLEMDS $ost_name)
	local hwm=$(do_facet $SINGLEMDS $LCTL get_param -n \
			osp.$mdtosc_proc.reserved_mb_high)
	local lwm=$(do_facet $SINGLEMDS $LCTL get_param -n \
			osp.$mdtosc_proc.reserved_mb_low)
	echo "$lwm $hwm"
}
ost_watermarks_set() {
	local ost_idx=$1
	local lwm=$2
	local hwm=$3
	local ost_name=$(ostname_from_index $ost_idx)
	local facets=$(get_facets MDS)
	do_nodes $(mdts_nodes) $LCTL set_param -n \
		osp.*$ost_name*.reserved_mb_low=$lwm \
		osp.*$ost_name*.reserved_mb_high=$hwm > /dev/null
	sleep_maxage
}
ost_watermarks_set_low_space() {
	local ost_idx=$1
	local wms=$(ost_watermarks_get $ost_idx)
	local ost_name=$(ostname_from_index $ost_idx)
	local old_lwm=$(echo $wms | awk '{ print $1 }')
	local old_hwm=$(echo $wms | awk '{ print $2 }')
	local blocks=$($LFS df $MOUNT | awk "/$ost_name/ { print \$4 }")
	local new_lwm=50
	if (( $blocks / 1024 > 50 )); then
		new_lwm=$((blocks / 1024 - 50))
	fi
	local new_hwm=$((new_lwm + 5))
	ost_watermarks_set $ost_idx $new_lwm $new_hwm
	echo "watermarks: $old_lwm $old_hwm $new_lwm $new_hwm"
}
ost_watermarks_set_enospc() {
	local filename=$1
	local ost_idx=$2
	local ost_name=$(ostname_from_index $ost_idx)
	local facets=$(get_facets MDS)
	local wms
	local MDS
	for MDS in ${facets//,/ }; do
		local mdtosc_proc=$(get_mdtosc_proc_path $MDS $ost_name)
		do_facet $MDS $LCTL get_param -n \
			osp.$mdtosc_proc.reserved_mb_high ||
			skip  "remote MDS does not support reserved_mb_high"
	done
	wms=$(ost_watermarks_set_low_space $ost_idx)
	local new_lwm=$(echo $wms | awk '{ print $4 }')
	fill_ost $filename $ost_idx $new_lwm
	fill_ost $filename $ost_idx $new_lwm
	echo $wms
}
ost_watermarks_enospc_delete_files() {
	local filename=$1
	local ost_idx=$2
	rm -f $DIR/${filename}.fill_ost$ost_idx
	wait_delete_completed
	wait_mds_ost_sync
}
ost_watermarks_clear_enospc() {
	local filename=$1
	local ost_idx=$2
	local old_lwm=$4
	local old_hwm=$5
	ost_watermarks_enospc_delete_files $filename $ost_idx
	ost_watermarks_set $ost_idx $old_lwm $old_hwm
	echo "set OST$ost_idx lwm back to $old_lwm, hwm back to $old_hwm"
}
wait_delete_completed_mds() {
	local max_wait=${1:-60}
	local mds2sync=""
	local stime=$(date +%s)
	local etime
	local node
	local changes
	local mdts=$(mdts_nodes)
	for node in ${mdts//,/ }; do
		changes=$(do_node $node "$LCTL get_param -n osc.*MDT*.sync_*" \
			2>/dev/null | calc_sum)
		if [[ $changes -eq 0 ]]; then
			continue
		fi
		mds2sync="$mds2sync $node"
	done
	if [ -z "$mds2sync" ]; then
		wait_zfs_commit $SINGLEMDS
		return 0
	fi
	mds2sync=$(comma_list $mds2sync)
	do_nodes $mds2sync "$LCTL set_param -n os[cd]*.*MD*.force_sync 1"
	local WAIT=0
	while [[ $WAIT -ne $max_wait ]]; do
		changes=$(do_nodes $mds2sync \
			"$LCTL get_param -n osc.*MDT*.sync_*" | calc_sum)
		if [[ $changes -eq 0 ]]; then
			wait_zfs_commit $SINGLEMDS
			wait_zfs_commit ost1
			return 0
		fi
		sleep 1
		WAIT=$((WAIT + 1))
	done
	etime=$(date +%s)
	echo "Delete is not completed in $((etime - stime)) seconds"
	do_nodes $mds2sync "$LCTL get_param osc.*MDT*.sync_*"
	return 1
}
wait_for_host() {
	local hostlist=$1
	for host in ${hostlist//,/ }; do
		check_network "$host" 900
	done
	while ! do_nodes $hostlist hostname; do sleep 5; done
}
wait_for_facet() {
	local facetlist=$1
	local hostlist
	for facet in ${facetlist//,/ }; do
		hostlist=$(expand_list $hostlist $(facet_active_host $facet))
	done
	wait_for_host $hostlist
}
_wait_recovery_complete () {
	local param=$1
	local MAX=${2:-$(max_recovery_time)}
	local WAIT=0
	local STATUS=
	while [ $WAIT -lt $MAX ]; do
		STATUS=$(lctl get_param -n $param | grep status)
		echo $param $STATUS
		[[ $STATUS == "status: COMPLETE" ||
			$STATUS == "status: INACTIVE" ]] && return 0
		sleep 5
		WAIT=$((WAIT + 5))
		echo "Waiting $((MAX - WAIT)) secs for $param recovery done. $STATUS"
	done
	echo "$param recovery not done in $MAX sec. $STATUS"
	return 1
}
wait_recovery_complete () {
	local facet=$1
	local MAX=${2:-$(max_recovery_time)}
	local facets=$facet
	if [ "$FAILURE_MODE" = HARD ]; then
		facets=$(facets_on_host $(facet_active_host $facet))
	fi
	echo affected facets: $facets
	facets=${facets//,/ }
	for facet in ${facets//mgs/ }; do
		local var_svc=${facet}_svc
		local param="*.${!var_svc}.recovery_status"
		local host=$(facet_active_host $facet)
		do_rpc_nodes "$host" _wait_recovery_complete $param $MAX
	done
}
wait_mds_ost_sync () {
	echo "Waiting for orphan cleanup..."
	local MAX=$(( TIMEOUT * 2 ))
	local WAIT_TIMEOUT=${1:-$MAX}
	local WAIT=0
	local new_wait=true
	local list=$(mdts_nodes)
	local cmd="$LCTL get_param -n osp.*osc*.old_sync_processed"
	if ! do_facet $SINGLEMDS \
		"$LCTL list_param osp.*osc*.old_sync_processed 2> /dev/null"
	then
		new_wait=false
		list=$(osts_nodes)
		cmd="$LCTL get_param -n obdfilter.*.mds_sync"
	fi
	echo "wait $WAIT_TIMEOUT secs maximumly for $list mds-ost sync done."
	while [ $WAIT -lt $WAIT_TIMEOUT ]; do
		local -a sync=($(do_nodes $list "$cmd"))
		local con=1
		local i
		for ((i=0; i<${
			if $new_wait; then
				[ ${sync[$i]} -eq 1 ] && continue
			else
				[ ${sync[$i]} -eq 0 ] && continue
			fi
			con=0
			break;
		done
		sleep 2
		[ ${con} -eq 1 ] && return 0
		echo "Waiting $WAIT secs for $list $i mds-ost sync done."
		WAIT=$((WAIT + 2))
	done
	cmd=$(echo $cmd | sed 's/-n//')
	do_nodes $list "$cmd"
	echo "$facet recovery node $i not done in $WAIT_TIMEOUT sec. $STATUS"
	return 1
}
wait_osts_up() {
	local cmd="$LCTL get_param -n lov.$FSNAME-clilov-*.target_obd |
		awk 'BEGIN {c = 0} /ACTIVE/{c += 1} END {printf \\\"%d\\\", c}'"
	wait_update $HOSTNAME "eval $cmd" $OSTCOUNT ||
		error "wait_update OSTs up on client failed"
	cmd="$LCTL get_param osp.$FSNAME-OST*-MDT0000.prealloc_last_id |
	     awk '/=[1-9][0-9]/ { c += 1 } END { printf \\\"%d\\\", c }'"
	wait_update_facet $SINGLEMDS "eval $cmd" $OSTCOUNT ||
		error "wait_update OSTs up on MDT0000 failed"
}
wait_destroy_complete () {
	echo "Waiting for MDT destroys to complete"
	local MAX=${1:-5}
	local WAIT=0
	local mdts=$(mdts_nodes)
	while [ $WAIT -lt $MAX ]; do
		local -a RPCs=($(do_nodes $mdts $LCTL get_param -n osp.*.destroys_in_flight))
		local con=1
		local i
		for ((i=0; i<${
			[ ${RPCs[$i]} -eq 0 ] && continue
			con=0
			break;
		done
		[ ${con} -eq 1 ] && return 0
		sleep 1
		echo "Waiting ${WAIT}s for local destroys to complete"
		WAIT=$((WAIT + 1))
	done
	echo "MDT destroys weren't done in $MAX sec."
	return 1
}
fstrim_inram_devs() {
	local i
	local v
	local pids
	[[ "$(facet_fstype ost1)" = "ldiskfs" ]] || return 0
	[[ $OSTDEVBASE == */tmp/* ]] || return 0
	for (( i=1; i <= $OSTCOUNT; i++)); do
		v="ost${i}_FSTRIM"
		[[ ${!v} != "yes" ]] && continue
		do_facet ost$i "fstrim $(facet_mntpt ost$i)" &
		pids+=" $!"
	done
	[[ -n $pids ]] && wait $pids
	return 0
}
wait_delete_completed() {
	wait_delete_completed_mds $1 || return $?
	wait_destroy_complete || return $?
	fstrim_inram_devs
}
wait_exit_ST () {
	local facet=$1
	local WAIT=0
	local INTERVAL=1
	local running
	while [ $WAIT -lt 300 ]; do
		running=$(do_facet ${facet} "lsmod | grep lnet > /dev/null &&
lctl dl | grep ' ST ' || true")
		[ -z "${running}" ] && return 0
		echo "waited $WAIT for${running}"
		[ $INTERVAL -lt 64 ] && INTERVAL=$((INTERVAL + INTERVAL))
		sleep $INTERVAL
		WAIT=$((WAIT + INTERVAL))
	done
	echo "service didn't stop after $WAIT seconds.  Still running:"
	echo ${running}
	return 1
}
wait_remote_prog () {
	local prog=$1
	local WAIT=0
	local INTERVAL=5
	local rc=0
	[ "$PDSH" = "no_dsh" ] && return 0
	while [ $WAIT -lt $2 ]; do
		running=$(ps uax | grep "$PDSH.*$prog.*$MOUNT" |
			grep -v grep) || true
		[ -z "${running}" ] && return 0 || true
		echo "waited $WAIT for: "
		echo "$running"
		[ $INTERVAL -lt 60 ] && INTERVAL=$((INTERVAL + INTERVAL))
		sleep $INTERVAL
		WAIT=$((WAIT + INTERVAL))
	done
	local pids=$(ps  uax | grep "$PDSH.*$prog.*$MOUNT" |
			grep -v grep | awk '{print $2}')
	[ -z "$pids" ] && return 0
	echo "$PDSH processes still exists after $WAIT seconds.  Still running: $pids"
	for pid in $pids; do
		cat /proc/${pid}/status || true
		cat /proc/${pid}/wchan || true
		echo "Killing $pid"
		kill -9 $pid || true
		sleep 1
		ps -P $pid && rc=1
	done
	return $rc
}
_lfs_df_check() {
	local clients=${1:-$CLIENTS}
	local rc=0
	if [[ -z "$clients" ]]; then
		$LFS df $MOUNT > /dev/null || rc=$?
	else
		$PDSH $clients "$LFS df $MOUNT" > /dev/null || rc=$?
	fi
	return $rc
}
lfs_df_check() {
	local clients=${1:-$CLIENTS}
	local rc=0
	_lfs_df_check "$clients" || rc=$?
	check_lfs_df_ret_val $rc
}
clients_up() {
	sleep 1
	lfs_df_check
}
all_mds_up() {
	(( MDSCOUNT == 1 )) && return
	local delay=$(do_facet mds1 $LCTL \
		get_param -n osp.*MDT*MDT0000.maxage | sort -n | tail -1)
	[ -n "$delay" ] || error "fail to get maxage"
	sleep $delay
	local mdts=$(mdts_nodes)
	do_nodes $mdts $LCTL get_param -N osp.*MDT*MDT*.filesfree >&/dev/null
	do_nodes $mdts $LCTL get_param -N osp.*MDT*MDT*.filesfree >&/dev/null
}
client_up() {
	sleep 1
	lfs_df_check $1
}
client_evicted() {
	local testid=$(echo $TESTNAME | tr '_' ' ')
	local client=$1
	local facet=${2:-mds1}
	local dev=$(facet_svc $facet)
	client_up $client
	$PDSH $client "dmesg | tac | sed \"/$testid/,$ d\"" |
		grep -q "client was evicted by ${dev}"
}
client_reconnect_try() {
	local f=$MOUNT/recon
	uname -n >> $f
	if [ -z "$CLIENTS" ]; then
		$LFS df $MOUNT; uname -n >> $f
	else
		do_nodes $CLIENTS "$LFS df $MOUNT; uname -n >> $f" > /dev/null
	fi
	echo "Connected clients: $(cat $f)"
	ls -l $f > /dev/null
	rm $f
}
client_reconnect() {
	while true ; do
		client_reconnect_try && break
		sleep 1
	done
}
affected_facets () {
	local facet=$1
	local host=$(facet_active_host $facet)
	local affected=$facet
	if [ "$FAILURE_MODE" = HARD ]; then
		affected=$(facets_up_on_host $host)
	fi
	echo $affected
}
facet_failover() {
	local E2FSCK_ON_MDT0=false
	if [ "$1" == "--fsck" ]; then
		shift
		[ $(facet_fstype $SINGLEMDS) == ldiskfs ] &&
			E2FSCK_ON_MDT0=true
	fi
	local facets=$1
	local sleep_time=$2
	local -a affecteds
	local facet
	local total=0
	local index=0
	local skip
	for facet in ${facets//,/ }; do
		local affected_facet
		skip=0
		for ((index=0; index<$total; index++)); do
			[[ ,${affecteds[index]}, == *,$facet,* ]] && skip=1
		done
		if [ $skip -eq 0 ]; then
			affecteds[$total]=$(affected_facets $facet)
			total=$((total+1))
		fi
	done
	for ((index=0; index<$total; index++)); do
		facet=$(echo ${affecteds[index]} | tr -s " " | cut -d"," -f 1)
		local host=$(facet_active_host $facet)
		echo "Failing ${affecteds[index]} on $host"
		shutdown_facet $facet
	done
	echo "$(date +'%H:%M:%S (%s)') shut down"
	local hostlist
	local waithostlist
	for facet in ${facets//,/ }; do
		local host=$(facet_active_host $facet)
		hostlist=$(expand_list $hostlist $host)
		local fhost=$(facet_host $facet)
		local ffhost=$(facet_failover_host $facet)
		echo "facet: $facet facet_host: $fhost facet_failover_host: $ffhost"
		if [ $(facet_host $facet) = \
			$(facet_failover_host $facet) ]; then
			waithostlist=$(expand_list $waithostlist $host)
		fi
	done
	if [ "$FAILURE_MODE" = HARD ]; then
		for host in ${hostlist//,/ }; do
			reboot_node $host
		done
		echo "$(date +'%H:%M:%S (%s)') $hostlist rebooted; waithostlist: $waithostlist"
		if ! [ -z "$waithostlist" ]; then
			wait_for_host $waithostlist
			if $LOAD_MODULES_REMOTE; then
				echo "loading modules on $waithostlist"
				do_rpc_nodes $waithostlist load_modules_local
			fi
		fi
	else
		sleep 10
	fi
	if [[ " ${affecteds[@]} " =~ " $SINGLEMDS " ]]; then
		change_active $SINGLEMDS
	fi
	$E2FSCK_ON_MDT0 && (run_e2fsck $(facet_active_host $SINGLEMDS) \
		$(facet_device $SINGLEMDS) "-n" || error "Running e2fsck")
	local -a mountpids
	for ((index=0; index<$total; index++)); do
		if [[ ${affecteds[index]} != $SINGLEMDS ]]; then
			change_active ${affecteds[index]}
		fi
		if $GSS_SK; then
			init_gss
			init_facets_vars_simple
		fi
		if ! combined_mgs_mds &&
			list_member ${affecteds[index]} mgs; then
			mount_facet mgs || error "Restart of mgs failed"
			affecteds[index]=$(exclude_items_from_list \
				${affecteds[index]} mgs)
		fi
		if [ -n "${affecteds[index]}" ]; then
			echo mount facets: ${affecteds[index]}
			mount_facets ${affecteds[index]} &
			mountpids[index]=$!
		fi
	done
	for ((index=0; index<$total; index++)); do
		if [ -n "${affecteds[index]}" ]; then
			wait ${mountpids[index]}
		fi
		if $GSS_SK; then
			do_nodes $(comma_list $(all_nodes)) \
				"keyctl show | grep grumple | cut -c1-11 |
				sed -e 's/ //g;' |
				xargs -IX keyctl setperm X 0x3f3f3f3f"
		fi
	done
	echo "$(date +'%H:%M:%S (%s)') targets are mounted"
	if [ "$FAILURE_MODE" = HARD ]; then
		hostlist=$(exclude_items_from_list $hostlist $waithostlist)
		if ! [ -z "$hostlist" ]; then
			wait_for_host $hostlist
			if $LOAD_MODULES_REMOTE; then
				echo "loading modules on $hostlist"
				do_rpc_nodes $hostlist load_modules_local
			fi
		fi
	fi
	echo "$(date +'%H:%M:%S (%s)') facet_failover done"
}
replay_barrier() {
	local facet=$1
	do_facet $facet "sync; sync; sync"
	$LFS df $MOUNT
	local clients=${CLIENTS:-$HOSTNAME}
	local f=fsa-\\\$\(hostname\)
	do_nodes $clients "mcreate $MOUNT/$f; rm $MOUNT/$f"
	do_nodes $clients "if [ -d $MOUNT2 ]; then mcreate $MOUNT2/$f; rm $MOUNT2/$f; fi"
	local svc=${facet}_svc
	do_facet $facet $LCTL --device ${!svc} notransno
	set_dev_readonly $facet
	do_facet $facet $LCTL mark "$facet REPLAY BARRIER on ${!svc}"
	$LCTL mark "local REPLAY BARRIER on ${!svc}"
}
replay_barrier_nodf() {
	local facet=$1    echo running=${running}
	do_facet $facet "sync; sync; sync"
	local svc=${facet}_svc
	echo Replay barrier on ${!svc}
	do_facet $facet $LCTL --device ${!svc} notransno
	set_dev_readonly $facet
	do_facet $facet $LCTL mark "$facet REPLAY BARRIER on ${!svc}"
	$LCTL mark "local REPLAY BARRIER on ${!svc}"
}
replay_barrier_nosync() {
	local facet=$1    echo running=${running}
	local svc=${facet}_svc
	echo Replay barrier on ${!svc}
	do_facet $facet $LCTL --device ${!svc} notransno
	set_dev_readonly $facet
	do_facet $facet $LCTL mark "$facet REPLAY BARRIER on ${!svc}"
	$LCTL mark "local REPLAY BARRIER on ${!svc}"
}
get_client_uuid() {
	local mntpnt=${1:-$MOUNT}
	echo -n $($LFS getname -u $mntpnt)
}
mds_evict_client() {
	local mntpnt=${1:-$MOUNT}
	local uuid=$(get_client_uuid $mntpnt)
	do_facet $SINGLEMDS \
		"$LCTL set_param -n mdt.${mds1_svc}.evict_client $uuid"
}
ost_evict_client() {
	local mntpnt=${1:-$MOUNT}
	local uuid=$(get_client_uuid $mntpnt)
	do_facet ost1 \
		"$LCTL set_param -n obdfilter.${ost1_svc}.evict_client $uuid"
}
fail() {
	local facets=$1
	local clients=${CLIENTS:-$HOSTNAME}
	SK_NO_KEY_save=$SK_NO_KEY
	if $GSS_SK; then
		export SK_NO_KEY=false
	fi
	facet_failover $* || error "failover: $?"
	export SK_NO_KEY=$SK_NO_KEY_save
	clients_up
	wait_clients_import_ready "$clients" "$facets"
	clients_up || error "post-failover stat: $?"
}
fail_nodf() {
	local facet=$1
	facet_failover $facet
}
fail_abort() {
	local facet=$1
	local abort_type=${2:-"abort_recovery"}
	stop $facet
	change_active $facet
	wait_for_facet $facet
	mount_facet $facet -o $abort_type
	clients_up || echo "first stat failed: $?"
	clients_up || error "post-failover stat: $?"
	all_mds_up
}
fail_abort_cleanup() {
	rm -rf $DIR/$tdir/*
	find $DIR/$tdir -depth | while read D; do
		rmdir "$D" || $LFS rm_entry "$D" || error "rm $D failed"
	done
}
host_nids_address() {
	local nodes=$1
	local net=${2:-"."}
	do_nodes $nodes "$LCTL list_nids | grep -w $net | cut -f 1 -d @"
}
ip_is_v4() {
	local ipv4_re='^([0-9]{1,3}\.){3,3}[0-9]{1,3}$'
	if ! [[ $1 =~ $ipv4_re ]]; then
		return 1
	fi
	local quads=(${1//\./ })
	(( ${
	(( quads[0] < 256 && quads[1] < 256 &&
	   quads[2] < 256 && quads[3] < 256 )) || return 1
	return 0
}
ip_is_v6() {
	local ipv6_re='^([0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}$'
	if ! [[ $1 =~ $ipv6_re ]]; then
		return 1
	fi
	local segment
	for segment in ${1//:/ }; do
		((0x$segment <= 0xFFFF)) || return 1
	done
	return 0
}
h2name_or_ip() {
	if [[ "$1" == '*' ]]; then
		echo \'*\'
	elif ip_is_v4 "$1" || ip_is_v6 "$1" ; then
		echo "$1@$2"
	else
		local addr nidlist large_nidlist
		local iplist=$(do_node $1 hostname -I | sed "s/$1://")
		for addr in ${iplist}; do
			nid="${addr}@$2"
			ip_is_v4 "$addr" &&
				nidlist="${nidlist:+$nidlist,}${nid}" ||
				large_nidlist="${large_nidlist:+$large_nidlist,}${nid}"
		done
		if [[ -n $nidlist ]] && [[ -n $large_nidlist ]]; then
			if ${FORCE_LARGE_NID}; then
				echo "$large_nidlist"
			else
				echo "$nidlist"
			fi
		elif [[ -n $nidlist ]]; then
			echo "$nidlist"
		elif [[ -n $large_nidlist ]]; then
			echo "$large_nidlist"
		else
			echo "$1@$2"
		fi
	fi
}
h2nettype() {
	if [[ -n "$NETTYPE" ]]; then
		h2name_or_ip "$1" "$NETTYPE"
	else
		h2name_or_ip "$1" "$2"
	fi
}
declare -fx h2nettype
hostlist_expand() {
	local hostlist=$1
	local offset=$2
	local myList
	local item
	local list
	[ -z "$hostlist" ] && return
	list="${hostlist/],/] }"
	front=${list%%[*}
	[[ "$front" == *,* ]] && {
		new="${list%,*} "
		old="${list%,*},"
		list=${list/${old}/${new}}
	}
	for item in $list; do
		if [ "$item" != "${item/\[/}" ]; then {
		name=${item%%[*}
		back=${item
			if [ "$name" != "$item" ]; then
				group=${item
				group=${group%%]*}
				for range in ${group//,/ }; do
					local order
					begin=${range%-*}
					end=${range
					padlen=${
					padlen2=${
					end=$(echo $end | sed 's/0*//')
					[[ -z "$end" ]] && end=0
					[[ $padlen2 -gt $padlen ]] && {
						[[ $padlen2 -eq ${
							padlen2=0
						padlen=$padlen2
					}
					begin=$(echo $begin | sed 's/0*//')
					[ -z $begin ] && begin=0
					if [ ! -z "${begin
						order=$(seq -f "%0${padlen}g" $begin $end)
					else
						order=$(eval echo {$begin..$end});
					fi
					for num in $order; do
						value="${name
						[ "$value" != "${value/\[/}" ] && {
						    value=$(hostlist_expand "$value")
						}
						myList="$myList $value"
					done
				done
			fi
		} else {
			myList="$myList $item"
		} fi
	done
	myList=${myList//,/ }
	myList=${myList:1}
	list="$myList "
	myList="${list%% *}"
	while [[ "$list" != ${myList
		local tlist=" $list"
		list=${tlist// ${list%% *} / }
		list=${list:1}
		myList="$myList ${list%% *}"
	done
	myList="${myList%* }";
	[ $
	cnt=0
	for item in $myList; do
		let cnt=cnt+1
		[ $cnt -eq $offset ] && {
			myList=$item
		}
	done
	[ $(get_node_count $myList) -ne 1 ] && myList=""
	}
	echo $myList
}
facet_host() {
	local facet=$1
	local varname
	[ "$facet" == client ] && echo -n $HOSTNAME && return
	varname=${facet}_HOST
	if [ -z "${!varname}" ]; then
		if [ "${facet:0:3}" == "ost" ]; then
			local fh=${facet%failover}_HOST
			eval export ${facet}_HOST=${!fh}
			if [ -z "${!varname}" ]; then
				eval export ${facet}_HOST=${ost_HOST}
			fi
		elif [ "${facet:0:3}" == "mdt" -o \
			"${facet:0:3}" == "mds" -o \
			"${facet:0:3}" == "mgs" ]; then
			local temp
			if [ "${facet}" == "mgsfailover" ] &&
			   [ -n "$mds1failover_HOST" ]; then
				temp=$mds1failover_HOST
			else
				temp=${mds_HOST}
			fi
			eval export ${facet}_HOST=$temp
		fi
	fi
	echo -n ${!varname}
}
facet_failover_host() {
	local facet=$1
	local varname
	var=${facet}failover_HOST
	if [ -n "${!var}" ]; then
		echo ${!var}
		return
	fi
	if combined_mgs_mds && [ $facet == "mgs" ] &&
		[ -n "$mds1failover_HOST" ]; then
		echo $mds1failover_HOST
		return
	fi
	if [ "${facet:0:3}" == "mdt" -o "${facet:0:3}" == "mds" -o \
	     "${facet:0:3}" == "mgs" ]; then
		eval export ${facet}failover_host=${mds_HOST}
		echo ${mds_HOST}
		return
	fi
	if [[ $facet == ost* ]]; then
		eval export ${facet}failover_host=${ost_HOST}
		echo ${ost_HOST}
		return
	fi
}
facet_active() {
	local facet=$1
	local activevar=${facet}active
	if [ -f $TMP/${facet}active ] ; then
		source $TMP/${facet}active
	fi
	active=${!activevar}
	if [ -z "$active" ] ; then
		echo -n ${facet}
	else
		echo -n ${active}
	fi
}
facet_active_host() {
	facet_host $(facet_active $1)
}
facet_passive_host() {
	local facet=$1
	[[ $facet = client ]] && return
	local host=${facet}_HOST
	local failover_host=${facet}failover_HOST
	local active_host=$(facet_active_host $facet)
	[[ -z ${!failover_host} || ${!failover_host} = ${!host} ]] && return
	if [[ $active_host = ${!host} ]]; then
		echo -n ${!failover_host}
	else
		echo -n ${!host}
	fi
}
change_active() {
	local facetlist=$1
	local facet
	for facet in ${facetlist//,/ }; do
		local failover=${facet}failover
		local host=`facet_host $failover`
		[ -z "$host" ] && return
		local curactive=`facet_active $facet`
		if [ -z "${curactive}" -o "$curactive" == "$failover" ] ; then
			eval export ${facet}active=$facet
		else
			eval export ${facet}active=$failover
		fi
		local activevar=${facet}active
		echo "$activevar=${!activevar}" > $TMP/$activevar
		[[ $facet = mds1 ]] && combined_mgs_mds && \
		echo "mgsactive=${!activevar}" > $TMP/mgsactive
		local TO=`facet_active_host $facet`
		echo "Failover $facet to $TO"
	done
}
do_node() {
	local verbose
	local quiet
	[[ "$1" == "--verbose" ]] && verbose="$1" && shift
	[[ "$1" == "--quiet" || "$1" == "-q" ]] && quiet="$1" && shift
	local HOST=$1
	shift
	local myPDSH=$PDSH
	if [ "$HOST" = "$HOSTNAME" ]; then
		myPDSH="no_dsh"
	elif [ -z "$myPDSH" -o "$myPDSH" = "no_dsh" ]; then
		echo "cannot run remote command on $HOST with $myPDSH"
		return 128
	fi
	if $VERBOSE && [[ -z "$quiet" ]]; then
		echo "CMD: $HOST $*" >&2
		$myPDSH $HOST "$LCTL mark \"$*\"" > /dev/null 2>&1 || :
	fi
	if [[ "$myPDSH" == "rsh" ]] ||
	   [[ "$myPDSH" == *pdsh* && "$myPDSH" != *-S* ]]; then
		local command_status="$TMP/cs"
		eval $myPDSH $HOST ":> $command_status"
		eval $myPDSH $HOST "(PATH=\$PATH:$RLUSTRE/utils:$RLUSTRE/tests;
				     PATH=\$PATH:/sbin:/usr/sbin;
				     cd $RPWD;
				     LUSTRE=\"$RLUSTRE\" bash -c \"$*\") ||
				     echo command failed >$command_status"
		[[ -n "$($myPDSH $HOST cat $command_status)" ]] && return 1 ||
			return 0
	fi
	if [[ -n "$verbose" ]]; then
		if [[ $myPDSH = no_dsh ]]; then
			$myPDSH $HOST \
			"(PATH=\$PATH:$RLUSTRE/utils:$RLUSTRE/tests:/sbin:/usr/sbin;\
			cd $RPWD; LUSTRE=\"$RLUSTRE\" bash -c \"$*\")" |
			sed -e "s/^/${HOSTNAME}: /"
		else
			$myPDSH $HOST \
			"(PATH=\$PATH:$RLUSTRE/utils:$RLUSTRE/tests:/sbin:/usr/sbin;\
			cd $RPWD; LUSTRE=\"$RLUSTRE\" bash -c \"$*\")"
		fi
	else
		$myPDSH $HOST \
		"(PATH=\$PATH:$RLUSTRE/utils:$RLUSTRE/tests:/sbin:/usr/sbin;\
		cd $RPWD; LUSTRE=\"$RLUSTRE\" bash -c \"$*\")" |
		sed "s/^${HOST}: //"
	fi
	return ${PIPESTATUS[0]}
}
do_node_vp() {
	local host="$1"
	shift
	if [[ "$host" == "$HOSTNAME" ]]; then
		bash -c "$(printf -- ' %q' "$@")"
		return $?
	fi
	if [[ "${PDSH}" != *pdsh* || "${PDSH}" != *-S* ]]; then
		echo "cannot run '$*' on host '${host}' with PDSH='${PDSH}'" >&2
		return 128
	fi
	$PDSH "${host}" -N "cd $RPWD; PATH=\$PATH:$RLUSTRE/utils:$RLUSTRE/tests:/sbin:/usr/sbin; export LUSTRE=$RLUSTRE; $(printf -- ' %q' "$@")"
}
single_local_node () {
	[ "$1" = "$HOSTNAME" ]
}
get_env_vars() {
	local var
	local value
	local facets=$(get_facets)
	local facet
	for var in ${!MODOPTS_*}; do
		value=${!var//\"/\\\"}
		echo -n " ${var}=\"$value\""
	done
	for facet in ${facets//,/ }; do
		var=${facet}_FSTYPE
		if [ -n "${!var}" ]; then
			echo -n " $var=${!var}"
		fi
	done
	for var in MGSFSTYPE MDSFSTYPE OSTFSTYPE; do
		if [ -n "${!var}" ]; then
			echo -n " $var=${!var}"
		fi
	done
	for var in VERBOSE; do
		if [ -n "${!var}" ]; then
			echo -n " $var=${!var}"
		fi
	done
	if [ -n "$FSTYPE" ]; then
		echo -n " FSTYPE=$FSTYPE"
	fi
	for var in LNETLND NETTYPE; do
		if [ -n "${!var}" ]; then
			echo -n " $var=${!var}"
		fi
	done
}
do_nodes() {
	local verbose
	local quiet
	[[ "$1" == "--verbose" ]] && verbose="$1" && shift
	[[ "$1" == "--quiet" || "$1" == "-q" ]] && quiet="$1" && shift
	local rnodes=$1
	shift
	if single_local_node $rnodes; then
		do_node $verbose $quiet $rnodes "$@"
		return $?
	fi
	local myPDSH=$PDSH
	[ -z "$myPDSH" -o "$myPDSH" = "no_dsh" -o "$myPDSH" = "rsh" ] &&
		echo "cannot run remote command on $rnodes with $myPDSH" &&
		return 128
	export FANOUT=$(get_node_count "${rnodes//,/ }")
	if $VERBOSE && [[ -z "$quiet" ]]; then
		echo "CMD: $rnodes $*" >&2
		$myPDSH $rnodes "$LCTL mark \"$*\"" > /dev/null 2>&1 || :
	fi
	if [[ -n "$verbose" || $myPDSH = *-N* ]]; then
		$myPDSH $rnodes "(PATH=\$PATH:$RLUSTRE/utils:$RLUSTRE/tests:/sbin:/usr/sbin; cd $RPWD; LUSTRE=\"$RLUSTRE\" $(get_env_vars) bash -c \"$*\")"
	else
		$myPDSH $rnodes "(PATH=\$PATH:$RLUSTRE/utils:$RLUSTRE/tests:/sbin:/usr/sbin; cd $RPWD; LUSTRE=\"$RLUSTRE\" $(get_env_vars) bash -c \"$*\")" | sed -re "s/^[^:]*: //g"
	fi
	return ${PIPESTATUS[0]}
}
do_facet() {
	local verbose
	local quiet
	[[ "$1" == "--verbose" ]] && verbose="$1" && shift
	[[ "$1" == "--quiet" || "$1" == "-q" ]] && quiet="$1" && shift
	local facet=$1
	shift
	local host=$(facet_active_host $facet)
	[ -z "$host" ] && echo "No host defined for facet ${facet}" && exit 1
	do_node $verbose $quiet $host "$@"
}
do_facet_vp() {
	local facet="$1"
	local host=$(facet_active_host "$facet")
	shift
	if [[ -z "$host" ]]; then
		echo "no host defined for facet ${facet}" >&2
		exit 1
	fi
	do_node_vp "$host" "$@"
}
do_facet_random_file() {
	local facet="$1"
	local fpath="$2"
	local fsize="$3"
	local cmd="dd if=/dev/urandom of='$fpath' bs=$fsize count=1"
	do_facet $facet "$cmd 2>/dev/null"
}
do_facet_create_file() {
	local facet="$1"
	local fpath="$2"
	local fsize="$3"
	local cmd="dd if=/dev/zero of='$fpath' bs=$fsize count=1"
	do_facet $facet "$cmd 2>/dev/null"
}
do_nodesv() {
	do_nodes --verbose "$@"
}
add() {
	local facet=$1
	shift
	stop ${facet} -f
	rm -f $TMP/${facet}active
	[[ $facet = mds1 ]] && combined_mgs_mds && rm -f $TMP/mgsactive
	if local_mode && [[ $(node_fstypes $HOSTNAME) == *ldiskfs* ]]; then
		load_module ../ldiskfs/ldiskfs
	fi
	do_facet ${facet} $MKFS $* || return ${PIPESTATUS[0]}
	if [[ $(facet_fstype $facet) == zfs ]]; then
		refresh_partition_table $facet $(facet_vdevice $facet)
		disable_zpool_cache $facet
		export_zpool $facet
	fi
}
ostdevname() {
	local num=$1
	local DEVNAME=OSTDEV$num
	local fstype=$(facet_fstype ost$num)
	case $fstype in
		ldiskfs )
			local dev=ost${num}_dev
			[[ -n ${!dev} ]] && eval DEVPTR=${!dev} ||
			eval DEVPTR=${!DEVNAME:=${OSTDEVBASE}${num}};;
		zfs )
			DEVNAME=OSTZFSDEV$num
			eval DEVPTR=${!DEVNAME:=${FSNAME}-ost${num}/ost${num}};;
		wbcfs )
			:;;
		* )
			error "unknown fstype!";;
	esac
	echo -n $DEVPTR
}
ostvdevname() {
	local num=$1
	local DEVNAME
	local VDEVPTR
	local fstype=$(facet_fstype ost$num)
	case $fstype in
		ldiskfs )
			eval VDEVPTR="";;
		zfs )
			DEVNAME=OSTDEV$num
			eval VDEVPTR=${!DEVNAME:=${OSTDEVBASE}${num}};;
		wbcfs )
			:;;
		* )
			error "unknown fstype!";;
	esac
	echo -n $VDEVPTR
}
mdsdevname() {
	local num=$1
	local DEVNAME=MDSDEV$num
	local fstype=$(facet_fstype mds$num)
	case $fstype in
		ldiskfs )
			local dev=mds${num}_dev
			[[ -n ${!dev} ]] && eval DEVPTR=${!dev} ||
			eval DEVPTR=${!DEVNAME:=${MDSDEVBASE}${num}};;
		zfs )
			DEVNAME=MDSZFSDEV$num
			eval DEVPTR=${!DEVNAME:=${FSNAME}-mdt${num}/mdt${num}};;
		wbcfs )
			:;;
		* )
			error "unknown fstype!";;
	esac
	echo -n $DEVPTR
}
mdsvdevname() {
	local VDEVPTR=""
	local num=$1
	local fstype=$(facet_fstype mds$num)
	case $fstype in
		ldiskfs )
			eval VDEVPTR="";;
		zfs )
			local DEVNAME=MDSDEV$num
			eval VDEVPTR=${!DEVNAME:=${MDSDEVBASE}${num}};;
		wbcfs )
			:;;
		* )
			error "unknown fstype!";;
	esac
	echo -n $VDEVPTR
}
mgsdevname() {
	local DEVPTR
	local fstype=$(facet_fstype mgs)
	case $fstype in
	ldiskfs )
		if [ $(facet_host mgs) = $(facet_host mds1) ] &&
		   ( [ -z "$MGSDEV" ] || [ $MGSDEV = $MDSDEV1 ] ); then
			DEVPTR=$(mdsdevname 1)
		else
			[[ -n $mgs_dev ]] && DEVPTR=$mgs_dev ||
			DEVPTR=$MGSDEV
		fi;;
	zfs )
		if [ $(facet_host mgs) = $(facet_host mds1) ] &&
		    ( [ -z "$MGSZFSDEV" ] &&
			[ -z "$MGSDEV" -o "$MGSDEV" = $(mdsvdevname 1) ] ); then
			DEVPTR=$(mdsdevname 1)
		else
			DEVPTR=${MGSZFSDEV:-${FSNAME}-mgs/mgs}
		fi;;
	wbcfs )
		:;;
	* )
		error "unknown fstype!";;
	esac
	echo -n $DEVPTR
}
mgsvdevname() {
	local VDEVPTR=""
	local fstype=$(facet_fstype mgs)
	case $fstype in
	ldiskfs )
		;;
	zfs )
		if [ $(facet_host mgs) = $(facet_host mds1) ] &&
		   ( [ -z "$MGSDEV" ] &&
		       [ -z "$MGSZFSDEV" -o "$MGSZFSDEV" = $(mdsdevname 1) ]); then
			VDEVPTR=$(mdsvdevname 1)
		elif [ -n "$MGSDEV" ]; then
			VDEVPTR=$MGSDEV
		fi;;
	wbcfs )
		:;;
	* )
		error "unknown fstype!";;
	esac
	echo -n $VDEVPTR
}
facet_mntpt () {
	local facet=$1
	[[ $facet = mgs ]] && combined_mgs_mds && facet="mds1"
	local var=${facet}_MOUNT
	eval mntpt=${!var:-${MOUNT}-$facet}
	echo -n $mntpt
}
mount_ldiskfs() {
	local facet=$1
	local dev=$(facet_device $facet)
	local mnt=${2:-$(facet_mntpt $facet)}
	local opts
	local dm_dev=$dev
	if dm_flakey_supported $facet; then
		dm_dev=$(dm_create_dev $facet $dev)
		[[ -n "$dm_dev" ]] || dm_dev=$dev
	fi
	is_blkdev $facet $dm_dev || opts=$(csa_add "$opts" -o loop)
	export_dm_dev $facet $dm_dev
	do_facet $facet mount -t ldiskfs $opts $dm_dev $mnt
}
unmount_ldiskfs() {
	local facet=$1
	local dev=$(facet_device $facet)
	local mnt=${2:-$(facet_mntpt $facet)}
	do_facet $facet $UMOUNT $mnt
}
var_name() {
	echo -n "$1" | tr -c '[:alnum:]\n' '_'
}
mount_zfs() {
	local facet=$1
	local ds=$(facet_device $facet)
	local mnt=${2:-$(facet_mntpt $facet)}
	local canmnt
	local mntpt
	import_zpool $facet
	canmnt=$(do_facet $facet $ZFS get -H -o value canmount $ds)
	mntpt=$(do_facet $facet $ZFS get -H -o value mountpoint $ds)
	do_facet $facet $ZFS set canmount=noauto $ds
	do_facet $facet $ZFS set mountpoint=legacy $ds
	do_facet $facet mount -t zfs $ds $mnt
	eval export mz_$(var_name ${facet}_$ds)_canmount=$canmnt
	eval export mz_$(var_name ${facet}_$ds)_mountpoint=$mntpt
}
unmount_zfs() {
	local facet=$1
	local ds=$(facet_device $facet)
	local mnt=${2:-$(facet_mntpt $facet)}
	local var_mntpt=mz_$(var_name ${facet}_$ds)_mountpoint
	local var_canmnt=mz_$(var_name ${facet}_$ds)_canmount
	local mntpt=${!var_mntpt}
	local canmnt=${!var_canmnt}
	unset $var_mntpt
	unset $var_canmnt
	do_facet $facet umount $mnt
	do_facet $facet $ZFS set mountpoint=$mntpt $ds
	do_facet $facet $ZFS set canmount=$canmnt $ds
	export_zpool $facet
}
mount_fstype() {
	local facet=$1
	local mnt=$2
	local fstype=$(facet_fstype $facet)
	mount_$fstype $facet $mnt
}
unmount_fstype() {
	local facet=$1
	local mnt=$2
	local fstype=$(facet_fstype $facet)
	unmount_$fstype $facet $mnt
}
stopall() {
	activemds=`facet_active mds1`
	if [ $activemds != "mds1" ]; then
		fail mds1
	fi
	local clients=$CLIENTS
	[ -z $clients ] && clients=$(hostname)
	zconf_umount_clients $clients $MOUNT "$*" || true
	[ -n "$MOUNT2" ] && zconf_umount_clients $clients $MOUNT2 "$*" || true
	[ -n "$CLIENTONLY" ] && return
	local num
	for num in `seq $MDSCOUNT`; do
		stop mds$num -f
		rm -f ${TMP}/mds${num}active
	done
	combined_mgs_mds && rm -f $TMP/mgsactive
	for num in `seq $OSTCOUNT`; do
		stop ost$num -f
		rm -f $TMP/ost${num}active
	done
	if ! combined_mgs_mds ; then
		stop mgs
	fi
	if $SHARED_KEY; then
		export SK_MOUNTED=false
	fi
	return 0
}
cleanup_echo_devs () {
	trap 0
	local dev
	local devs=$($LCTL dl | grep echo | awk '{print $4}')
	for dev in $devs; do
		$LCTL --device $dev cleanup
		$LCTL --device $dev detach
	done
}
kptr_enable_and_save() {
	[[ -f $TMP/kptr-$PPID-env ]] && return
	local nodes=$(all_nodes)
	declare -A kptr
	for node in ${nodes//,/ }; do
		kptr[$node]=$(do_node $node "sysctl --values kernel/kptr_restrict")
		do_node $node "sysctl -wq kernel/kptr_restrict=1"
	done
	declare -p kptr > $TMP/kptr-$PPID-env
}
kptr_restore() {
	[[ ! -f $TMP/kptr-$PPID-env ]] && return
	local nodes=$(all_nodes)
	source $TMP/kptr-$PPID-env
	local param
	for node in ${nodes//,/ }; do
		[[ -z ${kptr[$node]} ]] && continue
		param="kernel/kptr_restrict=${kptr[$node]}"
		do_node $node "sysctl -wq ${param} || true"
	done
}
cleanupall() {
	nfs_client_mode && return
	cifs_client_mode && return
	cleanup_echo_devs
	CLEANUP_DM_DEV=true stopall $*
	[[ $KPTR_ON_MOUNT ]] && kptr_restore
	unload_modules
	cleanup_sk
	cleanup_gss
}
combined_mgs_mds () {
	[[ "$(mdsdevname 1)" = "$(mgsdevname)" ]] &&
		[[ "$(facet_host mds1)" = "$(facet_host mgs)" ]]
}
lower() {
	echo -n "$1" | tr '[:upper:]' '[:lower:]'
}
upper() {
	echo -n "$1" | tr '[:lower:]' '[:upper:]'
}
squash_opt() {
	local var="$*"
	local other=""
	local opt_o=""
	local opt_e=""
	local first_e=0
	local first_o=0
	local take=""
	var=$(echo "$var" | sed -e 's/,\( \)*/,/g')
	for i in $(echo "$var"); do
		if [ "$i" == "-O" ]; then
			take="o";
			first_o=$(($first_o + 1))
			continue;
		fi
		if [ "$i" == "-E" ]; then
			take="e";
			first_e=$(($first_e + 1 ))
			continue;
		fi
		case $take in
			"o")
				[ $first_o -gt 1 ] && opt_o+=",";
				opt_o+="$i";
				;;
			"e")
				[ $first_e -gt 1 ] && opt_e+=",";
				opt_e+="$i";
				;;
			*)
				other+=" $i";
				;;
		esac
		take=""
	done
	echo -n "$other"
	[ -n "$opt_o" ] && echo " -O $opt_o"
	[ -n "$opt_e" ] && echo " -E $opt_e"
}
mkfs_opts() {
	local facet=$1
	local dev=$2
	local fsname=${3:-"$FSNAME"}
	local type=$(facet_type $facet)
	local index=$(facet_index $facet)
	local fstype=$(facet_fstype $facet)
	local host=$(facet_host $facet)
	local opts
	local fs_mkfs_opts
	local var
	local varbs=${facet}_BLOCKSIZE
	if [[ ("$type" == "MDS"  && "$dev" == $(mgsdevname) &&
	       "$host" == "$(facet_host mgs)" ) || "$type" == "MGS"  ]]; then
		opts="--mgs"
	else
		opts="--mgsnode=$MGSNID"
	fi
	if [ $type != MGS ]; then
		opts+=" --fsname=$fsname --$(lower ${type/MDS/MDT}) \
			--index=$index"
	fi
	var=${facet}failover_HOST
	if [ -n "${!var}" ] && [ ${!var} != $(facet_host $facet) ]; then
		opts+=" --failnode=$(h2nettype ${!var})"
	fi
	opts+=${TIMEOUT:+" --param=sys.timeout=$TIMEOUT"}
	opts+=${LDLM_TIMEOUT:+" --param=sys.ldlm_timeout=$LDLM_TIMEOUT"}
	if [ $type == MDS ]; then
		opts+=${DEF_STRIPE_SIZE:+" --param=lov.stripesize=$DEF_STRIPE_SIZE"}
		opts+=${DEF_STRIPE_COUNT:+" --param=lov.stripecount=$DEF_STRIPE_COUNT"}
		opts+=${L_GETIDENTITY:+" --param=mdt.identity_upcall=$L_GETIDENTITY"}
		if [ $fstype == ldiskfs ]; then
			var=${facet}_JRN
			if [ -n "${!var}" ]; then
				fs_mkfs_opts+=" -J device=${!var}"
			else
				fs_mkfs_opts+=${MDSJOURNALSIZE:+" -J size=$MDSJOURNALSIZE"}
			fi
			fs_mkfs_opts+=${MDSISIZE:+" -i $MDSISIZE"}
		fi
	fi
	if [ $type == OST ]; then
		if [ $fstype == ldiskfs ]; then
			var=${facet}_JRN
			if [ -n "${!var}" ]; then
				fs_mkfs_opts+=" -J device=${!var}"
			else
				fs_mkfs_opts+=${OSTJOURNALSIZE:+" -J size=$OSTJOURNALSIZE"}
			fi
		fi
	fi
	opts+=" --backfstype=$fstype"
	var=${type}SIZE
	if [ -n "${!var}" ]; then
		opts+=" --device-size=${!var}"
	fi
	var=$(upper $fstype)_MKFS_OPTS
	fs_mkfs_opts+=${!var:+" ${!var}"}
	var=${type}_FS_MKFS_OPTS
	fs_mkfs_opts+=${!var:+" ${!var}"}
	[[ "$QUOTA_TYPE" =~ "p" ]] && fs_mkfs_opts+=" -O project"
	[ $fstype == ldiskfs ] && fs_mkfs_opts+=" -b ${!varbs:-$BLCKSIZE}"
	[ $fstype == ldiskfs ] && fs_mkfs_opts=$(squash_opt $fs_mkfs_opts)
	if [ -n "${fs_mkfs_opts
		opts+=" --mkfsoptions=\\\"${fs_mkfs_opts
	fi
	var=${type}OPT
	opts+=${!var:+" ${!var}"}
	echo -n "$opts"
}
mountfs_opts() {
	local facet=$1
	local type=$(facet_type $facet)
	local var=${type}_MOUNT_FS_OPTS
	local opts=""
	if [ -n "${!var}" ]; then
		opts+=" --mountfsoptions=${!var}"
	fi
	echo -n "$opts"
}
check_ost_indices() {
	local index_count=${
	[[ $index_count -eq 0 || $OSTCOUNT -le $index_count ]] && return 0
	local i
	local j
	local index
	for i in $(seq $((index_count + 1)) $OSTCOUNT); do
		index=$(facet_index ost$i)
		for j in $(seq 0 $((index_count - 1))); do
			[[ $index -ne ${OST_INDICES[j]} ]] ||
			error "ost$i has the same index $index as ost$((j+1))"
		done
	done
}
__touch_device()
{
	local facet_type=$1
	local facet_num=$2
	local facet=${1}${2}
	local device
	case "$(facet_fstype $facet)" in
	ldiskfs)
		device=$(${facet_type}devname $facet_num)
		;;
	zfs)
		device=$(${facet_type}vdevname $facet_num)
		;;
	*)
		error "Unhandled filesystem type"
		;;
	esac
	do_facet $facet "[ -e \"$device\" ]" && return
	[[ ! "$device" =~ ^/dev/ ]] || [[ "$device" =~ ^/dev/shm/ ]] ||
		error "$facet: device '$device' does not exist"
	[[ $(facet_fstype $facet) == zfs ]] && return 0
	do_facet $facet "touch \"${device}\""
}
format_mgs() {
	local quiet
	local fstype=$(facet_fstype mgs)
	[[ "$fstype" == "wbcfs" ]] && return
	if ! $VERBOSE; then
		quiet=yes
	fi
	echo "Format mgs: $(mgsdevname)"
	reformat_external_journal mgs
	__touch_device mgs
	add mgs $(mkfs_opts mgs $(mgsdevname)) $(mountfs_opts mgs) --reformat \
		$(mgsdevname) $(mgsvdevname) ${quiet:+>/dev/null} || exit 10
}
format_mdt() {
	local num=$1
	local quiet
	local fstype=$(facet_fstype mdt$num)
	[[ "$fstype" == "wbcfs" ]] && return
	if ! $VERBOSE; then
		quiet=yes
	fi
	echo "Format mds$num: $(mdsdevname $num)"
	reformat_external_journal mds$num
	__touch_device mds $num
	add mds$num $(mkfs_opts mds$num $(mdsdevname ${num})) \
		$(mountfs_opts mds$num) --reformat $(mdsdevname $num) \
		$(mdsvdevname $num) ${quiet:+>/dev/null} || exit 10
}
format_ost() {
	local num=$1
	local fstype=$(facet_fstype ost$num)
	[[ "$fstype" == "wbcfs" ]] && return
	if ! $VERBOSE; then
		quiet=yes
	fi
	echo "Format ost$num: $(ostdevname $num)"
	reformat_external_journal ost$num
	__touch_device ost $num
	add ost$num $(mkfs_opts ost$num $(ostdevname ${num})) \
		$(mountfs_opts ost$num) --reformat $(ostdevname $num) \
		$(ostvdevname ${num}) ${quiet:+>/dev/null} || exit 10
}
formatall() {
	stopall -f
	if [ $(grumple_version_code $SINGLEMDS) -ge $(version_code 2.8.54) ];
	then
		do_rpc_nodes "$(comma_list $(all_server_nodes))" set_hostid
	fi
	load_modules
	[ -n "$CLIENTONLY" ] && return
	echo Formatting mgs, mds, osts
	if ! combined_mgs_mds ; then
		format_mgs
	fi
	for num in $(seq $MDSCOUNT); do
		format_mdt $num
	done
	export OST_INDICES=($(hostlist_expand "$OST_INDEX_LIST"))
	check_ost_indices
	for num in $(seq $OSTCOUNT); do
		format_ost $num
	done
}
mount_client() {
	grep " $1 " /proc/mounts || zconf_mount $HOSTNAME $*
}
umount_client() {
	grep " $1 " /proc/mounts && zconf_umount $HOSTNAME $*
}
switch_identity() {
	local num=$1
	local enable=$2
	local facet=mds$num
	local MDT="$(mdtname_from_index $((num - 1)) $MOUNT)"
	local upcall="$L_GETIDENTITY"
	[[ -n "$MDT" ]] || return 2
	local param="mdt.$MDT.identity_upcall"
	local old="$(do_facet $facet "lctl get_param -n $param")"
	[[ "$enable" == "true" ]] || upcall="NONE"
	do_facet $facet "lctl set_param -n $param='$upcall'" || return 2
	do_facet $facet "lctl set_param -n mdt.$MDT.identity_flush=-1"
	[[ "$old" != "NONE" ]]
}
remount_client()
{
	zconf_umount $HOSTNAME $1 || error "umount failed"
	zconf_mount $HOSTNAME $1 || error "mount failed with ($?)"
}
writeconf_facet() {
	local facet=$1
	local dev=$2
	stop ${facet} -f
	rm -f $TMP/${facet}active
	do_facet ${facet} "$TUNEFS --quiet --writeconf $dev" || return 1
	return 0
}
writeconf_all () {
	local mdt_count=${1:-$MDSCOUNT}
	local ost_count=${2:-$OSTCOUNT}
	local rc=0
	for num in $(seq $mdt_count); do
		DEVNAME=$(mdsdevname $num)
		writeconf_facet mds$num $DEVNAME || rc=$?
	done
	for num in $(seq $ost_count); do
		DEVNAME=$(ostdevname $num)
		writeconf_facet ost$num $DEVNAME || rc=$?
	done
	return $rc
}
mountmgs() {
	if ! combined_mgs_mds ; then
		start mgs $(mgsdevname) $MGS_MOUNT_OPTS
		do_facet mgs "$LCTL set_param -P debug_raw_pointers=Y"
	fi
}
mountmds() {
	local num
	local devname
	local host
	local varname
	for num in $(seq $MDSCOUNT); do
		devname=$(mdsdevname $num)
		start mds$num $devname $MDS_MOUNT_OPTS
		host=$(facet_host mds$num)
		for varname in mds${num}_HOST mds${num}failover_HOST; do
			if [[ -z "${!varname}" ]]; then
				eval $varname=$host
			fi
		done
		if [[ "$IDENTITY_UPCALL" != "default" ]]; then
			switch_identity $num $IDENTITY_UPCALL
		fi
	done
	if combined_mgs_mds ; then
		do_facet mgs "$LCTL set_param -P debug_raw_pointers=Y"
	fi
}
unmountoss() {
	local num
	for num in $(seq $OSTCOUNT); do
		stop ost$num -f
		rm -f $TMP/ost${num}active
	done
}
mountoss() {
	local num
	local devname
	local host
	local varname
	for num in $(seq $OSTCOUNT); do
		devname=$(ostdevname $num)
		start ost$num $devname $OST_MOUNT_OPTS
		host=$(facet_host ost$num)
		for varname in ost${num}_HOST ost${num}failover_HOST; do
			if [[ -z "${!varname}" ]]; then
				eval $varname=$host
			fi
		done
	done
}
mountcli() {
	[ "$DAEMONFILE" ] && $LCTL debug_daemon start $DAEMONFILE $DAEMONSIZE
	if [ ! -z $arg1 ]; then
		[ "$arg1" = "server_only" ] && return
	fi
	mount_client $MOUNT
	if [ -n "$CLIENTS" ]; then
		zconf_mount_clients $CLIENTS $MOUNT
	fi
	clients_up
	if [ "$MOUNT_2" ]; then
		mount_client $MOUNT2
		if [ -n "$CLIENTS" ]; then
			zconf_mount_clients $CLIENTS $MOUNT2
		fi
	fi
}
sk_nodemap_setup() {
	local sk_map_name=${1:-$SK_S2SNM}
	local sk_map_nodes=${2:-$HOSTNAME}
	do_node $(mgs_node) "$LCTL nodemap_add $sk_map_name"
	for servernode in $sk_map_nodes; do
		local nids=$(do_nodes $servernode "$LCTL list_nids")
		for nid in $nids; do
			do_node $(mgs_node) "$LCTL nodemap_add_range --name \
				$sk_map_name --range $nid"
		done
	done
}
setupall() {
	local arg1=$1
	nfs_client_mode && return
	cifs_client_mode && return
	sanity_mount_check || error "environments are insane!"
	load_modules
	init_gss
	if [ -z "$CLIENTONLY" ]; then
		echo Setup mgs, mdt, osts
		echo $WRITECONF | grep -q "writeconf" && writeconf_all
		if $SK_MOUNTED; then
			echo "Shared Key file system already mounted"
		else
			mountmgs
			mountmds
			mountoss
			if $SHARED_KEY; then
				export SK_MOUNTED=true
			fi
		fi
		if $GSS_SK; then
			echo "GSS_SK: setting kernel keyring perms"
			do_nodes $(comma_list $(all_nodes)) \
				"keyctl show | grep grumple | cut -c1-11 |
				sed -e 's/ //g;' |
				xargs -IX keyctl setperm X 0x3f3f3f3f"
			if $SK_S2S; then
				sk_nodemap_setup $SK_S2SNM \
					$(comma_list $(all_server_nodes))
				mountcli
				sk_nodemap_setup $SK_S2SNMCLI \
					${CLIENTS:-$HOSTNAME}
				echo "Nodemap set up for SK S2S, remounting."
				stopall
				mountmgs
				mountmds
				mountoss
			fi
		fi
	fi
	if $GSS; then
		sleep 10
	fi
	mountcli
	init_param_vars
	[[ $KPTR_ON_MOUNT ]] && kptr_enable_and_save
	if $GSS; then
		if $GSS_SK; then
			set_rule $FSNAME any cli2mdt $SK_FLAVOR
			set_rule $FSNAME any cli2ost $SK_FLAVOR
			if $SK_SKIPFIRST; then
				export SK_SKIPFIRST=false
				sleep 30
				do_nodes $CLIENTS \
					 "lctl set_param osc.*.idle_connect=1"
				return
			else
				wait_flavor cli2mdt $SK_FLAVOR
				wait_flavor cli2ost $SK_FLAVOR
			fi
		else
			set_flavor_all $SEC
		fi
		sleep $((TIMEOUT + 5))
	else
		sleep 5
	fi
}
mounted_grumple_filesystems() {
	awk '($3 ~ "grumple" && $1 ~ ":") { print $2 }' /proc/mounts
}
init_facet_vars () {
	[ -n "$CLIENTONLY" ] && return 0
	local facet=$1
	shift
	local device=$1
	shift
	eval export ${facet}_dev=${device}
	eval export ${facet}_opt=\"$*\"
	local dev=${facet}_dev
	for wait_time in {0,1,3,5,10}; do
		if [ $wait_time -gt 0 ]; then
			echo "${!dev} not yet initialized,"\
				"waiting ${wait_time} seconds."
			sleep $wait_time
		fi
		local label=$(devicelabel ${facet} ${!dev})
		if [[ $label =~ [f|F]{4}$ ]]; then
			unset label
		else
			break
		fi
	done
	[ -z "$label" ] && echo no label for ${!dev} && exit 1
	eval export ${facet}_svc=${label}
	local varname=${facet}failover_HOST
	if [ -z "${!varname}" ]; then
		local temp
		if combined_mgs_mds && [ $facet == "mgs" ] &&
		   [ -n "$mds1failover_HOST" ]; then
			temp=$mds1failover_HOST
		else
			temp=$(facet_host $facet)
		fi
		eval export $varname=$temp
	fi
	varname=${facet}_HOST
	if [ -z "${!varname}" ]; then
		eval export $varname=$(facet_host $facet)
 	fi
	varname=${facet}failover_dev
	if [ -n "${!varname}" ] ; then
		eval export ${facet}failover_dev=${!varname}
	else
		eval export ${facet}failover_dev=$device
	fi
	local mntpt=$(do_facet ${facet} cat /proc/mounts | \
			awk '"'${!dev}'" == $1 && $3 == "grumple" { print $2 }')
	if [ -z $mntpt ]; then
		mntpt=$(facet_mntpt $facet)
	fi
	eval export ${facet}_MOUNT=$mntpt
}
init_facets_vars () {
	local DEVNAME
	if ! remote_mds_nodsh; then
		for num in $(seq $MDSCOUNT); do
			DEVNAME=$(mdsdevname $num)
			init_facet_vars mds$num $DEVNAME $MDS_MOUNT_OPTS
		done
	fi
	init_facet_vars mgs $(mgsdevname) $MGS_MOUNT_OPTS
	if ! remote_ost_nodsh; then
		for num in $(seq $OSTCOUNT); do
			DEVNAME=$(ostdevname $num)
			init_facet_vars ost$num $DEVNAME $OST_MOUNT_OPTS
		done
	fi
}
init_facets_vars_simple () {
	local devname
	if ! remote_mds_nodsh; then
		for num in $(seq $MDSCOUNT); do
			devname=$(mdsdevname $num)
			eval export mds${num}_dev=${devname}
			eval export mds${num}_opt=\"${MDS_MOUNT_OPTS}\"
		done
	fi
	if ! combined_mgs_mds ; then
		eval export mgs_dev=$(mgsdevname)
		eval export mgs_opt=\"${MGS_MOUNT_OPTS}\"
	fi
	if ! remote_ost_nodsh; then
		for num in $(seq $OSTCOUNT); do
			devname=$(ostdevname $num)
			eval export ost${num}_dev=${devname}
			eval export ost${num}_opt=\"${OST_MOUNT_OPTS}\"
		done
	fi
}
osc_ensure_active () {
	local facet=$1
	local timeout=$2
	local period=0
	while [ $period -lt $timeout ]; do
		count=$(do_facet $facet "lctl dl | grep ' IN osc ' 2>/dev/null | wc -l")
		if [ $count -eq 0 ]; then
			break
		fi
		echo "$count OST inactive, wait $period seconds, and try again"
		sleep 3
		period=$((period+3))
	done
	[ $period -lt $timeout ] ||
		log "$count OST are inactive after $timeout seconds, give up"
}
set_conf_param_and_check() {
	local myfacet=$1
	local TEST=$2
	local PARAM=$3
	local ORIG=$(do_facet $myfacet "$TEST")
	if [ $
		local FINAL=$4
	else
		local -i FINAL
		FINAL=$((ORIG + 5))
	fi
	echo "Setting $PARAM from $ORIG to $FINAL"
	do_facet mgs "$LCTL conf_param $PARAM='$FINAL'" ||
		error "conf_param $PARAM failed"
	wait_update_facet $myfacet "$TEST" "$FINAL" ||
		error "check $PARAM failed!"
}
set_persistent_param() {
	local myfacet=$1
	local test_param=$2
	local param=$3
	local orig=$(do_facet $myfacet "$LCTL get_param -n $test_param")
	if [ $
		local final=$4
	else
		local -i final
		final=$((orig + 5))
	fi
	if [[ $PERM_CMD == *"set_param -P"* ]]; then
		echo "Setting $test_param from $orig to $final"
		do_facet mgs "$PERM_CMD $test_param='$final'" ||
			error "$PERM_CMD $test_param failed"
	else
		echo "Setting $param from $orig to $final"
		do_facet mgs "$PERM_CMD $param='$final'" ||
			error "$PERM_CMD $param failed"
	fi
}
set_persistent_param_and_check() {
	local myfacet=$1
	local test_param=$2
	local param=$3
	local orig=$(do_facet $myfacet "$LCTL get_param -n $test_param")
	if [ $
		local final=$4
	else
		local -i final
		final=$((orig + 5))
	fi
	set_persistent_param $myfacet $test_param $param "$final"
	wait_update_facet $myfacet "$LCTL get_param -n $test_param" "$final" ||
		error "check $param failed!"
}
init_param_vars () {
	TIMEOUT=$(lctl get_param -n timeout)
	TIMEOUT=${TIMEOUT:-20}
	if [ -n "$arg1" ]; then
		[ "$arg1" = "server_only" ] && return
	fi
	remote_mds_nodsh && log "Using TIMEOUT=$TIMEOUT" && return 0
	TIMEOUT=$(do_facet $SINGLEMDS "lctl get_param -n timeout")
	log "Using TIMEOUT=$TIMEOUT"
	local mgc_timeout=/sys/module/mgc/parameters/mgc_requeue_timeout_min
	do_nodes $(comma_list $(nodes_list)) \
		"[ -f $mgc_timeout ] && echo 1 > $mgc_timeout; exit 0"
	osc_ensure_active $SINGLEMDS $TIMEOUT
	osc_ensure_active client $TIMEOUT
	$LCTL set_param osc.*.idle_timeout=debug
	if [ -n "$(lctl get_param -n mdc.*.connect_flags|grep jobstats)" ]; then
		local current_jobid_var=$($LCTL get_param -n jobid_var)
		if [ $JOBID_VAR = "existing" ]; then
			echo "keeping jobstats as $current_jobid_var"
		elif [ $current_jobid_var != $JOBID_VAR ]; then
			echo "setting jobstats to $JOBID_VAR"
			set_persistent_param_and_check client \
				"jobid_var" "$FSNAME.sys.jobid_var" $JOBID_VAR
		fi
	else
		echo "jobstats not supported by server"
	fi
	if [ $QUOTA_AUTO -ne 0 ]; then
		if [ "$ENABLE_QUOTA" ]; then
			echo "enable quota as required"
			setup_quota $MOUNT || return 2
		else
			echo "disable quota as required"
		fi
	fi
	(( MDS1_VERSION <= $(version_code 2.13.52) )) ||
		do_facet mgs "$LCTL set_param -P lod.*.mdt_hash=crush"
	return 0
}
nfs_client_mode () {
	if [ "$NFSCLIENT" ]; then
		echo "NFSCLIENT mode: setup, cleanup, check config skipped"
		local clients=$CLIENTS
		[ -z $clients ] && clients=$(hostname)
		do_nodes $clients "echo \\\$(hostname); grep ' '$MOUNT' ' /proc/mounts"
		declare -a nfsexport=(`grep ' '$MOUNT' ' /proc/mounts |
			awk '{print $1}' | awk -F: '{print $1 " "  $2}'`)
		if [[ ${
			error_exit NFSCLIENT=$NFSCLIENT mode, but no NFS export found!
		fi
		do_nodes ${nfsexport[0]} "echo \\\$(hostname); df -T  ${nfsexport[1]}"
		return
	fi
	return 1
}
cifs_client_mode () {
	[ x$CIFSCLIENT = xyes ] &&
		echo "CIFSCLIENT=$CIFSCLIENT mode: setup, cleanup, check config skipped"
}
check_config_client () {
	local mntpt=$1
	local mounted=$(mount | grep " $mntpt ")
	if [ -n "$CLIENTONLY" ]; then
		local mgc=$($LCTL device_list | awk '/MGC/ {print $4}')
		[[ x$MGSNID = x ]] &&
		MGSNID=${mgc//MGC/}
		if [[ x$mgc != xMGC$MGSNID ]]; then
			if [ "$mgs_HOST" ]; then
				local mgc_ip=$(ping -q -c1 -w1 $mgs_HOST |
					grep PING | awk '{print $3}' |
					sed -e "s/(//g" -e "s/)//g")
			fi
		fi
		return 0
	fi
	echo Checking config grumple mounted on $mntpt
	local mgshost=$(mount | grep " $mntpt " | awk -F@ '{print $1}')
	mgshost=$(echo $mgshost | awk -F: '{print $1}')
}
check_config_clients () {
	local clients=${CLIENTS:-$HOSTNAME}
	local mntpt=$1
	nfs_client_mode && return
	cifs_client_mode && return
	do_rpc_nodes "$clients" check_config_client $mntpt
	sanity_mount_check || error "environments are insane!"
}
check_timeout () {
	local mdstimeout=$(do_facet $SINGLEMDS "lctl get_param -n timeout")
	local cltimeout=$(lctl get_param -n timeout)
	if [ $mdstimeout -ne $TIMEOUT ] || [ $mdstimeout -ne $cltimeout ]; then
		error "timeouts are wrong! mds: $mdstimeout, client: $cltimeout, TIMEOUT=$TIMEOUT"
		return 1
	fi
}
is_mounted () {
	local mntpt=$1
	[ -z $mntpt ] && return 1
	local mounted=$(mounted_grumple_filesystems)
	echo $mounted' ' | grep -w -q $mntpt' '
}
create_pools () {
	local pool=$1
	local ostsn=${2:-$OSTCOUNT}
	local npools=${FS_NPOOLS:-$((OSTCOUNT / ostsn))}
	local n
	echo ostsn=$ostsn npools=$npools
	if [[ $ostsn -gt $OSTCOUNT ]];  then
		echo "request to use $ostsn OSTs in the pool, \
			using max available OSTCOUNT=$OSTCOUNT"
		ostsn=$OSTCOUNT
	fi
	for (( n=0; n < $npools; n++ )); do
		p=${pool}$n
		if ! $DELETE_OLD_POOLS; then
			log "request to not delete old pools: $FSNAME.$p exist?"
			if ! check_pool_not_exist $FSNAME.$p; then
				echo "Using existing $FSNAME.$p"
				$LCTL pool_list $FSNAME.$p
				continue
			fi
		fi
		create_pool $FSNAME.$p $KEEP_POOLS ||
			error "create_pool $FSNAME.$p failed"
		local first=$(( (n * ostsn) % OSTCOUNT ))
		local last=$(( (first + ostsn - 1) % OSTCOUNT ))
		if [[ $first -le $last ]]; then
			pool_add_targets $p $first $last ||
				error "pool_add_targets $p $first $last failed"
		else
			pool_add_targets $p $first $(( OSTCOUNT - 1 )) ||
				error "pool_add_targets $p $first \
					$(( OSTCOUNT - 1 )) failed"
			pool_add_targets $p 0 $last ||
				error "pool_add_targets $p 0 $last failed"
		fi
	done
}
set_pools_quota () {
	local u
	local o
	local p
	local i
	local j
	[[ $ENABLE_QUOTA ]] || error "Required Pool Quotas: \
		$POOLS_QUOTA_USERS_SET, but ENABLE_QUOTA not set!"
	declare -a pq_userset=(${POOLS_QUOTA_USERS_SET="mpiuser"})
	declare -a pq_users
	declare -A pq_limits
	for ((i=0; i<${
		u=${pq_userset[i]%%:*}
		o=""
		[[ ${pq_userset[i]} =~ : ]] && o=${pq_userset[i]
		pq_limits[$u]+=" $o"
	done
	pq_users=(${!pq_limits[@]})
	declare -a opts
	local pool
	for ((i=0; i<${
		u=${pq_users[i]}
		$LFS setquota -u $u -B $((2**24 - 1))T $DIR
		opts=(${pq_limits[$u]})
		for ((j=0; j<${
			p=${opts[j]
			o=${opts[j]%%:*}
			if [ $p == $o ];  then
				p=$(list_pool $FSNAME | sed "s/$FSNAME.//")
				echo "No pool specified for $u,
					set limit $o for all existing pools"
			fi
			for pool in $p; do
				$LFS setquota -u $u -B $o --pool $pool $DIR ||
					error "setquota -u $u -B $o --pool $pool failed"
			done
		done
		$LFS quota -uv $u --pool  $DIR
	done
}
do_check_and_setup_grumple() {
	! ${do_setup} && return
	log "=== $TESTSUITE: start setup $(date +'%H:%M:%S (%s)') ==="
	sanitize_parameters
	nfs_client_mode && return
	cifs_client_mode && return
	local MOUNTED=$(mounted_grumple_filesystems)
	local do_check=true
	if ! is_mounted $MOUNT && ! is_mounted $MOUNT2; then
		[ "$REFORMAT" = "yes" ] && CLEANUP_DM_DEV=true formatall
		setupall
		is_mounted $MOUNT || error "NAME=$NAME not mounted"
		export I_MOUNTED=yes
		do_check=false
	elif is_mounted $MOUNT2; then
		if ! [ "$MOUNT_2" ]; then
			cleanup_mount $MOUNT2
			export I_UMOUNTED2=yes
		else
			if ! check_config_clients $MOUNT2; then
				cleanup_mount $MOUNT2
				restore_mount $MOUNT2
				export I_MOUNTED2=yes
			fi
		fi
	elif [ "$MOUNT_2" ]; then
		restore_mount $MOUNT2
		export I_MOUNTED2=yes
	fi
	if $do_check; then
		check_config_clients $MOUNT
		init_facets_vars
		init_param_vars
		set_default_debug_nodes $(comma_list $(nodes_list))
		set_params_clients
	fi
	if [ -z "$CLIENTONLY" -a $(lower $OSD_TRACK_DECLARES_LBUG) == 'yes' ]; then
		local facets=""
		[ "$(facet_fstype ost1)" = "ldiskfs" ] &&
			facets="$(get_facets OST)"
		[ "$(facet_fstype mds1)" = "ldiskfs" ] &&
			facets="$facets,$(get_facets MDS)"
		[ "$(facet_fstype mgs)" = "ldiskfs" ] &&
			facets="$facets,mgs"
		local nodes="$(facets_hosts ${facets})"
		if [ -n "$nodes" ] ; then
			do_nodes $nodes "$LCTL set_param \
				 osd-ldiskfs.track_declares_assert=1 || true"
		fi
	fi
	if [ -n "$fs_STRIPEPARAMS" ]; then
		setstripe_getstripe $MOUNT $fs_STRIPEPARAMS
	fi
	if $GSS_SK; then
		set_flavor_all null
	elif $GSS; then
		set_flavor_all $SEC
	fi
	if $DELETE_OLD_POOLS; then
		destroy_all_pools
	fi
	if [[ -n "$FS_POOL" ]]; then
		create_pools $FS_POOL $FS_POOL_NOSTS
	fi
	if [[ -n "$POOLS_QUOTA_USERS_SET" ]]; then
		set_pools_quota
	fi
	set_params_clients
	set_params_mdts
	set_params_osts
	TESTNAME="start setup" check_dmesg_for_errors ||
		TESTNAME="test_setup" error "Error in dmesg detected"
	log "=== $TESTSUITE: finish setup $(date +'%H:%M:%S (%s)') ==="
	if [[ "$ONLY" == "setup" ]]; then
		exit 0
	fi
}
check_and_setup_grumple() {
	local start_stamp=$(date +%s)
	local saved_umask=$(umask)
	local log=$TESTLOG_PREFIX.test_setup.test_log.$(hostname -s).log
	local status='PASS'
	local stop_stamp=0
	local duration=0
	local error=''
	local rc=0
	umask 0022
	log_sub_test_begin test_setup
	if ! do_check_and_setup_grumple 2>&1 > >(tee -i $log); then
		error=$(tail -1 $log)
		status='FAIL'
		rc=1
	fi
	stop_stamp=$(date +%s)
	duration=$((stop_stamp - start_stamp))
	log_sub_test_end "$status" "$duration" "$rc" "$error"
	umask $saved_umask
	return $rc
}
restore_mount () {
	local clients=${CLIENTS:-$HOSTNAME}
	local mntpt=$1
	zconf_mount_clients $clients $mntpt
}
cleanup_mount () {
	local clients=${CLIENTS:-$HOSTNAME}
	local mntpt=$1
	zconf_umount_clients $clients $mntpt
}
cleanup_and_setup_grumple() {
	if [[ "$ONLY" == "cleanup" ]] || grep -q "$MOUNT" /proc/mounts; then
		lctl set_param debug=0 || true
		cleanupall
		if [[ "$ONLY" == "cleanup" ]]; then
			exit 0
		fi
	fi
	do_check_and_setup_grumple
}
run_e2fsck() {
	local node=$1
	local target_dev=$2
	local extra_opts=$3
	local cmd="$E2FSCK -d -v -t -t -f $extra_opts $target_dev"
	local log=$TMP/e2fsck.log
	local rc=0
	do_node $node $E2FSCK -h 2>&1 | grep -qw -- -m && cmd+=" -m8"
	echo $cmd
	do_node $node $cmd 2>&1 | tee $log
	rc=${PIPESTATUS[0]}
	if [ -n "$(grep "DNE mode isn't supported" $log)" ]; then
		rm -f $log
		if [ $MDSCOUNT -gt 1 ]; then
			skip_noexit "DNE mode isn't supported!"
			cleanupall
			exit_status
		else
			error "It's not DNE mode."
		fi
	fi
	rm -f $log
	[ $rc -le $FSCK_MAX_ERR ] ||
		error "$cmd returned $rc, should be <= $FSCK_MAX_ERR"
	return 0
}
run_resize2fs() {
	local facet=$1
	local device=$2
	local size=$3
	shift 3
	local opts="$@"
	do_facet $facet "$RESIZE2FS $opts $device $size"
}
check_shared_dir() {
	local dir=$1
	local list=${2:-$(comma_list $(nodes_list))}
	[ -z "$dir" ] && return 1
	do_rpc_nodes "$list" check_logdir $dir
	check_write_access $dir "$list" || return 1
	return 0
}
run_lfsck() {
	do_nodes $(tgts_nodes) $LCTL set_param printk=+lfsck
	do_facet $SINGLEMDS "$LCTL lfsck_start -M $FSNAME-MDT0000 -r -A -t all"
	for k in $(seq $MDSCOUNT); do
		wait_update_facet --verbose mds${k} "$LCTL get_param -n \
			mdd.$(facet_svc mds${k}).lfsck_layout |
			awk '/^status/ { print \\\$2 }'" "completed" 600 ||
			error "MDS${k} layout isn't the expected 'completed'"
		wait_update_facet --verbose mds${k} "$LCTL get_param -n \
			mdd.$(facet_svc mds${k}).lfsck_namespace |
			awk '/^status/ { print \\\$2 }'" "completed" 60 ||
			error "MDS${k} namespace isn't the expected 'completed'"
	done
	local repaired=$(do_nodes $(tgts_nodes) \
			 "$LCTL get_param -n *.$FSNAME-*.lfsck_*" |
			 awk '/repaired/ { print $2 }' | calc_sum)
	(( repaired == 0 )) ||
		error "lfsck repaired $rep_mdt MDT and $rep_ost OST errors"
}
dump_file_contents() {
	local nodes=$1
	local dir=$2
	local logname=$3
	local node
	if [ -z "$nodes" -o -z "$dir" -o -z "$logname" ]; then
		error_noexit false \
			"Invalid parameters for dump_file_contents()"
		return 1
	fi
	for node in ${nodes//,/ }; do
		do_node $node "for i in \\\$(find $dir -type f); do
				echo ====\\\${i}=======================;
				cat \\\${i};
				done" >> ${logname}.${node}.log
	done
}
dump_command_output() {
	local nodes=$1
	local cmd=$2
	local logname=$3
	local node
	if [ -z "$nodes" -o -z "$cmd" -o -z "$logname" ]; then
		error_noexit false \
			"Invalid parameters for dump_command_output()"
		return 1
	fi
	for node in ${nodes//,/ }; do
		do_node $node "echo ====${cmd}=======================;
				$cmd" >> ${logname}.${node}.log
	done
}
log_zfs_info() {
	local logname=$1
	if [ "$(facet_fstype ost1)" = "zfs" ]; then
		dump_file_contents "$(osts_nodes)" "/proc/spl" "${logname}"
		dump_command_output \
			"$(osts_nodes)" "zpool events -v" "${logname}"
	fi
	if [ "$(facet_fstype $SINGLEMDS)" = "zfs" ]; then
		dump_file_contents "$(mdts_nodes)" "/proc/spl" "${logname}"
		dump_command_output \
			"$(mdts_nodes)" "zpool events -v" "${logname}"
	fi
}
do_check_and_cleanup_grumple() {
	log "=== $TESTSUITE: start cleanup $(date +'%H:%M:%S (%s)') ==="
	if [[ "$LFSCK_ALWAYS" == "yes" && "$TESTSUITE" != "sanity-lfsck" && \
	      "$TESTSUITE" != "sanity-scrub" ]]; then
		run_lfsck
	fi
	if [[ "$FSTYPE" == "wbcfs" ]]; then
		DO_CLEANUP=false
	fi
	if is_mounted $MOUNT; then
		if $DO_CLEANUP; then
			[[ -n "$DIR" ]] && rm -rf $DIR/[Rdfs][0-9]* ||
				error "remove sub-test dirs failed"
		else
			echo "skip cleanup"
		fi
		[[ -n "$ENABLE_QUOTA" ]] && restore_quota || true
	fi
	if [[ "$I_UMOUNTED2" == "yes" ]]; then
		restore_mount $MOUNT2 || error "restore $MOUNT2 failed"
	fi
	if [[ "$I_MOUNTED2" == "yes" ]]; then
		cleanup_mount $MOUNT2
	fi
	if [[ "$I_MOUNTED" == "yes" ]] && ! $AUSTER_CLEANUP; then
		cleanupall -f || error "cleanup failed"
		unset I_MOUNTED
	fi
	TESTNAME="start cleanup" check_dmesg_for_errors ||
		TESTNAME="test_cleanup" error "Error in dmesg detected"
	log "=== $TESTSUITE: finish cleanup $(date +'%H:%M:%S (%s)') ==="
}
check_and_cleanup_grumple() {
	local start_stamp=$(date +%s)
	local saved_umask=$(umask)
	local log=$TESTLOG_PREFIX.test_cleanup.test_log.$(hostname -s).log
	local status='PASS'
	local stop_stamp=0
	local duration=0
	local error=''
	local rc=0
	umask 0022
	log_sub_test_begin test_cleanup
	if ! do_check_and_cleanup_grumple 2>&1 > >(tee -i $log); then
		error=$(tail -1 $log)
		status='FAIL'
		rc=1
	fi
	stop_stamp=$(date +%s)
	duration=$((stop_stamp - start_stamp))
	log_sub_test_end "$status" "$duration" "$rc" "$error"
	umask $saved_umask
	return $rc
}
wait_for_function () {
	local quiet=""
	if [ "$1" = "--quiet" ]; then
		shift
		quiet=" > /dev/null 2>&1"
	fi
	local fn=$1
	local max=${2:-900}
	local sleep=${3:-5}
	local wait=0
	while true; do
		eval $fn $quiet && return 0
		[ $wait -lt $max ] || return 1
		echo waiting $fn, $((max - wait)) secs left ...
		wait=$((wait + sleep))
		[ $wait -gt $max ] && ((sleep -= wait - max))
		sleep $sleep
	done
}
check_network() {
	local host=$1
	local max=$2
	local sleep=${3:-5}
	[ "$host" = "$HOSTNAME" ] && return 0
	if ! wait_for_function --quiet "ping -c 1 -w 3 $host" $max $sleep; then
		echo "$(date +'%H:%M:%S (%s)') waited for $host network ${max}s"
		exit 1
	fi
}
no_dsh() {
	shift
	eval "$@"
}
comma_list() {
	echo $(tr -s ", " "\n" <<< $* | sort -b -u) | tr ' ' ','
}
list_member () {
	local list=$1
	local item=$2
	echo $list | grep -qw $item
}
exclude_items_from_list () {
	local list=$1
	local excluded=$2
	local item
	list=${list//,/ }
	for item in ${excluded//,/ }; do
		list=$(echo " $list " | sed -re "s/\s+$item\s+/ /g")
	done
	echo $(comma_list $list)
}
expand_list () {
	local list=${1//,/ }
	local expand=${2//,/ }
	local expanded=
	expanded=$(for i in $list $expand; do echo $i; done | sort -u)
	echo $(comma_list $expanded)
}
testslist_filter () {
	local script=$LUSTRE/tests/${TESTSUITE}.sh
	[ -f $script ] || return 0
	local start_at=$START_AT
	local stop_at=$STOP_AT
	local var=${TESTSUITE//-/_}_START_AT
	[ x"${!var}" != x ] && start_at=${!var}
	var=${TESTSUITE//-/_}_STOP_AT
	[ x"${!var}" != x ] && stop_at=${!var}
	sed -n 's/^test_\([^ (]*\).*/\1/p' $script |
	awk ' BEGIN { if ("'${start_at:-0}'" != 0) flag = 1 }
	    /^'${start_at}'$/ {flag = 0}
	    {if (flag == 1) print $0}
	    /^'${stop_at}'$/ { flag = 1 }'
}
absolute_path() {
	(cd `dirname $1`; echo $PWD/`basename $1`)
}
get_facets () {
	local types=${*:-"OST MDS MGS"}
	local list=""
	for entry in $types; do
		local name=$(echo $entry | tr "[:upper:]" "[:lower:]")
		local type=$(echo $entry | tr "[:lower:]" "[:upper:]")
		case $type in
			MGS ) list="$list $name";;
			MDS|OST|AGT ) local count=${type}COUNT
				for ((i=1; i<=${!count}; i++)) do
					list="$list ${name}$i"
				done;;
			* ) error "Invalid facet type"
				exit 1;;
		esac
	done
	echo $(comma_list $list)
}
at_is_enabled() {
	local at_max=$(do_facet $SINGLEMDS "lctl get_param -n at_max")
	if [ $at_max -eq 0 ]; then
		return 1
	else
		return 0
	fi
}
at_get() {
	local facet=$1
	local at=$2
	[ $facet != "ost" ] || facet=ost1
	do_facet $facet "lctl get_param -n $at"
}
at_max_get() {
	at_get $1 at_max
}
at_max_set() {
	local at_max=$1
	shift
	local facet
	local hosts
	for facet in "$@"; do
		if [ $facet == "ost" ]; then
			facet=$(get_facets OST)
		elif [ $facet == "mds" ]; then
			facet=$(get_facets MDS)
		fi
		hosts=$(expand_list $hosts $(facets_hosts $facet))
	done
	do_nodes $hosts lctl set_param at_max=$at_max
}
at_min_get() {
	at_get $1 at_min
}
at_min_set() {
	local at_min=$1
	shift
	local facet
	local hosts
	for facet in "$@"; do
		if [ $facet == "ost" ]; then
			facet=$(get_facets OST)
		elif [ $facet == "mds" ]; then
			facet=$(get_facets MDS)
		fi
		hosts=$(expand_list $hosts $(facets_hosts $facet))
	done
	do_nodes $hosts lctl set_param at_min=$at_min
}
drop_request() {
	RC=0
	do_facet $SINGLEMDS lctl set_param fail_val=0 fail_loc=0x123
	do_facet client "$1" || RC=$?
	do_facet $SINGLEMDS lctl set_param fail_loc=0
	return $RC
}
drop_reply() {
	RC=0
	do_facet $SINGLEMDS $LCTL set_param fail_loc=0x122
	eval "$@" || RC=$?
	do_facet $SINGLEMDS $LCTL set_param fail_loc=0
	return $RC
}
drop_reint_reply() {
	RC=0
	do_facet $SINGLEMDS $LCTL set_param fail_loc=0x119
	eval "$@" || RC=$?
	do_facet $SINGLEMDS $LCTL set_param fail_loc=0
	return $RC
}
drop_update_reply() {
	local index=$1
	shift 1
	local rc=0
	do_facet mds${index} $LCTL set_param fail_loc=0x1701
	do_facet client "$@" || rc=$?
	do_facet mds${index} $LCTL set_param fail_loc=0
	return $rc
}
pause_bulk() {
	local cmd=${1:-0}
	local timeout=${2:-0}
	local rc=0
	echo "timeout is $timeout"
	do_facet ost1 $LCTL set_param fail_val=$timeout fail_loc=0x80000214
	do_facet client "$cmd" || rc=$?
	do_facet client "sync"
	do_facet ost1 $LCTL set_param fail_loc=0
	return $rc
}
drop_ldlm_cancel() {
	local tgts=$(tgts_nodes)
	local rc=0
	do_nodes $tgts $LCTL set_param fail_loc=0x304
	do_facet client "$@" || rc=$?
	do_nodes $tgts $LCTL set_param fail_loc=0
	return $rc
}
drop_bl_callback_once() {
	local rc=0
	do_facet client lctl set_param ldlm.namespaces.*.early_lock_cancel=0
	do_facet client lctl set_param fail_loc=0x80000305
	do_facet client "$@" || rc=$?
	do_facet client lctl set_param fail_loc=0
	do_facet client lctl set_param fail_val=0
	do_facet client lctl set_param ldlm.namespaces.*.early_lock_cancel=1
	return $rc
}
drop_bl_callback() {
	rc=0
	do_facet client lctl set_param ldlm.namespaces.*.early_lock_cancel=0
	do_facet client lctl set_param fail_loc=0x305
	do_facet client "$@" || rc=$?
	do_facet client lctl set_param fail_loc=0
	do_facet client lctl set_param fail_val=0
	do_facet client lctl set_param ldlm.namespaces.*.early_lock_cancel=1
	return $rc
}
drop_mdt_ldlm_reply() {
	RC=0
	local mdts=$(mdts_nodes)
	do_nodes $mdts lctl set_param fail_loc=0x157
	do_facet client "$@" || RC=$?
	do_nodes $mdts lctl set_param fail_loc=0
	return $RC
}
drop_mdt_ldlm_reply_once() {
	RC=0
	local mdts=$(mdts_nodes)
	do_nodes $mdts lctl set_param fail_loc=0x80000157
	do_facet client "$@" || RC=$?
	do_nodes $mdts lctl set_param fail_loc=0
	return $RC
}
clear_failloc() {
	local facet=$1
	local pause=$2
	sleep $pause
	echo "clearing fail_loc on $facet"
	do_facet $facet "lctl set_param fail_loc=0 2>/dev/null || true"
}
set_nodes_failloc () {
	local fv=${3:-0}
	do_nodes $(comma_list $1)  lctl set_param fail_val=$fv fail_loc=$2
}
total_unused_locks() {
	$LCTL get_param -n "ldlm.namespaces.*$1*.lock_unused_count" | calc_sum
}
total_used_locks() {
	$LCTL get_param -n "ldlm.namespaces.*$1*.lock_count" | calc_sum
}
cancel_lru_locks() {
	$LCTL set_param -t4 -n "ldlm.namespaces.*$1*.lru_size=clear"
	$LCTL get_param "ldlm.namespaces.*$1*.lock_unused_count" | grep -v '=0'
}
default_lru_size()
{
	local nr_cpu=$(grep -c "processor" /proc/cpuinfo)
	echo $((100 * nr_cpu))
}
lru_resize_enable()
{
	$LCTL set_param -n ldlm.namespaces.*$1*.lru_size=0
}
lru_resize_disable()
{
	local dev=${1}
	local lru_size=${2:-$(default_lru_size)}
	local size_param="ldlm.namespaces.*$dev*.lru_size"
	local age_param="ldlm.namespaces.*$dev*.lru_max_age"
	local old_age=($($LCTL get_param -n $age_param))
	echo "$size_param=0->$lru_size"
	echo "$age_param=$old_age->3900s"
	$LCTL set_param -n $size_param=$lru_size
	$LCTL set_param -n $age_param=3900s
	stack_trap "cancel_lru_locks $dev || true"
	stack_trap "lru_resize_enable $dev || true"
	stack_trap "$LCTL set_param -n $age_param=$old_age || true"
}
flock_is_enabled()
{
	local mountpath=${1:-$MOUNT}
	local RC=0
	[ -z "$(mount | grep "$mountpath .*flock" | grep -v noflock)" ] && RC=1
	return $RC
}
pgcache_empty() {
	local FILE
	for FILE in `lctl get_param -N "llite.*.dump_page_cache"`; do
		if [ `lctl get_param -n $FILE | wc -l` -gt 1 ]; then
			echo there is still data in page cache $FILE ?
			lctl get_param -n $FILE
			return 1
		fi
	done
	return 0
}
debugsave() {
	DEBUGSAVE="$(lctl get_param -n debug)"
	DEBUGSAVE_SERVER=$(do_facet $SINGLEMDS "$LCTL get_param -n debug")
}
debugrestore() {
	[ -n "$DEBUGSAVE" ] &&
		do_nodes $CLIENTS $LCTL set_param -n debug=${DEBUGSAVE// /+} ||
		true
	DEBUGSAVE=""
	[ -n "$DEBUGSAVE_SERVER" ] &&
		do_nodes $(comma_list $(all_server_nodes)) \
			 $LCTL set_param -n debug=${DEBUGSAVE_SERVER// /+} ||
			 true
	DEBUGSAVE_SERVER=""
}
debug_size_save() {
	DEBUG_SIZE_SAVED="$(lctl get_param -n debug_mb)"
}
debug_size_restore() {
	[ -n "$DEBUG_SIZE_SAVED" ] &&
		do_nodes $(comma_list $(nodes_list)) "$LCTL set_param debug_mb=$DEBUG_SIZE_SAVED"
	DEBUG_SIZE_SAVED=""
}
start_full_debug_logging() {
	debugsave
	debug_size_save
	local fulldebug=-1
	local debug_size=150
	local nodes=$(comma_list $(nodes_list))
	do_nodes $nodes "$LCTL set_param debug=$fulldebug debug_mb=$debug_size"
}
stop_full_debug_logging() {
	debug_size_restore
	debugrestore
}
print_stack_trace() {
	local skip=${1:-1}
	echo "  Trace dump:"
	for (( i=$skip; i < ${
		local src=${BASH_SOURCE[$i]}
		local lineno=${BASH_LINENO[$i-1]}
		local funcname=${FUNCNAME[$i]}
		echo "  = $src:$lineno:$funcname()"
	done
}
report_error() {
	local TYPE=${TYPE:-"FAIL"}
	local dump=true
	if [ "x$1" = "xfalse" ]; then
		shift
		dump=false
	fi
	log " ${TESTSUITE} ${TESTNAME}: @@@@@@ ${TYPE}: $* "
	(print_stack_trace 2) >&2
	mkdir -p $LOGDIR
	if $dump; then
		gather_logs $(comma_list $(nodes_list))
	fi
	debugrestore
	[ "$TESTSUITELOG" ] &&
		echo "$TESTSUITE: $TYPE: $TESTNAME $*" >> $TESTSUITELOG
	if [ -z "$*" ]; then
		echo "error() without useful message, please fix" > $LOGDIR/err
	else
		if [[ `echo $TYPE | grep ^IGNORE` ]]; then
			echo "$@" > $LOGDIR/ignore
		else
			echo "$@" > $LOGDIR/err
		fi
	fi
	reset_fail_loc
}
stack_trap()
{
	local arg="$1"
	local sigspec="${2:-EXIT}"
	local old_trap="$(trap -p "$sigspec")"
	old_trap="${old_trap:+"; ${old_trap
	local new_trap="$(trap -- "$arg" "$sigspec"
			  trap -p "$sigspec"
			  trap -- '' "$sigspec")"
	eval "${new_trap%\' $sigspec}${old_trap:-"' $sigspec"}"
}
error_noexit() {
	report_error "$@"
}
exit_status () {
	local status=0
	local logs="$TESTSUITELOG $1"
	for log in $logs; do
		if [ -f "$log" ]; then
			grep -qw FAIL $log && status=1
		fi
	done
	exit $status
}
error() {
	report_error "$@"
	exit 1
}
error_exit() {
	report_error "$@"
	exit 1
}
error_ignore() {
	local TYPE="IGNORE ($1)"
	shift
	report_error false "$@"
}
error_and_remount() {
	report_error "$@"
	remount_client $MOUNT
	exit 1
}
error_not_in_vm() {
	local virt=$(running_in_vm)
	if [[ -n "$virt" ]]; then
		echo "running in VM '$virt', ignore error"
		error_ignore env=$virt "$@"
	else
		error "$@"
	fi
}
skip_env () {
	$FAIL_ON_SKIP_ENV && error false "$@" || skip "$@"
}
skip_noexit() {
	echo
	log " SKIP: $TESTSUITE $TESTNAME $*"
	if [[ -n "$ALWAYS_SKIPPED" ]]; then
		skip_logged $TESTNAME "$@"
	else
		mkdir -p $LOGDIR
		echo "$@" > $LOGDIR/skip
	fi
	[[ -n "$TESTSUITELOG" ]] &&
		echo "$TESTSUITE: SKIP: $TESTNAME $*" >> $TESTSUITELOG || true
	unset TESTNAME
}
skip() {
	skip_noexit "$@"
	exit 0
}
skip_eopnotsupp() {
	local retstr=$@
	echo $retstr | awk -F'|' '{print $1}' |
		grep -E unsupported\|"(Operation not supported)"
	(( $? == 0 )) || error "$retstr"
	skip $retstr
}
function \
always_except() {
	local issue="${1:-}"
	local test_num
	shift
	if ! [[ "$issue" =~ ^[[:upper:]]+-[[:digit:]]+$ ]]; then
		error "always_except: invalid issue '$issue' for tests '$*'"
	fi
	for test_num in "$@"; do
		ALWAYS_EXCEPT+=" $test_num"
	done
}
build_test_filter() {
	EXCEPT="$EXCEPT $(testslist_filter)"
	for O in ${ONLY//[+,]/ }; do
		if [[ $O =~ [0-9]*-[0-9]* ]]; then
			for ((num=${O%-[0-9]*}; num <= ${O
				eval ONLY_$num=true
			done
		else
			eval ONLY_${O}=true
		fi
	done
	local nodes=$(comma_list $(facets_nodes mds1,ost1))
	local exceptions="$LUSTRE/tests/except/$TESTSUITE.*ex"
	do_nodes --verbose $nodes "ls $exceptions || true"
	while read facet op need_ver jira subs; do
		local have_ver_code=${facet^^*}_VERSION
		local need_ver_code
		[[ "$facet" =~ "
		[[ "$need_ver" =~ _VERSION ]] && need_ver_code=${!need_ver} ||
			need_ver_code=$(version_code $need_ver)
		(( ${!have_ver_code} $op $need_ver_code )) &&
			echo "- see $have_ver_code $op $need_ver (${!have_ver_code} $op $need_ver_code) for $jira, go $subs" ||
		{
			log "- need $have_ver_code $op $need_ver (${!have_ver_code} $op $need_ver_code) for $jira, skip $subs"
			for E in $subs; do
				eval EXCEPT_${E}=true
			done
		}
	done < <(do_nodes $nodes "cat $exceptions 2>/dev/null ||true" | sort -u)
	[[ -z "$EXCEPT$ALWAYS_EXCEPT" ]] ||
		log "excepting tests: $(echo $EXCEPT $ALWAYS_EXCEPT)"
	[[ -z "$EXCEPT_SLOW" ]] ||
		log "skipping tests SLOW=no: $(echo $EXCEPT_SLOW)"
	for E in ${EXCEPT//[+,]/ }; do
		eval EXCEPT_${E}=true
	done
	for E in ${ALWAYS_EXCEPT//[+,]/ }; do
		eval EXCEPT_ALWAYS_${E}=true
	done
	for E in ${EXCEPT_SLOW//[+,]/ }; do
		eval EXCEPT_SLOW_${E}=true
	done
	for G in ${GRANT_CHECK_LIST//[+,]/ }; do
		eval GCHECK_ONLY_${G}=true
	done
	for T in $STOP_ON_ERROR; do
		eval STOP_ON_ERROR_${T}=true
	done
}
basetest() {
	if [[ $1 = [a-z]* ]]; then
		echo $1
	else
		echo ${1%%[a-zA-Z]*}
	fi
}
export LAST_SKIPPED=
export ALWAYS_SKIPPED=
run_test() {
	assert_DIR
	local testnum=$1
	local testmsg=$2
	export base=$(basetest $testnum)
	export TESTNAME=test_$testnum
	LAST_SKIPPED=
	ALWAYS_SKIPPED=
	local isexcept=EXCEPT_$testnum
	local isexcept_base=EXCEPT_$base
	if [ ${!isexcept}x != x ]; then
		ALWAYS_SKIPPED="y"
		skip_message="skipping excluded test $testnum"
	elif [ ${!isexcept_base}x != x ]; then
		ALWAYS_SKIPPED="y"
		skip_message="skipping excluded test $testnum (base $base)"
	fi
	isexcept=EXCEPT_ALWAYS_$testnum
	isexcept_base=EXCEPT_ALWAYS_$base
	if [ ${!isexcept}x != x ]; then
		ALWAYS_SKIPPED="y"
		skip_message="skipping ALWAYS excluded test $testnum"
	elif [ ${!isexcept_base}x != x ]; then
		ALWAYS_SKIPPED="y"
		skip_message="skipping ALWAYS excluded test $testnum (base $base)"
	fi
	isexcept=EXCEPT_SLOW_$testnum
	isexcept_base=EXCEPT_SLOW_$base
	if [ ${!isexcept}x != x ]; then
		ALWAYS_SKIPPED="y"
		skip_message="skipping SLOW test $testnum"
	elif [ ${!isexcept_base}x != x ]; then
		ALWAYS_SKIPPED="y"
		skip_message="skipping SLOW test $testnum (base $base)"
	fi
	if [ -n "$ONLY" ]; then
		local isonly=ONLY_$testnum
		local isonly_base=ONLY_$base
		if [[ ${!isonly}x != x || ${!isonly_base}x != x ]]; then
			if [[ -n "$ALWAYS_SKIPPED" &&
					-n "$HONOR_EXCEPT" ]]; then
				LAST_SKIPPED="y"
				skip_noexit "$skip_message"
				return 0
			else
				[ -n "$LAST_SKIPPED" ] &&
					echo "" && LAST_SKIPPED=
				ALWAYS_SKIPPED=
				run_one_logged $testnum "$testmsg"
				return $?
			fi
		else
			LAST_SKIPPED="y"
			return 0
		fi
	fi
	if [ -n "$ALWAYS_SKIPPED" ]; then
		LAST_SKIPPED="y"
		skip_noexit "$skip_message"
		return 0
	else
		run_one_logged $testnum "$testmsg"
		if [[ "$FSTYPE" == "wbcfs" ]]; then
			rm -rf "$MOUNT/*"
		fi
		return $?
	fi
}
log() {
	echo "$*" >&2
	load_module ../libcfs/libcfs/libcfs
	local MSG="$*"
	MSG=${MSG//\'/\\\'}
	MSG=${MSG//\*/\\\*}
	MSG=${MSG//\(/\\\(}
	MSG=${MSG//\)/\\\)}
	MSG=${MSG//\;/\\\;}
	MSG=${MSG//\|/\\\|}
	MSG=${MSG//\>/\\\>}
	MSG=${MSG//\</\\\<}
	MSG=${MSG//\//\\\/}
	do_nodes $(comma_list $(nodes_list)) $LCTL mark "$MSG" 2> /dev/null || true
}
trace() {
	log "STARTING: $*"
	strace -o $TMP/$1.strace -ttt $*
	RC=$?
	log "FINISHED: $*: rc $RC"
	return 1
}
complete_test() {
	local duration=$1
	banner "test complete, duration $duration sec"
	[ -f "$TESTSUITELOG" ] && egrep .FAIL $TESTSUITELOG || true
	echo "duration $duration" >>$TESTSUITELOG
}
pass() {
	TEST_STATUS="PASS"
	if [[ -f $LOGDIR/err ]]; then
		TEST_STATUS="FAIL"
	elif [[ -f $LOGDIR/skip ]]; then
		TEST_STATUS="SKIP"
	fi
	echo "$TEST_STATUS $*" 2>&1 | tee -a $TESTSUITELOG
}
check_mds() {
	local ffree=$(do_node $SINGLEMDS \
		      $LCTL get_param -n osd*.*MDT*.filesfree | calc_sum)
	local ftotaL=$(do_node $SINGLEMDS \
		       $LCTL get_param -n osd*.*MDT*.filestotal | calc_sum)
	(( $ffree < $ftotal )) || error "files free $ffree >= total $ftotal"
}
reset_fail_loc () {
	do_nodes --quiet $(comma_list $(nodes_list)) \
		"lctl set_param -n fail_loc=0 fail_val=0 2>/dev/null" || true
}
EQUALS="========================================================"
banner() {
	msg="== ${TESTSUITE} $*"
	last=${msg: -1:1}
	[[ $last != "=" && $last != " " ]] && msg="$msg "
	msg=$(printf '%s%.*s'  "$msg"  $((${
	log "$msg== $(date +"%H:%M:%S (%s)")"
}
check_dmesg_for_errors() {
	local res
	local errors
	local testid=$(tr '_' ' ' <<< $TESTNAME)
	errors="VFS: Busy inodes after unmount of"
	errors+="\|ldiskfs_check_descriptors: Checksum for group 0 failed"
	errors+="\|group descriptors corrupted"
	errors+="\|UBSAN\|KASAN"
	res=$(do_nodes -q $(comma_list $(nodes_list)) "dmesg" |
		tac | sed "/$testid/,$ d" | grep "$errors")
	[[ -n "$res" ]] || return 0
	echo "Kernel error detected: $res"
	return 1
}
run_one() {
	local testnum=$1
	local testmsg="$2"
	local SAVE_UMASK=`umask`
	umask 0022
	if ! grep -q $DIR /proc/mounts; then
		$SETUP
	fi
	banner "test $testnum: $testmsg"
	test_${testnum} || error "test_$testnum failed with $?"
	cd $SAVE_PWD
	reset_fail_loc
	check_grant ${testnum} || error "check_grant $testnum failed with $?"
	check_node_health
	check_dmesg_for_errors || error "Error in dmesg detected"
	if [ "$PARALLEL" != "yes" ]; then
		ps auxww | grep -v grep | grep -q "multiop " &&
					error "multiop still running"
	fi
	umask $SAVE_UMASK
	$CLEANUP
	return 0
}
run_one_logged() {
	local before=$SECONDS
	local testnum=$1
	local testmsg=$2
	export tfile=f${testnum}.${TESTSUITE}
	export tdir=d${testnum}.${TESTSUITE}
	local test_log=$TESTLOG_PREFIX.$TESTNAME.test_log.$(hostname -s).log
	local zfs_debug_log=$TESTLOG_PREFIX.$TESTNAME.zfs_log
	local SAVE_UMASK=$(umask)
	local rc=0
	local node
	umask 0022
	[[ $KPTR_ON_MOUNT ]] || kptr_enable_and_save
	rm -f $LOGDIR/err $LOGDIR/ignore $LOGDIR/skip
	echo
	local repeat=${ONLY:+$ONLY_REPEAT}
	if [[ -n "$ONLY" && "$ONLY_MINUTES" ]]; then
		local repeat_end_sec=$((SECONDS + ONLY_MINUTES * 60))
	fi
	export ONLY_REPEAT_ITER=1
	while true; do
		local before_sub=$SECONDS
		local iter
		log_sub_test_begin $TESTNAME
		if [[ -n "$append" ]]; then
			[[ -n "$tdir" ]] && rm -rvf $DIR/$tdir*
			[[ -n "$tfile" ]] && rm -vf $DIR/$tfile*
			iter=" (repeat $ONLY_REPEAT_ITER/$repeat iter, $(((SECONDS-before)/60))/$ONLY_MINUTES min)"
		fi
		(run_one $testnum "$testmsg$iter") 2>&1 | tee -i $append $test_log
		rc=${PIPESTATUS[0]}
		local append=-a
		local duration_sub=$((SECONDS - before_sub))
		local test_error
		[[ $rc != 0 && ! -f $LOGDIR/err ]] &&
			echo "$TESTNAME returned $rc" | tee $LOGDIR/err
		if [[ -f $LOGDIR/err ]]; then
			test_error=$(cat $LOGDIR/err)
			TEST_STATUS="FAIL"
		elif [[ -f $LOGDIR/ignore ]]; then
			test_error=$(cat $LOGDIR/ignore)
		elif [[ -f $LOGDIR/skip ]]; then
			test_error=$(cat $LOGDIR/skip)
			TEST_STATUS="SKIP"
		else
			TEST_STATUS="PASS"
		fi
		pass "$testnum" "(${duration_sub}s)"
		if [ -n "${DUMP_OK}" ]; then
			gather_logs $(comma_list $(nodes_list))
		fi
		log_sub_test_end $TEST_STATUS $duration_sub "$rc" "$test_error"
		[[ $TEST_STATUS == "FAIL" ]] &&
			[[ -v STOP_ON_ERROR_$testnum ]] &&
			exit $STOP_NOW_RC
		[[ $rc != 0 || "$TEST_STATUS" != "PASS" ]] && break
		[[ -z "$repeat" && -z "$repeat_end_sec" ]] && break
		[[ -n "$repeat" ]] && (( ONLY_REPEAT_ITER >= repeat )) && break
		[[ -n "$repeat_end_sec" ]] &&
			(( $SECONDS >= $repeat_end_sec )) && break
		((ONLY_REPEAT_ITER++))
	done
	[[ $KPTR_ON_MOUNT ]] || kptr_restore
	if [[ "$TEST_STATUS" != "SKIP" && -f $TF_SKIP ]]; then
		rm -f $TF_SKIP
	fi
	if [ -f $LOGDIR/err ]; then
		log_zfs_info "$zfs_debug_log"
		$FAIL_ON_ERROR && exit $rc
	fi
	umask $SAVE_UMASK
	unset TESTNAME
	unset tdir
	unset tfile
	return 0
}
skip_logged(){
	log_sub_test_begin $1
	shift
	log_sub_test_end "SKIP" "0" "0" "$@"
}
grant_from_clients() {
	local nodes="$1"
	do_nodes $nodes "$LCTL get_param -n osc.${FSNAME}-*.cur_*grant_bytes" |
		calc_sum
}
grant_from_servers() {
	local nodes="$1"
	do_nodes $nodes "$LCTL get_param obdfilter.${FSNAME}-OST*.tot_granted" \
		" obdfilter.${FSNAME}-OST*.tot_pending" \
		" obdfilter.${FSNAME}-OST*.grant_precreate" |
		tr '=' ' ' | awk '/tot_granted/{ total += $2 };
				  /tot_pending/{ total -= $2 };
				  /grant_precreate/{ total -= $2 };
				  END { printf("%0.0f", total) }'
}
check_grant() {
	export base=$(basetest $1)
	[ "$CHECK_GRANT" == "no" ] && return 0
	local isonly_base=GCHECK_ONLY_${base}
	local isonly=GCHECK_ONLY_$1
	[ ${!isonly_base}x == x -a ${!isonly}x == x ] && return 0
	echo -n "checking grant......"
	local osts=$(osts_nodes)
	local clients=$CLIENTS
	[ -z "$clients" ] && clients=$(hostname)
	do_nodes $clients sync
	do_nodes $clients $LFS df
	cli_grant=$(grant_from_clients $clients)
	srv_grant=$(grant_from_servers $osts)
	count=0
	while [[ $cli_grant != $srv_grant && count++ -lt 30 ]]; do
		echo "wait for client:$cli_grant == server:$srv_grant"
		sleep 1
		cli_grant=$(grant_from_clients $clients)
		srv_grant=$(grant_from_servers $osts)
	done
	if [[ $cli_grant -ne $srv_grant ]]; then
		do_nodes $osts "$LCTL get_param obdfilter.${FSNAME}-OST*.tot*" \
			"obdfilter.${FSNAME}-OST*.grant_*"
		do_nodes $clients "$LCTL get_param osc.${FSNAME}-*.cur_*_bytes"
		error "failed grant check: client:$cli_grant server:$srv_grant"
	else
		echo "pass grant check: client:$cli_grant server:$srv_grant"
	fi
}
osc_to_ost() {
	local osc=$1
	echo ${osc/-osc*/}
}
ostuuid_from_index() {
	local uuid=($($LFS osts $2 | sed -ne "/^$1: /s/.* \(.*\) .*$/\1/p"))
	echo ${uuid}
}
ostname_from_index() {
	local uuid=$(ostuuid_from_index $1 $2)
	echo ${uuid/_UUID/}
}
mdtuuid_from_index() {
	local uuid=($($LFS mdts $2 | sed -ne "/^$1: /s/.* \(.*\) .*$/\1/p"))
	echo ${uuid}
}
mdtname_from_index() {
	local uuid=$(mdtuuid_from_index $1 $2)
	echo ${uuid/_UUID/}
}
mdssize_from_index() {
	local mdt=$(mdtname_from_index $2)
	$LFS df $1 | awk "/$mdt/ { print \$2 }"
}
index_from_ostuuid()
{
	local ostidx=($($LFS osts $2 | sed -ne "/${1}/s/\(.*\): .* .*$/\1/p"))
	echo ${ostidx}
}
host_id() {
	local host_name=$1
	echo $host_name | md5sum | cut -d' ' -f1
}
local_addr_list() {
	ip -o a s | awk '{print $4}' | awk -F/ '{print $1}'
}
lnet_if_list() {
	local nids=( $($LCTL list_nids | xargs echo) )
	[[ -z ${nids[@]} ]] &&
		return 0
	if [[ ${NETTYPE} =~ kfi* ]]; then
		$LNETCTL net show 2>/dev/null | awk '/ cxi[0-9]+$/{print $NF}' |
			sort -u | xargs echo
		return 0
	fi
	declare -a INTERFACES
	for ((i = 0; i < ${
		ip=$(sed 's/^\(.*\)@.*$/\1/'<<<${nids[i]})
		INTERFACES[i]=$(ip -o a s |
				awk '$4 ~ /^'$ip'\//{print $2}')
		INTERFACES=($(echo "${INTERFACES[@]}" | tr ' ' '\n' | uniq | tr '\n' ' '))
		if [[ -z ${INTERFACES[i]} ]]; then
			error "Can't determine interface name for NID ${nids[i]}"
		elif [[ 1 -ne $(wc -w <<<${INTERFACES[i]}) ]]; then
			error "Found $(wc -w <<<${INTERFACES[i]}) interfaces for NID ${nids[i]}. Expect 1"
		fi
	done
	echo "${INTERFACES[@]}"
	return 0
}
is_local_addr() {
	local addr=$1
	LOCAL_ADDR_LIST=${LOCAL_ADDR_LIST:-$(local_addr_list)}
	local i
	for i in $LOCAL_ADDR_LIST ; do
		[[ "$i" == "$addr" ]] && return 0
	done
	return 1
}
local_node() {
	local host_name=$1
	local is_local="IS_LOCAL_$(host_id $host_name)"
	if [ -z "${!is_local-}" ] ; then
		eval $is_local=false
		local ip4=$(getent ahostsv4 $host_name |
			    awk 'NR == 1 { print $1 }')
		local ip6=$(getent ahostsv6 $host_name |
			    awk 'NR == 1 { print $1 }')
		if is_local_addr $ip4 || is_local_addr $ip6 ; then
			eval $is_local=true
		fi
	fi
	${!is_local}
}
remote_node() {
	local node=$1
	! local_node $node
}
remote_mds()
{
	local mdts=$(mdts_nodes)
	local node
	for node in ${mdts//,/ }; do
		remote_node $node && return 0
	done
	return 1
}
remote_mds_nodsh()
{
	[ -n "$CLIENTONLY" ] && return 0 || true
	remote_mds && [ "$PDSH" = "no_dsh" -o -z "$PDSH" -o -z "$mds_HOST" ]
}
require_dsh_mds()
{
	remote_mds_nodsh && echo "SKIP: $TESTSUITE: remote MDS with nodsh" &&
		MSKIPPED=1 && return 1
	return 0
}
remote_ost()
{
	local osts=$(osts_nodes)
	local node
	for node in ${osts//,/ }; do
		remote_node $node && return 0
	done
	return 1
}
remote_ost_nodsh()
{
	[ -n "$CLIENTONLY" ] && return 0 || true
	remote_ost && [ "$PDSH" = "no_dsh" -o -z "$PDSH" -o -z "$ost_HOST" ]
}
require_dsh_ost()
{
	remote_ost_nodsh && echo "SKIP: $TESTSUITE: remote OST with nodsh" &&
		OSKIPPED=1 && return 1
	return 0
}
remote_mgs_nodsh()
{
	[ -n "$CLIENTONLY" ] && return 0 || true
	local MGS
	MGS=$(facet_host mgs)
	remote_node $MGS && [ "$PDSH" = "no_dsh" -o -z "$PDSH" -o -z "$ost_HOST" ]
}
local_mode ()
{
	remote_mds_nodsh || remote_ost_nodsh ||
		$(single_local_node $(comma_list $(nodes_list)))
}
remote_servers () {
	remote_ost && remote_mds
}
facets_nodes () {
	local facets=$1
	local facet
	local nodes
	local nodes_sort
	local i
	for facet in ${facets//,/ }; do
		nodes="$nodes $(facet_active_host $facet)"
	done
	nodes_sort=$(for i in ${nodes//,/ }; do echo $i; done | sort -u)
	echo -n $nodes_sort
}
mgs_node () {
	echo -n $(facets_nodes $(get_facets MGS))
}
mdts_nodes() {
	comma_list $(facets_nodes $(get_facets MDS))
}
osts_nodes() {
	comma_list $(facets_nodes $(get_facets OST))
}
tgts_nodes() {
	comma_list $(facets_nodes $(get_facets MDS OST))
}
nodes_list () {
	local nodes=$HOSTNAME
	local nodes_sort
	local i
	[ -n "$CLIENTS" ] && nodes=${CLIENTS//,/ }
	if [ "$PDSH" -a "$PDSH" != "no_dsh" ]; then
		nodes="$nodes $(facets_nodes $(get_facets))"
	fi
	nodes_sort=$(for i in ${nodes//,/ }; do echo $i; done | sort -u)
	echo -n $nodes_sort
}
remote_nodes_list () {
	echo -n $(nodes_list) | sed -re "s/\<$HOSTNAME\>//g"
}
all_mdts_nodes () {
	local host
	local failover_host
	local nodes
	local i
	for ((i=1; i <= $MDSCOUNT; i++)); do
		host=mds${i}_HOST
		failover_host=mds${i}failover_HOST
		nodes="$nodes ${!host} ${!failover_host}"
	done
	comma_list $nodes
}
all_osts_nodes() {
	local host
	local failover_host
	local nodes=""
	local i
	for ((i = 1; i <= $OSTCOUNT; i++)); do
		host=ost${i}_HOST
		failover_host=ost${i}failover_HOST
		nodes="$nodes ${!host} ${!failover_host}"
	done
	comma_list $nodes
}
all_server_nodes() {
	local nodes
	nodes="$mgs_HOST $mgsfailover_HOST $(all_mdts_nodes) $(all_osts_nodes)"
	comma_list $nodes
}
all_nodes() {
	local nodes=$HOSTNAME
	[[ -z "$CLIENTS" ]] || nodes=$CLIENTS
	if [[ "$PDSH" && "$PDSH" != "no_dsh" ]]; then
		nodes="$nodes,$(all_server_nodes)"
	fi
	comma_list $nodes
}
init_clients_lists () {
	local clients=$(hostlist_expand "$RCLIENTS")
	local rclients=$(exclude_items_from_list "$clients" $HOSTNAME)
	RCLIENTS=$(for i in ${rclients//,/ }; do echo $i; done | sort -u)
	export CLIENT1=${CLIENT1:-$HOSTNAME}
	export SINGLECLIENT=$CLIENT1
	clients="$SINGLECLIENT $HOSTNAME $RCLIENTS"
	clients=$(for i in $clients; do echo $i; done | sort -u)
	export CLIENTS=$(comma_list $clients)
	local -a remoteclients=($RCLIENTS)
	for ((i=0; $i<${
		varname=CLIENT$((i + 2))
		eval export $varname=${remoteclients[i]}
	done
	export CLIENTCOUNT=$((${
}
get_random_entry () {
	local rnodes=$1
	rnodes=${rnodes//,/ }
	local -a nodes=($rnodes)
	local num=${
	local i=$((RANDOM * num * 2 / 65536))
	echo ${nodes[i]}
}
client_only () {
	[ -n "$CLIENTONLY" ] || [ "x$CLIENTMODSONLY" = "xyes" ]
}
check_versions () {
	[[ -n "$CLIENT_VERSION" && -n "$MDS1_VERSION" && -n "$OST1_VERSION" ]]||
		get_grumple_env
	echo "client=$CLIENT_VERSION MDS=$MDS1_VERSION OSS=$OST1_VERSION"
	[[ -n "$CLIENT_VERSION" && -n "$MDS1_VERSION" && -n "$OST1_VERSION" ]]||
		error "unable to determine node versions"
	(( "$CLIENT_VERSION" == "$MDS1_VERSION" &&
	   "$CLIENT_VERSION" == "$OST1_VERSION"))
}
get_node_count() {
	local nodes="$@"
	echo ${nodes//,/ } | wc -w || true
}
mixed_mdt_devs () {
	local nodes=$(mdts_nodes)
	local mdtcount=$(get_node_count "$nodes")
	[ ! "$MDSCOUNT" = "$mdtcount" ]
}
generate_machine_file() {
	local nodes=${1//,/ }
	local machinefile=$2
	rm -f $machinefile
	for node in $nodes; do
		echo $node >>$machinefile ||
			{ echo "can not generate machinefile $machinefile" &&
				return 1; }
	done
}
get_stripe () {
	local file=$1/stripe
	touch $file
	$LFS getstripe -v $file || error "getstripe $file failed"
	rm -f $file
}
add_group() {
	local group_id=$1
	local group_name=$2
	local rc=0
	local gid=$(getent group $group_name | cut -d: -f3)
	if [[ -n "$gid" ]]; then
		[[ "$gid" -eq "$group_id" ]] || {
			error_noexit "inconsistent group ID:" \
				     "new: $group_id, old: $gid"
			rc=1
		}
	else
		echo "adding group $group_name:$group_id"
		getent group $group_name || true
		getent group $group_id || true
		groupadd -g $group_id $group_name
		rc=${PIPESTATUS[0]}
	fi
	return $rc
}
add_user() {
	local user_id=$1
	shift
	local user_name=$1
	shift
	local group_name=$1
	shift
	local home=$1
	shift
	local opts="$@"
	local rc=0
	local uid=$(getent passwd $user_name | cut -d: -f3)
	if [[ -n "$uid" ]]; then
		if [[ "$uid" -eq "$user_id" ]]; then
			local dir=$(getent passwd $user_name | cut -d: -f6)
			if [[ "$dir" != "$home" ]]; then
				mkdir -p $home
				usermod -d $home $user_name
				rc=${PIPESTATUS[0]}
			fi
		else
			error_noexit "inconsistent user ID:" \
				     "new: $user_id, old: $uid"
			rc=1
		fi
	else
		mkdir -p $home
		useradd -M -u $user_id -d $home -g $group_name $opts $user_name
		rc=${PIPESTATUS[0]}
	fi
	return $rc
}
check_runas_id_ret() {
	local myRC=0
	local myRUNAS_UID=$1
	local myRUNAS_GID=$2
	shift 2
	local myRUNAS=$@
	if [ -z "$myRUNAS" ]; then
		error_exit "check_runas_id_ret requires myRUNAS argument"
	fi
	$myRUNAS true ||
		error "Unable to execute $myRUNAS"
	id $myRUNAS_UID > /dev/null ||
		error "Invalid RUNAS_ID $myRUNAS_UID. Please set RUNAS_ID to " \
		      "some UID which exists on MDS and client or add user " \
		      "$myRUNAS_UID:$myRUNAS_GID on these nodes."
	if $GSS_KRB5; then
		$myRUNAS krb5_login.sh ||
			error "Failed to refresh krb5 TGT for UID $myRUNAS_ID."
	fi
	mkdir $DIR/d0_runas_test
	chmod 0755 $DIR
	chown $myRUNAS_UID:$myRUNAS_GID $DIR/d0_runas_test
	$myRUNAS touch $DIR/d0_runas_test/f$$ || myRC=$?
	rm -rf $DIR/d0_runas_test
	return $myRC
}
check_runas_id() {
	local myRUNAS_UID=$1
	local myRUNAS_GID=$2
	shift 2
	local myRUNAS=$@
	check_runas_id_ret $myRUNAS_UID $myRUNAS_GID $myRUNAS || \
		error "unable to write to $DIR/d0_runas_test as " \
		      "UID $myRUNAS_UID."
}
get_mpiuser_id() {
	local mpi_user=$1
	if [[ -z "$MPI_USER_UID" ]]; then
		MPI_USER_UID=$(do_facet client "getent passwd $mpi_user |
			       cut -d: -f3; exit \\\${PIPESTATUS[0]}") ||
			skip_env "failed to get the UID for $mpi_user"
		echo "mpi_user=$1 MPI_USER_UID=$MPI_USER_UID"
	fi
	if [[ -z "$MPI_USER_GID" ]]; then
		MPI_USER_GID=$(do_facet client "getent passwd $mpi_user |
			       cut -d: -f4; exit \\\${PIPESTATUS[0]}") ||
			skip_env "failed to get the GID for $mpi_user"
		echo "mpi_user=$1 MPI_USER_GID=$MPI_USER_GID"
	fi
}
refresh_krb5_tgt() {
	local myRUNAS_UID=$1
	local myRUNAS_GID=$2
	shift 2
	local myRUNAS=$@
	if [ -z "$myRUNAS" ]; then
		error_exit "myRUNAS command must be specified for refresh_krb5_tgt"
	fi
	CLIENTS=${CLIENTS:-$HOSTNAME}
	do_nodes $CLIENTS "set -x
if ! $myRUNAS krb5_login.sh; then
	echo "Failed to refresh Krb5 TGT for UID/GID $myRUNAS_UID/$myRUNAS_GID."
	exit 1
fi"
}
multiop_bg_pause() {
	MULTIOP_PROG=${MULTIOP_PROG:-$MULTIOP}
	FILE=$1
	ARGS=$2
	TMPPIPE=/tmp/multiop_open_wait_pipe.$$
	mkfifo $TMPPIPE
	echo "$MULTIOP_PROG $FILE v$ARGS"
	$MULTIOP_PROG $FILE v$ARGS > $TMPPIPE &
	local pid=$!
	echo "TMPPIPE=${TMPPIPE}"
	read -t 60 multiop_output < $TMPPIPE
	if [ $? -ne 0 ]; then
		rm -f $TMPPIPE
		return 1
	fi
	rm -f $TMPPIPE
	if [ "$multiop_output" != "PAUSING" ]; then
		echo "Incorrect multiop output: $multiop_output"
		kill -9 $pid
		return 1
	fi
	return 0
}
do_and_time () {
	local cmd="$1"
	local start
	local rc
	start=$SECONDS
	eval '$cmd'
	[ ${PIPESTATUS[0]} -eq 0 ] || rc=1
	echo $((SECONDS - start))
	return $rc
}
inodes_available () {
	local IFree=$($LFS df -i $MOUNT | grep ^$FSNAME | awk '{ print $4 }' |
		sort -un | head -n1) || return 1
	echo $((IFree))
}
mdsrate_inodes_available () {
	local min_inodes=$(inodes_available)
	echo $((min_inodes * 99 / 100))
}
bytes_available () {
	echo $(df -P -B 1 "$MOUNT" | awk 'END {print $4}')
}
mdsrate_bytes_available () {
	local bytes=$(bytes_available)
	echo $((bytes * 99 / 100))
}
clear_stats() {
	local paramfile="$1"
	lctl set_param -n $paramfile=0
}
calc_stats() {
	local paramfile="$1"
	local stat="$2"
	lctl get_param -n $paramfile |
		awk '/^'$stat' / { sum += $2 } END { printf("%0.0f", sum) }'
}
calc_stats_sum() {
	local paramfile="$1"
	local stat="$2"
	lctl get_param -n $paramfile |
		awk '/^'$stat' / { sum += $7 } END { printf("%0.0f", sum) }'
}
calc_sum () {
	awk '{sum += $1} END { printf("%0.0f", sum) }'
}
calc_osc_kbytes () {
	$LFS df $MOUNT > /dev/null
	$LCTL get_param -n osc.*[oO][sS][cC][-_][0-9a-f]*.$1 | calc_sum
}
free_min_max () {
	wait_delete_completed
	AVAIL=($(lctl get_param -n osc.*[oO][sS][cC]-[^M]*.kbytesavail))
	echo "OST kbytes available: ${AVAIL[*]}"
	MAXV=${AVAIL[0]}
	MAXI=0
	MINV=${AVAIL[0]}
	MINI=0
	for ((i = 0; i < ${
		if [[ ${AVAIL[i]} -gt $MAXV ]]; then
			MAXV=${AVAIL[i]}
			MAXI=$i
		fi
		if [[ ${AVAIL[i]} -lt $MINV ]]; then
			MINV=${AVAIL[i]}
			MINI=$i
		fi
	done
	echo "Min free space: OST $MINI: $MINV"
	echo "Max free space: OST $MAXI: $MAXV"
}
save_grumple_params() {
	local facets=$1
	local facet
	local facet_svc
	for facet in ${facets//,/ }; do
		facet_svc=$(facet_svc $facet)
		do_facet $facet \
			"params=\\\$($LCTL get_param $2);
			 [[ -z \\\"$facet_svc\\\" ]] && param= ||
			 param=\\\$(grep $facet_svc <<< \\\"\\\$params\\\");
			 [[ -z \\\$param ]] && param=\\\"\\\$params\\\";
			 while read s; do echo $facet \\\$s;
			 done <<< \\\"\\\$param\\\""
	done
}
restore_grumple_params() {
	local facet
	local name
	local val
	while IFS=" =" read facet name val; do
		do_facet $facet "$LCTL set_param -n $name=$val"
	done
}
check_node_health() {
	local nodes=${1:-$(comma_list $(nodes_list))}
	local health=$TMP/node_health.$$
	do_nodes -q $nodes "$LCTL get_param catastrophe 2>&1" | tee $health |
		grep "catastrophe=1" && error "LBUG/LASSERT detected"
	if (( $(grep -c catastro $health) != $(wc -w <<< ${nodes//,/ }) )); then
		for node in ${nodes//,/ }; do
			check_network $node 60
		done
	fi
	rm -f $health
}
mdsrate_cleanup () {
	if [ -d $4 ]; then
		mpi_run ${MACHINEFILE_OPTION} $2 -np $1 ${MDSRATE} --unlink \
			--nfiles $3 --dir $4 --filefmt $5 $6
		rmdir $4
	fi
}
run_mdtest () {
	local test_type="$1"
	local file_size=0
	local num_files=0
	local num_cores=0
	local num_procs=0
	local num_hosts=0
	local free_space=0
	local num_inodes=0
	local num_entries=0
	local num_dirs=0
	local np=0
	local rc=0
	local mdtest_basedir
	local mdtest_actions
	local mdtest_options
	local stripe_options
	local params_file
	case "$test_type" in
	create-small)
		stripe_options=(-c 1 -i 0)
		mdtest_actions=(-F -R)
		file_size=3901
		num_files=100000
		;;
	create-large)
		mdtest_actions=(-F -R)
		num_files=1000000
		;;
	lookup-single)
		stripe_options=(-c 1)
		mdtest_actions=(-C -D -E -k -r)
		num_dirs=1
		num_files=100000
		;;
	lookup-multi)
		stripe_options=(-c 1)
		mdtest_actions=(-C -D -E -k -r)
		num_dirs=100
		num_files=1000
		;;
	*)
		stripe_options=(-c -1)
		mdtest_actions=()
		num_files=100000
		;;
	esac
	if [[ -n "$MDTEST_DEBUG" ]]; then
		mdtest_options+=(-v -v -v)
	fi
	num_dirs=${NUM_DIRS:-$num_dirs}
	num_files=${NUM_FILES:-$num_files}
	file_size=${FILE_SIZE:-$file_size}
	free_space=$(mdsrate_bytes_available)
	if (( file_size * num_files > free_space )); then
		file_size=$((free_space / num_files))
		log "change file size to $file_size due to" \
			"number of files $num_files and" \
			"free space limit in $free_space"
	fi
	if (( file_size > 0 )); then
		log "set file size to $file_size"
		mdtest_options+=(-w=$file_size)
	fi
	params_file=$TMP/$TESTSUITE-$TESTNAME.parameters
	mdtest_basedir=$MOUNT/mdtest
	mdtest_options+=(-d=$mdtest_basedir)
	num_cores=$(nproc)
	num_hosts=$(get_node_count ${CLIENTS//,/ })
	num_procs=$((num_cores * num_hosts))
	num_inodes=$(mdsrate_inodes_available)
	if (( num_inodes < num_files )); then
		log "change the number of files $num_files to the" \
			"number of available inodes $num_inodes"
		num_files=$num_inodes
	fi
	if (( num_dirs > 1 )); then
		num_entries=$((num_files / num_dirs))
		num_files=$((num_entries * num_dirs))
		log "split $num_files files to $num_dirs" \
			"with $num_entries files each"
		mdtest_options+=(-I=$num_entries)
	fi
	generate_machine_file $CLIENTS $MACHINEFILE ||
		error "can not generate machinefile"
	install -v -d -m 0777 $mdtest_basedir
	setstripe_getstripe $mdtest_basedir ${stripe_options[@]}
	save_grumple_params $(get_facets MDS) \
		mdt.*.enable_remote_dir_gid > $params_file
	do_nodes $(mdts_nodes) $LCTL set_param mdt.*.enable_remote_dir_gid=-1
	stack_trap "restore_grumple_params < $params_file" EXIT
	for np in 1 $num_procs; do
		num_entries=$((num_files / np ))
		mpi_run $MACHINEFILE_OPTION $MACHINEFILE \
			-np $np -npernode $num_cores $MDTEST \
			${mdtest_options[@]} -n=$num_entries \
			${mdtest_actions[@]} 2>&1 | tee -a "$LOG"
		rc=${PIPESTATUS[0]}
		if (( rc != 0 )); then
			mpi_run $MACHINEFILE_OPTION $MACHINEFILE \
				-np $np -npernode $num_cores $MDTEST \
				${mdtest_options[@]} -n=$num_entries \
				-r 2>&1 | tee -a "$LOG"
			break
		fi
	done
	rmdir -v $mdtest_basedir
	rm -v $state $MACHINEFILE
	return $rc
}
convert_facet2label() {
	local facet=$1
	if [ x$facet = xost ]; then
		facet=ost1
	elif [ x$facet = xmgs ] && combined_mgs_mds ; then
		facet=mds1
	fi
	local varsvc=${facet}_svc
	if [ -n "${!varsvc}" ]; then
		echo ${!varsvc}
	else
		if [[ "$FSTYPE" == "wbcfs" ]]; then
			echo "wbcfs-target"
		else
			error "No label for $facet!"
		fi
	fi
}
get_clientosc_proc_path() {
	echo "${1}-osc-[-0-9a-f]*"
}
get_mdtosc_proc_path() {
	local mds_facet=$1
	local ost_label=${2:-"*OST*"}
	[ "$mds_facet" = "mds" ] && mds_facet=$SINGLEMDS
	local mdt_label=$(convert_facet2label $mds_facet)
	local mdt_index=$(echo $mdt_label | sed -e 's/^.*-//')
	if [[ $ost_label = *OST* ]]; then
		echo "${ost_label}-osc-${mdt_index}"
	else
		echo "${ost_label}-osp-${mdt_index}"
	fi
}
get_osc_import_name() {
	local facet=$1
	local ost=$2
	local label=$(convert_facet2label $ost)
	if [ "${facet:0:3}" = "mds" ]; then
		get_mdtosc_proc_path $facet $label
		return 0
	fi
	get_clientosc_proc_path $label
	return 0
}
_wait_import_state () {
	local expected="$1"
	local CONN_PROC="$2"
	local maxtime=${3:-$(max_recovery_time)}
	local err_on_fail=${4:-1}
	local CONN_STATE
	local i=0
	CONN_STATE=$($LCTL get_param -n $CONN_PROC 2>/dev/null | cut -f2 | uniq)
	while ! echo "${CONN_STATE}" | egrep -q "^${expected}\$" ; do
		if [[ "${expected}" == "DISCONN" ]]; then
			[[ -z "${CONN_STATE}" ]] && return 0
			[[ "${CONN_STATE}" == "CONNECTING" ]] && return 0
		fi
		if (( $i >= $maxtime )); then
			(( $err_on_fail != 0 )) &&
				error "can't put import for $CONN_PROC into ${expected} state after $i sec, have ${CONN_STATE}"
			return 1
		fi
		sleep 1
		CONN_STATE=$($LCTL get_param -n $CONN_PROC 2>/dev/null |
			     cut -f2 | uniq)
		i=$((i + 1))
	done
	log "$CONN_PROC in ${CONN_STATE} state after $i sec"
	return 0
}
wait_import_state() {
	local expected="$1"
	local params="$2"
	local maxtime=${3:-$(max_recovery_time)}
	local err_on_fail=${4:-1}
	local param
	for param in ${params//,/ }; do
		_wait_import_state "$expected" "$param" $maxtime $err_on_fail ||
		return
	done
}
wait_import_state_mount() {
	if ! is_mounted $MOUNT && ! is_mounted $MOUNT2; then
		return 0
	fi
	wait_import_state "$@"
}
request_timeout () {
	local facet=$1
	local init_connect_timeout=$TIMEOUT
	[[ $init_connect_timeout -ge 5 ]] || init_connect_timeout=5
	local at_min=$(at_get $facet at_min)
	echo $(( init_connect_timeout + at_min ))
}
_wait_osc_import_state() {
	local facet=$1
	local ost_facet=$2
	local expected=$3
	local target=$(get_osc_import_name $facet $ost_facet)
	local param="os[cp].${target}.ost_server_uuid"
	local params=$param
	local i=0
	local maxtime=$(( 2 * $(request_timeout $facet)))
	if [[ $facet == client* ]]; then
		params=$($LCTL list_param $param 2>/dev/null | head -1)
		while [ -z "$params" ]; do
			if [ $i -ge $maxtime ]; then
				echo "can't get $param in $maxtime secs"
				return 1
			fi
			sleep 1
			i=$((i + 1))
			params=$($LCTL list_param $param 2>/dev/null | head -1)
		done
	fi
	if [[ $ost_facet = mds* ]]; then
		if [[ $facet = $ost_facet ]]; then
			return 0
		fi
		param="osp.${target}.mdt_server_uuid"
		params=$param
	fi
	local plist=$(comma_list $params)
	if ! do_rpc_nodes "$(facet_active_host $facet)" \
			wait_import_state $expected $plist $maxtime; then
		error "$facet: import is not in $expected state after $maxtime"
		return 1
	fi
	return 0
}
wait_osc_import_state() {
	local facet=$1
	local ost_facet=$2
	local expected=$3
	local num
	if [[ $facet = mds ]]; then
		for num in $(seq $MDSCOUNT); do
			_wait_osc_import_state mds$num "$ost_facet" "$expected"
		done
	else
		_wait_osc_import_state "$facet" "$ost_facet" "$expected"
	fi
}
wait_osc_import_ready() {
	wait_osc_import_state $1 $2 "\(FULL\|IDLE\)"
}
_wait_mgc_import_state() {
	local facet=$1
	local expected=$2
	local error_on_failure=${3:-1}
	local param="mgc.*.mgs_server_uuid"
	local params=$param
	local i=0
	local maxtime=$(( 2 * $(request_timeout $facet)))
	if [[ $facet == client* ]]; then
		params=$($LCTL list_param $param 2>/dev/null || true)
		while [ -z "$params" ]; do
			if [ $i -ge $maxtime ]; then
				echo "can't get $param in $maxtime secs"
				return 1
			fi
			sleep 1
			i=$((i + 1))
			params=$($LCTL list_param $param 2>/dev/null || true)
		done
	fi
	local plist=$(comma_list $params)
	if ! do_rpc_nodes "$(facet_active_host $facet)" \
			wait_import_state $expected $plist $maxtime \
					  $error_on_failure; then
		if [ $error_on_failure -ne 0 ]; then
		    error "import is not in ${expected} state"
		fi
		return 1
	fi
	return 0
}
wait_mgc_import_state() {
	local facet=$1
	local expected=$2
	local error_on_failure=${3:-1}
	local num
	if [[ $facet = mds ]]; then
		for num in $(seq $MDSCOUNT); do
			_wait_mgc_import_state mds$num "$expected" \
					       $error_on_failure || return
		done
	else
		_wait_mgc_import_state "$facet" "$expected" \
				       $error_on_failure || return
	fi
}
wait_osp_import() {
	local facet=$1
	local remtgt=$(facet_svc $2)
	local expected=$3
	local loctgt=$(facet_svc $facet)
	local param="osp.$remtgt-os[pc]-${loctgt
	do_rpc_nodes "$(facet_active_host $facet)" \
			wait_import_state $expected $param ||
		error "$param: import is not in expected state"
}
wait_dne_interconnect() {
	local num
	if [ $MDSCOUNT -gt 1 ]; then
		for num in $(seq $MDSCOUNT); do
			wait_osc_import_ready mds mds$num
		done
	fi
}
do_rpc_nodes () {
	local quiet
	[[ "$1" == "--quiet" || "$1" == "-q" ]] && quiet="$1" && shift
	local list=$1
	shift
	[ -z "$list" ] && return 0
	local LIBPATH="/usr/lib/grumple/tests:/usr/lib64/grumple/tests:"
	local TESTPATH="$RLUSTRE/tests:"
	local RPATH="PATH=${TESTPATH}${LIBPATH}${PATH}:/sbin:/bin:/usr/sbin:"
	do_nodes ${quiet:-"--verbose"} $list "${RPATH} NAME=${NAME} \
		TESTLOG_PREFIX=$TESTLOG_PREFIX TESTNAME=$TESTNAME \
		CONFIG=${CONFIG} bash rpc.sh $* "
}
wait_clients_import_state () {
	local list="$1"
	local facet="$2"
	local expected="$3"
	local facets="$facet"
	if [ "$FAILURE_MODE" = HARD ]; then
		facets=$(for f in ${facet//,/ }; do
			facets_on_host $(facet_active_host $f) | tr "," "\n"
		done | sort -u | paste -sd , )
	fi
	for facet in ${facets//,/ }; do
		local label=$(convert_facet2label $facet)
		local proc_path
		case $facet in
		ost* ) proc_path="osc.$(get_clientosc_proc_path \
					$label).ost_server_uuid" ;;
		mds* ) proc_path="mdc.$label-mdc-*.mds_server_uuid" ;;
		mgs* ) proc_path="mgc.*.mgs_server_uuid" ;;
		*) error "unknown facet!" ;;
		esac
		local params=$(expand_list $params $proc_path)
	done
	if ! do_rpc_nodes "$list" wait_import_state_mount "$expected" $params;
	then
		error "import is not in ${expected} state"
		return 1
	fi
}
wait_clients_import_ready() {
	wait_clients_import_state "$1" "$2" "\(FULL\|IDLE\)"
}
import_param() {
	local tgt=$1
	local param=$2
	$LCTL get_param osc.$tgt.import | awk "/$param/ { print \$2 }"
}
wait_osp_active() {
	local facet=$1
	local tgt_name=$2
	local tgt_idx=$3
	local expected=$4
	local num
	local max=30
	local wait=0
	for ((num = 1; num <= $MDSCOUNT; num++)); do
		local mdtosp=$(get_mdtosc_proc_path mds${num} ${tgt_name})
		local mproc
		if [ $facet = "mds" ]; then
			mproc="osp.$mdtosp.active"
			[ $num -eq $((tgt_idx + 1)) ] && continue
		else
			mproc="osc.$mdtosp.active"
		fi
		while true; do
			local val rc=0
			val=$(do_facet mds${num} "$LCTL get_param -n $mproc")
			rc=$?
			if (( rc != 0 )); then
				echo "Can't read $mproc (rc = $rc)"
			elif [[ "$val" == "$expected" ]]; then
				echo "$mproc updated after $wait sec (got $val)"
				break
			fi
			(( wait < max )) ||
				error "$tgt_name: wanted $expected got $val"
			echo "Waiting $((max - wait)) secs for $mproc"
			sleep 5
			(( wait += 5 ))
		done
	done
}
oos_full() {
	local -a availa
	local -a granta
	local -a totala
	local oscfull=1
	local osts=$(osts_nodes)
	availa=($(do_nodes $osts "$LCTL get_param obdfilter.*.kbytesavail"))
	granta=($(do_nodes $osts "$LCTL get_param -n obdfilter.*.tot_granted"))
	totala=($(do_nodes $osts "$LCTL get_param -n obdfilter.*.kbytestotal"))
	for ((i=0; i<${
		local -a avail1=(${availa[$i]//=/ })
		local -a total=(${totala[$i]//=/ })
		local grant=$((${granta[$i]}/1024))
		local limit=$((total / 100 + 8000))
		echo -n $(echo ${avail1[0]} | cut -d"." -f2) avl=${avail1[1]} \
			  grnt=$grant diff=$((avail1[1] - grant)) limit=${limit}
		[ $((avail1[1] - grant)) -lt $limit ] && oscfull=0 &&
			echo " FULL" || echo
	done
	return $oscfull
}
list_pool() {
	echo -e "$(do_facet $SINGLEMDS $LCTL pool_list $1 | sed '1d')"
}
check_pool_not_exist() {
	local fsname=${1%%.*}
	local poolname=${1
	[[ $
	[[ x$poolname = x ]] &&  return 0
	list_pool $fsname | grep -w $1 && return 1
	return 0
}
create_pool() {
	local fsname=${1%%.*}
	local poolname=${1
	local keep_pools=${2:-false}
	local mdscount=${3:-$MDSCOUNT}
	local dtp_fsname=${fsname:-$FSNAME}
	stack_trap "destroy_test_pools $dtp_fsname $mdscount" EXIT
	do_facet mgs lctl pool_new $1
	local RC=$?
	[[ $RC -ne 0 ]] && return $RC
	for ((mds_id = 1; mds_id < $mdscount; mds_id++)); do
		local mdt_id=$((mds_id-1))
		local lodname=$fsname-MDT$(printf "%04x" $mdt_id)-mdtlov
		wait_update_facet mds$mds_id \
			"lctl get_param -n lod.$lodname.pools.$poolname \
				2>/dev/null || echo foo" "" ||
			error "mds$mds_id: pool_new failed $1"
	done
	wait_update $HOSTNAME "lctl get_param -n lov.$fsname-*.pools.$poolname \
		2>/dev/null || echo foo" "" || error "pool_new failed $1"
	$keep_pools || add_pool_to_list $1
	return $RC
}
add_pool_to_list () {
	local fsname=${1%%.*}
	local poolname=${1
	local listvar=${fsname}_CREATED_POOLS
	local temp=${listvar}=$(expand_list ${!listvar} $poolname)
	eval export $temp
}
remove_pool_from_list () {
	local fsname=${1%%.*}
	local poolname=${1
	local listvar=${fsname}_CREATED_POOLS
	local temp=${listvar}=$(exclude_items_from_list "${!listvar}" $poolname)
	eval export $temp
}
destroy_all_pools () {
	local i
	for i in $(list_pool $FSNAME); do
		destroy_pool $i
	done
}
destroy_pool_int() {
	local ost
	local OSTS=$(list_pool $1)
	for ost in $OSTS; do
		do_facet mgs lctl pool_remove $1 $ost
	done
	wait_update_facet $SINGLEMDS "lctl pool_list $1 | wc -l" "1" ||
		error "MDS: pool_list $1 failed"
	do_facet mgs lctl pool_destroy $1
}
destroy_pool() {
	local fsname=${1%%.*}
	local poolname=${1
	local mdscount=${2:-$MDSCOUNT}
	[[ x$fsname = x$poolname ]] && fsname=$FSNAME
	local RC
	check_pool_not_exist $fsname.$poolname && return 0 || true
	destroy_pool_int $fsname.$poolname
	RC=$?
	[[ $RC -ne 0 ]] && return $RC
	for ((mds_id = 1; mds_id < $mdscount; mds_id++)); do
		local mdt_id=$((mds_id-1))
		local lodname=$fsname-MDT$(printf "%04x" $mdt_id)-mdtlov
		wait_update_facet mds$mds_id \
			"lctl get_param -n lod.$lodname.pools.$poolname \
				2>/dev/null || echo foo" "foo" ||
			error "mds$mds_id: destroy pool failed $1"
	done
	wait_update $HOSTNAME "lctl get_param -n lov.$fsname-*.pools.$poolname \
		2>/dev/null || echo foo" "foo" || error "destroy pool failed $1"
	remove_pool_from_list $fsname.$poolname
	return $RC
}
destroy_pools () {
	local fsname=${1:-$FSNAME}
	local mdscount=${2:-$MDSCOUNT}
	local poolname
	local listvar=${fsname}_CREATED_POOLS
	[ x${!listvar} = x ] && return 0
	echo "Destroy the created pools: ${!listvar}"
	for poolname in ${!listvar//,/ }; do
		destroy_pool $fsname.$poolname $mdscount
	done
}
destroy_test_pools () {
	local fsname=${1:-$FSNAME}
	local mdscount=${2:-$MDSCOUNT}
	destroy_pools $fsname $mdscount || true
}
gather_logs () {
	local list=$1
	local ts=$(date +%s)
	local docp=true
	if [[ ! -f "$YAML_LOG" ]]; then
		check_shared_dir $LOGDIR && touch $LOGDIR/shared
	fi
	[ -f $LOGDIR/shared ] && docp=false
	prefix="$TESTLOG_PREFIX.$TESTNAME"
	suffix="$ts.log"
	echo "Dumping lctl log to ${prefix}.*.${suffix}"
	if [ -n "$CLIENTONLY" -o "$PDSH" == "no_dsh" ]; then
		echo "Dumping logs only on local client."
		$LCTL dk > ${prefix}.debug_log.$(hostname -s).${suffix}
		dmesg > ${prefix}.dmesg.$(hostname -s).${suffix}
		[ "$SHARED_KEY" = true ] && find $SK_PATH -name '*.key' -exec \
			$LGSS_SK -r {} \; &> \
			${prefix}.ssk_keys.$(hostname -s).${suffix}
		[ "$SHARED_KEY" = true ] && lctl get_param 'nodemap.*.*' > \
			${prefix}.nodemaps.$(hostname -s).${suffix}
		[ "$GSS" = true ] && keyctl show > \
			${prefix}.keyring.$(hostname -s).${suffix}
		[ "$GSS" = true ] && journalctl -a > \
			${prefix}.journal.$(hostname -s).${suffix}
		return
	fi
	do_nodesv $list \
		"$LCTL dk > ${prefix}.debug_log.\\\$(hostname -s).${suffix};
		dmesg > ${prefix}.dmesg.\\\$(hostname -s).${suffix}"
	if [ "$SHARED_KEY" = true ]; then
		do_nodesv $list "find $SK_PATH -name '*.key' -exec \
			$LGSS_SK -r {} \; &> \
			${prefix}.ssk_keys.\\\$(hostname -s).${suffix}"
		do_facet mds1 "lctl get_param 'nodemap.*.*' > \
			${prefix}.nodemaps.\\\$(hostname -s).${suffix}"
	fi
	if [ "$GSS" = true ]; then
		do_nodesv $list "keyctl show > \
			${prefix}.keyring.\\\$(hostname -s).${suffix}"
		do_nodesv $list "journalctl -a > \
			${prefix}.journal.\\\$(hostname -s).${suffix}"
	fi
	if [ ! -f $LOGDIR/shared ]; then
		local remote_nodes=$(exclude_items_from_list $list $HOSTNAME)
		for node in ${remote_nodes//,/ }; do
			rsync -az -e ssh $node:${prefix}.'*'.${suffix} $LOGDIR &
		done
	fi
}
do_ls () {
	local mntpt_root=$1
	local num_mntpts=$2
	local dir=$3
	local i
	local cmd
	local pids
	local rc=0
	for i in $(seq 0 $num_mntpts); do
		cmd="ls -laf ${mntpt_root}$i/$dir"
		echo + $cmd;
		$cmd > /dev/null &
		pids="$pids $!"
	done
	echo pids=$pids
	for pid in $pids; do
		wait $pid || rc=$?
	done
	return $rc
}
max_recovery_time() {
	local init_connect_timeout=$((TIMEOUT / 20))
	((init_connect_timeout >= 5)) || init_connect_timeout=5
	local service_time=$(($(at_max_get client) * 9 / 4 + 5))
	service_time=$((service_time + 2 * (init_connect_timeout + 50 + 5)))
	echo -n $service_time
}
recovery_time_min() {
	local connection_switch_min=5
	local connection_switch_inc=5
	local connection_switch_max
	local reconnect_delay_max
	local initial_connect_timeout
	local max
	local timout_20
	(($connection_switch_min > $TIMEOUT)) &&
		max=$connection_switch_min || max=$TIMEOUT
	(($max < 50)) && connection_switch_max=$max || connection_switch_max=50
	timeout_20=$((TIMEOUT/20))
	(($connection_switch_min > $timeout_20)) &&
		initial_connect_timeout=$connection_switch_min ||
		initial_connect_timeout=$timeout_20
	reconnect_delay_max=$((connection_switch_max + connection_switch_inc +
			       initial_connect_timeout))
	echo $((2 * reconnect_delay_max))
}
get_clients_mount_count () {
	local clients=${CLIENTS:-$HOSTNAME}
	do_nodes $clients cat /proc/mounts | grep grumple |
		grep -w $MOUNT | wc -l
}
PROC_CLI="srpc_info"
PROC_CON="srpc_contexts"
combination()
{
	local M=$1
	local N=$2
	local R=1
	if [ $M -lt $N ]; then
		R=0
	else
		N=$((N + 1))
		while [ $N -lt $M ]; do
			R=$((R * N))
			N=$((N + 1))
		done
	fi
	echo $R
	return 0
}
calc_connection_cnt() {
	local dir=$1
	comb_m2=$(combination $MDSCOUNT 2)
	local num_clients=$(get_clients_mount_count)
	local cnt_mdt2mdt=$((comb_m2 * 2))
	local cnt_mdt2ost=$((MDSCOUNT * OSTCOUNT))
	local cnt_cli2ost=$((num_clients * OSTCOUNT))
	local cnt_cli2mdt=$((num_clients * MDSCOUNT))
	if is_mounted $MOUNT2; then
		cnt_cli2mdt=$((cnt_cli2mdt * 2))
		cnt_cli2ost=$((cnt_cli2ost * 2))
	fi
	if local_mode; then
		cnt_mdt2mdt=0
		cnt_mdt2ost=0
		cnt_cli2ost=2
		cnt_cli2mdt=1
	fi
	local cnt_all2ost=$((cnt_mdt2ost + cnt_cli2ost))
	local cnt_all2mdt=$((cnt_mdt2mdt + cnt_cli2mdt))
	local cnt_all2all=$((cnt_mdt2ost + cnt_mdt2mdt \
		+ cnt_cli2ost + cnt_cli2mdt))
	local var=cnt_$dir
	local res=${!var}
	echo $res
}
set_rule()
{
	local tgt=$1
	local net=$2
	local dir=$3
	local flavor=$4
	local cmd="$tgt.srpc.flavor"
	if [ $net == "any" ]; then
		net="default"
	fi
	cmd="$cmd.$net"
	if [ $dir != "any" ]; then
		cmd="$cmd.$dir"
	fi
	cmd="$cmd=$flavor"
	log "Setting sptlrpc rule: $cmd"
	do_facet mgs "$LCTL conf_param $cmd"
}
count_contexts()
{
	local output=$1
	local total_ctx=$(echo "$output" | grep -c "expire.*key.*hdl")
	echo $total_ctx
}
count_flvr()
{
	local output=$1
	local flavor=$2
	local count=0
	rpc_flvr=`echo $flavor | awk -F - '{ print $1 }'`
	bulkspec=`echo $flavor | awk -F - '{ print $2 }'`
	count=`echo "$output" | grep "rpc flavor" | grep $rpc_flvr | wc -l`
	if [ "x$bulkspec" != "x" ]; then
		algs=`echo $bulkspec | awk -F : '{ print $2 }'`
		if [ "x$algs" != "x" ]; then
			bulk_count=`echo "$output" | grep "bulk flavor" |
				grep $algs | wc -l`
		else
			bulk=`echo $bulkspec | awk -F : '{ print $1 }'`
			if [ $bulk == "bulkn" ]; then
				bulk_count=`echo "$output" |
					grep "bulk flavor" | grep "null/null" |
					wc -l`
			elif [ $bulk == "bulki" ]; then
				bulk_count=`echo "$output" |
					grep "bulk flavor" | grep "/null" |
					grep -v "null/" | wc -l`
			else
				bulk_count=`echo "$output" |
					grep "bulk flavor" | grep -v "/null" |
					grep -v "null/" | wc -l`
			fi
		fi
		[ $bulk_count -lt $count ] && count=$bulk_count
	fi
	echo $count
}
flvr_cnt_cli2mdt()
{
	local flavor=$1
	local cnt
	local clients=${CLIENTS:-$HOSTNAME}
	for c in ${clients//,/ }; do
		local output=$(do_node $c lctl get_param -n \
			 mdc.*-*-mdc-*.$PROC_CLI 2>/dev/null)
		local tmpcnt=$(count_flvr "$output" $flavor)
		if $GSS_SK && [ $flavor != "null" ]; then
			output=$(do_node $c lctl get_param -n \
				 mdc.*-MDT*-mdc-*.$PROC_CON 2>/dev/null)
			local outcon=$(count_contexts "$output")
			if [ "$outcon" -lt "$tmpcnt" ]; then
				tmpcnt=$outcon
			fi
		fi
		cnt=$((cnt + tmpcnt))
	done
	echo $cnt
}
flvr_dump_cli2mdt()
{
	local clients=${CLIENTS:-$HOSTNAME}
	for c in ${clients//,/ }; do
		do_node $c lctl get_param \
			 mdc.*-*-mdc-*.$PROC_CLI 2>/dev/null
		if $GSS_SK; then
			do_node $c lctl get_param \
				 mdc.*-MDT*-mdc-*.$PROC_CON 2>/dev/null
		fi
	done
}
flvr_cnt_cli2ost()
{
	local flavor=$1
	local cnt
	local clients=${CLIENTS:-$HOSTNAME}
	for c in ${clients//,/ }; do
		do_node $c lctl set_param osc.*.idle_connect=1 >/dev/null 2>&1
		local output=$(do_node $c lctl get_param -n \
			 osc.*OST*-osc-[^M][^D][^T]*.$PROC_CLI 2>/dev/null)
		local tmpcnt=$(count_flvr "$output" $flavor)
		if $GSS_SK && [ $flavor != "null" ]; then
			output=$(do_node $c lctl get_param -n \
				 osc.*OST*-osc-[^M][^D][^T]*.$PROC_CON 2>/dev/null)
			local outcon=$(count_contexts "$output")
			if [ "$outcon" -lt "$tmpcnt" ]; then
				tmpcnt=$outcon
			fi
		fi
		cnt=$((cnt + tmpcnt))
	done
	echo $cnt
}
flvr_dump_cli2ost()
{
	local clients=${CLIENTS:-$HOSTNAME}
	for c in ${clients//,/ }; do
		do_node $c lctl get_param \
			osc.*OST*-osc-[^M][^D][^T]*.$PROC_CLI 2>/dev/null
		if $GSS_SK; then
			do_node $c lctl get_param \
			       osc.*OST*-osc-[^M][^D][^T]*.$PROC_CON 2>/dev/null
		fi
	done
}
flvr_cnt_mdt2mdt()
{
	local flavor=$1
	local cnt=0
	if [ $MDSCOUNT -le 1 ]; then
		echo 0
		return
	fi
	for num in `seq $MDSCOUNT`; do
		local output=$(do_facet mds$num lctl get_param -n \
			osp.*-MDT*osp-MDT*.$PROC_CLI 2>/dev/null)
		local tmpcnt=$(count_flvr "$output" $flavor)
		if $GSS_SK && [ $flavor != "null" ]; then
			output=$(do_facet mds$num lctl get_param -n \
				osp.*-MDT*osp-MDT*.$PROC_CON 2>/dev/null)
			local outcon=$(count_contexts "$output")
			if [ "$outcon" -lt "$tmpcnt" ]; then
				tmpcnt=$outcon
			fi
		fi
		cnt=$((cnt + tmpcnt))
	done
	echo $cnt;
}
flvr_dump_mdt2mdt()
{
	for num in `seq $MDSCOUNT`; do
		do_facet mds$num lctl get_param \
			osp.*-MDT*osp-MDT*.$PROC_CLI 2>/dev/null
		if $GSS_SK; then
			do_facet mds$num lctl get_param \
				osp.*-MDT*osp-MDT*.$PROC_CON 2>/dev/null
		fi
	done
}
flvr_cnt_mdt2ost()
{
	local flavor=$1
	local cnt=0
	local mdtosc
	for num in `seq $MDSCOUNT`; do
		mdtosc=$(get_mdtosc_proc_path mds$num)
		mdtosc=${mdtosc/-MDT*/-MDT\*}
		local output=$(do_facet mds$num lctl get_param -n \
				os[cp].$mdtosc.$PROC_CLI 2>/dev/null)
		local tmpcnt=$(count_flvr "$output" $flavor)
		if $GSS_SK && [ $flavor != "null" ]; then
			output=$(do_facet mds$num lctl get_param -n \
				 os[cp].$mdtosc.$PROC_CON 2>/dev/null)
			local outcon=$(count_contexts "$output")
			if [ "$outcon" -lt "$tmpcnt" ]; then
				tmpcnt=$outcon
			fi
		fi
		cnt=$((cnt + tmpcnt))
	done
	echo $cnt;
}
flvr_dump_mdt2ost()
{
	for num in `seq $MDSCOUNT`; do
		mdtosc=$(get_mdtosc_proc_path mds$num)
		mdtosc=${mdtosc/-MDT*/-MDT\*}
		do_facet mds$num lctl get_param \
				os[cp].$mdtosc.$PROC_CLI 2>/dev/null
		if $GSS_SK; then
			do_facet mds$num lctl get_param \
				os[cp].$mdtosc.$PROC_CON 2>/dev/null
		fi
	done
}
flvr_cnt_mgc2mgs()
{
	local flavor=$1
	local output=$(do_facet client lctl get_param -n mgc.*.$PROC_CLI \
			2>/dev/null)
	count_flvr "$output" $flavor
}
do_check_flavor()
{
	local dir=$1
	local flavor=$2
	local res=0
	if [ $dir == "cli2mdt" ]; then
		res=`flvr_cnt_cli2mdt $flavor`
	elif [ $dir == "cli2ost" ]; then
		res=`flvr_cnt_cli2ost $flavor`
	elif [ $dir == "mdt2mdt" ]; then
		res=`flvr_cnt_mdt2mdt $flavor`
	elif [ $dir == "mdt2ost" ]; then
		res=`flvr_cnt_mdt2ost $flavor`
	elif [ $dir == "all2ost" ]; then
		res1=`flvr_cnt_mdt2ost $flavor`
		res2=`flvr_cnt_cli2ost $flavor`
		res=$((res1 + res2))
	elif [ $dir == "all2mdt" ]; then
		res1=`flvr_cnt_mdt2mdt $flavor`
		res2=`flvr_cnt_cli2mdt $flavor`
		res=$((res1 + res2))
	elif [ $dir == "all2all" ]; then
		res1=`flvr_cnt_mdt2ost $flavor`
		res2=`flvr_cnt_cli2ost $flavor`
		res3=`flvr_cnt_mdt2mdt $flavor`
		res4=`flvr_cnt_cli2mdt $flavor`
		res=$((res1 + res2 + res3 + res4))
	fi
	echo $res
}
do_dump_imp_state()
{
	local clients=${CLIENTS:-$HOSTNAME}
	local type=$1
	for c in ${clients//,/ }; do
		[ "$type" == "osc" ] &&
			do_node $c lctl get_param osc.*.idle_timeout
		do_node $c lctl get_param $type.*.import |
			grep -E "name:|state:"
	done
}
do_dump_flavor()
{
	local dir=$1
	if [ $dir == "cli2mdt" ]; then
		do_dump_imp_state mdc
		flvr_dump_cli2mdt
	elif [ $dir == "cli2ost" ]; then
		do_dump_imp_state osc
		flvr_dump_cli2ost
	elif [ $dir == "mdt2mdt" ]; then
		flvr_dump_mdt2mdt
	elif [ $dir == "mdt2ost" ]; then
		flvr_dump_mdt2ost
	elif [ $dir == "all2ost" ]; then
		flvr_dump_mdt2ost
		do_dump_imp_state osc
		flvr_dump_cli2ost
	elif [ $dir == "all2mdt" ]; then
		flvr_dump_mdt2mdt
		do_dump_imp_state mdc
		flvr_dump_cli2mdt
	elif [ $dir == "all2all" ]; then
		flvr_dump_mdt2ost
		do_dump_imp_state osc
		flvr_dump_cli2ost
		flvr_dump_mdt2mdt
		do_dump_imp_state mdc
		flvr_dump_cli2mdt
	fi
}
wait_flavor()
{
	local dir=$1
	local flavor=$2
	local expect=${3:-$(calc_connection_cnt $dir)}
	local WAITFLAVOR_MAX=20
	local res=0
	for ((i = 0; i < $WAITFLAVOR_MAX; i++)); do
		echo -n "checking $dir..."
		res=$(do_check_flavor $dir $flavor)
		echo "found $res/$expect $flavor connections"
		[ $res -ge $expect ] && return 0
		sleep 4
	done
	echo "Error checking $flavor of $dir: expect $expect, actual $res"
	do_nodes $(comma_list $(all_server_nodes)) "keyctl show"
	do_dump_flavor $dir
	if $dump; then
		gather_logs $(comma_list $(nodes_list))
	fi
	return 1
}
restore_to_default_flavor()
{
	local proc="mgs.MGS.live.$FSNAME"
	echo "restoring to default flavor..."
	local nrule=$(do_facet mgs lctl get_param -n $proc 2>/dev/null |
		grep ".srpc.flavor" | wc -l)
	if [ $nrule -ne 0 ]; then
		echo "$nrule existing rules"
		for rule in $(do_facet mgs lctl get_param -n $proc 2>/dev/null |
		    grep ".srpc.flavor."); do
			echo "remove rule: $rule"
			spec=`echo $rule | awk -F = '{print $1}'`
			do_facet mgs "$LCTL conf_param -d $spec"
		done
	fi
	nrule=$(do_facet mgs lctl get_param -n $proc 2>/dev/null |
		grep ".srpc.flavor." | wc -l)
	[ $nrule -ne 0 ] && error "still $nrule rules left"
	if $GSS_SK; then
		if $SK_S2S; then
			set_rule $FSNAME any any $SK_FLAVOR
			wait_flavor all2all $SK_FLAVOR
		else
			set_rule $FSNAME any cli2mdt $SK_FLAVOR
			set_rule $FSNAME any cli2ost $SK_FLAVOR
			wait_flavor cli2mdt $SK_FLAVOR
			wait_flavor cli2ost $SK_FLAVOR
		fi
		echo "GSS_SK now at default flavor: $SK_FLAVOR"
	else
		wait_flavor all2all null
	fi
}
set_flavor_all()
{
	local flavor=${1:-null}
	local maxtime=$(( 2 * $(request_timeout client)))
	local clients=${CLIENTS:-$HOSTNAME}
	echo "setting all flavor to $flavor"
	for c in ${clients//,/ }; do
		do_node $c lfs df -h
		do_rpc_nodes $c wait_import_state "FULL" \
			"osc.*.ost_server_uuid" $maxtime ||
		error "OSCs not in FULL state for client $c"
	done
	local cnt_all2all=$(calc_connection_cnt all2all)
	local res=$(do_check_flavor all2all $flavor)
	if [ $res -eq $cnt_all2all ]; then
		echo "already have total $res $flavor connections"
		return
	fi
	echo "found $res $flavor out of total $cnt_all2all connections"
	restore_to_default_flavor
	[[ $flavor = null ]] && return 0
	if $GSS_SK && [ $flavor != "null" ]; then
		if $SK_S2S; then
			set_rule $FSNAME any any $flavor
			wait_flavor all2all $flavor
		else
			set_rule $FSNAME any cli2mdt $flavor
			set_rule $FSNAME any cli2ost $flavor
			set_rule $FSNAME any mdt2ost null
			set_rule $FSNAME any mdt2mdt null
			wait_flavor cli2mdt $flavor
			wait_flavor cli2ost $flavor
		fi
		echo "GSS_SK now at flavor: $flavor"
	else
		set_rule $FSNAME any cli2mdt $flavor
		set_rule $FSNAME any cli2ost $flavor
		set_rule $FSNAME any mdt2ost null
		set_rule $FSNAME any mdt2mdt null
		wait_flavor cli2mdt $flavor
		wait_flavor cli2ost $flavor
	fi
}
check_logdir() {
	local dir=$1
	if [ ! -d $dir ]; then
		mkdir -p $dir
	else
		touch $dir/check_file.$(hostname -s)
	fi
	return 0
}
check_write_access() {
	local dir=$1
	local list=${2:-$(comma_list $(nodes_list))}
	local node
	local file
	for node in ${list//,/ }; do
		file=$dir/check_file.$(short_nodename $node)
		if [[ ! -f "$file" ]]; then
			return 1
		fi
		rm -f $file || return 1
	done
	return 0
}
init_logging() {
	[[ -n $YAML_LOG ]] && return
	local save_umask=$(umask)
	umask 0000
	export YAML_LOG=${LOGDIR}/results.yml
	mkdir -p $LOGDIR
	init_clients_lists
	if [ ! -f $YAML_LOG ]; then
		if check_shared_dir $LOGDIR; then
			touch $LOGDIR/shared
			echo "Logging to shared log directory: $LOGDIR"
		else
			echo "Logging to local directory: $LOGDIR"
		fi
		yml_nodes_file $LOGDIR >> $YAML_LOG
		yml_results_file >> $YAML_LOG
	fi
	umask $save_umask
	log "Client: $(grumple_build_version client)"
	log "MDS: $(grumple_build_version mds1)"
	log "OSS: $(grumple_build_version ost1)"
}
log_test() {
	yml_log_test $1 >> $YAML_LOG
}
log_test_status() {
	yml_log_test_status "$@" >> $YAML_LOG
}
log_sub_test_begin() {
	yml_log_sub_test_begin "$@" >> $YAML_LOG
}
log_sub_test_end() {
	yml_log_sub_test_end "$@" >> $YAML_LOG
}
run_llverdev()
{
	local dev=$1; shift
	local llverdev_opts="$*"
	local devname=$(basename $dev)
	local size=$(awk "/$devname$/ {print \$3}" /proc/partitions)
	[[ -z "$size" ]] && size=$(stat -c %s $dev)
	local size_gb=$((size / 1024 / 1024))
	local partial_arg=""
	(( $size == 0 || $size_gb > 1 )) && partial_arg="-p"
	llverdev --force $partial_arg $llverdev_opts $dev
}
run_llverfs()
{
	local dir=$1
	local llverfs_opts=$2
	local use_partial_arg=$3
	local partial_arg=""
	local size=$(df -B G $dir |tail -n 1 |awk '{print $2}' |sed 's/G//')
	[ "x$use_partial_arg" != "xno" ] && [ $size -gt 1 ] && partial_arg="-p"
	llverfs $partial_arg $llverfs_opts $dir
}
run_sgpdd () {
	local devs=${1//,/ }
	shift
	local params=$@
	local rslt=$TMP/sgpdd_survey
	local cmd="rslt=$rslt $params scsidevs=\"$devs\" $SGPDDSURVEY"
	echo + $cmd
	eval $cmd
	cat ${rslt}.detail
}
ldiskfs_canon() {
	local dev="$1"
	local facet="$2"
	do_facet $facet "dv=\\\$($LCTL get_param -n $dev);
			 if foo=\\\$(lvdisplay -c \\\$dv 2>/dev/null); then
				echo dm-\\\${foo
			 else
				name=\\\$(basename \\\$dv);
				if [[ \\\$name = *flakey* ]]; then
					name=\\\$(lsblk -o NAME,KNAME |
						awk /\\\$name/'{print \\\$NF}');
				fi;
				echo \\\$name;
			 fi;"
}
is_sanity_benchmark() {
	local benchmarks="dbench bonnie iozone fsx"
	local suite=$1
	for b in $benchmarks; do
		if [ "$b" == "$suite" ]; then
			return 0
		fi
	done
	return 1
}
min_ost_size () {
	$LFS df | grep OST | awk '{print $4}' | sort -un | head -1
}
get_obd_size() {
	local facet=$1
	local obd=$2
	local size
	[[ $facet != client ]] || return 0
	size=$(do_facet $facet $LCTL get_param -n *.$obd.kbytesavail | head -n1)
	echo -n $size
}
get_page_size() {
	local facet=$1
	local page_size=$(getconf PAGE_SIZE 2>/dev/null)
	[ -z "$CLIENTONLY" -a "$facet" != "client" ] &&
		page_size=$(do_facet $facet getconf PAGE_SIZE)
	echo -n ${page_size:-4096}
}
get_block_count() {
	local facet=$1
	local device=$2
	local count
	[ -z "$CLIENTONLY" ] &&
		count=$(do_facet $facet "$DUMPE2FS -h $device 2>&1" |
			awk '/^Block count:/ {print $3}')
	echo -n ${count:-0}
}
large_xattr_enabled() {
	[[ $(facet_fstype $SINGLEMDS) == zfs ]] && return 0
	local mds_dev=$(mdsdevname ${SINGLEMDS//mds/})
	do_facet $SINGLEMDS "$DUMPE2FS -h $mds_dev 2>&1 |
		grep -E -q '(ea_inode|large_xattr)'"
	return ${PIPESTATUS[0]}
}
max_xattr_size() {
	$LCTL get_param -n llite.*.max_easize
}
get_xattr_value() {
	local xattr_name=$1
	local file=$2
	echo "$(getfattr -n $xattr_name --absolute-names --only-values $file)"
}
generate_string() {
	local size=${1:-1024}
	echo "$(head -c $size < /dev/zero | tr '\0' y)"
}
reformat_external_journal() {
	local facet=$1
	local var
	var=${facet}_JRN
	local varbs=${facet}_BLOCKSIZE
	if [ -n "${!var}" ]; then
		local rcmd="do_facet $facet"
		local bs=${!varbs:-$BLCKSIZE}
		bs="-b $bs"
		echo "reformat external journal on $facet:${!var}"
		${rcmd} mke2fs -O journal_dev $bs ${!var} || return 1
	fi
}
mds_backup_restore() {
	local facet=$1
	local igif=$2
	local devname=$(mdsdevname $(facet_number $facet))
	local mntpt=$(facet_mntpt brpt)
	local rcmd="do_facet $facet"
	local metadata=${TMP}/backup_restore.tgz
	local opts=${MDS_MOUNT_FS_OPTS}
	local svc=${facet}_svc
	if ! ${rcmd} test -b ${devname}; then
		opts=$(csa_add "$opts" -o loop)
	fi
	echo "file-level backup/restore on $facet:${devname}"
	${rcmd} mkdir -p $mntpt
	${rcmd} rm -f $metadata
	${rcmd} mount -t ldiskfs $opts $devname $mntpt || return 3
	if [ ! -z $igif ]; then
		${rcmd} rm -rf $mntpt/ROOT/.grumple || return 3
	fi
	echo "backup data"
	${rcmd} tar zcf $metadata --xattrs --xattrs-include="trusted.*" \
		--sparse -C $mntpt/ . > /dev/null 2>&1 || return 4
	${rcmd} $UMOUNT $mntpt || return 5
	echo "reformat new device"
	format_mdt $(facet_number $facet)
	${rcmd} mount -t ldiskfs $opts $devname $mntpt || return 7
	echo "restore data"
	${rcmd} tar zxfp $metadata --xattrs --xattrs-include="trusted.*" \
		--sparse -C $mntpt > /dev/null 2>&1 || return 8
	echo "remove recovery logs"
	${rcmd} rm -fv $mntpt/OBJECTS/* $mntpt/CATALOGS
	${rcmd} $UMOUNT $mntpt || return 10
	${rcmd} rm -f $metaea $metadata
	${rcmd} e2label $devname ${!svc}
}
mds_remove_ois() {
	local facet=$1
	local idx=$2
	local devname=$(mdsdevname $(facet_number $facet))
	local mntpt=$(facet_mntpt brpt)
	local rcmd="do_facet $facet"
	local opts=${MDS_MOUNT_FS_OPTS}
	if ! ${rcmd} test -b ${devname}; then
		opts=$(csa_add "$opts" -o loop)
	fi
	echo "removing OI files on $facet: idx=${idx}"
	${rcmd} mkdir -p $mntpt
	${rcmd} mount -t ldiskfs $opts $devname $mntpt || return 1
	if [ -z $idx ]; then
		${rcmd} rm -fv $mntpt/oi.16*
	elif [ $idx -lt 2 ]; then
		${rcmd} rm -fv $mntpt/oi.16.${idx}
	else
		local i
		for ((i=${idx}; i<64; i=$((i * idx)))); do
			${rcmd} rm -fv $mntpt/oi.16.${i}
		done
	fi
	${rcmd} $UMOUNT $mntpt || return 2
}
generate_logname() {
	local logname=${1:-"default_logname"}
	echo "$TESTLOG_PREFIX.$TESTNAME.$logname.$(hostname -s).log"
}
test_mkdir() {
	local path
	local p_option
	local hash_type
	local hash_name=("all_char" "fnv_1a_64" "crush")
	local dirstripe_count=${DIRSTRIPE_COUNT:-"2"}
	local dirstripe_index=${DIRSTRIPE_INDEX:-$((base % $MDSCOUNT))}
	local OPTIND=1
	local overstripe_count
	local stripe_command="-c"
	(( $MDS1_VERSION > $(version_code v2_15_50-185-g1ac4b9598a) )) &&
		hash_name+=("crush2")
	while getopts "c:C:H:i:p" opt; do
		case $opt in
			c) dirstripe_count=$OPTARG;;
			C) overstripe_count=$OPTARG;;
			H) hash_type=$OPTARG;;
			i) dirstripe_index=$OPTARG;;
			p) p_option="-p";;
			\?) error "only support -c -H -i -p";;
		esac
	done
	shift $((OPTIND - 1))
	[ $
	path="$*"
	local parent=$(dirname $path)
	if [ "$p_option" == "-p" ]; then
		[ -d $path ] && return 0
		if [ ! -d ${parent} ]; then
			mkdir -p ${parent} ||
				error "mkdir parent '$parent' failed"
		fi
	fi
	if [[ -n "$overstripe_count" ]]; then
		stripe_command="-C"
		dirstripe_count=$overstripe_count
	fi
	if [ $MDSCOUNT -le 1 ] || ! is_grumple ${parent}; then
		mkdir $path || error "mkdir '$path' failed"
	else
		local mdt_index
		if [ $dirstripe_index -eq -1 ]; then
			mdt_index=$((base % MDSCOUNT))
		else
			mdt_index=$dirstripe_index
		fi
		[ -z "$hash_type" ] &&
			hash_type=${hash_name[$((RANDOM % ${
		if (($MDS1_VERSION >= $(version_code 2.8.0))); then
			if [ $dirstripe_count -eq -1 ]; then
				dirstripe_count=$((RANDOM % MDSCOUNT + 1))
			fi
		else
			dirstripe_count=1
		fi
		echo "striped dir -i$mdt_index $stripe_command$dirstripe_count -H $hash_type $path"
		$LFS mkdir -i$mdt_index $stripe_command$dirstripe_count -H $hash_type $path ||
			error "mkdir -i $mdt_index $stripe_command$dirstripe_count -H $hash_type $path failed"
	fi
}
free_fd()
{
	local max_fd=$(ulimit -n)
	local fd=$((${1:-2} + 1))
	while [[ $fd -le $max_fd && -e /proc/self/fd/$fd ]]; do
		((++fd))
	done
	[ $fd -lt $max_fd ] || error "finding free file descriptor failed"
	echo $fd
}
check_mount_and_prep()
{
	is_mounted $MOUNT || setupall
	rm -rf $DIR/[df][0-9]* || error "Fail to cleanup the env!"
	mkdir_on_mdt0 $DIR/$tdir || error "Fail to mkdir $DIR/$tdir."
	for idx in $(seq $MDSCOUNT); do
		local name="MDT$(printf '%04x' $((idx - 1)))"
		rm -rf $MOUNT/.grumple/lost+found/$name/*
	done
}
precreated_ost_obj_count()
{
	local mdt_idx=$1
	local ost_idx=$2
	local mdt_name="MDT$(printf '%04x' $mdt_idx)"
	local ost_name="OST$(printf '%04x' $ost_idx)"
	local proc_path="${FSNAME}-${ost_name}-osc-${mdt_name}"
	local last_id=$(do_facet mds$((mdt_idx + 1)) lctl get_param -n \
			osp.$proc_path.prealloc_last_id)
	local next_id=$(do_facet mds$((mdt_idx + 1)) lctl get_param -n \
			osp.$proc_path.prealloc_next_id)
	local ost_obj_count=$((last_id - next_id + 1))
	echo " - precreated_ost_obj_count $proc_path" \
	     "prealloc_last_id: $last_id" \
	     "prealloc_next_id: $next_id" \
	     "count: $ost_obj_count" 1>&2
	echo $ost_obj_count
}
check_file_in_pool()
{
	local file=$1
	local pool=$2
	local tlist="$3"
	local res=$($LFS getstripe $file | grep 0x | cut -f2)
	for i in $res
	do
		for t in $tlist ; do
			[ "$i" -eq "$t" ] && continue 2
		done
		echo "pool list: $tlist"
		echo "striping: $res"
		error_noexit "$file not allocated in $pool"
		return 1
	done
	return 0
}
pool_add() {
	local pool=$1
	local mdscount=${2:-$MDSCOUNT}
	echo "Creating new pool $pool"
	create_pool $FSNAME.$pool false $mdscount ||
		{ error_noexit "No pool created, result code $?"; return 1; }
	[ $($LFS pool_list $FSNAME | grep -c "$FSNAME.${pool}\$") -eq 1 ] ||
		{ error_noexit "$pool not in lfs pool_list"; return 2; }
}
pool_add_targets() {
	echo "Adding targets to pool"
	local pool=$1
	local first=$2
	local last=${3:-$first}
	local step=${4:-1}
	local mdscount=${5:-$MDSCOUNT}
	local list=$(seq $first $step $last)
	local t=$(for i in $list; do printf "$FSNAME-OST%04x_UUID " $i; done)
	local tg=$(for i in $list;
		do printf -- "-e $FSNAME-OST%04x_UUID " $i; done)
	local firstx=$(printf "%04x" $first)
	local lastx=$(printf "%04x" $last)
	do_facet mgs $LCTL pool_add \
		$FSNAME.$pool $FSNAME-OST[$firstx-$lastx/$step]
	if (( $? != 0 && $? != 17 )); then
		error_noexit "pool_add $FSNAME-OST[$firstx-$lastx/$step] failed"
		return 3
	fi
	for ((mds_id = 1; mds_id < $mdscount; mds_id++)); do
		local mdt_id=$((mds_id-1))
		local lodname=$FSNAME-MDT$(printf "%04x" $mdt_id)-mdtlov
		wait_update_facet mds$mds_id \
			"lctl get_param -n lod.$lodname.pools.$pool |
				grep $tg | sort -u | tr '\n' ' '" "$t" || {
			error_noexit "mds$mds_id: Add to pool failed"
			return 2
		}
	done
	wait_update $HOSTNAME "lctl get_param -n lov.$FSNAME-*.pools.$pool |
			grep $tg | sort -u | tr '\n' ' ' " "$t" || {
		error_noexit "Add to pool failed"
		return 1
	}
}
pool_set_dir() {
	local pool=$1
	local tdir=$2
	echo "Setting pool on directory $tdir"
	$LFS setstripe -c 2 -p $pool $tdir && return 0
	error_noexit "Cannot set pool $pool to $tdir"
	return 1
}
pool_check_dir() {
	local pool=$1
	local tdir=$2
	echo "Checking pool on directory $tdir"
	local res=$($LFS getstripe --pool $tdir | sed "s/\s*$//")
	[ "$res" = "$pool" ] && return 0
	error_noexit "Pool on '$tdir' is '$res', not '$pool'"
	return 1
}
pool_dir_rel_path() {
	echo "Testing relative path works well"
	local pool=$1
	local tdir=$2
	local root=$3
	mkdir -p $root/$tdir/$tdir
	cd $root/$tdir
	pool_set_dir $pool $tdir          || return 1
	pool_set_dir $pool ./$tdir        || return 2
	pool_set_dir $pool ../$tdir       || return 3
	pool_set_dir $pool ../$tdir/$tdir || return 4
	rm -rf $tdir; cd - > /dev/null
}
pool_alloc_files() {
	echo "Checking files allocation from directory pool"
	local pool=$1
	local tdir=$2
	local count=$3
	local tlist="$4"
	local failed=0
	for i in $(seq -w 1 $count)
	do
		local file=$tdir/file-$i
		touch $file
		check_file_in_pool $file $pool "$tlist" || \
			failed=$((failed + 1))
	done
	[ "$failed" = 0 ] && return 0
	error_noexit "$failed files not allocated in $pool"
	return 1
}
pool_create_files() {
	echo "Creating files in pool"
	local pool=$1
	local tdir=$2
	local count=$3
	local tlist="$4"
	mkdir -p $tdir
	local failed=0
	for i in $(seq -w 1 $count)
	do
		local file=$tdir/spoo-$i
		$LFS setstripe -p $pool $file
		check_file_in_pool $file $pool "$tlist" || \
			failed=$((failed + 1))
	done
	[ "$failed" = 0 ] && return 0
	error_noexit "$failed files not allocated in $pool"
	return 1
}
pool_lfs_df() {
	echo "Checking 'lfs df' output"
	local pool=$1
	local t=$($LCTL get_param -n lov.$FSNAME-clilov-*.pools.$pool |
			tr '\n' ' ')
	local res=$($LFS df --pool $FSNAME.$pool |
			awk '{print $1}' |
			grep "$FSNAME-OST" |
			tr '\n' ' ')
	[ "$res" = "$t" ] && return 0
	error_noexit "Pools OSTs '$t' is not '$res' that lfs df reports"
	return 1
}
pool_file_rel_path() {
	echo "Creating files in a pool with relative pathname"
	local pool=$1
	local tdir=$2
	mkdir -p $tdir ||
		{ error_noexit "unable to create $tdir"; return 1 ; }
	local file="/..$tdir/$tfile-1"
	$LFS setstripe -p $pool $file ||
		{ error_noexit "unable to create $file" ; return 2 ; }
	cd $tdir
	$LFS setstripe -p $pool $tfile-2 || {
		error_noexit "unable to create $tfile-2 in $tdir"
		return 3
	}
}
pool_remove_first_target() {
	echo "Removing first target from a pool"
	pool_remove_target $1 -1
}
pool_remove_target() {
	local pool=$1
	local index=$2
	local pname="lov.$FSNAME-*.pools.$pool"
	if [ $index -eq -1 ]; then
		local t=$($LCTL get_param -n $pname | head -1)
	else
		local t=$(printf "$FSNAME-OST%04x_UUID" $index)
	fi
	echo "Removing $t from $pool"
	do_facet mgs $LCTL pool_remove $FSNAME.$pool $t
	for mds_id in $(seq $MDSCOUNT); do
		local mdt_id=$((mds_id-1))
		local lodname=$FSNAME-MDT$(printf "%04x" $mdt_id)-mdtlov
		wait_update_facet mds$mds_id \
			"lctl get_param -n lod.$lodname.pools.$pool |
				grep $t" "" || {
			error_noexit "mds$mds_id: $t not removed from" \
			"$FSNAME.$pool"
			return 2
		}
	done
	wait_update $HOSTNAME "lctl get_param -n $pname | grep $t" "" || {
		error_noexit "$t not removed from $FSNAME.$pool"
		return 1
	}
}
pool_remove_all_targets() {
	echo "Removing all targets from pool"
	local pool=$1
	local file=$2
	local pname="lov.$FSNAME-*.pools.$pool"
	for t in $($LCTL get_param -n $pname | sort -u)
	do
		do_facet mgs $LCTL pool_remove $FSNAME.$pool $t
	done
	for mds_id in $(seq $MDSCOUNT); do
		local mdt_id=$((mds_id-1))
		local lodname=$FSNAME-MDT$(printf "%04x" $mdt_id)-mdtlov
		wait_update_facet mds$mds_id "lctl get_param -n \
			lod.$lodname.pools.$pool" "" || {
			error_noexit "mds$mds_id: Pool $pool not drained"
			return 4
		}
	done
	wait_update $HOSTNAME "lctl get_param -n $pname" "" || {
		error_noexit "Pool $FSNAME.$pool cannot be drained"
		return 1
	}
	touch $file || {
		error_noexit "failed to use fallback striping for empty pool"
		return 2
	}
	$LFS setstripe -p $pool $file 2>/dev/null && {
		error_noexit "expected failure when creating file" \
							"with empty pool"
		return 3
	}
	return 0
}
pool_remove() {
	echo "Destroying pool"
	local pool=$1
	local file=$2
	do_facet mgs $LCTL pool_destroy $FSNAME.$pool
	sleep 2
	touch $file || {
		error_noexit "failed to use fallback striping for missing pool"
		return 1
	}
	$LFS setstripe -p $pool $file 2>/dev/null && {
		error_noexit "expected failure when creating file" \
							"with missing pool"
		return 2
	}
	if wait_update $HOSTNAME "lctl get_param -n \
		lov.$FSNAME-*.pools.$pool 2>/dev/null || echo foo" "foo"
	then
		remove_pool_from_list $FSNAME.$pool
		return 0
	fi
	error_noexit "Pool $FSNAME.$pool is not destroyed"
	return 3
}
check_stripe_count() {
	local file=$1
	local expected=$2
	local actual
	[[ -z "$file" || -z "$expected" ]] &&
		error "check_stripe_count: invalid argument"
	local cmd="$LFS getstripe -c $file"
	actual=$($cmd) || error "$cmd failed"
	actual=${actual%% *}
	if [[ $actual -ne $expected ]]; then
		[[ $expected -eq -1 ]] || { $LFS getstripe $file;
			error "$cmd not expected ($expected): found $actual"; }
		[[ $actual -eq $OSTCOUNT ]] || { $LFS getstripe $file;
			error "$cmd not OST count ($OSTCOUNT): found $actual"; }
	fi
}
check_obdidx() {
	local file=$1
	local expected=$2
	local obdidx
	[[ -z "$file" || -z "$expected" ]] &&
		error "check_obdidx: invalid argument!"
	obdidx=$(comma_list $($LFS getstripe $file | grep -A $OSTCOUNT obdidx |
			      grep -v obdidx | awk '{print $1}' | xargs))
	[[ $obdidx = $expected ]] ||
		error "list of OST indices on $file is $obdidx," \
		      "should be $expected"
}
check_start_ost_idx() {
	local file=$1
	local expected=$2
	local start_ost_idx
	[[ -z "$file" || -z "$expected" ]] &&
		error "check_start_ost_idx: invalid argument!"
	start_ost_idx=$($LFS getstripe $file | grep -A 1 obdidx |
			 grep -v obdidx | awk '{print $1}')
	[[ $start_ost_idx = $expected ]] ||
		error "OST index of the first stripe on $file is" \
		      "$start_ost_idx, should be $expected"
}
killall_process () {
	local clients=${1:-$(hostname)}
	local name=$2
	local signal=$3
	local rc=0
	do_nodes $clients "killall $signal $name"
}
lsnapshot () {
	local cmd=$1
	shift
	if (( $MDS1_VERSION >= $(version_code 2.16.50) )); then
		do_facet mgs "$LCTL snapshot $cmd -F $FSNAME $*"
	else
		do_facet mgs "$LCTL snapshot_$cmd -F $FSNAME $*"
	fi
}
lsnapshot_create()
{
	lsnapshot create $*
}
lsnapshot_destroy()
{
	lsnapshot destroy $*
}
lsnapshot_modify()
{
	lsnapshot modify $*
}
lsnapshot_list()
{
	lsnapshot list $*
}
lsnapshot_mount()
{
	lsnapshot mount $*
}
lsnapshot_umount()
{
	lsnapshot umount $*
}
lss_err()
{
	local msg=$1
	do_facet mgs "cat $LSNAPSHOT_LOG"
	error $msg
}
lss_cleanup()
{
	echo "Cleaning test environment ..."
	while true; do
		local ssname=$(lsnapshot_list | grep snapshot_name |
			grep lss_ | awk '{ print $2 }' | head -n 1)
		[ -z "$ssname" ] && break
		lsnapshot_destroy -n $ssname -f ||
			lss_err "Fail to destroy $ssname by force"
	done
}
lss_gen_conf_one()
{
	local facet=$1
	local role=$2
	local idx=$3
	local host=$(facet_active_host $facet)
	local dir=$(dirname $(facet_vdevice $facet))
	local pool=$(zpool_name $facet)
	local lfsname=$(zfs_local_fsname $facet)
	local label=${FSNAME}-${role}$(printf '%04x' $idx)
	do_facet mgs \
		"echo '$host - $label zfs:${dir}/${pool}/${lfsname} - -' >> \
		$LSNAPSHOT_CONF"
}
lss_gen_conf()
{
	do_facet mgs "rm -f $LSNAPSHOT_CONF"
	echo "Generating $LSNAPSHOT_CONF on MGS ..."
	if ! combined_mgs_mds ; then
		[ $(facet_fstype mgs) != zfs ] &&
			skip "Lustre snapshot 1 only works for ZFS backend"
		local host=$(facet_active_host mgs)
		local dir=$(dirname $(facet_vdevice mgs))
		local pool=$(zpool_name mgs)
		local lfsname=$(zfs_local_fsname mgs)
		do_facet mgs \
			"echo '$host - MGS zfs:${dir}/${pool}/${lfsname} - -' \
			>> $LSNAPSHOT_CONF" || lss_err "generate lss conf (mgs)"
	fi
	for num in `seq $MDSCOUNT`; do
		[ $(facet_fstype mds$num) != zfs ] &&
			skip "Lustre snapshot 1 only works for ZFS backend"
		lss_gen_conf_one mds$num MDT $((num - 1)) ||
			lss_err "generate lss conf (mds$num)"
	done
	for num in `seq $OSTCOUNT`; do
		[ $(facet_fstype ost$num) != zfs ] &&
			skip "Lustre snapshot 1 only works for ZFS backend"
		lss_gen_conf_one ost$num OST $((num - 1)) ||
			lss_err "generate lss conf (ost$num)"
	done
	do_facet mgs "cat $LSNAPSHOT_CONF"
}
parse_plain_dir_param()
{
	local invalues=($1)
	local param=""
	if [[ ${invalues[0]} =~ "stripe_count:" ]]; then
		(( ${invalues[1]} == $OSTCOUNT - 1 )) &&
			param="-c $OSTCOUNT" || param="-c ${invalues[1]}"
	fi
	if [[ ${invalues[2]} =~ "stripe_size:" ]]; then
		param="$param -S ${invalues[3]}"
	fi
	if [[ ${invalues[4]} =~ "pattern:" ]]; then
		if [[ ${invalues[5]} =~ "stripe_offset:" ]]; then
			param="$param -i ${invalues[6]}"
		else
			param="$param -L ${invalues[5]} -i ${invalues[7]}"
		fi
	elif [[ ${invalues[4]} =~ "stripe_offset:" ]]; then
		param="$param -i ${invalues[5]}"
	fi
	echo "$param"
}
parse_plain_param()
{
	local line=$1
	local val=$(awk '{print $2}' <<< $line)
	if [[ $line =~ ^"lmm_stripe_count:" ]]; then
		(( $val == $OSTCOUNT - 1 )) &&
			param="-c $OSTCOUNT" || param="-c $val"
		echo "-c $val"
	elif [[ $line =~ ^"lmm_stripe_size:" ]]; then
		echo "-S $val"
	elif [[ $line =~ ^"lmm_stripe_offset:" && $SKIP_INDEX != yes ]]; then
		echo "-i $val"
	elif [[ $line =~ ^"lmm_pattern:" ]]; then
		echo "-L $val"
	fi
}
parse_dir_param()
{
	local line=$1
	local val=$(awk '{print $2}' <<< $line)
	if [[ $line =~ ^"lmv_stripe_count:" ]]; then
		echo "-c $val"
	elif [[ $line =~ ^"lmv_stripe_offset:" ]]; then
		echo "-i $val"
	elif [[ $line =~ ^"lmv_hash_type:" ]]; then
		echo "-H $val"
	elif [[ $line =~ ^"lmv_max_inherit:" ]]; then
		echo "-X $val"
	fi
}
parse_layout_param()
{
	local mode=""
	local val=""
	local param=""
	while read line; do
		if [[ ! -z $line ]]; then
			if [[ -z $mode ]]; then
				if [[ $line =~ ^"stripe_count:" ]]; then
					mode="plain_dir"
				elif [[ $line =~ ^"lmm_stripe_count:" ]]; then
					mode="plain_file"
				elif [[ $line =~ ^"lcm_layout_gen:" ]]; then
					mode="pfl"
				elif [[ $line =~ ^"lmv_stripe_count" ]]; then
					mode="dne"
				fi
			fi
			if [[ $mode = "plain_dir" ]]; then
				param=$(parse_plain_dir_param "$line")
			elif [[ $mode = "plain_file" ]]; then
				val=$(parse_plain_param "$line")
				[[ ! -z $val ]] && param="$param $val"
			elif [[ $mode = "pfl" ]]; then
				val=$(echo $line | awk '{print $2}')
				if [[ $line =~ ^"lcme_extent.e_end:" ]]; then
					if [[ $val = "EOF" ]]; then
						param="$param -E -1"
					else
						param="$param -E $val"
					fi
				elif [[ $line =~ ^"stripe_count:" ]]; then
					val=$(parse_plain_dir_param "$line")
					param="$param $val"
				else
					val=$(parse_plain_param "$line")
					[[ ! -z $val ]] && param="$param $val"
				fi
			elif [[ $mode = "dne" ]]; then
				val=$(parse_dir_param "$line")
				[[ ! -z $val ]] && param="$param $val"
			fi
		fi
	done
	echo "$param"
}
get_layout_param()
{
	local param=$($LFS getstripe -dy $1 | parse_layout_param)
	echo "$param"
}
get_dir_layout_param()
{
	local param=$($LFS getdirstripe -y $1 | parse_layout_param)
	echo "$param"
}
lfsck_verify_pfid()
{
	local f
	local rc=0
	cancel_lru_locks mdc
	cancel_lru_locks osc
	do_nodes $(osts_nodes) \
	       "$LCTL set_param -n obdfilter.${FSNAME}-OST*.lfsck_verify_pfid=1"
	for f in "$@"; do
		cat $f &> /dev/nullA ||
			{ rc=$?; echo "verify $f failed"; break; }
	done
	do_nodes $(osts_nodes) \
	       "$LCTL set_param -n obdfilter.${FSNAME}-OST*.lfsck_verify_pfid=0"
	return $rc
}
check_clients_evicted() {
	local before=$1
	shift
	local oscs=${@}
	local osc
	local rc=0
	for osc in $oscs; do
		echo "Check state for $osc"
		local evicted=$(do_facet client $LCTL get_param osc.$osc.state |
			tail -n 5 | awk -F"[ ,]" \
			'/EVICTED/ { if (mx<$4) { mx=$4; } } END { print mx }')
		if (($? == 0)) && (($evicted > $before)); then
			echo "$osc is evicted at $evicted"
		else
			((rc++))
			echo "$osc was not evicted after $before:"
			do_facet client $LCTL get_param osc.$osc.state |
				tail -n 8
		fi
	done
	[ $rc -eq 0 ] || error "client not evicted from OST"
}
check_clients_full() {
	local timeout=$1
	shift
	local oscs=${@}
	for osc in $oscs; do
		wait_update_facet client \
			"lctl get_param -n osc.$osc.state |
			grep 'current_state: FULL'" \
			"current_state: FULL" $timeout
		[ $? -eq 0 ] || error "$osc state is not FULL"
	done
}
__changelog_deregister() {
	local facet=$1
	local mdt="$(facet_svc $facet)"
	local cl_user=$2
	local rc=0
	if (( $MDS1_VERSION >= $(version_code 2.16.50) )); then
		changelog_deregister="changelog deregister"
	else
		changelog_deregister="changelog_deregister"
	fi
	[ -z "$cl_user" ] && echo "$mdt: no changelog user" && return 0
	changelog_users "$facet" | grep -q "$cl_user" ||
		{ echo "$mdt: changelog user '$cl_user' not found"; return 0; }
	__changelog_clear $facet $cl_user 0 ||
		error_noexit "$mdt: changelog_clear $cl_user 0 fail: $rc"
	do_facet $facet $LCTL --device $mdt $changelog_deregister $cl_user ||
		error_noexit "$mdt: changelog_deregister '$cl_user' fail: $rc"
}
declare -Ax CL_USERS
changelog_register() {
	if (( $MDS1_VERSION >= $(version_code 2.16.50) )); then
		changelog_register="changelog register"
	else
		changelog_register="changelog_register"
	fi
	for M in $(seq $MDSCOUNT); do
		local facet=mds$M
		local mdt="$(facet_svc $facet)"
		local cl_mask
		cl_mask=$(do_facet $facet $LCTL get_param \
			     mdd.${mdt}.changelog_mask -n)
		stack_trap "do_facet $facet $LCTL \
			set_param mdd.$mdt.changelog_mask=\'$cl_mask\' -n" EXIT
		do_facet $facet $LCTL set_param mdd.$mdt.changelog_mask=+hsm ||
			error "$mdt: changelog_mask=+hsm failed: $?"
		local cl_user
		cl_user=$(do_facet $facet $LCTL --device $mdt \
			$changelog_register -n "$@") ||
			error "$mdt: register changelog user failed: $?"
		stack_trap "__changelog_deregister $facet $cl_user" EXIT
		stack_trap "CL_USERS[$facet]='${CL_USERS[$facet]}'" EXIT
		CL_USERS[$facet]+="$cl_user "
	done
	echo "Registered $MDSCOUNT changelog users: '${CL_USERS[*]% }'"
}
changelog_deregister() {
	local cl_user
	local cl_facets=$(echo "${!CL_USERS[@]}" | tr " " "\n" | sort |
			  tr "\n" " ")
	for facet in $cl_facets; do
		for cl_user in ${CL_USERS[$facet]}; do
			__changelog_deregister $facet $cl_user || return $?
		done
		unset CL_USERS[$facet]
	done
}
changelog_users() {
	local facet=$1
	local service=$(facet_svc $facet)
	do_facet $facet $LCTL get_param -n mdd.$service.changelog_users
}
changelog_user_rec() {
	local facet=$1
	local cl_user=$2
	local service=$(facet_svc $facet)
	changelog_users $facet | awk '$1 == "'$cl_user'" { print $2 }'
}
changelog_chmask() {
	local mask=$1
	do_nodes $(mdts_nodes) $LCTL set_param mdd.*.changelog_mask="$mask"
}
__changelog_clear()
{
	local facet=$1
	local mdt="$(facet_svc $facet)"
	local cl_user=$2
	local -i rec
	case "$3" in
	+*)
		rec=${3:1}
		rec+=$(changelog_user_rec $facet $cl_user)
		;;
	*)
		rec=$3
		;;
	esac
	if [ $rec -eq 0 ]; then
		echo "$mdt: clear the changelog for $cl_user of all records"
	else
		echo "$mdt: clear the changelog for $cl_user to record
	fi
	$LFS changelog_clear $mdt $cl_user $rec
}
changelog_clear() {
	local rc
	local idx=$1
	shift
	local cl_facets="$@"
	[[ -n "$cl_facets" ]] ||
		cl_facets=$(echo "${!CL_USERS[@]}" | tr " " "\n" | sort |
			tr "\n" " ")
	local cl_user
	for facet in $cl_facets; do
		for cl_user in ${CL_USERS[$facet]}; do
			__changelog_clear $facet $cl_user $idx || rc=${rc:-$?}
		done
	done
	return ${rc:-0}
}
changelog_dump() {
	local rc
	for M in $(seq $MDSCOUNT); do
		local facet=mds$M
		local mdt="$(facet_svc $facet)"
		local output
		local ret
		output=$($LFS changelog $mdt)
		ret=$?
		if [ $ret -ne 0 ]; then
			rc=${rc:-$ret}
		elif [ -n "$output" ]; then
			echo "$output" | sed -e 's/^/'$mdt'./'
		fi
	done
	return ${rc:-0}
}
changelog_extract_field() {
	local cltype=$1
	local file=$2
	local identifier=$3
	changelog_dump | gawk "/$cltype.*$file$/ {
		print gensub(/^.* "$identifier'(\[[^\]]*\]).*$/,"\\1",1)}' |
		tail -1
}
changelog2array()
{
	printf '('
	local index="${1
	printf "[index]='%s' [type]='%s' [time]='%s' [date]='%s' [flags]='%s'" \
	       "$index" "${2:2}" "$3" "$4" "$5"
	for arg in "${@:5}"; do
		[[ "$arg" =~ ^[[:alpha:]]+= ]] || continue
		local key="${arg%%=*}"
		local value="${arg
		case "$key" in
		u)
			printf " [uid]='%s'" "${value%:*}"
			key=gid
			value="${value
			;;
		t)
			key=target-fid
			value="${value
			value="${value%]}"
			;;
		j)
			key=jobid
			;;
		p)
			key=parent-fid
			value="${value
			value="${value%]}"
			;;
		ef)
			key=extra-flags
			;;
		m)
			key=mode
			;;
		x)
			key=xattr
			;;
		s)
			key=source-fid
			value="${value
			value="${value%]}"
			;;
		*)
			;;
		esac
		printf " ['%s']='%s'" "$key" "$value"
	done
	printf ')'
}
__changelog_printf()
{
	local format="$1"
	local -i i
	for ((i = 0; i < ${
		local char="${format:$i:1}"
		if [ "$char" != % ]; then
			printf '%c' "$char"
			continue
		fi
		i+=1
		char="${format:$i:1}"
		case "$char" in
		f)
			printf '%s' "${changelog[flags]}"
			;;
		%)
			printf '%'
			;;
		esac
	done
	printf '\n'
}
changelog_find()
{
	local -A filter
	local action='print'
	local format
	while [ $
		case "$1" in
		-print)
			action='print'
			;;
		-printf)
			action='printf'
			format="$2"
			shift
			;;
		-*)
			filter[${1
			shift
			;;
		esac
		shift
	done
	local found=false
	local record
	changelog_dump | { while read -r record; do
		eval local -A changelog=$(changelog2array $record)
		for key in "${!filter[@]}"; do
			case "$key" in
			*)
				[ "${changelog[$key]}" == "${filter[$key]}" ]
				;;
			esac || continue 2
		done
		found=true
		case "${action:-print}" in
		print)
			printf '%s\n' "$record"
			;;
		printf)
			__changelog_printf "$format"
			;;
		esac
	done; $found; }
}
restore_layout() {
	local dir=$1
	local layout=$2
	[ ! -d "$dir" ] && return
	[ -z "$layout" ] && {
		$LFS setstripe -d $dir || error "error deleting stripe '$dir'"
		return
	}
	setfattr -n trusted.lov -v $layout $dir ||
		error "error restoring layout '$layout' to '$dir'"
}
save_layout() {
	local dir=$1
	local str=$(getfattr -n trusted.lov --absolute-names -e hex $dir \
		    2> /dev/null | awk -F'=' '/trusted.lov/{ print $2 }')
	echo "$str"
}
save_layout_restore_at_exit() {
	local dir=$1
	local layout=$(save_layout $dir)
	stack_trap "restore_layout $dir $layout" EXIT
}
init_stripe_dir_params() {
	local varremote=$1
	local varstriped=$2
	if ((MDSCOUNT > 1 &&
		$MDS1_VERSION >=
		$(version_code 2.8.0))); then
		eval $varremote=${!varremote:-true}
		eval $varstriped=${!varstriped:-true}
	elif ((MDSCOUNT > 1 &&
		$MDS1_VERSION >=
		$(version_code 2.5.0))); then
		eval $varremote=${!varremote:-true}
		eval $varstriped=${!varstriped:-false}
	fi
	eval $varremote=${!varremote:-false}
	eval $varstriped=${!varstriped:-false}
}
verify_yaml_layout() {
	local src=$1
	local dst=$2
	local temp=$3
	local msg_prefix=$4
	echo "$msg_prefix: getstripe --yaml $src"
	$LFS getstripe --yaml $src > $temp ||
		error "$msg_prefix: getstripe $src failed"
	echo "$msg_prefix: setstripe --yaml=$temp $dst"
	$LFS setstripe --yaml=$temp $dst || {
		$LFS df -v $dst
		$LFS df -i $dst
		sed -e "s/^/$msg_prefix-yaml: /" $temp
		getfattr -d -m - -e hex $src
		getfattr -d -m - -e hex $dst
		error "$msg_prefix: setstripe '$dst' failed"
	}
	echo "$msg_prefix: compare"
	local layout_src=$(get_layout_param $src)
	local layout_dst=$(get_layout_param $dst)
	[ "$layout_src" == "$layout_dst" ] || {
		sed -e "s/^/$msg_prefix-src: /" <<< $layout_src
		sed -e "s/^/$msg_prefix-dst: /" <<< $layout_dst
		error "$msg_prefix: $src/$dst layouts are not equal"
	}
}
is_project_quota_supported() {
	$ENABLE_PROJECT_QUOTAS || return 1
	[[ -z "$SAVE_PROJECT_SUPPORTED" ]] || return $SAVE_PROJECT_SUPPORTED
	local save_project_supported=1
	[[ "$(facet_fstype $SINGLEMDS)" == "ldiskfs" &&
	   $(grumple_version_code $SINGLEMDS) -gt $(version_code 2.9.55) ]] &&
		do_facet mds1 lfs --list-commands |& grep -q project &&
			save_project_supported=0
	[[ "$(facet_fstype $SINGLEMDS)" == "zfs" &&
	   $(grumple_version_code $SINGLEMDS) -gt $(version_code 2.10.53) ]] &&
		do_facet mds1 $ZPOOL get all | grep -q project_quota &&
			save_project_supported=0
	export SAVE_PROJECT_SUPPORTED=$save_project_supported
	echo "using SAVE_PROJECT_SUPPORTED=$SAVE_PROJECT_SUPPORTED"
	return $save_project_supported
}
enable_project_quota() {
	is_project_quota_supported || return 0
	local zkeeper=${KEEP_ZPOOL}
	stack_trap "KEEP_ZPOOL=$zkeeper" EXIT
	KEEP_ZPOOL="true"
	stopall || error "failed to stopall (1)"
	local zfeat_en="feature@project_quota=enabled"
	for facet in $(seq -f mds%g $MDSCOUNT) $(seq -f ost%g $OSTCOUNT); do
		local facet_fstype=${facet:0:3}1_FSTYPE
		local devname
		if [ "${!facet_fstype}" = "zfs" ]; then
			devname=$(zpool_name ${facet})
			do_facet ${facet} $ZPOOL set "$zfeat_en" $devname ||
				error "$ZPOOL set $zfeat_en $devname"
		else
			[ ${facet:0:3} == "mds" ] &&
				devname=$(mdsdevname ${facet:3}) ||
				devname=$(ostdevname ${facet:3})
			do_facet ${facet} $TUNE2FS -O project $devname ||
				error "tune2fs $devname failed"
		fi
	done
	KEEP_ZPOOL="${zkeeper}"
	mount
	setupall
}
disable_project_quota() {
	is_project_quota_supported || return 0
	[ "$mds1_FSTYPE" != "ldiskfs" ] && return 0
	stopall || error "failed to stopall (1)"
	for num in $(seq $MDSCOUNT); do
		do_facet mds$num $TUNE2FS -Q ^prj $(mdsdevname $num) ||
			error "tune2fs $(mdsdevname $num) failed"
	done
	for num in $(seq $OSTCOUNT); do
		do_facet ost$num $TUNE2FS -Q ^prj $(ostdevname $num) ||
			error "tune2fs $(ostdevname $num) failed"
	done
	mount
	setupall
}
change_project() {
	echo "$LFS project $*"
	$LFS project $* || error "$LFS project $* failed"
}
getquota() {
	local type=$1
	local id=$2
	local uuid
	local spec=$4
	local pool=$5
	local pool_arg
	sync_all_data > /dev/null 2>&1 || true
	[[ "$
		error "getquota: wrong number of arguments: $
	[[ "$type" != "-u" && "$type" != "-g" && "$type" != "-p" ]] &&
		error "getquota: wrong u/g/p specifier $1 passed"
	[[ "$spec" =~ "curspace" ]] && spec="space"
	[[ "$spec" =~ "curinode" ]] && spec="inodes"
	[[ ! -z "$pool" ]] && pool_arg="--pool $pool "
	[[ "$3" =~ "OST" ]] && uuid="--ost $(echo "$3" | tail -c 4) "
	[[ "$3" =~ "MDT" ]] && uuid="--mdt $(echo "$3" | tail -c 4) "
	echo -n "$type $id $uuid $spec:" 1>&2
	$LFS quota -q $uuid --$spec "$type" "$id" $pool_arg$DIR | tr -d "*" 1>&2
	$LFS quota -q $uuid --$spec "$type" "$id" $pool_arg$DIR | tr -d "*"
}
set_mdt_qtype() {
	local qtype=$1
	local varsvc
	local mdts=$(get_facets MDS)
	local cmd
	[[ "$qtype" =~ "p" ]] && ! is_project_quota_supported &&
		qtype=$(tr -d 'p' <<<$qtype)
	if [[ $PERM_CMD == *"set_param -P"* ]]; then
		do_facet mgs $PERM_CMD \
			osd-*.$FSNAME-MDT*.quota_slave.enabled=$qtype
	else
		do_facet mgs $PERM_CMD $FSNAME.quota.mdt=$qtype
	fi
	for mdt in ${mdts//,/ }; do
		varsvc=${mdt}_svc
		cmd="$LCTL get_param -n "
		cmd=${cmd}osd-$(facet_fstype $mdt).${!varsvc}
		cmd=${cmd}.quota_slave.enabled
		if $(facet_up $mdt); then
			wait_update_facet $mdt "$cmd" "$qtype" || return 1
		fi
	done
	return 0
}
set_ost_qtype() {
	local qtype=$1
	local varsvc
	local osts=$(get_facets OST)
	local cmd
	[[ "$qtype" =~ "p" ]] && ! is_project_quota_supported &&
		qtype=$(tr -d 'p' <<<$qtype)
	if [[ $PERM_CMD == *"set_param -P"* ]]; then
		do_facet mgs $PERM_CMD \
			osd-*.$FSNAME-OST*.quota_slave.enabled=$qtype
	else
		do_facet mgs $PERM_CMD $FSNAME.quota.ost=$qtype
	fi
	for ost in ${osts//,/ }; do
		varsvc=${ost}_svc
		cmd="$LCTL get_param -n "
		cmd=${cmd}osd-$(facet_fstype $ost).${!varsvc}
		cmd=${cmd}.quota_slave.enabled
		if $(facet_up $ost); then
			wait_update_facet $ost "$cmd" "$qtype" || return 1
		fi
	done
	return 0
}
init_agt_vars() {
	local n
	local agent
	export AGTCOUNT=${AGTCOUNT:-$((CLIENTCOUNT - 1))}
	[[ $AGTCOUNT -gt 0 ]] || AGTCOUNT=1
	export SHARED_DIRECTORY=${SHARED_DIRECTORY:-$TMP}
	if [[ $CLIENTCOUNT -gt 1 ]] &&
		! check_shared_dir $SHARED_DIRECTORY $CLIENTS; then
		skip_env "SHARED_DIRECTORY should be accessible"\
			 "on all client nodes"
		exit 0
	fi
	for n in $(seq $AGTCOUNT); do
		eval export AGTDEV$n=\$\{AGTDEV$n:-"$TMP/arc$n"\}
		agent=CLIENT$((n + 1))
		if [[ -z "${!agent}" ]]; then
			[[ $CLIENTCOUNT -eq 1 ]] && agent=CLIENT1 ||
				agent=CLIENT2
		fi
		eval export agt${n}_HOST=\$\{agt${n}_HOST:-${!agent}\}
		local var=agt${n}_HOST
		[[ ! -z "${!var}" ]] || error "agt${n}_HOST is empty!"
	done
	export SINGLEAGT=${SINGLEAGT:-agt1}
	export HSMTOOL=${HSMTOOL:-"lhsmtool_posix"}
	export HSMTOOL_PID_FILE=${HSMTOOL_PID_FILE:-"/var/run/lhsmtool_posix.pid"}
	export HSMTOOL_VERBOSE=${HSMTOOL_VERBOSE:-""}
	export HSMTOOL_UPDATE_INTERVAL=${HSMTOOL_UPDATE_INTERVAL:=""}
	export HSMTOOL_EVENT_FIFO=${HSMTOOL_EVENT_FIFO:=""}
	export HSMTOOL_TESTDIR
	export HSMTOOL_ARCHIVE_FORMAT=${HSMTOOL_ARCHIVE_FORMAT:-v2}
	if ! [[ $HSMTOOL =~ hsmtool ]]; then
		echo "HSMTOOL = '$HSMTOOL' does not contain 'hsmtool', GLWT" >&2
	fi
	HSM_ARCHIVE_NUMBER=2
	MDT_PREFIX="mdt.$FSNAME-MDT000"
	HSM_PARAM="${MDT_PREFIX}0.hsm"
	HSM_ARCHIVE_PURGE=true
	HSMTOOL_NOERROR=false
}
copytool_device() {
	local facet=$1
	local dev=AGTDEV$(facet_number $facet)
	echo -n ${!dev}
}
get_mdt_devices() {
	local mdtno
	for mdtno in $(seq 1 $MDSCOUNT); do
		local idx=$(($mdtno - 1))
		MDT[$idx]=$($LCTL get_param -n \
			mdc.$FSNAME-MDT000${idx}-mdc-*.mds_server_uuid |
			awk '{gsub(/_UUID/,""); print $1}' | head -n1)
	done
}
pkill_copytools() {
	local hosts="$1"
	local signal="$2"
	do_nodes "$hosts" \
		"pkill --pidfile=$HSMTOOL_PID_FILE --signal=$signal hsmtool"
}
copytool_continue() {
	local agents=${1:-$(facet_active_host $SINGLEAGT)}
	pkill_copytools "$agents" CONT || return 0
	echo "Copytool is continued on $agents"
}
kill_copytools() {
	local hosts=${1:-$(facet_active_host $SINGLEAGT)}
	echo "Killing existing copytools on $hosts"
	pkill_copytools "$hosts" TERM || return 0
	copytool_continue "$hosts"
}
copytool_monitor_cleanup() {
	local facet=${1:-$SINGLEAGT}
	local agent=$(facet_active_host $facet)
	if [ -n "$HSMTOOL_MONITOR_DIR" ]; then
		local cmd="kill \\\$(cat $HSMTOOL_MONITOR_DIR/monitor_pid)"
		cmd+=" 2>/dev/null || true"
		do_node $agent "$cmd"
		do_node $agent "rm -fr $HSMTOOL_MONITOR_DIR"
		export HSMTOOL_MONITOR_DIR=
	fi
	if [ -n "$HSMTOOL_MONITOR_PDSH" ]; then
		kill $HSMTOOL_MONITOR_PDSH 2>/dev/null || true
		export HSMTOOL_MONITOR_PDSH=
	fi
}
copytool_logfile()
{
	local host="$(facet_host "$1")"
	local prefix=$TESTLOG_PREFIX
	[ -n "$TESTNAME" ] && prefix+=.$TESTNAME
	printf "${prefix}.copytool${archive_id}_log.${host}.log"
}
__lhsmtool_rebind()
{
	do_facet $facet $HSMTOOL \
		"${hsmtool_options[@]}" --rebind "$@" "$mountpoint"
}
__lhsmtool_import()
{
	mkdir -p "$(dirname "$2")" ||
		error "cannot create directory '$(dirname "$2")'"
	do_facet $facet $HSMTOOL \
		"${hsmtool_options[@]}" --import "$@" "$mountpoint"
}
__lhsmtool_setup()
{
	local host="$(facet_host "$facet")"
	local cmd="$HSMTOOL ${hsmtool_options[@]} --daemon --pid-file=$HSMTOOL_PID_FILE"
	[ -n "$bandwidth" ] && cmd+=" --bandwidth $bandwidth"
	[ -n "$archive_id" ] && cmd+=" --archive $archive_id"
	cmd+=" $@ \"$mountpoint\""
	echo "Starting copytool '$facet' on '$host' with cmdline '$cmd'"
	stack_trap "pkill_copytools $host TERM || true" EXIT
	do_node "$host" "$cmd < /dev/null > \"$(copytool_logfile $facet)\" 2>&1"
}
hsm_root() {
	local facet="${1:-$SINGLEAGT}"
	printf "$(copytool_device "$facet")/${TESTSUITE}.${TESTNAME}/"
}
copytool()
{
	local action=$1
	shift
	local facet=$SINGLEAGT
	local mountpoint="${MOUNT2:-$MOUNT}"
	local fail_on_error=true
	local -a hsmtool_options=()
	local -a action_options=()
	if [[ -n "$HSMTOOL_ARCHIVE_FORMAT" ]]; then
		hsmtool_options+=("--archive-format=$HSMTOOL_ARCHIVE_FORMAT")
	fi
	if [[ -n "$HSMTOOL_VERBOSE" ]]; then
		hsmtool_options+=("$HSMTOOL_VERBOSE")
	fi
	while [ $
		case "$1" in
		-f|--facet)
			shift
			facet="$1"
			;;
		-m|--mountpoint)
			shift
			mountpoint="$1"
			;;
		-a|--archive-id)
			shift
			local archive_id="$1"
			;;
		-h|--hsm-root)
			shift
			local hsm_root="$1"
			;;
		-b|--bwlimit)
			shift
			local bandwidth="$1"
			;;
		-n|--no-fail)
			local fail_on_error=false
			;;
		*)
			action_options+=("$1")
			;;
		esac
		shift
	done
	local hsm_root="${hsm_root:-$(hsm_root "$facet")}"
	hsmtool_options+=("--hsm-root=$hsm_root")
	stack_trap "do_facet $facet rm -rf '$hsm_root'" EXIT
	do_facet $facet mkdir -p "$hsm_root" ||
		error "mkdir '$hsm_root' failed"
	case "$HSMTOOL" in
	lhsmtool_posix)
		local copytool=lhsmtool
		;;
	esac
	__${copytool}_${action} "${action_options[@]}"
	if [ $? -ne 0 ]; then
		local error_msg
		case $action in
		setup)
			local host="$(facet_host $facet)"
			error_msg="Failed to start copytool $facet on '$host'"
			;;
		import)
			local src="${action_options[0]}"
			local dest="${action_options[1]}"
			error_msg="Failed to import '$src' to '$dest'"
			;;
		rebind)
			error_msg="could not rebind file"
			;;
		esac
		$fail_on_error && error "$error_msg" || echo "$error_msg"
	fi
}
needclients() {
	local client_count=$1
	if [[ $CLIENTCOUNT -lt $client_count ]]; then
		skip "Need $client_count or more clients, have $CLIENTCOUNT"
		return 1
	fi
	return 0
}
path2fid() {
	$LFS path2fid $1 | tr -d '[]'
	return ${PIPESTATUS[0]}
}
get_hsm_flags() {
	local f=$1
	local u=$2
	local st
	if [[ $u == "user" ]]; then
		st=$($RUNAS $LFS hsm_state $f)
	else
		u=root
		st=$($LFS hsm_state $f)
	fi
	[[ $? == 0 ]] || error "$LFS hsm_state $f failed (run as $u)"
	st=$(echo $st | cut -f 2 -d" " | tr -d "()," )
	echo $st
}
check_hsm_flags() {
	local f=$1
	local fl=$2
	local st=$(get_hsm_flags $f)
	[[ $st == $fl ]] || error "hsm flags on $f are $st != $fl"
}
mdts_set_param() {
	local arg=$1
	local key=$2
	local value=$3
	local mdtno
	local rc=0
	if [[ "$value" != "" ]]; then
		value="='$value'"
	fi
	for mdtno in $(seq 1 $MDSCOUNT); do
		local idx=$(($mdtno - 1))
		local facet=mds${mdtno}
		[[ $arg = *"-P"* ]] && facet=mgs
		do_facet $facet $LCTL set_param $arg mdt.${MDT[$idx]}.$key$value ||
			rc=$?
	done
	return $rc
}
mdts_check_param() {
	local key="$1"
	local target="$2"
	local timeout="$3"
	local mdtno
	for mdtno in $(seq 1 $MDSCOUNT); do
		local idx=$(($mdtno - 1))
		wait_update_facet --verbose mds${mdtno} \
			"$LCTL get_param -n $MDT_PREFIX${idx}.$key" "$target" \
			$timeout ||
			error "$key state is not '$target' on mds${mdtno}"
	done
}
cdt_set_mount_state() {
	mdts_set_param "-P" hsm_control "$1"
	sleep 20
}
cdt_check_state() {
	mdts_check_param hsm_control "$1" 20
}
cdt_set_sanity_policy() {
	if [[ "$CDT_POLICY_HAD_CHANGED" ]]
	then
		mdts_set_param "" hsm.policy "+NRA"
		mdts_set_param "" hsm.policy "-NBR"
		CDT_POLICY_HAD_CHANGED=
	fi
}
set_hsm_param() {
	local param=$1
	local value=$2
	local opt=$3
	mdts_set_param "$opt -n" "hsm.$param" "$value"
	return $?
}
wait_request_state() {
	local fid=$1
	local request=$2
	local state=$3
	local mdtidx=${4:-0}
	local mds=mds$(($mdtidx + 1))
	local cmd="$LCTL get_param -n ${MDT_PREFIX}${mdtidx}.hsm.actions"
	cmd+=" | awk '/'$fid'.*action='$request'/ {print \\\$13}' | cut -f2 -d="
	wait_update_facet --verbose $mds "$cmd" "$state" 200 ||
		error "request on $fid is not $state on $mds"
}
rmultiop_start() {
	local client=$1
	local file=$2
	local cmds=$3
	local WAIT_MAX=${4:-60}
	local wait_time=0
	local pid_file=$TMP/multiop_bg.pid.$$
	do_node $client "MULTIOP_PID_FILE=$pid_file LUSTRE= \
			runmultiop_bg_pause $file $cmds" &
	local pid=$!
	local multiop_pid
	while [[ $wait_time -lt $WAIT_MAX ]]; do
		sleep 3
		wait_time=$((wait_time + 3))
		multiop_pid=$(do_node $client cat $pid_file)
		if [ -n "$multiop_pid" ]; then
			break
		fi
	done
	[ -n "$multiop_pid" ] ||
		error "$client : Can not get multiop_pid from $pid_file "
	eval export $(node_var_name $client)_multiop_pid=$multiop_pid
	eval export $(node_var_name $client)_do_node_pid=$pid
	local var=$(node_var_name $client)_multiop_pid
	echo client $client multiop_bg started multiop_pid=${!var}
	return $?
}
rmultiop_stop() {
	local client=$1
	local multiop_pid=$(node_var_name $client)_multiop_pid
	local do_node_pid=$(node_var_name $client)_do_node_pid
	echo "Stopping multiop_pid=${!multiop_pid} (kill ${!multiop_pid} on $client)"
	do_node $client kill -USR1 ${!multiop_pid}
	wait ${!do_node_pid}
}
sleep_maxage() {
	local delay=$(do_facet mds1 lctl get_param -n lod.*.qos_maxage |
		      awk '{ print $1 + 5; exit; }')
	sleep $delay
}
sleep_maxage_lmv() {
	local delay=$(lctl get_param -n lmv.*.qos_maxage |
		      awk '{ print $1 + 5; exit; }')
	sleep $delay
}
check_component_count() {
	local comp_cnt=$($LFS getstripe --component-count $1)
	[ $comp_cnt -eq $2 ] || error "$1, component count $comp_cnt != $2"
}
verify_no_init_extension() {
	local flg_opts="--component-flags init,extension"
	local found=$($LFS find $flg_opts $1 | wc -l)
	[ $found -eq 0 ] || error "$1 has component with initialized extension"
}
verify_comp_at_zero() {
	flg_opts="--component-flags init"
	found=$($LFS find --component-start 0M $flg_opts $1 | wc -l)
	[ $found -eq 1 ] ||
		error "No component starting at zero(!)"
}
SEL_VER="2.12.55"
sel_layout_sanity() {
	local file=$1
	local comp_cnt=$2
	verify_no_init_extension $file
	verify_comp_at_zero $file
	check_component_count $file $comp_cnt
}
statx_supported() {
	$STATX --quiet --version
	return $?
}
is_rmentry_supported() {
	$LFS rm_entry $DIR/dir/not/exists > /dev/null
	(( $? == 2 ))
}
function createmany() {
	local count=${!
	local rc
	if (( count > 100 )); then
		debugsave
		do_nodes $(comma_list $(all_nodes)) $LCTL set_param -n debug=ha
	fi
	$LUSTRE/tests/createmany $*
	rc=$?
	debugrestore > /dev/null
	return $rc
}
function unlinkmany() {
	local count=${!
	local rc
	if (( count > 100 )); then
		debugsave
		do_nodes $(comma_list $(all_nodes)) $LCTL set_param -n debug=0
	fi
	$LUSTRE/tests/unlinkmany $*
	rc=$?
	debugrestore > /dev/null
	return $rc
}
function check_fallocate_supported()
{
	local facet=${1:-ost1}
	local supported="FALLOCATE_SUPPORTED_$facet"
	local fstype="${facet}_FSTYPE"
	if [[ -n "${!supported}" ]]; then
		echo "${!supported}"
		return 0
	fi
	if [[ -z "${!fstype}" ]]; then
		eval export $fstype=$(facet_fstype $facet)
	fi
	if [[ "${!fstype}" != "ldiskfs" ]]; then
		echo "fallocate on ${!fstype} doesn't consume space" 1>&2
		return 1
	fi
	local fa_mode="osd-ldiskfs.$(facet_svc $facet).fallocate_zero_blocks"
	local mode=$(do_facet $facet $LCTL get_param -n $fa_mode 2>/dev/null |
		     head -n 1)
	! [[ "$facet" =~ "mds" ]] ||
		(( MDS1_VERSION >= $(version_code v2_14_53-10-g163870abfb) )) ||
			mode=""
	if [[ -z "$mode" ]]; then
		echo "fallocate not supported on $facet" 1>&2
		return 1
	fi
	eval export $supported="$mode"
	echo ${!supported}
	return 0
}
function check_fallocate_or_skip()
{
	local facet=$1
	check_fallocate_supported $1 || skip "fallocate not supported"
}
function check_set_fallocate()
{
	local new_mode="$1"
	local fa_mode="osd-ldiskfs.*.fallocate_zero_blocks"
	local old_mode="$(check_fallocate_supported)"
	[[ -n "$old_mode" ]] || { echo "fallocate not supported"; return 1; }
	[[ -z "$new_mode" && "$old_mode" != "-1" ]] &&
		{ echo "keep default fallocate mode: $old_mode"; return 0; }
	[[ "$new_mode" && "$old_mode" == "$new_mode" ]] &&
		{ echo "keep current fallocate mode: $old_mode"; return 0; }
	local osts=$(osts_nodes)
	stack_trap "do_nodes $osts $LCTL set_param $fa_mode=$old_mode"
	do_nodes $osts $LCTL set_param $fa_mode=${new_mode:-0} ||
		error "set $fa_mode=$new_mode"
}
function check_set_fallocate_or_skip()
{
	check_set_fallocate || skip "need >= 2.13.57 and ldiskfs for fallocate"
}
function disable_opencache()
{
	local state=$($LCTL get_param -n "llite.*.opencache_threshold_count" |
			head -1)
	test -z "${saved_OPENCACHE_value}" &&
					export saved_OPENCACHE_value="$state"
	[[ "$state" = "off" ]] && return
	$LCTL set_param -n "llite.*.opencache_threshold_count"=off
}
function set_opencache()
{
	local newvalue="$1"
	local state=$($LCTL get_param -n "llite.*.opencache_threshold_count")
	[[ -n "$newvalue" ]] || return
	[[ -n "${saved_OPENCACHE_value}" ]] ||
					export saved_OPENCACHE_value="$state"
	$LCTL set_param -n "llite.*.opencache_threshold_count"=$newvalue
}
function restore_opencache()
{
	[[ -z "${saved_OPENCACHE_value}" ]] ||
		$LCTL set_param -n "llite.*.opencache_threshold_count"=${saved_OPENCACHE_value}
}
mkdir_on_mdt() {
	local mdt
	local OPTIND=1
	while getopts "i:" opt $*; do
		case $opt in
			i) mdt=$OPTARG;;
		esac
	done
	shift $((OPTIND - 1))
	$LFS mkdir -i $mdt -c 1 $*
}
mkdir_on_mdt0() {
	mkdir_on_mdt -i0 $*
}
wait_nm_sync() {
	local nodemap_name=$1
	local key=$2
	local value=$3
	local opt=$4
	local pipe=${5:-""}
	local proc_param
	local is_active=$(do_facet mgs $LCTL get_param -n nodemap.active)
	local max_retries=20
	local is_sync
	local out1=""
	local out2
	local mgs_ip=$(host_nids_address $mgs_HOST $NETTYPE | cut -d' ' -f1)
	local i
	if [[ "$nodemap_name" == "active" ]]; then
		proc_param="active"
	elif [[ -z "$key" ]]; then
		proc_param=${nodemap_name}
	else
		proc_param="${nodemap_name}.${key}"
	fi
	if [[ "$opt" == "inactive" ]]; then
		is_active=1
		opt=""
	fi
	(( is_active == 0 )) && [[ "$proc_param" != "active" ]] && return 0
	if [[ -z "$value" ]]; then
		do_node_cmd="do_facet mgs $LCTL get_param $opt \
			       nodemap.$proc_param 2>/dev/null"
		if [[ -n "$pipe" ]]; then
			do_node_cmd="$do_node_cmd | $pipe"
		fi
		out1=$(eval $do_node_cmd)
		echo "On MGS ${mgs_ip}, ${proc_param} = $out1"
	else
		out1=$value;
	fi
	if [[ $(facet_active_host mgs) == $(facet_active_host mds) &&
	      $(facet_active_host mgs) == $(facet_active_host ost1) ]]; then
		echo "waiting 10 secs for sync"
		sleep 10
		return 0
	fi
	local nodes=$(all_server_nodes)
	for i in {1..10}; do
		for node in ${nodes//,/ }; do
			local node_ip=$(host_nids_address $node $NETTYPE |
					cut -d' ' -f1)
			is_sync=true
			[[ -n "$value" || $node_ip != $mgs_ip ]] ||
				continue
			do_node_cmd="do_node $node $LCTL get_param $opt \
			       nodemap.$proc_param 2>/dev/null"
			if [[ -n "$pipe" ]]; then
				do_node_cmd="$do_node_cmd | $pipe"
			fi
			out2=$(eval $do_node_cmd)
			echo "On $node ${node_ip}, ${proc_param} = $out2"
			[[ "$out1" != "$out2" ]] && is_sync=false && break
		done
		$is_sync && break
		sleep 1
	done
	if ! $is_sync; then
		echo MGS
		echo $out1
		echo OTHER - IP: $node_ip
		echo $out2
		error "mgs and $nodemap_name ${key} mismatch, $i attempts"
	fi
	echo "waited $((i - 1)) seconds for sync"
}
consume_precreations() {
	local dir=$1
	local mfacet=$2
	local OSTIDX=$3
	local extra=${4:-2}
	local OST=$(ostname_from_index $OSTIDX $dir)
	mkdir_on_mdt -i $(facet_index $mfacet) $dir/${OST}
	$LFS setstripe -i $OSTIDX -c 1 ${dir}/${OST}
	local mdtosc_proc=$(get_mdtosc_proc_path $mfacet $OST)
	local last_id=$(do_facet $mfacet $LCTL get_param -n \
			osp.$mdtosc_proc.prealloc_last_id)
	local next_id=$(do_facet $mfacet $LCTL get_param -n \
			osp.$mdtosc_proc.prealloc_next_id)
	echo "Creating to objid $last_id on ost $OST..."
	createmany -o $dir/${OST}/f $next_id $((last_id - next_id + extra))
}
__exhaust_precreations() {
	local OSTIDX=$1
	local FAILLOC=$2
	local FAILIDX=${3:-$OSTIDX}
	local ofacet=ost$((OSTIDX + 1))
	mkdir_on_mdt0 $DIR/$tdir
	local mdtidx=$($LFS getstripe -m $DIR/$tdir)
	local mfacet=mds$((mdtidx + 1))
	echo OSTIDX=$OSTIDX MDTIDX=$mdtidx
	local mdtosc_proc=$(get_mdtosc_proc_path $mfacet)
	do_facet $mfacet $LCTL get_param osp.$mdtosc_proc.prealloc*
	do_facet $ofacet $LCTL set_param fail_val=$FAILIDX fail_loc=0x215
	consume_precreations $DIR/$tdir $mfacet $OSTIDX
	do_facet $mfacet $LCTL get_param osp.$mdtosc_proc.prealloc*
	do_facet $ofacet $LCTL set_param fail_loc=$FAILLOC
}
exhaust_precreations() {
	__exhaust_precreations $1 $2 $3
	sleep_maxage
}
exhaust_all_precreations() {
	local i
	for (( i=0; i < OSTCOUNT; i++ )) ; do
		__exhaust_precreations $i $1 -1
	done
	sleep_maxage
}
force_new_seq_ost() {
	local dir=$1
	local mfacet=$2
	local OSTIDX=$3
	local OST=$(ostname_from_index $OSTIDX)
	local mdtosc_proc=$(get_mdtosc_proc_path $mfacet $OST)
	do_facet $mfacet $LCTL set_param \
		osp.$mdtosc_proc.prealloc_force_new_seq=1
	consume_precreations $dir $mfacet $OSTIDX
	do_facet $mfacet $LCTL set_param \
		osp.$mdtosc_proc.prealloc_force_new_seq=0
}
force_new_seq() {
	local mfacet=$1
	local MDTIDX=$(facet_index $mfacet)
	local MDT=$(mdtname_from_index $MDTIDX $DIR)
	local i
	mkdir_on_mdt -i $MDTIDX $DIR/${MDT}
	for (( i=0; i < OSTCOUNT; i++ )) ; do
		force_new_seq_ost $DIR/${MDT} $mfacet $i &
	done
	wait
	rm -rf $DIR/${MDT}
}
force_new_seq_all() {
	local i
	for (( i=0; i < MDSCOUNT; i++ )) ; do
		force_new_seq mds$((i + 1)) &
	done
	wait
	sleep_maxage
}
ost_set_temp_seq_width_all() {
	local osts=$(osts_nodes)
	local width=$(do_facet ost1 $LCTL get_param -n seq.*OST0000-super.width)
	(( $width != $1 )) || return 0
	do_nodes $osts $LCTL set_param seq.*OST*-super.width=$1
	stack_trap "do_nodes $osts $LCTL set_param seq.*OST*-super.width=$width"
}
verify_yaml_available() {
	python3 -c "import yaml; yaml.safe_load('''a: b''')"
}
verify_yaml() {
	python3 -c "import sys, yaml; obj = yaml.safe_load(sys.stdin)"
}
verify_compare_yaml() {
	python3 -c "import sys, yaml; f=open(\"$1\", \"r\"); obj1 = yaml.safe_load(f); f=open(\"$2\", \"r\"); obj2 = yaml.safe_load(f); sys.exit(obj1 != obj2)"
}
zfs_or_rotational() {
	local ost_idx=0
	local ost_name=$(ostname_from_index $ost_idx $MOUNT)
	local param="get_param -n osd-*.${ost_name}.nonrotational"
	local nonrotat=$(do_facet ost1 $LCTL $param)
	if [[ -z "$nonrotat" ]]; then
		set -x
		local ost_name=$(ostname_from_index $ost_idx)
		set +x
		error "$LCTL $input_str"
	fi
	if [[ "$ost1_FSTYPE" == "zfs" ]] || (( "$nonrotat" == 0 )); then
		return 0
	else
		return 1
	fi
}
ost_fid2_objpath() {
	local facet=$1
	local fid=$2
	fid=$(echo $fid | tr -d '[]')
	seq=$(echo $fid | awk -F ':' '{ print $1 }' | sed -e "s/^0x//g")
	oidhex=$(echo $fid | awk -F ':' '{ print $2 }')
	if [ $seq == 0 ] || [ $(facet_fstype $facet) == zfs ]; then
		oid=$((16
	else
		oid=${oidhex
	fi
	echo "O/$seq/d$((oidhex%32))/$oid"
}
check_seq_oid()
{
	log "check file $1"
	lmm_count=$($LFS getstripe -c $1)
	lmm_seq=$($LFS getstripe -v $1 | awk '/lmm_seq/ { print $2 }')
	lmm_oid=$($LFS getstripe -v $1 | awk '/lmm_object_id/ { print $2 }')
	local old_ifs="$IFS"
	IFS=$'[:]'
	fid=($($LFS path2fid $1))
	IFS="$old_ifs"
	log "FID seq ${fid[1]}, oid ${fid[2]} ver ${fid[3]}"
	log "LOV seq $lmm_seq, oid $lmm_oid, count: $lmm_count"
	[ $lmm_seq = ${fid[1]} ] || error "SEQ mismatch"
	[ $lmm_oid = ${fid[2]} ] || error "OID mismatch"
	local have_obdidx=false
	local stripe_nr=0
	$LFS getstripe $1 | while read obdidx oid hex seq; do
		[ -z "$obdidx" ] && break
		[ "$obdidx" = "obdidx" ] && have_obdidx=true && continue
		$have_obdidx || continue
		local ost=$((obdidx + 1))
		local dev=$(ostdevname $ost)
		log "want: stripe:$stripe_nr ost:$obdidx oid:$oid/$hex seq:$seq"
		local obj_file=$(ost_fid2_objpath ost$ost "$seq:$hex:0")
		local ff=""
		if [ $(facet_fstype ost$ost) == ldiskfs ]; then
			ff=$(do_facet ost$ost "$DEBUGFS -c -R 'stat $obj_file' \
				$dev 2>/dev/null" | grep "parent=")
		fi
		if [ -z "$ff" ]; then
			stop ost$ost
			mount_fstype ost$ost
			ff=$(do_facet ost$ost $LL_DECODE_FILTER_FID \
				$(facet_mntpt ost$ost)/$obj_file)
			unmount_fstype ost$ost
			start ost$ost $dev $OST_MOUNT_OPTS
			clients_up
		fi
		[ -z "$ff" ] && error "$obj_file: no filter_fid info"
		echo "$ff" | sed -e 's
		local ff_parent=$(sed -e 's/.*parent=.//' <<<$ff)
		local ff_pseq=$(cut -d: -f1 <<<$ff_parent)
		local ff_poid=$(cut -d: -f2 <<<$ff_parent)
		local ff_pstripe
		if grep -q 'stripe=' <<<$ff; then
			ff_pstripe=$(sed -e 's/.*stripe=//' -e 's/ .*//' <<<$ff)
		else
			ff_pstripe=$(cut -d: -f3 <<<$ff_parent | sed -e 's/]//')
		fi
		[ $ff_pseq = $lmm_seq ] ||
			error "FF parent SEQ $ff_pseq != $lmm_seq"
		[ $ff_poid = $lmm_oid ] ||
			error "FF parent OID $ff_poid != $lmm_oid"
		(($ff_pstripe == $stripe_nr)) ||
			error "FF stripe $ff_pstripe != $stripe_nr"
		stripe_nr=$((stripe_nr + 1))
		[ $CLIENT_VERSION -lt $(version_code 2.9.55) ] &&
			continue
		if grep -q 'stripe_count=' <<<$ff; then
			local ff_scnt=$(sed -e 's/.*stripe_count=//' \
					    -e 's/ .*//' <<<$ff)
			[ $lmm_count = $ff_scnt ] ||
				error "FF stripe count $lmm_count != $ff_scnt"
		fi
	done
}
get_test_project() {
	local projid_file="$LIBLUSTREAPI_PROJID_FILE"
	local tstid=$(id -u $TSTUSR)
	grep -qw $TSTUSR "$projid_file" ||
		echo "${TSTUSR}:$tstid" >> "$projid_file" ||
		error "cannot add user $TSTUSR:$tstid to $projid_file"
	echo "$TSTUSR" "$tstid"
}
