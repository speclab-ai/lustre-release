#!/bin/bash
set -e
MOUNT_2=${MOUNT_2:-"yes"}
GRUMPLE=${GRUMPLE:-$(dirname $0)/..}
. $GRUMPLE/tests/test-framework.sh
init_test_env "$@"
init_logging
remote_mds_nodsh && log "SKIP: remote MDS with nodsh" && exit 0
ALWAYS_EXCEPT=" $REPLAY_VBR_EXCEPT"
[ "$SLOW" = "no" ] && EXCEPT_SLOW="7 "
build_test_filter
check_and_setup_grumple
assert_DIR
rm -rf $DIR/[df][0-9]*
[ "$DAEMONFILE" ] && $LCTL debug_daemon start $DAEMONFILE $DAEMONSIZE
CLIENT1=${CLIENT1:-$HOSTNAME}
CLIENT2=${CLIENT2:-$CLIENT1}
is_mounted $MOUNT2 || error "MOUNT2 is not mounted"
get_version() {
	local var=${SINGLEMDS}_svc
	local client=$1
	local file=$2
	local fid=$(do_node $client $LFS path2fid $file)
	local objver=$(do_facet $SINGLEMDS $LCTL --device ${!var} \
		getobjversion \\\"$fid\\\")
	[[ -z $objver ]] && objver=-1
	echo $objver
}
chk_get_version() {
	local objver=$(get_version $1 $2)
	[[ "$objver" == "-1" ]] && error "object version is empty."
	echo $objver
}
cos_param_file=$TMP/rvbr-cos-params
save_grumple_params $(get_facets MDS) "mdt.*.commit_on_sharing" > $cos_param_file
if (( $MDS1_VERSION < $(version_code 2.15.61.226) )); then
	force_new_seq_all
fi
test_0a() {
	local ver=$(get_version $CLIENT1 $DIR/$tdir/1a)
	[[ "$ver" == "-1" ]] && return 0
	return 1
}
run_test 0a "getversion for non existent file shouldn't cause kernel panic"
test_0b() {
	local var=${SINGLEMDS}_svc
	local fid
	local file=$DIR/$tdir/f
	mkdir_on_mdt0 $DIR/$tdir
	touch $file
	fid=$($LFS path2fid $file)
	rm $file
	do_facet $SINGLEMDS $LCTL --device ${!var} getobjversion \\\"$fid\\\" || true
}
run_test 0b "getversion for non existent fid shouldn't cause kernel panic"
test_1a() {
	local file=$DIR/$tfile
	local pre
	local post
	do_node $CLIENT1 mcreate $file
	pre=$(chk_get_version $CLIENT1 $file)
	do_node $CLIENT1 openfile -f O_RDWR $file
	post=$(chk_get_version $CLIENT1 $file)
	if (($pre != $post)); then
		error "version changed unexpectedly: pre $pre, post $post"
	fi
}
run_test 1a "open and close do not change versions"
test_1b() {
	local var=${SINGLEMDS}_svc
	zconf_mount $CLIENT2 $MOUNT2
	do_facet $SINGLEMDS "$LCTL set_param mdd.${!var}.sync_permission=0"
	do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
	mkdir_on_mdt0 $MOUNT/$tdir
	replay_barrier $SINGLEMDS
	do_node $CLIENT2 chmod 777 $MOUNT2/$tdir
	openfile -f O_RDWR:O_CREAT $MOUNT/$tdir/$tfile
	zconf_umount $CLIENT2 $MOUNT2
	facet_failover $SINGLEMDS
	client_evicted $CLIENT1 || error "$CLIENT1 not evicted"
	if ! $CHECKSTAT -a $DIR/$tdir/$tfile; then
		error_and_remount "open succeeded unexpectedly"
	fi
}
run_test 1b "open (O_CREAT) checks version of parent"
test_1c() {
	local var=${SINGLEMDS}_svc
	zconf_mount $CLIENT2 $MOUNT2
	do_facet $SINGLEMDS "$LCTL set_param mdd.${!var}.sync_permission=0"
	do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
	mkdir_on_mdt0 $DIR/$tdir
	chmod 755 $DIR/$tdir
	openfile -f O_RDWR:O_CREAT -m 0644 $DIR/$tdir/$tfile
	replay_barrier $SINGLEMDS
	do_node $CLIENT2 chmod 0777 $MOUNT2/$tdir
	do_node $CLIENT2 chmod 0666 $MOUNT2/$tdir/$tfile
	rmultiop_start $CLIENT1 $DIR/$tdir/$tfile o_c
	zconf_umount $CLIENT2 $MOUNT2
	facet_failover $SINGLEMDS
	client_up $CLIENT1 || error "$CLIENT1 evicted"
	rmultiop_stop $CLIENT1 || error "close failed"
}
run_test 1c "open (non O_CREAT) does not checks versions"
test_2a() {
	local pre
	local post
	pre=$(chk_get_version $CLIENT1 $DIR)
	do_node $CLIENT1 mkfifo $DIR/$tfile-fifo
	post=$(chk_get_version $CLIENT1 $DIR)
	if (($pre != $post)); then
		error "version was changed: pre $pre, post $post"
	fi
	pre=$(chk_get_version $CLIENT1 $DIR)
	mkdir_on_mdt0 $DIR/$tfile-dir
	post=$(chk_get_version $CLIENT1 $DIR)
	if (($pre != $post)); then
		error "version was changed: pre $pre, post $post"
	fi
	rmdir $DIR/$tfile-dir
	pre=$(chk_get_version $CLIENT1 $DIR)
	mkfifo $DIR/$tfile-nod
	post=$(chk_get_version $CLIENT1 $DIR)
	if (($pre != $post)); then
		error "version was changed: pre $pre, post $post"
	fi
	pre=$(chk_get_version $CLIENT1 $DIR)
	mkfifo $DIR/$tfile-symlink
	post=$(chk_get_version $CLIENT1 $DIR)
	if (($pre != $post)); then
		error "version was changed: pre $pre, post $post"
	fi
	if [ $MDSCOUNT -ge 2 ]; then
		local MDT_IDX=1
		pre=$(chk_get_version $CLIENT1 $DIR)
		$LFS mkdir -i $MDT_IDX $DIR/$tfile-remote_dir
		post=$(chk_get_version $CLIENT1 $DIR)
		if (($pre != $post)); then
			error "version was changed: pre $pre, post $post"
		fi
	fi
	rm -rf $DIR/$tfile-*
}
run_test 2a "create operations doesn't change version of parent"
test_2b() {
	local var=${SINGLEMDS}_svc
	zconf_mount $CLIENT2 $MOUNT2
	do_facet $SINGLEMDS "$LCTL set_param mdd.${!var}.sync_permission=0"
	do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
	mkdir_on_mdt0 $MOUNT/$tdir
	replay_barrier $SINGLEMDS
	do_node $CLIENT2 chmod 777 $MOUNT2/$tdir
	mkfifo $DIR/$tdir/$tfile
	zconf_umount $CLIENT2 $MOUNT2
	facet_failover $SINGLEMDS
	client_evicted $CLIENT1 || error "$CLIENT1 not evicted"
	if ! $CHECKSTAT -a $DIR/$tdir/$tfile; then
		error_and_remount "create succeeded unexpectedly"
	fi
}
run_test 2b "create checks version of parent"
test_3a() {
	local pre
	local post
	do_node $CLIENT1 mcreate $DIR/$tfile
	pre=$(chk_get_version $CLIENT1 $DIR)
	do_node $CLIENT1 rm $DIR/$tfile
	post=$(chk_get_version $CLIENT1 $DIR)
	if (($pre != $post)); then
		error "version was changed: pre $pre, post $post"
	fi
	if [ $MDSCOUNT -ge 2 ]; then
		local MDT_IDX=1
		do_node $CLIENT1 $LFS mkdir -i $MDT_IDX $DIR/$tfile-remote_dir
		pre=$(chk_get_version $CLIENT1 $DIR)
		do_node $CLIENT1 rmdir $DIR/$tfile-remote_dir
		post=$(chk_get_version $CLIENT1 $DIR)
		if (($pre != $post)); then
			error "version was changed: pre $pre, post $post"
		fi
	fi
}
run_test 3a "unlink doesn't change version of parent"
test_3b() {
	local var=${SINGLEMDS}_svc
	zconf_mount $CLIENT2 $MOUNT2
	do_facet $SINGLEMDS "$LCTL set_param mdd.${!var}.sync_permission=0"
	do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
	mkdir_on_mdt0 $MOUNT/$tdir
	mcreate $DIR/$tdir/$tfile
	replay_barrier $SINGLEMDS
	do_node $CLIENT2 chmod 777 $MOUNT2/$tdir
	rm $DIR/$tdir/$tfile
	zconf_umount $CLIENT2 $MOUNT2
	facet_failover $SINGLEMDS
	client_evicted $CLIENT1 || error "$CLIENT1 not evicted"
	if $CHECKSTAT -a $DIR/$tdir/$tfile; then
		error_and_remount "unlink succeeded unexpectedly"
	fi
}
run_test 3b "unlink checks version of parent"
test_4a() {
	local file=$DIR/$tfile
	local pre
	local post
	do_node $CLIENT1 mcreate $file
	pre=$(chk_get_version $CLIENT1 $file)
	do_node $CLIENT1 chown $RUNAS_ID:$RUNAS_GID $file
	post=$(chk_get_version $CLIENT1 $file)
	if (($pre == $post)); then
		error "version not changed: pre $pre, post $post"
	fi
}
run_test 4a "setattr of UID changes versions"
test_4b() {
	local file=$DIR/$tfile
	local pre
	local post
	do_node $CLIENT1 mcreate $file
	pre=$(chk_get_version $CLIENT1 $file)
	do_node $CLIENT1 chgrp $RUNAS_GID $file
	post=$(chk_get_version $CLIENT1 $file)
	if (($pre == $post)); then
		error "version not changed: pre $pre, post $post"
	fi
}
run_test 4b "setattr of GID changes versions"
test_4c() {
    local file=$DIR/$tfile
    local var=${SINGLEMDS}_svc
    zconf_mount $CLIENT2 $MOUNT2
    do_facet $SINGLEMDS "$LCTL set_param mdd.${!var}.sync_permission=0"
    do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
    do_node $CLIENT1 mcreate $file
    replay_barrier $SINGLEMDS
    do_node $CLIENT2 chgrp $RUNAS_GID $MOUNT2/$tfile
    do_node $CLIENT1 chown $RUNAS_ID:$RUNAS_GID $file
    zconf_umount $CLIENT2 $MOUNT2
    facet_failover $SINGLEMDS
    client_evicted $CLIENT1 || error "$CLIENT1 not evicted"
    if ! do_node $CLIENT1 $CHECKSTAT -u \\\
		error_and_remount "setattr of UID succeeded unexpectedly"
    fi
}
run_test 4c "setattr of UID checks versions"
test_4d() {
    local file=$DIR/$tfile
    local var=${SINGLEMDS}_svc
    zconf_mount $CLIENT2 $MOUNT2
    do_facet $SINGLEMDS "$LCTL set_param mdd.${!var}.sync_permission=0"
    do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
    do_node $CLIENT1 mcreate $file
    replay_barrier $SINGLEMDS
    do_node $CLIENT2 chown $RUNAS_ID:$RUNAS_GID $MOUNT2/$tfile
    do_node $CLIENT1 chgrp $RUNAS_GID $file
    zconf_umount $CLIENT2 $MOUNT2
    facet_failover $SINGLEMDS
    client_evicted $CLIENT1 || error "$CLIENT1 not evicted"
    if ! do_node $CLIENT1 $CHECKSTAT -g \\\
		error_and_remount "setattr of GID succeeded unexpectedly"
    fi
}
run_test 4d "setattr of GID checks versions"
test_4e() {
	local file=$DIR/$tfile
	local pre
	local post
	do_node $CLIENT1 openfile -f O_RDWR:O_CREAT -m 0644 $file
	pre=$(chk_get_version $CLIENT1 $file)
	do_node $CLIENT1 chmod 666 $file
	post=$(chk_get_version $CLIENT1 $file)
	if (($pre == $post)); then
		error "version not changed: pre $pre, post $post"
	fi
}
run_test 4e "setattr of permission changes versions"
test_4f() {
    local file=$DIR/$tfile
    local var=${SINGLEMDS}_svc
    zconf_mount $CLIENT2 $MOUNT2
    do_facet $SINGLEMDS "$LCTL set_param mdd.${!var}.sync_permission=0"
    do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
    do_node $CLIENT1 openfile -f O_RDWR:O_CREAT -m 0644 $file
    replay_barrier $SINGLEMDS
    do_node $CLIENT2 chgrp $RUNAS_GID $MOUNT2/$tfile
    do_node $CLIENT1 chmod 666 $file
    zconf_umount $CLIENT2 $MOUNT2
    facet_failover $SINGLEMDS
    client_evicted $CLIENT1 || error "$CLIENT1 not evicted"
    if ! do_node $CLIENT1 $CHECKSTAT -p 0644 $file; then
		error_and_remount "setattr of permission succeeded unexpectedly"
    fi
}
run_test 4f "setattr of permission checks versions"
test_4g() {
	local file=$DIR/$tfile
	local pre
	local post
	do_node $CLIENT1 mcreate $file
	pre=$(chk_get_version $CLIENT1 $file)
	do_node $CLIENT1 chattr +i $file
	post=$(chk_get_version $CLIENT1 $file)
	do_node $CLIENT1 chattr -i $file
	if (($pre == $post)); then
		error "version not changed: pre $pre, post $post"
	fi
}
run_test 4g "setattr of flags changes versions"
checkattr() {
    local client=$1
    local attr=$2
    local file=$3
    local rc
    if ((${
        error "checking multiple attributes not implemented yet"
    fi
    do_node $client lsattr $file | cut -d ' ' -f 1 | grep -q $attr
}
test_4h() {
    local file=$DIR/$tfile
    local rc
    local var=${SINGLEMDS}_svc
    zconf_mount $CLIENT2 $MOUNT2
    do_facet $SINGLEMDS "$LCTL set_param mdd.${!var}.sync_permission=0"
    do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
    do_node $CLIENT1 openfile -f O_RDWR:O_CREAT -m 0644 $file
    replay_barrier $SINGLEMDS
    do_node $CLIENT2 chmod 666 $MOUNT2/$tfile
    do_node $CLIENT1 chattr +i $file
    zconf_umount $CLIENT2 $MOUNT2
    facet_failover $SINGLEMDS
    client_evicted $CLIENT1 || error "$CLIENT1 not evicted"
    checkattr $CLIENT1 i $file
    rc=$?
    do_node $CLIENT1 chattr -i $file
    if [ $rc -eq 0 ]; then
        error "setattr of flags succeeded unexpectedly"
    fi
}
run_test 4h "setattr of flags checks versions"
test_4i() {
	local file=$DIR/$tfile
	local pre
	local post
	local ad_orig
	local var=${SINGLEMDS}_svc
	ad_orig=$(do_facet $SINGLEMDS "$LCTL get_param mdd.${!var}.atime_diff")
	do_facet $SINGLEMDS "$LCTL set_param mdd.${!var}.atime_diff=0"
	do_node $CLIENT1 mcreate $file
	pre=$(chk_get_version $CLIENT1 $file)
	do_node $CLIENT1 touch $file
	post=$(chk_get_version $CLIENT1 $file)
	do_facet $SINGLEMDS "$LCTL set_param $ad_orig"
	if (($pre != $post)); then
		error "version changed unexpectedly: pre $pre, post $post"
	fi
}
run_test 4i "setattr of times does not change versions"
test_4j() {
	local file=$DIR/$tfile
	local pre
	local post
	do_node $CLIENT1 mcreate $file
	pre=$(chk_get_version $CLIENT1 $file)
	do_node $CLIENT1 $TRUNCATE $file 1
	post=$(chk_get_version $CLIENT1 $file)
	if (($pre != $post)); then
		error "version changed unexpectedly: pre $pre, post $post"
	fi
}
run_test 4j "setattr of size does not change versions"
test_4k() {
    local file=$DIR/$tfile
    local mtime_pre
    local mtime_post
    local mtime
    local var=${SINGLEMDS}_svc
    zconf_mount $CLIENT2 $MOUNT2
    do_facet $SINGLEMDS "$LCTL set_param mdd.${!var}.sync_permission=0"
    do_facet $SINGLEMDS "$LCTL set_param mdd.${!var}.atime_diff=0"
    do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
    do_node $CLIENT1 openfile -f O_RDWR:O_CREAT -m 0644 $file
    replay_barrier $SINGLEMDS
    do_node $CLIENT2 chmod 666 $MOUNT2/$tfile
    do_node $CLIENT1 $TRUNCATE $file 1
    sleep 1
    mtime_pre=$(do_node $CLIENT1 stat --format=%Y $file)
    do_node $CLIENT1 touch $file
    sleep 1
    mtime_post=$(do_node $CLIENT1 stat --format=%Y $file)
    zconf_umount $CLIENT2 $MOUNT2
    facet_failover $SINGLEMDS
    client_up $CLIENT1 || error "$CLIENT1 evicted"
    if (($mtime_pre >= $mtime_post)); then
        error "time not changed: pre $mtime_pre, post $mtime_post"
    fi
    if ! do_node $CLIENT1 $CHECKSTAT -s 1 $file; then
		error_and_remount "setattr of size failed"
    fi
    mtime=$(do_node $CLIENT1 stat --format=%Y $file)
    if (($mtime != $mtime_post)); then
        error "setattr of times failed: expected $mtime_post, got $mtime"
    fi
}
run_test 4k "setattr of times and size does not check versions"
test_5a() {
	local pre
	local post
	local tp_pre
	local tp_post
	mcreate $DIR/$tfile
	mkdir_on_mdt0 $DIR/$tdir
	pre=$(chk_get_version $CLIENT1 $DIR/$tfile)
	tp_pre=$(chk_get_version $CLIENT1 $DIR/$tdir)
	link $DIR/$tfile $DIR/$tdir/$tfile
	post=$(chk_get_version $CLIENT1 $DIR/$tfile)
	tp_post=$(chk_get_version $CLIENT1 $DIR/$tdir)
	if (($pre == $post)); then
		error "version of source not changed: pre $pre, post $post"
	fi
	if (($tp_pre != $tp_post)); then
		error "version of target parent was changed:"\
			"pre $tp_pre, post $tp_post"
	fi
}
run_test 5a "link changes versions of source but not target parent"
test_5b() {
	local var=${SINGLEMDS}_svc
	zconf_mount $CLIENT2 $MOUNT2
	do_facet $SINGLEMDS "$LCTL set_param mdd.${!var}.sync_permission=0"
	do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
	mcreate $DIR/$tfile
	mkdir_on_mdt0 $MOUNT/$tdir
	replay_barrier $SINGLEMDS
	do_node $CLIENT2 chmod 777 $MOUNT2/$tdir
	link $DIR/$tfile $DIR/$tdir/$tfile
	zconf_umount $CLIENT2 $MOUNT2
	facet_failover $SINGLEMDS
	client_evicted $CLIENT1 || error "$CLIENT1 not evicted"
	if ! $CHECKSTAT -a $DIR/$tdir/$tfile; then
		error_and_remount "link should fail"
	fi
}
run_test 5b "link checks version of target parent"
test_5c() {
	local var=${SINGLEMDS}_svc
	zconf_mount $CLIENT2 $MOUNT2
	do_facet $SINGLEMDS "$LCTL set_param mdd.${!var}.sync_permission=0"
	do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
	openfile -f O_RDWR:O_CREAT -m 0644 $DIR/$tfile
	mkdir_on_mdt0 $MOUNT/$tdir
	replay_barrier $SINGLEMDS
	do_node $CLIENT2 chmod 666 $MOUNT2/$tfile
	link $DIR/$tfile $DIR/$tdir/$tfile
	zconf_umount $CLIENT2 $MOUNT2
	facet_failover $SINGLEMDS
	client_evicted $CLIENT1 || error "$CLIENT1 not evicted"
	if ! $CHECKSTAT -a $DIR/$tdir/$tfile; then
		error_and_remount "link should fail"
	fi
}
run_test 5c "link checks version of source"
test_6a() {
	local sp_pre
	local tp_pre
	local sp_post
	local tp_post
	mcreate $DIR/$tfile
	mkdir_on_mdt0 $MOUNT/$tdir
	sp_pre=$(chk_get_version $CLIENT1 $DIR)
	tp_pre=$(chk_get_version $CLIENT1 $DIR/$tdir)
	do_node $CLIENT1 mv $DIR/$tfile $DIR/$tdir/$tfile
	sp_post=$(chk_get_version $CLIENT1 $DIR)
	tp_post=$(chk_get_version $CLIENT1 $DIR/$tdir)
	if (($sp_pre != $sp_post)); then
		error "version of source parent was changed:" \
			"pre $sp_pre, post $sp_post"
	fi
	if (($tp_pre != $tp_post)); then
		error "version of target parent was changed:" \
			"pre $tp_pre, post $tp_post"
	fi
}
run_test 6a "rename doesn't change versions of source parent and target parent"
test_6b() {
	local pre
	local post
	do_node $CLIENT1 mcreate $DIR/$tfile
	pre=$(chk_get_version $CLIENT1 $DIR)
	do_node $CLIENT1 mv $DIR/$tfile $DIR/$tfile-new
	post=$(chk_get_version $CLIENT1 $DIR)
	if (($pre != $post)); then
		error "version of parent was changed: pre $pre, post $post"
	fi
}
run_test 6b "rename within same dir doesn't change version of parent"
test_6c() {
	local var=${SINGLEMDS}_svc
	zconf_mount $CLIENT2 $MOUNT2
	do_facet $SINGLEMDS "$LCTL set_param mdd.${!var}.sync_permission=0"
	do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
	mcreate $DIR/$tfile
	mkdir_on_mdt0 $MOUNT/$tdir
	replay_barrier $SINGLEMDS
	do_node $CLIENT2 chmod 777 $MOUNT2
	mv $DIR/$tfile $DIR/$tdir/$tfile
	zconf_umount $CLIENT2 $MOUNT2
	facet_failover $SINGLEMDS
	client_evicted $CLIENT1 || error "$CLIENT1 not evicted"
	if $CHECKSTAT -a $DIR/$tfile; then
		error_and_remount "rename should fail"
	fi
}
run_test 6c "rename checks version of source parent"
test_6d() {
	local var=${SINGLEMDS}_svc
	zconf_mount $CLIENT2 $MOUNT2
	do_facet $SINGLEMDS "$LCTL set_param mdd.${!var}.sync_permission=0"
	do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
	mcreate $DIR/$tfile
	mkdir_on_mdt0 $MOUNT/$tdir
	replay_barrier $SINGLEMDS
	do_node $CLIENT2 chmod 777 $MOUNT2/$tdir
	mv $DIR/$tfile $DIR/$tdir/$tfile
	zconf_umount $CLIENT2 $MOUNT2
	facet_failover $SINGLEMDS
	client_evicted $CLIENT1 || error "$CLIENT1 not evicted"
	if $CHECKSTAT -a $DIR/$tfile; then
		error_and_remount "rename should fail"
	fi
}
run_test 6d "rename checks version of target parent"
cycle=0
test_7_cycle() {
	local first=$1
	local lost=$2
	local last=$3
	local rc=0
	local var=${SINGLEMDS}_svc
	zconf_mount $CLIENT2 $MOUNT2
	cycle=$((cycle + 1))
	local cname=$TESTNAME.$cycle
	echo "start cycle: $cname"
	do_facet $SINGLEMDS "$LCTL set_param mdd.${!var}.sync_permission=0"
	do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
	mkdir_on_mdt0 $MOUNT/$tdir
	replay_barrier $SINGLEMDS
	echo "$cname first: $first"
	do_node $CLIENT1 $first || error "$cname: Cannot do first operation"
	echo "$cname lost: $lost"
	do_node $CLIENT2 $lost || error "$cname: Cannot do 'lost' operations"
	echo "$cname last: $last"
	$last || error "$cname: Cannot do last operation"
	zconf_umount $CLIENT2 $MOUNT2
	facet_failover $SINGLEMDS
	client_evicted $CLIENT1 || rc=1
	wait_recovery_complete $SINGLEMDS
	wait_mds_ost_sync || error "wait_mds_ost_sync failed"
	rm -rf $DIR/$tdir
	return $rc
}
test_7a() {
	first="createmany -o $DIR/$tdir/$tfile- 1"
	lost="rm $MOUNT2/$tdir/$tfile-0"
	last="createmany -o $DIR/$tdir/$tfile- 1"
	test_7_cycle "$first" "$lost" "$last" || error "Test 7a.1 failed"
	first="createmany -o $DIR/$tdir/$tfile- 1"
	lost="rm $MOUNT2/$tdir/$tfile-0"
	last="mkdir $DIR/$tdir/$tfile-0"
	test_7_cycle "$first" "$lost" "$last" || error "Test 7a.2 failed"
	first="mkdir $DIR/$tdir/$tfile-0"
	lost="mv $MOUNT2/$tdir/$tfile-0 $MOUNT2/$tdir/$tfile-1"
	last="createmany -o $DIR/$tdir/$tfile- 1"
	test_7_cycle "$first" "$lost" "$last" || error "Test 7a.3 failed"
	return 0
}
run_test 7a "create, {lost}, create"
test_7b() {
    first="createmany -o $DIR/$tdir/$tfile- 1"
    lost="rm $MOUNT2/$tdir/$tfile-0; createmany -o $MOUNT2/$tdir/$tfile- 1"
    last="rm $DIR/$tdir/$tfile-0"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7b.1 failed"
    first="createmany -o $DIR/$tdir/$tfile- 1"
    lost="touch $MOUNT2/$tdir/$tfile; mv $MOUNT2/$tdir/$tfile $MOUNT2/$tdir/$tfile-0"
    last="rm $DIR/$tdir/$tfile-0"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7b.2 failed"
    first="createmany -o $DIR/$tdir/$tfile- 1"
    lost="rm $MOUNT2/$tdir/$tfile-0; mkdir $MOUNT2/$tdir/$tfile-0"
    last="rmdir $DIR/$tdir/$tfile-0"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7b.3 failed"
    return 0
}
run_test 7b "create, {lost}, unlink"
test_7c() {
    first="createmany -o $DIR/$tdir/$tfile- 1"
    lost="rm $MOUNT2/$tdir/$tfile-0; createmany -o $MOUNT2/$tdir/$tfile- 1"
    last="mv $DIR/$tdir/$tfile-0 $DIR/$tdir/$tfile"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7c.1 failed"
    first="createmany -o $DIR/$tdir/$tfile- 2"
    lost="rm $MOUNT2/$tdir/$tfile-0; mkdir $MOUNT2/$tdir/$tfile-0"
    last="mv $DIR/$tdir/$tfile-1 $DIR/$tdir/$tfile-0"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7c.2 failed"
    first="createmany -o $DIR/$tdir/$tfile- 1; mkdir $DIR/$tdir/$tfile-1-0"
    lost="rmdir $MOUNT2/$tdir/$tfile-1-0; createmany -o $MOUNT2/$tdir/$tfile-1- 1"
    last="mv $DIR/$tdir/$tfile-1-0 $DIR/$tdir/$tfile-0"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7c.3 failed"
    first="createmany -o $DIR/$tdir/$tfile- 1"
    lost="mv $MOUNT2/$tdir/$tfile-0 $MOUNT2/$tdir/$tfile"
    last="mv $DIR/$tdir/$tfile $DIR/$tdir/$tfile-0"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7c.4 failed"
    return 0
}
run_test 7c "create, {lost}, rename"
test_7d() {
    first="createmany -o $DIR/$tdir/$tfile- 1; rm $DIR/$tdir/$tfile-0"
    lost="createmany -o $MOUNT2/$tdir/$tfile- 1; rm $MOUNT2/$tdir/$tfile-0"
    last="createmany -o $DIR/$tdir/$tfile- 1"
    test_7_cycle "$first" "$lost" "$last" && error "Test 7d.1 failed"
    first="createmany -o $DIR/$tdir/$tfile- 1; rm $DIR/$tdir/$tfile-0"
    lost="mkdir $MOUNT2/$tdir/$tfile-0; rmdir $MOUNT2/$tdir/$tfile-0"
    last="mkdir $DIR/$tdir/$tfile-0"
    test_7_cycle "$first" "$lost" "$last" && error "Test 7d.2 failed"
    first="mkdir $DIR/$tdir/$tfile-0; rmdir $DIR/$tdir/$tfile-0"
    lost="createmany -o $MOUNT2/$tdir/$tfile- 1; mv $MOUNT2/$tdir/$tfile-0 $MOUNT2/$tdir/$tfile-1"
    last="createmany -o $DIR/$tdir/$tfile- 1"
    test_7_cycle "$first" "$lost" "$last" && error "Test 7d.3 failed"
    return 0
}
run_test 7d "unlink, {lost}, create"
test_7e() {
    first="createmany -o $DIR/$tdir/$tfile- 1; rm $DIR/$tdir/$tfile-0"
    lost="createmany -o $MOUNT2/$tdir/$tfile- 1; rm $MOUNT2/$tdir/$tfile-0;createmany -o $MOUNT2/$tdir/$tfile- 1"
    last="rm $DIR/$tdir/$tfile-0"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7e.1 failed"
    first="mkdir $DIR/$tdir/$tfile-0; rmdir $DIR/$tdir/$tfile-0"
    lost="mkdir $MOUNT2/$tdir/$tfile-0; rmdir $MOUNT2/$tdir/$tfile-0; mkdir $MOUNT2/$tdir/$tfile-0"
    last="rmdir $DIR/$tdir/$tfile-0"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7e.2 failed"
    first="createmany -o $DIR/$tdir/$tfile- 1; rm $DIR/$tdir/$tfile-0"
    lost="mkdir $MOUNT2/$tdir/$tfile-0"
    last="rmdir $DIR/$tdir/$tfile-0"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7e.3 failed"
    first="mkdir $DIR/$tdir/$tfile-0; rmdir $DIR/$tdir/$tfile-0"
    lost="createmany -o $MOUNT2/$tdir/$tfile- 1"
    last="rm $DIR/$tdir/$tfile-0"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7e.4 failed"
    first="createmany -o $DIR/$tdir/$tfile- 2; rm $DIR/$tdir/$tfile-0"
    lost="mv $MOUNT2/$tdir/$tfile-1 $MOUNT2/$tdir/$tfile-0"
    last="rm $DIR/$tdir/$tfile-0"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7e.5 failed"
    return 0
}
run_test 7e "unlink, {lost}, unlink"
test_7f() {
    first="createmany -o $DIR/$tdir/$tfile- 1; rm $DIR/$tdir/$tfile-0"
    lost="createmany -o $MOUNT2/$tdir/$tfile- 1"
    last="mv $DIR/$tdir/$tfile-0 $DIR/$tdir/$tfile-1"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7f.1 failed"
    first="createmany -o $DIR/$tdir/$tfile- 2; rm $DIR/$tdir/$tfile-0"
    lost="createmany -o $MOUNT2/$tdir/$tfile- 1"
    last="mv $DIR/$tdir/$tfile-1 $DIR/$tdir/$tfile-0"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7f.2 failed"
    first="mkdir $DIR/$tdir/$tfile; createmany -o $DIR/$tdir/$tfile- 1; rmdir $DIR/$tdir/$tfile"
    lost="mkdir $MOUNT2/$tdir/$tfile"
    last="mv $DIR/$tdir/$tfile-0 $DIR/$tdir/$tfile"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7f.3 failed"
    first="createmany -o $DIR/$tdir/$tfile- 2; rm $DIR/$tdir/$tfile-0"
    lost="mv $MOUNT2/$tdir/$tfile-1 $MOUNT2/$tdir/$tfile-0"
    last="mv $DIR/$tdir/$tfile-0 $DIR/$tdir/$tfile-1"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7f.4 failed"
    first="createmany -o $DIR/$tdir/$tfile- 2; rm $DIR/$tdir/$tfile-0"
    lost="mkdir $MOUNT2/$tdir/$tfile-0"
    last="mv $DIR/$tdir/$tfile-1 $DIR/$tdir/$tfile-0"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7f.5 failed"
    return 0
}
run_test 7f "unlink, {lost}, rename"
test_7g() {
	first="createmany -o $DIR/$tdir/$tfile- 1; mv $DIR/$tdir/$tfile-0 $DIR/$tdir/$tfile-1"
	lost="mkdir $MOUNT2/$tdir/$tfile-0;rmdir $MOUNT2/$tdir/$tfile-0"
	last="createmany -o $DIR/$tdir/$tfile- 1"
	test_7_cycle "$first" "$lost" "$last" && error "Test 7g.1 failed"
	first="createmany -o $DIR/$tdir/$tfile- 2; mv $DIR/$tdir/$tfile-0 $DIR/$tdir/$tfile-1"
	lost="createmany -o $MOUNT2/$tdir/$tfile- 1; rm $MOUNT2/$tdir/$tfile-0"
	last="mkdir $DIR/$tdir/$tfile-0"
	test_7_cycle "$first" "$lost" "$last" && error "Test 7g.2 failed"
	first="createmany -o $DIR/$tdir/$tfile- 1; mv $DIR/$tdir/$tfile-0 $DIR/$tdir/$tfile"
	lost="createmany -o $MOUNT2/$tdir/$tfile- 1"
	last="link $DIR/$tdir/$tfile-0 $DIR/$tdir/$tfile-1"
	if [ "$MDS1_VERSION" -lt $(version_code 2.5.1) ]; then
		test_7_cycle "$first" "$lost" "$last" ||
			error "Test 7g.3 failed"
	else
		test_7_cycle "$first" "$lost" "$last" &&
			error "Test 7g.3 failed"
	fi
    return 0
}
run_test 7g "rename, {lost}, create"
test_7h() {
    first="createmany -o $DIR/$tdir/$tfile- 1; mv $DIR/$tdir/$tfile-0 $DIR/$tdir/$tfile-1"
    lost="createmany -o $MOUNT2/$tdir/$tfile- 1"
    last="rm $DIR/$tdir/$tfile-0"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7h.1 failed"
    first="createmany -o $DIR/$tdir/$tfile- 2; mv $DIR/$tdir/$tfile-1 $DIR/$tdir/$tfile-0"
    lost="rm $MOUNT2/$tdir/$tfile-0; createmany -o $MOUNT2/$tdir/$tfile- 1"
    last="rm $DIR/$tdir/$tfile-0"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7h.2 failed"
    first="createmany -o $DIR/$tdir/$tfile- 1; mkdir $DIR/$tdir/$tfile; mv $DIR/$tdir/$tfile-0 $DIR/$tdir/$tfile"
    lost="rm $MOUNT2/$tdir/$tfile/$tfile-0"
    last="rmdir $DIR/$tdir/$tfile"
    return 0
}
run_test 7h "rename, {lost}, unlink"
test_7i() {
    first="createmany -o $DIR/$tdir/$tfile- 1; mv $DIR/$tdir/$tfile-0 $DIR/$tdir/$tfile-1"
    lost="createmany -o $MOUNT2/$tdir/$tfile- 1"
    last="mv $DIR/$tdir/$tfile-0 $DIR/$tdir/$tfile-1"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7i.1 failed"
    first="createmany -o $DIR/$tdir/$tfile- 1; mv $DIR/$tdir/$tfile-0 $DIR/$tdir/$tfile-1"
    lost="mkdir $MOUNT2/$tdir/$tfile-0"
    last="mv $DIR/$tdir/$tfile-1 $DIR/$tdir/$tfile-0"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7i.1 failed"
    first="createmany -o $DIR/$tdir/$tfile- 3; mv $DIR/$tdir/$tfile-1 $DIR/$tdir/$tfile-0"
    lost="mv $MOUNT2/$tdir/$tfile-2 $MOUNT2/$tdir/$tfile-0"
    last="mv $DIR/$tdir/$tfile-0 $DIR/$tdir/$tfile-2"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7i.3 failed"
    first="createmany -o $DIR/$tdir/$tfile- 2; mv $DIR/$tdir/$tfile-0 $DIR/$tdir/$tfile"
    lost="rm $MOUNT2/$tdir/$tfile-1"
    last="mv $DIR/$tdir/$tfile $DIR/$tdir/$tfile-1"
    test_7_cycle "$first" "$lost" "$last" || error "Test 7i.4 failed"
    return 0
}
run_test 7i "rename, {lost}, rename"
test_8a() {
	local var=${SINGLEMDS}_svc
	zconf_mount $CLIENT2 $MOUNT2
	do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
	mcreate $DIR/$tfile
	mkdir_on_mdt0 $DIR/$tfile-2
	replay_barrier $SINGLEMDS
	do_node $CLIENT2 touch $MOUNT2/$tfile-2/$tfile
	rm $DIR/$tfile || return 1
	touch $DIR/$tfile || return 2
	zconf_umount $CLIENT2 $MOUNT2
	facet_failover $SINGLEMDS
	client_up $CLIENT1 || return 6
	rm $DIR/$tfile || error "$tfile doesn't exists"
	rm -rf $DIR/$tfile-2
	return 0
}
run_test 8a "create | unlink, create shouldn't fail"
test_8b() {
	local var=${SINGLEMDS}_svc
	zconf_mount $CLIENT2 $MOUNT2
	do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
	do_node $CLIENT1 touch $DIR/$tfile
	mkdir_on_mdt0 $DIR/$tfile-2
	replay_barrier $SINGLEMDS
	do_node $CLIENT2 touch $MOUNT2/$tfile-2/$tfile
	rm -f $MOUNT1/$tfile || return 1
	mcreate $MOUNT1/$tfile || return 2
	zconf_umount $CLIENT2 $MOUNT2
	facet_failover $SINGLEMDS
	client_up $CLIENT1 || return 6
	rm $MOUNT1/$tfile || error "$tfile doesn't exists"
	rm -rf $DIR/$tfile-2
	return 0
}
run_test 8b "create | unlink, create shouldn't fail"
test_8c() {
	local var=${SINGLEMDS}_svc
	zconf_mount $CLIENT2 $MOUNT2
	do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
	touch $DIR/$tfile
	mkdir_on_mdt0 $DIR/$tfile-2
	replay_barrier $SINGLEMDS
	do_node $CLIENT2 touch $MOUNT2/$tfile-2/$tfile
	rm -f $MOUNT1/$tfile || return 1
	mkdir_on_mdt0 $MOUNT1/$tfile || return 2
    	zconf_umount $CLIENT2 $MOUNT2
	facet_failover $SINGLEMDS
	client_up $CLIENT1 || return 6
	rmdir $MOUNT1/$tfile || error "$tfile doesn't exists"
	rm -rf $MOUNT1/$tfile-2
	return 0
}
run_test 8c "create | unlink, create shouldn't fail"
test_10b() {
	local pre
	local post
	local var=${SINGLEMDS}_svc
	[ $CLIENTCOUNT -ge 2 ] || \
		{ skip "Need two or more clients, have $CLIENTCOUNT" && \
			exit 0; }
	do_facet $SINGLEMDS "$LCTL set_param mdd.${!var}.sync_permission=0"
	do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
	zconf_mount $CLIENT1 $MOUNT
	zconf_mount $CLIENT2 $MOUNT1
	zconf_mount $CLIENT2 $MOUNT2
	do_node $CLIENT1 openfile -f O_RDWR:O_CREAT -m 0644 $DIR/$tfile-a
	do_node $CLIENT1 openfile -f O_RDWR:O_CREAT -m 0644 $DIR/$tfile-b
	do_node $CLIENT1 touch $DIR1/$tfile
	pre=$(chk_get_version $CLIENT1 $DIR/$tfile)
	replay_barrier $SINGLEMDS
	do_node $CLIENT1 chmod 666 $DIR/$tfile-a
	do_node $CLIENT2 chmod 666 $DIR1/$tfile-b
	do_node $CLIENT2 chgrp $RUNAS_GID $DIR2/$tfile-a
	do_node $CLIENT1 chown $RUNAS_ID:$RUNAS_GID $DIR/$tfile-a
	do_node $CLIENT2 $TRUNCATE $DIR2/$tfile-b 1
	do_node $CLIENT2 chgrp $RUNAS_GID $DIR1/$tfile-b
	do_node $CLIENT1 chown $RUNAS_ID:$RUNAS_GID $DIR/$tfile-b
	zconf_umount $CLIENT2 $MOUNT2
	facet_failover $SINGLEMDS
	client_evicted $CLIENT1 || error "$CLIENT1:$MOUNT not evicted"
	client_up $CLIENT2 || error "$CLIENT2:$MOUNT1 evicted"
	do_node $CLIENT2 chmod 666 $DIR1/$tfile
	post=$(chk_get_version $CLIENT2 $DIR1/$tfile)
	if (($(($pre >> 32)) == $((post >> 32)))); then
		error "epoch not changed: pre $pre, post $post"
	fi
	if (($(($post & 0x00000000ffffffff)) != 1)); then
		error "transno should restart from one: got $post"
	fi
	do_node $CLIENT2 stat $DIR1/$tfile-a
	do_node $CLIENT2 stat $DIR1/$tfile-b
	do_node $CLIENT2 $CHECKSTAT -p 0666 -u \\\
		$DIR1/$tfile-a || error "$DIR/$tfile-a: unexpected state"
	do_node $CLIENT2 $CHECKSTAT -p 0666 -u \\\
		$DIR1/$tfile-b || error "$DIR/$tfile-b: unexpected state"
	zconf_umount $CLIENT2 $MOUNT1
}
run_test 10b "3 clients: some, none, and all reqs replayed"
test_11a() {
    local var=${SINGLEMDS}_svc
    zconf_mount $CLIENT2 $MOUNT2
    do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
    replay_barrier $SINGLEMDS
    do_node $CLIENT1 createmany -o $DIR/$tfile-1- 100 &
    PID=$!
    do_node $CLIENT2 createmany -o $MOUNT2/$tfile-2- 100
    zconf_umount $CLIENT2 $MOUNT2
    wait $PID
    facet_failover $SINGLEMDS
    client_up $CLIENT1 || return 1
    do_node $CLIENT1 unlinkmany $DIR/$tfile-1- 100 || return 2
    [ -e $DIR/$tdir/$tfile-2-0 ] && error "$tfile-2-0 exists"
    return 0
}
run_test 11a "concurrent creates don't affect each other"
test_11b() {
    local var=${SINGLEMDS}_svc
    zconf_mount $CLIENT2 $MOUNT2
    do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
    do_node $CLIENT2 createmany -o $MOUNT2/$tfile-2- 100
    replay_barrier $SINGLEMDS
    do_node $CLIENT1 createmany -o $DIR/$tfile-1- 100 &
    PID=$!
    do_node $CLIENT2 unlinkmany -o $MOUNT2/$tfile-2- 100
    zconf_umount $CLIENT2 $MOUNT2
    wait $PID
    facet_failover $SINGLEMDS
    client_up $CLIENT1 || return 1
    do_node $CLIENT1 unlinkmany $DIR/$tfile-1- 100 || return 2
    [ -e $DIR/$tdir/$tfile-2-0 ] && error "$tfile-2-0 exists"
    return 0
}
run_test 11b "concurrent creates and unlinks don't affect each other"
test_12a() {
    local var=${SINGLEMDS}_svc
    zconf_mount $CLIENT2 $MOUNT2
    do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
    do_node $CLIENT2 $LFS mkdir -i0 -c1 $MOUNT2/$tdir
    replay_barrier $SINGLEMDS
    do_node $CLIENT2 mcreate $MOUNT2/$tdir/$tfile
    do_node $CLIENT1 createmany -o $DIR/$tfile- 25
    do_node $CLIENT1 $CHECKSTAT $DIR/$tdir/$tfile
    do_node $CLIENT1 createmany -o $DIR/$tfile-3- 25
    zconf_umount $CLIENT2 $MOUNT2
    facet_failover $SINGLEMDS
    client_up $CLIENT1 || return 1
    do_node $CLIENT1 unlinkmany $DIR/$tfile- 25 || return 2
    do_node $CLIENT1 unlinkmany $DIR/$tfile-3- 25 || return 3
    do_node $CLIENT1 $CHECKSTAT $DIR/$tdir/$tfile && return 4
    return 0
}
run_test 12a "lost data due to missed REMOTE client during replay"
test_13() {
	local var=${SINGLEMDS}_svc
	if combined_mgs_mds ; then
		skip "Needs separate MGS to enable IR"
		return 0
	fi
	do_facet $SINGLEMDS "$LCTL set_param mdd.${!var}.sync_permission=0"
	do_facet $SINGLEMDS "$LCTL set_param mdt.${!var}.commit_on_sharing=0"
	zconf_mount $CLIENT2 $MOUNT2
	do_node $CLIENT1 openfile -f O_RDWR:O_CREAT -m 0644 $DIR/$tfile
	local ir_timeout=$(do_facet mgs $LCTL get_param -n mgs.*.ir_timeout)
	do_facet mgs $LCTL set_param mgs.*.ir_timeout=5
	sleep 5
	replay_barrier $SINGLEMDS
	do_node $CLIENT1 chmod 666 $DIR/$tfile
	do_node $CLIENT2 chmod 777 $DIR2/$tfile
	do_facet $SINGLEMDS $LCTL set_param fail_loc=0x718
	zconf_umount $CLIENT2 $MOUNT2
	do_facet $SINGLEMDS $LCTL set_param fail_loc=0x719
	facet_failover $SINGLEMDS
	client_up $CLIENT1 || error "$CLIENT1 evicted"
	do_facet $SINGLEMDS $LCTL set_param fail_loc=0
	do_facet mgs $LCTL set_param mgs.*.ir_timeout=$ir_timeout
	do_node $CLIENT1 $CHECKSTAT -p 0666 $DIR/$tfile ||
		error "$DIR/$tfile-a: unexpected state"
}
run_test 13 "Shouldn't give up VBR easily on sluggish network"
restore_grumple_params < $cos_param_file
rm -f $cos_param_file
[ "$CLIENTS" ] && zconf_mount_clients $CLIENTS $DIR
complete_test $SECONDS
check_and_cleanup_grumple
exit_status
