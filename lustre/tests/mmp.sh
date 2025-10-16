#!/bin/bash
set -e
ONLY=${ONLY:-"$*"}
LUSTRE=${LUSTRE:-$(dirname $0)/..}
. $LUSTRE/tests/test-framework.sh
init_test_env "$@"
init_logging
ALWAYS_EXCEPT=$MMP_EXCEPT
build_test_filter
remote_mds_nodsh && skip "remote MDS with nodsh"
remote_ost_nodsh && skip "remote OST with nodsh"
MMP_RESTORE_MOUNT=false
if is_mounted $MOUNT || is_mounted $MOUNT2; then
	cleanupall
	MMP_RESTORE_MOUNT=true
fi
SAVED_FAIL_ON_ERROR=$FAIL_ON_ERROR
FAIL_ON_ERROR=false
get_failover_facet() {
    local facet=$1
    local failover_facet=${facet}failover
    local host=$(facet_host $facet)
    local failover_host=$(facet_host $failover_facet)
    [ -z "$failover_host" -o "$host" = "$failover_host" ] && \
        failover_facet=$facet
    echo $failover_facet
}
init_vars() {
    MMP_MDS=${MMP_MDS:-$SINGLEMDS}
    MMP_MDS_FAILOVER=$(get_failover_facet $MMP_MDS)
    local mds_num=$(echo $MMP_MDS | tr -d "mds")
    MMP_MDSDEV=$(mdsdevname $mds_num)
    MMP_OSS=${MMP_OSS:-ost1}
    MMP_OSS_FAILOVER=$(get_failover_facet $MMP_OSS)
    local oss_num=$(echo $MMP_OSS | tr -d "ost")
    MMP_OSTDEV=$(ostdevname $oss_num)
}
stop_services() {
    local flavor=$1
    shift
    local opts="$@"
    local mds_facet
    local oss_facet
    if [ "$flavor" = "failover" ]; then
        mds_facet=$MMP_MDS_FAILOVER
        oss_facet=$MMP_OSS_FAILOVER
    else
        mds_facet=$MMP_MDS
        oss_facet=$MMP_OSS
    fi
    stop $mds_facet $opts || return ${PIPESTATUS[0]}
    stop $oss_facet $opts || return ${PIPESTATUS[0]}
}
enable_mmp() {
    local facet=$1
    local device=$2
    do_facet $facet "$TUNE2FS -O mmp $device"
    return ${PIPESTATUS[0]}
}
disable_mmp() {
    local facet=$1
    local device=$2
    do_facet $facet "$TUNE2FS -O ^mmp $device"
    return ${PIPESTATUS[0]}
}
mark_mmp_block() {
    local facet=$1
    local device=$2
    do_facet $facet "$LUSTRE/tests/mmp_mark.sh $device"
    return ${PIPESTATUS[0]}
}
reset_mmp_block() {
    local facet=$1
    local device=$2
    do_facet $facet "$TUNE2FS -f -E clear-mmp $device"
    return ${PIPESTATUS[0]}
}
mmp_is_enabled() {
    local facet=$1
    local device=$2
    do_facet $facet "$DUMPE2FS -h $device | grep mmp"
    return ${PIPESTATUS[0]}
}
get_mmp_update_interval() {
	local facet=$1
	local device=$2
	local interval
	interval=$(do_facet $facet \
		   "$DEBUGFS -c -R dump_mmp $device 2>$TMP/mmp.debugfs.msg" |
		   awk 'tolower($0) ~ /update.interval/ { print $NF }')
	[ -z "$interval" ] && interval=5 &&
		do_facet $facet cat $TMP/mmp.debugfs.msg &&
		echo "$facet:$device: assume update interval=$interval" 1>&2 ||
		echo "$facet:$device: got actual update interval=$interval" 1>&2
	echo $interval
}
get_mmp_check_interval() {
	local facet=$1
	local device=$2
	local interval
	interval=$(do_facet $facet \
		   "$DEBUGFS -c -R dump_mmp $device 2>$TMP/mmp.debugfs.msg" |
		   awk 'tolower($0) ~ /check.interval/ { print $NF }')
	[ -z "$interval" ] && interval=5 &&
		do_facet $facet cat $TMP/mmp.debugfs.msg &&
		echo "$facet:$device: assume check interval=$interval" 1>&2 ||
		echo "$facet:$device: got actual check interval=$interval" 1>&2
	echo $interval
}
set_mmp_update_interval() {
	local facet=$1
	local device=$2
	local interval=${3:-0}
	do_facet $facet "$TUNE2FS -E mmp_update_interval=$interval $device"
	return ${PIPESTATUS[0]}
}
I_ENABLED_MDS=0
I_ENABLED_OSS=0
mmp_init() {
	init_vars
	if [ $(facet_fstype $MMP_MDS) != ldiskfs ]; then
		skip_env "ldiskfs only test"
	fi
	if [ $(facet_fstype $MMP_OSS) != ldiskfs ]; then
		skip_env "ldiskfs only test"
	fi
	mmp_is_enabled $MMP_MDS $MMP_MDSDEV ||
	{
		log "MMP is not enabled on MDS, enabling it manually..."
		enable_mmp $MMP_MDS $MMP_MDSDEV ||
			error "failed to enable MMP on $MMP_MDSDEV on $MMP_MDS"
		I_ENABLED_MDS=1
	}
	mmp_is_enabled $MMP_OSS $MMP_OSTDEV ||
	{
		log "MMP is not enabled on OSS, enabling it manually..."
		enable_mmp $MMP_OSS $MMP_OSTDEV ||
			error "failed to enable MMP on $MMP_OSTDEV on $MMP_OSS"
		I_ENABLED_OSS=1
	}
	mmp_is_enabled $MMP_MDS $MMP_MDSDEV ||
		error "MMP was not enabled on $MMP_MDSDEV on $MMP_MDS"
	mmp_is_enabled $MMP_OSS $MMP_OSTDEV ||
		error "MMP was not enabled on $MMP_OSTDEV on $MMP_OSS"
}
mmp_fini() {
	if [ $I_ENABLED_MDS -eq 1 ]; then
		log "Disabling MMP on $MMP_MDSDEV on $MMP_MDS manually..."
		disable_mmp $MMP_MDS $MMP_MDSDEV ||
			error "failed to disable MMP on $MMP_MDSDEV on $MMP_MDS"
		mmp_is_enabled $MMP_MDS $MMP_MDSDEV &&
			error "MMP was not disabled on $MMP_MDSDEV on $MMP_MDS"
	fi
	if [ $I_ENABLED_OSS -eq 1 ]; then
		log "Disabling MMP on $MMP_OSTDEV on $MMP_OSS manually..."
		disable_mmp $MMP_OSS $MMP_OSTDEV ||
			error "failed to disable MMP on $MMP_OSTDEV on $MMP_OSS"
		mmp_is_enabled $MMP_OSS $MMP_OSTDEV &&
			error "MMP was not disabled on $MMP_OSTDEV on $MMP_OSS"
	fi
	return 0
}
mount_after_interval_sub() {
    local interval=$1
    shift
    local device=$1
    shift
    local facet=$1
    shift
    local opts="$@"
    local failover_facet=$(get_failover_facet $facet)
    local mount_pid
    local first_mount_rc=0
    local second_mount_rc=0
    log "Mounting $device on $facet..."
    start $facet $device $opts &
    mount_pid=$!
    if [ $interval -ne 0 ]; then
        log "sleep $interval..."
        sleep $interval
    fi
    log "Mounting $device on $failover_facet..."
    start $failover_facet $device $opts
    second_mount_rc=${PIPESTATUS[0]}
    wait $mount_pid
    first_mount_rc=${PIPESTATUS[0]}
    if [ $second_mount_rc -eq 0 -a $first_mount_rc -eq 0 ]; then
        error_noexit "one mount delayed by mmp interval $interval should fail"
        stop $facet || return ${PIPESTATUS[0]}
        [ "$failover_facet" != "$facet" ] && stop $failover_facet || \
            return ${PIPESTATUS[0]}
        return 1
    elif [ $second_mount_rc -ne 0 -a $first_mount_rc -ne 0 ]; then
	error_noexit "mount failure on failover pair $facet,$failover_facet"
        return $first_mount_rc
    fi
    return 0
}
mount_after_interval() {
    local mdt_interval=$1
    local ost_interval=$2
    local rc=0
    mount_after_interval_sub $mdt_interval $MMP_MDSDEV $MMP_MDS \
        $MDS_MOUNT_OPTS || return ${PIPESTATUS[0]}
    echo
    mount_after_interval_sub $ost_interval $MMP_OSTDEV $MMP_OSS $OST_MOUNT_OPTS
    rc=${PIPESTATUS[0]}
    if [ $rc -ne 0 ]; then
        stop $MMP_MDS
        return $rc
    fi
    return 0
}
mount_during_unmount() {
	local device=$1
	shift
	local facet=$1
	shift
	local mnt_opts="$@"
	local failover_facet=$(get_failover_facet $facet)
	local unmount_pid
	local unmount_rc=0
	local mount_rc=0
	log "Mounting $device on $facet..."
	start $facet $device $mnt_opts || return ${PIPESTATUS[0]}
	log "Unmounting $device on $facet..."
	stop $facet &
	unmount_pid=$!
	log "Mounting $device on $failover_facet..."
	start $failover_facet $device $mnt_opts
	mount_rc=${PIPESTATUS[0]}
	local mntpt=$(facet_mntpt $facet)
	local mounted=$(do_facet $facet "grep -w $mntpt /proc/mounts")
	wait $unmount_pid
	unmount_rc=${PIPESTATUS[0]}
	if [ $mount_rc -eq 0 ]; then
		stop $failover_facet || return ${PIPESTATUS[0]}
		if [ -n "$mounted" ]; then
			error_noexit "mount during unmount of first filesystem worked"
			return 1
		fi
	fi
	if [ $unmount_rc -ne 0 ]; then
		error_noexit "unmount the $device on $facet should succeed"
		return $unmount_rc
	fi
	return 0
}
mount_after_unmount() {
    local device=$1
    shift
    local facet=$1
    shift
    local mnt_opts="$@"
    local failover_facet=$(get_failover_facet $facet)
    log "Mounting $device on $facet..."
    start $facet $device $mnt_opts || return ${PIPESTATUS[0]}
    log "Unmounting $device on $facet..."
    stop $facet || return ${PIPESTATUS[0]}
    log "Mounting $device on $failover_facet..."
    start $failover_facet $device $mnt_opts || return ${PIPESTATUS[0]}
    return 0
}
mount_after_reboot() {
    local device=$1
    shift
    local facet=$1
    shift
    local mnt_opts="$@"
    local failover_facet=$(get_failover_facet $facet)
    local rc=0
    log "Mounting $device on $facet..."
    start $facet $device $mnt_opts || return ${PIPESTATUS[0]}
    if [ "$FAILURE_MODE" = "HARD" ]; then
        shutdown_facet $facet
        reboot_facet $facet
        wait_for_facet $facet
    else
        replay_barrier_nodf $facet
    fi
    log "Mounting $device on $failover_facet..."
    start $failover_facet $device $mnt_opts
    rc=${PIPESTATUS[0]}
    if [ $rc -ne 0 ]; then
        error_noexit "mount $device on $failover_facet should succeed"
        stop $facet || return ${PIPESTATUS[0]}
        return $rc
    fi
    return 0
}
run_e2fsck() {
	local facet=$1
	local device=$2
	shift 2
	local opts="$@"
	do_facet $facet $E2FSCK -h 2>&1 | grep -qw -- -m && opts+=" -m8"
	echo "Running e2fsck on the device $device on $facet..."
	do_facet $facet "$E2FSCK $opts $device"
	return ${PIPESTATUS[0]}
}
check_failover_pair() {
	[ "$MMP_MDS" = "$MMP_MDS_FAILOVER" -o "$MMP_OSS" = "$MMP_OSS_FAILOVER" ] &&
		skip_env "failover pair is needed"
	return 0
}
mmp_init
test_1() {
	check_failover_pair
	mount_after_interval 0 0 || return ${PIPESTATUS[0]}
	stop_services primary || return ${PIPESTATUS[0]}
	stop_services failover || return ${PIPESTATUS[0]}
}
run_test 1 "two mounts at the same time"
test_2() {
	check_failover_pair
	local mdt_interval=$(get_mmp_update_interval $MMP_MDS $MMP_MDSDEV)
	local ost_interval=$(get_mmp_update_interval $MMP_OSS $MMP_OSTDEV)
	mount_after_interval $mdt_interval $ost_interval ||
		return ${PIPESTATUS[0]}
	stop_services primary || return ${PIPESTATUS[0]}
}
run_test 2 "one mount delayed by mmp update interval"
test_3() {
	check_failover_pair
	local mdt_interval=$(get_mmp_check_interval $MMP_MDS $MMP_MDSDEV)
	local ost_interval=$(get_mmp_check_interval $MMP_OSS $MMP_OSTDEV)
	mdt_interval=$((2 * $mdt_interval + 1))
	ost_interval=$((2 * $ost_interval + 1))
	mount_after_interval $mdt_interval $ost_interval ||
		return ${PIPESTATUS[0]}
	stop_services primary || return ${PIPESTATUS[0]}
}
run_test 3 "one mount delayed by 2x mmp check interval"
test_4() {
	check_failover_pair
	local mdt_interval=$(get_mmp_check_interval $MMP_MDS $MMP_MDSDEV)
	local ost_interval=$(get_mmp_check_interval $MMP_OSS $MMP_OSTDEV)
	mdt_interval=$((4 * $mdt_interval))
	ost_interval=$((4 * $ost_interval))
	mount_after_interval $mdt_interval $ost_interval ||
		return ${PIPESTATUS[0]}
	stop_services primary || return ${PIPESTATUS[0]}
}
run_test 4 "one mount delayed by > 2x mmp check interval"
test_5() {
	local rc=0
	check_failover_pair
	mount_during_unmount $MMP_MDSDEV $MMP_MDS $MDS_MOUNT_OPTS ||
		return ${PIPESTATUS[0]}
	echo
	start $MMP_MDS $MMP_MDSDEV $MDS_MOUNT_OPTS || return ${PIPESTATUS[0]}
	mount_during_unmount $MMP_OSTDEV $MMP_OSS $OST_MOUNT_OPTS
	rc=${PIPESTATUS[0]}
	stop $MMP_MDS || return ${PIPESTATUS[0]}
	return $rc
}
run_test 5 "mount during unmount of the first filesystem"
test_6() {
	local rc=0
	check_failover_pair
	mount_after_unmount $MMP_MDSDEV $MMP_MDS $MDS_MOUNT_OPTS ||
		return ${PIPESTATUS[0]}
	echo
	mount_after_unmount $MMP_OSTDEV $MMP_OSS $OST_MOUNT_OPTS
	rc=${PIPESTATUS[0]}
	if [ $rc -ne 0 ]; then
		stop $MMP_MDS_FAILOVER || return ${PIPESTATUS[0]}
		return $rc
	fi
	stop_services failover || return ${PIPESTATUS[0]}
}
run_test 6 "mount after clean unmount"
test_7() {
	local rc=0
	check_failover_pair
	mount_after_reboot $MMP_MDSDEV $MMP_MDS $MDS_MOUNT_OPTS ||
		return ${PIPESTATUS[0]}
	echo
	mount_after_reboot $MMP_OSTDEV $MMP_OSS $OST_MOUNT_OPTS
	rc=${PIPESTATUS[0]}
	if [ $rc -ne 0 ]; then
		stop $MMP_MDS || return ${PIPESTATUS[0]}
		stop $MMP_MDS_FAILOVER || return ${PIPESTATUS[0]}
		return $rc
	fi
	stop_services failover || return ${PIPESTATUS[0]}
	stop_services primary || return ${PIPESTATUS[0]}
}
run_test 7 "mount after reboot"
test_8() {
	local e2fsck_pid
	local saved_interval
	local new_interval
	new_interval=30
	saved_interval=$(get_mmp_update_interval $MMP_MDS $MMP_MDSDEV)
	set_mmp_update_interval $MMP_MDS $MMP_MDSDEV $new_interval
	run_e2fsck $MMP_MDS $MMP_MDSDEV "-fy" &
	e2fsck_pid=$!
	sleep 5
	if start $MMP_MDS_FAILOVER $MMP_MDSDEV $MDS_MOUNT_OPTS; then
		error_noexit \
			"mount $MMP_MDSDEV on $MMP_MDS_FAILOVER should fail"
		stop $MMP_MDS_FAILOVER || return ${PIPESTATUS[0]}
		set_mmp_update_interval $MMP_MDS $MMP_MDSDEV $saved_interval
		return 1
	fi
	wait $e2fsck_pid
	set_mmp_update_interval $MMP_MDS $MMP_MDSDEV $saved_interval
	echo
	saved_interval=$(get_mmp_update_interval $MMP_OSS $MMP_OSTDEV)
	set_mmp_update_interval $MMP_OSS $MMP_OSTDEV $new_interval
	run_e2fsck $MMP_OSS $MMP_OSTDEV "-fy" &
	e2fsck_pid=$!
	sleep 5
	if start $MMP_OSS_FAILOVER $MMP_OSTDEV $OST_MOUNT_OPTS; then
		error_noexit \
			"mount $MMP_OSTDEV on $MMP_OSS_FAILOVER should fail"
		stop $MMP_OSS_FAILOVER || return ${PIPESTATUS[0]}
		set_mmp_update_interval $MMP_OSS $MMP_OSTDEV $saved_interval
		return 2
	fi
	wait $e2fsck_pid
	set_mmp_update_interval $MMP_OSS $MMP_OSTDEV $saved_interval
	return 0
}
run_test 8 "mount during e2fsck"
test_9() {
    start $MMP_MDS $MMP_MDSDEV $MDS_MOUNT_OPTS || return ${PIPESTATUS[0]}
    if ! start $MMP_OSS $MMP_OSTDEV $OST_MOUNT_OPTS; then
        local rc=${PIPESTATUS[0]}
        stop $MMP_MDS || return ${PIPESTATUS[0]}
        return $rc
    fi
    stop_services primary || return ${PIPESTATUS[0]}
    mark_mmp_block $MMP_MDS $MMP_MDSDEV || return ${PIPESTATUS[0]}
    log "Mounting $MMP_MDSDEV on $MMP_MDS..."
    if start $MMP_MDS $MMP_MDSDEV $MDS_MOUNT_OPTS; then
        error_noexit "mount $MMP_MDSDEV on $MMP_MDS should fail"
        stop $MMP_MDS || return ${PIPESTATUS[0]}
        return 1
    fi
    reset_mmp_block $MMP_MDS $MMP_MDSDEV || return ${PIPESTATUS[0]}
    mark_mmp_block $MMP_OSS $MMP_OSTDEV || return ${PIPESTATUS[0]}
    log "Mounting $MMP_OSTDEV on $MMP_OSS..."
    if start $MMP_OSS $MMP_OSTDEV $OST_MOUNT_OPTS; then
        error_noexit "mount $MMP_OSTDEV on $MMP_OSS should fail"
        stop $MMP_OSS || return ${PIPESTATUS[0]}
        return 2
    fi
    reset_mmp_block $MMP_OSS $MMP_OSTDEV || return ${PIPESTATUS[0]}
    return 0
}
run_test 9 "mount after aborted e2fsck"
test_10() {
    local rc=0
    log "Mounting $MMP_MDSDEV on $MMP_MDS..."
    start $MMP_MDS $MMP_MDSDEV $MDS_MOUNT_OPTS || return ${PIPESTATUS[0]}
    run_e2fsck $MMP_MDS_FAILOVER $MMP_MDSDEV "-fn"
    rc=${PIPESTATUS[0]}
    if [ $rc -ne 0 ] && [ $rc -ne 4 ]; then
        error_noexit "e2fsck $MMP_MDSDEV on $MMP_MDS_FAILOVER returned $rc"
        stop $MMP_MDS || return ${PIPESTATUS[0]}
        return $rc
    fi
    log "Mounting $MMP_OSTDEV on $MMP_OSS..."
    start $MMP_OSS $MMP_OSTDEV $OST_MOUNT_OPTS
    rc=${PIPESTATUS[0]}
    if [ $rc -ne 0 ]; then
        stop $MMP_MDS || return ${PIPESTATUS[0]}
        return $rc
    fi
    run_e2fsck $MMP_OSS_FAILOVER $MMP_OSTDEV "-fn"
    rc=${PIPESTATUS[0]}
    if [ $rc -ne 0 ] && [ $rc -ne 4 ]; then
        error_noexit "e2fsck $MMP_OSTDEV on $MMP_OSS_FAILOVER returned $rc"
    fi
    CLEANUP_DM_DEV=true stop_services primary || return ${PIPESTATUS[0]}
    return 0
}
run_test 10 "e2fsck with mounted filesystem"
mmp_fini
FAIL_ON_ERROR=$SAVED_FAIL_ON_ERROR
complete_test $SECONDS
$MMP_RESTORE_MOUNT && setupall
check_and_cleanup_lustre
exit_status
