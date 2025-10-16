#!/bin/bash
set -e
LUSTRE=${LUSTRE:-$(dirname $0)/..}
. $LUSTRE/tests/test-framework.sh
init_test_env "$@"
init_logging
ALWAYS_EXCEPT="$REPLAY_SINGLE_EXCEPT "
if [ "$mds1_FSTYPE" = zfs ]; then
	ALWAYS_EXCEPT+=""
fi
always_except LU-13614 59
always_except LU-12805 36
if $SHARED_KEY; then
	always_except LU-9795 121
fi
build_test_filter
CHECK_GRANT=${CHECK_GRANT:-"yes"}
GRANT_CHECK_LIST=${GRANT_CHECK_LIST:-""}
require_dsh_mds || exit 0
check_and_setup_lustre
mkdir -p $DIR
assert_DIR
rm -rf $DIR/[df][0-9]* $DIR/f.$TESTSUITE.*
if (( $MDS1_VERSION < $(version_code 2.15.61.226) )); then
	force_new_seq_all
fi
test_0a() {
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	replay_barrier $SINGLEMDS
	fail $SINGLEMDS
	rmdir $DIR/$tdir
}
run_test 0a "empty replay"
test_0b() {
	remote_ost_nodsh && skip "remote OST with nodsh" && return 0
	fail ost1
	createmany -o $DIR/$tfile 20 || error "createmany -o $DIR/$tfile failed"
	unlinkmany $DIR/$tfile 20 || error "unlinkmany $DIR/$tfile failed"
}
run_test 0b "ensure object created after recover exists. (3284)"
test_0c() {
	replay_barrier $SINGLEMDS
	mcreate $DIR/$tfile
	umount $MOUNT
	facet_failover $SINGLEMDS
	zconf_mount $(hostname) $MOUNT || error "mount fails"
	client_up || error "post-failover df failed"
	rm $DIR/$tfile && error "File exists and it shouldn't"
	return 0
}
run_test 0c "check replay-barrier"
test_0d() {
	replay_barrier $SINGLEMDS
	umount $MOUNT
	facet_failover $SINGLEMDS
	zconf_mount $(hostname) $MOUNT || error "mount fails"
	client_up || error "post-failover df failed"
}
run_test 0d "expired recovery with no clients"
test_1() {
	replay_barrier $SINGLEMDS
	mcreate $DIR/$tfile
	fail $SINGLEMDS
	$CHECKSTAT -t file $DIR/$tfile ||
		error "$CHECKSTAT $DIR/$tfile attribute check failed"
	rm $DIR/$tfile
}
run_test 1 "simple create"
test_2a() {
	replay_barrier $SINGLEMDS
	touch $DIR/$tfile
	fail $SINGLEMDS
	$CHECKSTAT -t file $DIR/$tfile ||
		error "$CHECKSTAT $DIR/$tfile attribute check failed"
	rm $DIR/$tfile
}
run_test 2a "touch"
test_2b() {
	mcreate $DIR/$tfile || error "mcreate $DIR/$tfile failed"
	replay_barrier $SINGLEMDS
	touch $DIR/$tfile
	fail $SINGLEMDS
	$CHECKSTAT -t file $DIR/$tfile ||
		error "$CHECKSTAT $DIR/$tfile attribute check failed"
	rm $DIR/$tfile
}
run_test 2b "touch"
test_2c() {
	replay_barrier $SINGLEMDS
	$LFS setstripe -c $OSTCOUNT $DIR/$tfile
	fail $SINGLEMDS
	$CHECKSTAT -t file $DIR/$tfile ||
		error "$CHECKSTAT $DIR/$tfile check failed"
}
run_test 2c "setstripe replay"
test_2d() {
	[[ "$mds1_FSTYPE" = zfs ]] &&
		[[ "$MDS1_VERSION" -lt $(version_code 2.12.51) ]] &&
		skip "requires LU-10143 fix on MDS"
	replay_barrier $SINGLEMDS
	$LFS setdirstripe -i 0 -c $MDSCOUNT $DIR/$tdir
	fail $SINGLEMDS
	$CHECKSTAT -t dir $DIR/$tdir ||
		error "$CHECKSTAT $DIR/$tdir check failed"
}
run_test 2d "setdirstripe replay"
test_2e() {
	testid=$(echo $TESTNAME | tr '_' ' ')
	do_facet $SINGLEMDS "$LCTL set_param fail_loc=0x8000013b"
	openfile -f O_CREAT:O_EXCL $DIR/$tfile &
	sleep 1
	replay_barrier $SINGLEMDS
	fail $SINGLEMDS
	wait
	$CHECKSTAT -t file $DIR/$tfile ||
		error "$CHECKSTAT $DIR/$tfile attribute check failed"
	dmesg | tac | sed "/$testid/,$ d" | \
		grep "Open request replay failed with -17" &&
		error "open replay failed" || true
}
run_test 2e "O_CREAT|O_EXCL create replay"
test_3a() {
	local file=$DIR/$tfile
	replay_barrier $SINGLEMDS
	mcreate $file
	openfile -f O_DIRECTORY $file
	fail $SINGLEMDS
	$CHECKSTAT -t file $file ||
		error "$CHECKSTAT $file attribute check failed"
	rm $file
}
run_test 3a "replay failed open(O_DIRECTORY)"
test_3b() {
	replay_barrier $SINGLEMDS
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x80000114"
	touch $DIR/$tfile
	do_facet $SINGLEMDS "lctl set_param fail_loc=0"
	fail $SINGLEMDS
	$CHECKSTAT -t file $DIR/$tfile &&
		error "$CHECKSTAT $DIR/$tfile attribute check should fail"
	return 0
}
run_test 3b "replay failed open -ENOMEM"
test_3c() {
	replay_barrier $SINGLEMDS
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x80000128"
	touch $DIR/$tfile
	do_facet $SINGLEMDS "lctl set_param fail_loc=0"
	fail $SINGLEMDS
	$CHECKSTAT -t file $DIR/$tfile &&
		error "$CHECKSTAT $DIR/$tfile attribute check should fail"
	return 0
}
run_test 3c "replay failed open -ENOMEM"
test_4a() {
	replay_barrier $SINGLEMDS
	for i in $(seq 10); do
		echo "tag-$i" > $DIR/$tfile-$i
	done
	fail $SINGLEMDS
	for i in $(seq 10); do
		grep -q "tag-$i" $DIR/$tfile-$i || error "$tfile-$i"
	done
}
run_test 4a "|x| 10 open(O_CREAT)s"
test_4b() {
	for i in $(seq 10); do
		echo "tag-$i" > $DIR/$tfile-$i
	done
	replay_barrier $SINGLEMDS
	rm -rf $DIR/$tfile-*
	fail $SINGLEMDS
	$CHECKSTAT -t file $DIR/$tfile-* &&
		error "$CHECKSTAT $DIR/$tfile-* attribute check should fail" ||
		true
}
run_test 4b "|x| rm 10 files"
test_5() {
	replay_barrier $SINGLEMDS
	for i in $(seq 220); do
		echo "tag-$i" > $DIR/$tfile-$i
	done
	fail $SINGLEMDS
	for i in $(seq 220); do
		grep -q "tag-$i" $DIR/$tfile-$i || error "$tfile-$i"
	done
	rm -rf $DIR/$tfile-*
	sleep 3
}
run_test 5 "|x| 220 open(O_CREAT)"
test_6a() {
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	replay_barrier $SINGLEMDS
	mcreate $DIR/$tdir/$tfile
	fail $SINGLEMDS
	$CHECKSTAT -t dir $DIR/$tdir ||
		error "$CHECKSTAT $DIR/$tdir attribute check failed"
	$CHECKSTAT -t file $DIR/$tdir/$tfile ||
		error "$CHECKSTAT $DIR/$tdir/$tfile attribute check failed"
	sleep 2
}
run_test 6a "mkdir + contained create"
test_6b() {
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	replay_barrier $SINGLEMDS
	rm -rf $DIR/$tdir
	fail $SINGLEMDS
	$CHECKSTAT -t dir $DIR/$tdir &&
		error "$CHECKSTAT $DIR/$tdir attribute check should fail" ||
		true
}
run_test 6b "|X| rmdir"
test_7() {
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	replay_barrier $SINGLEMDS
	mcreate $DIR/$tdir/$tfile
	fail $SINGLEMDS
	$CHECKSTAT -t dir $DIR/$tdir ||
		error "$CHECKSTAT $DIR/$tdir attribute check failed"
	$CHECKSTAT -t file $DIR/$tdir/$tfile ||
		error "$CHECKSTAT $DIR/$tdir/$tfile attribute check failed"
	rm -fr $DIR/$tdir
}
run_test 7 "mkdir |X| contained create"
test_8() {
	replay_barrier $SINGLEMDS
	multiop_bg_pause $DIR/$tfile mo_c ||
		error "multiop mknod $DIR/$tfile failed"
	MULTIPID=$!
	fail $SINGLEMDS
	ls $DIR/$tfile
	$CHECKSTAT -t file $DIR/$tfile ||
		error "$CHECKSTAT $DIR/$tfile attribute check failed"
	kill -USR1 $MULTIPID || error "multiop mknod $MULTIPID not running"
	wait $MULTIPID || error "multiop mknod $MULTIPID failed"
	rm $DIR/$tfile
}
run_test 8 "creat open |X| close"
test_9() {
	replay_barrier $SINGLEMDS
	mcreate $DIR/$tfile
	local old_inum=$(ls -i $DIR/$tfile | awk '{print $1}')
	fail $SINGLEMDS
	local new_inum=$(ls -i $DIR/$tfile | awk '{print $1}')
	echo " old_inum == $old_inum, new_inum == $new_inum"
	if [ $old_inum -eq $new_inum  ] ;
	then
		echo "old_inum and new_inum match"
	else
		echo " old_inum and new_inum do not match"
		error "old index($old_inum) does not match new index($new_inum)"
	fi
	rm $DIR/$tfile
}
run_test 9 "|X| create (same inum/gen)"
test_10() {
	mcreate $DIR/$tfile || error "mcreate $DIR/$tfile failed"
	replay_barrier $SINGLEMDS
	mv $DIR/$tfile $DIR/$tfile-2
	rm -f $DIR/$tfile
	fail $SINGLEMDS
	$CHECKSTAT $DIR/$tfile &&
		error "$CHECKSTAT $DIR/$tfile attribute check should fail"
	$CHECKSTAT $DIR/$tfile-2 ||
		error "$CHECKSTAT $DIR/$tfile-2 attribute check failed"
	rm $DIR/$tfile-2
	return 0
}
run_test 10 "create |X| rename unlink"
test_11() {
	mcreate $DIR/$tfile || error "mcreate $DIR/$tfile failed"
	echo "old" > $DIR/$tfile
	mv $DIR/$tfile $DIR/$tfile-2
	replay_barrier $SINGLEMDS
	echo "new" > $DIR/$tfile
	grep new $DIR/$tfile
	grep old $DIR/$tfile-2
	fail $SINGLEMDS
	grep new $DIR/$tfile || error "grep $DIR/$tfile failed"
	grep old $DIR/$tfile-2 || error "grep $DIR/$tfile-2 failed"
}
run_test 11 "create open write rename |X| create-old-name read"
test_12() {
	mcreate $DIR/$tfile || error "mcreate $DIR/$tfile failed"
	multiop_bg_pause $DIR/$tfile o_tSc ||
		error "multiop_bg_pause $DIR/$tfile failed"
	pid=$!
	rm -f $DIR/$tfile
	replay_barrier $SINGLEMDS
	kill -USR1 $pid || error "multiop $pid not running"
	wait $pid || error "multiop $pid failed"
	fail $SINGLEMDS
	[ -e $DIR/$tfile ] && error "file $DIR/$tfile should not exist"
	return 0
}
run_test 12 "open, unlink |X| close"
test_13() {
	mcreate $DIR/$tfile || error "mcreate $DIR/$tfile failed"
	multiop_bg_pause $DIR/$tfile O_wc ||
		error "multiop_bg_pause $DIR/$tfile failed"
	pid=$!
	chmod 0 $DIR/$tfile
	$CHECKSTAT -p 0 $DIR/$tfile ||
		error "$CHECKSTAT $DIR/$tfile attribute check failed"
	replay_barrier $SINGLEMDS
	fail $SINGLEMDS
	kill -USR1 $pid || error "multiop $pid not running"
	wait $pid || error "multiop $pid failed"
	$CHECKSTAT -s 1 -p 0 $DIR/$tfile ||
		error "second $CHECKSTAT $DIR/$tfile attribute check failed"
	rm $DIR/$tfile || error "rm $DIR/$tfile failed"
	return 0
}
run_test 13 "open chmod 0 |x| write close"
test_14() {
	multiop_bg_pause $DIR/$tfile O_tSc ||
		error "multiop_bg_pause $DIR/$tfile failed"
	pid=$!
	rm -f $DIR/$tfile
	replay_barrier $SINGLEMDS
	kill -USR1 $pid || error "multiop $pid not running"
	wait $pid || error "multiop $pid failed"
	fail $SINGLEMDS
	[ -e $DIR/$tfile ] && error "file $DIR/$tfile should not exist"
	return 0
}
run_test 14 "open(O_CREAT), unlink |X| close"
test_15() {
	multiop_bg_pause $DIR/$tfile O_tSc ||
		error "multiop_bg_pause $DIR/$tfile failed"
	pid=$!
	rm -f $DIR/$tfile
	replay_barrier $SINGLEMDS
	touch $DIR/$tfile-1 || error "touch $DIR/$tfile-1 failed"
	kill -USR1 $pid || error "multiop $pid not running"
	wait $pid || error "multiop $pid failed"
	fail $SINGLEMDS
	[ -e $DIR/$tfile ] && error "file $DIR/$tfile should not exist"
	touch $DIR/$tfile-2 || error "touch $DIR/$tfile-2 failed"
	return 0
}
run_test 15 "open(O_CREAT), unlink |X|  touch new, close"
test_16() {
	replay_barrier $SINGLEMDS
	mcreate $DIR/$tfile
	unlink $DIR/$tfile
	mcreate $DIR/$tfile-2
	fail $SINGLEMDS
	[ -e $DIR/$tfile ] && error "file $DIR/$tfile should not exist"
	[ -e $DIR/$tfile-2 ] || error "file $DIR/$tfile-2 does not exist"
	unlink $DIR/$tfile-2 || error "unlink $DIR/$tfile-2 failed"
}
run_test 16 "|X| open(O_CREAT), unlink, touch new,  unlink new"
test_17() {
	replay_barrier $SINGLEMDS
	multiop_bg_pause $DIR/$tfile O_c ||
		error "multiop_bg_pause $DIR/$tfile failed"
	pid=$!
	fail $SINGLEMDS
	kill -USR1 $pid || error "multiop $pid not running"
	wait $pid || error "multiop $pid failed"
	$CHECKSTAT -t file $DIR/$tfile ||
		error "$CHECKSTAT $DIR/$tfile attribute check failed"
	rm $DIR/$tfile
}
run_test 17 "|X| open(O_CREAT), |replay| close"
test_18() {
	replay_barrier $SINGLEMDS
	multiop_bg_pause $DIR/$tfile O_tSc ||
		error "multiop_bg_pause $DIR/$tfile failed"
	pid=$!
	rm -f $DIR/$tfile
	touch $DIR/$tfile-2 || error "touch $DIR/$tfile-2 failed"
	echo "pid: $pid will close"
	kill -USR1 $pid || error "multiop $pid not running"
	wait $pid || error "multiop $pid failed"
	fail $SINGLEMDS
	[ -e $DIR/$tfile ] && error "file $DIR/$tfile should not exist"
	[ -e $DIR/$tfile-2 ] || error "file $DIR/$tfile-2 does not exist"
	touch $DIR/$tfile-3 || error "touch $DIR/$tfile-3 failed"
	unlink $DIR/$tfile-2 || error "unlink $DIR/$tfile-2 failed"
	unlink $DIR/$tfile-3 || error "unlink $DIR/$tfile-3 failed"
	return 0
}
run_test 18 "open(O_CREAT), unlink, touch new, close, touch, unlink"
test_19() {
	replay_barrier $SINGLEMDS
	mcreate $DIR/$tfile
	echo "old" > $DIR/$tfile
	mv $DIR/$tfile $DIR/$tfile-2
	grep old $DIR/$tfile-2
	fail $SINGLEMDS
	grep old $DIR/$tfile-2 || error "grep $DIR/$tfile-2 failed"
}
run_test 19 "mcreate, open, write, rename "
test_20a() {
	replay_barrier $SINGLEMDS
	multiop_bg_pause $DIR/$tfile O_tSc ||
		error "multiop_bg_pause $DIR/$tfile failed"
	pid=$!
	rm -f $DIR/$tfile
	fail $SINGLEMDS
	kill -USR1 $pid || error "multiop $pid not running"
	wait $pid || error "multiop $pid failed"
	[ -e $DIR/$tfile ] && error "file $DIR/$tfile should not exist"
	return 0
}
run_test 20a "|X| open(O_CREAT), unlink, replay, close (test mds_cleanup_orphans)"
test_20b() {
	local wait_timeout=$((TIMEOUT * 4))
	local extra=$(fs_log_size)
	local n_attempts=1
	sync_all_data
	save_layout_restore_at_exit $MOUNT
	$LFS setstripe -i 0 -c 1 $DIR
	local beforeused=$(df -P $DIR | tail -1 | awk '{ print $3 }')
	dd if=/dev/zero of=$DIR/$tfile bs=4k count=10000 &
	while [ ! -e $DIR/$tfile ] ; do
		sleep 0.01
	done
	$LFS getstripe $DIR/$tfile || error "$LFS getstripe $DIR/$tfile failed"
	rm -f $DIR/$tfile || error "rm -f $DIR/$tfile failed"
	mds_evict_client
	client_up || client_up || true
	do_facet $SINGLEMDS "lctl set_param -n osd*.*MDT*.force_sync=1"
	fail $SINGLEMDS
	wait_recovery_complete $SINGLEMDS || error "MDS recovery not done"
	wait_delete_completed $wait_timeout || error "delete did not finish"
	sync_all_data
	while true; do
		local afterused=$(df -P $DIR | tail -1 | awk '{ print $3 }')
		log "before $beforeused, after $afterused"
		(( $beforeused + $extra >= $afterused )) && break
		n_attempts=$((n_attempts + 1))
		[ $n_attempts -gt 3 ] &&
			error "after $afterused > before $beforeused + $extra"
		wait_zfs_commit $SINGLEMDS 5
		sync_all_data
	done
}
run_test 20b "write, unlink, eviction, replay (test mds_cleanup_orphans)"
test_20c() {
	multiop_bg_pause $DIR/$tfile Ow_c ||
		error "multiop_bg_pause $DIR/$tfile failed"
	pid=$!
	ls -la $DIR/$tfile
	mds_evict_client
	client_up || client_up || true
	kill -USR1 $pid || error "multiop $pid not running"
	wait $pid || error "multiop $pid failed"
	[ -s $DIR/$tfile ] || error "File was truncated"
	return 0
}
run_test 20c "check that client eviction does not affect file content"
test_21() {
	replay_barrier $SINGLEMDS
	multiop_bg_pause $DIR/$tfile O_tSc ||
		error "multiop_bg_pause $DIR/$tfile failed"
	pid=$!
	rm -f $DIR/$tfile
	touch $DIR/$tfile-1 || error "touch $DIR/$tfile-1 failed"
	fail $SINGLEMDS
	kill -USR1 $pid || error "multiop $pid not running"
	wait $pid || error "multiop $pid failed"
	[ -e $DIR/$tfile ] && error "file $DIR/$tfile should not exist"
	touch $DIR/$tfile-2 || error "touch $DIR/$tfile-2 failed"
	return 0
}
run_test 21 "|X| open(O_CREAT), unlink touch new, replay, close (test mds_cleanup_orphans)"
test_22() {
	multiop_bg_pause $DIR/$tfile O_tSc ||
		error "multiop_bg_pause $DIR/$tfile failed"
	pid=$!
	replay_barrier $SINGLEMDS
	rm -f $DIR/$tfile
	fail $SINGLEMDS
	kill -USR1 $pid || error "multiop $pid not running"
	wait $pid || error "multiop $pid failed"
	[ -e $DIR/$tfile ] && error "file $DIR/$tfile should not exist"
	return 0
}
run_test 22 "open(O_CREAT), |X| unlink, replay, close (test mds_cleanup_orphans)"
test_23() {
	multiop_bg_pause $DIR/$tfile O_tSc ||
		error "multiop_bg_pause $DIR/$tfile failed"
	pid=$!
	replay_barrier $SINGLEMDS
	rm -f $DIR/$tfile
	touch $DIR/$tfile-1 || error "touch $DIR/$tfile-1 failed"
	fail $SINGLEMDS
	kill -USR1 $pid || error "multiop $pid not running"
	wait $pid || error "multiop $pid failed"
	[ -e $DIR/$tfile ] && error "file $DIR/$tfile should not exist"
	touch $DIR/$tfile-2 || error "touch $DIR/$tfile-2 failed"
	return 0
}
run_test 23 "open(O_CREAT), |X| unlink touch new, replay, close (test mds_cleanup_orphans)"
test_24() {
	multiop_bg_pause $DIR/$tfile O_tSc ||
		error "multiop_bg_pause $DIR/$tfile failed"
	pid=$!
	replay_barrier $SINGLEMDS
	fail $SINGLEMDS
	rm -f $DIR/$tfile
	kill -USR1 $pid || error "multiop $pid not running"
	wait $pid || error "multiop $pid failed"
	[ -e $DIR/$tfile ] && error "file $DIR/$tfile should not exist"
	return 0
}
run_test 24 "open(O_CREAT), replay, unlink, close (test mds_cleanup_orphans)"
test_25() {
	multiop_bg_pause $DIR/$tfile O_tSc ||
		error "multiop_bg_pause $DIR/$tfile failed"
	pid=$!
	rm -f $DIR/$tfile
	replay_barrier $SINGLEMDS
	fail $SINGLEMDS
	kill -USR1 $pid || error "multiop $pid not running"
	wait $pid || error "multiop $pid failed"
	[ -e $DIR/$tfile ] && error "file $DIR/$tfile should not exist"
	return 0
}
run_test 25 "open(O_CREAT), unlink, replay, close (test mds_cleanup_orphans)"
test_26() {
	replay_barrier $SINGLEMDS
	multiop_bg_pause $DIR/$tfile-1 O_tSc ||
		error "multiop_bg_pause $DIR/$tfile-1 failed"
	pid1=$!
	multiop_bg_pause $DIR/$tfile-2 O_tSc ||
		error "multiop_bg_pause $DIR/$tfile-2 failed"
	pid2=$!
	rm -f $DIR/$tfile-1
	rm -f $DIR/$tfile-2
	kill -USR1 $pid2 || error "second multiop $pid2 not running"
	wait $pid2 || error "second multiop $pid2 failed"
	fail $SINGLEMDS
	kill -USR1 $pid1 || error "multiop $pid1 not running"
	wait $pid1 || error "multiop $pid1 failed"
	[ -e $DIR/$tfile-1 ] && error "file $DIR/$tfile-1 should not exist"
	[ -e $DIR/$tfile-2 ] && error "file $DIR/$tfile-2 should not exist"
	return 0
}
run_test 26 "|X| open(O_CREAT), unlink two, close one, replay, close one (test mds_cleanup_orphans)"
test_27() {
	replay_barrier $SINGLEMDS
	multiop_bg_pause $DIR/$tfile-1 O_tSc ||
		error "multiop_bg_pause $DIR/$tfile-1 failed"
	pid1=$!
	multiop_bg_pause $DIR/$tfile-2 O_tSc ||
		error "multiop_bg_pause $DIR/$tfile-2 failed"
	pid2=$!
	rm -f $DIR/$tfile-1
	rm -f $DIR/$tfile-2
	fail $SINGLEMDS
	kill -USR1 $pid1 || error "multiop $pid1 not running"
	wait $pid1 || error "multiop $pid1 failed"
	kill -USR1 $pid2 || error "second multiop $pid2 not running"
	wait $pid2 || error "second multiop $pid2 failed"
	[ -e $DIR/$tfile-1 ] && error "file $DIR/$tfile-1 should not exist"
	[ -e $DIR/$tfile-2 ] && error "file $DIR/$tfile-2 should not exist"
	return 0
}
run_test 27 "|X| open(O_CREAT), unlink two, replay, close two (test mds_cleanup_orphans)"
test_28() {
	multiop_bg_pause $DIR/$tfile-1 O_tSc ||
		error "multiop_bg_pause $DIR/$tfile-1 failed"
	pid1=$!
	multiop_bg_pause $DIR/$tfile-2 O_tSc ||
		error "multiop_bg_pause $DIR/$tfile-2 failed"
	pid2=$!
	replay_barrier $SINGLEMDS
	rm -f $DIR/$tfile-1
	rm -f $DIR/$tfile-2
	kill -USR1 $pid2 || error "second multiop $pid2 not running"
	wait $pid2 || error "second multiop $pid2 failed"
	fail $SINGLEMDS
	kill -USR1 $pid1 || error "multiop $pid1 not running"
	wait $pid1 || error "multiop $pid1 failed"
	[ -e $DIR/$tfile-1 ] && error "file $DIR/$tfile-1 should not exist"
	[ -e $DIR/$tfile-2 ] && error "file $DIR/$tfile-2 should not exist"
	return 0
}
run_test 28 "open(O_CREAT), |X| unlink two, close one, replay, close one (test mds_cleanup_orphans)"
test_29() {
	multiop_bg_pause $DIR/$tfile-1 O_tSc ||
		error "multiop_bg_pause $DIR/$tfile-1 failed"
	pid1=$!
	multiop_bg_pause $DIR/$tfile-2 O_tSc ||
		error "multiop_bg_pause $DIR/$tfile-2 failed"
	pid2=$!
	replay_barrier $SINGLEMDS
	rm -f $DIR/$tfile-1
	rm -f $DIR/$tfile-2
	fail $SINGLEMDS
	kill -USR1 $pid1 || error "multiop $pid1 not running"
	wait $pid1 || error "multiop $pid1 failed"
	kill -USR1 $pid2 || error "second multiop $pid2 not running"
	wait $pid2 || error "second multiop $pid2 failed"
	[ -e $DIR/$tfile-1 ] && error "file $DIR/$tfile-1 should not exist"
	[ -e $DIR/$tfile-2 ] && error "file $DIR/$tfile-2 should not exist"
	return 0
}
run_test 29 "open(O_CREAT), |X| unlink two, replay, close two (test mds_cleanup_orphans)"
test_30() {
	multiop_bg_pause $DIR/$tfile-1 O_tSc ||
		error "multiop_bg_pause $DIR/$tfile-1 failed"
	pid1=$!
	multiop_bg_pause $DIR/$tfile-2 O_tSc ||
		error "multiop_bg_pause $DIR/$tfile-2 failed"
	pid2=$!
	rm -f $DIR/$tfile-1
	rm -f $DIR/$tfile-2
	replay_barrier $SINGLEMDS
	fail $SINGLEMDS
	kill -USR1 $pid1 || error "multiop $pid1 not running"
	wait $pid1 || error "multiop $pid1 failed"
	kill -USR1 $pid2 || error "second multiop $pid2 not running"
	wait $pid2 || error "second multiop $pid2 failed"
	[ -e $DIR/$tfile-1 ] && error "file $DIR/$tfile-1 should not exist"
	[ -e $DIR/$tfile-2 ] && error "file $DIR/$tfile-2 should not exist"
	return 0
}
run_test 30 "open(O_CREAT) two, unlink two, replay, close two (test mds_cleanup_orphans)"
test_31() {
	multiop_bg_pause $DIR/$tfile-1 O_tSc ||
		error "multiop_bg_pause $DIR/$tfile-1 failed"
	pid1=$!
	multiop_bg_pause $DIR/$tfile-2 O_tSc ||
		error "multiop_bg_pause $DIR/$tfile-2 failed"
	pid2=$!
	rm -f $DIR/$tfile-1
	replay_barrier $SINGLEMDS
	rm -f $DIR/$tfile-2
	fail $SINGLEMDS
	kill -USR1 $pid1 || error "multiop $pid1 not running"
	wait $pid1 || error "multiop $pid1 failed"
	kill -USR1 $pid2 || error "second multiop $pid2 not running"
	wait $pid2 || error "second multiop $pid2 failed"
	[ -e $DIR/$tfile-1 ] && error "file $DIR/$tfile-1 should not exist"
	[ -e $DIR/$tfile-2 ] && error "file $DIR/$tfile-2 should not exist"
	return 0
}
run_test 31 "open(O_CREAT) two, unlink one, |X| unlink one, close two (test mds_cleanup_orphans)"
test_32() {
	multiop_bg_pause $DIR/$tfile O_c ||
		error "multiop_bg_pause $DIR/$tfile failed"
	pid1=$!
	multiop_bg_pause $DIR/$tfile O_c ||
		error "second multiop_bg_pause $DIR/$tfile failed"
	pid2=$!
	mds_evict_client
	client_up || client_up || error "client_up failed"
	kill -USR1 $pid1 || error "multiop $pid1 not running"
	kill -USR1 $pid2 || error "second multiop $pid2 not running"
	wait $pid1 || error "multiop $pid1 failed"
	wait $pid2 || error "second multiop $pid2 failed"
	return 0
}
run_test 32 "close() notices client eviction; close() after client eviction"
test_33a() {
	createmany -o $DIR/$tfile-%d 10 ||
		error "createmany create $DIR/$tfile failed"
	replay_barrier_nosync $SINGLEMDS
	fail_abort $SINGLEMDS
	createmany -o $DIR/$tfile--%d 10 ||
		error "createmany recreate $DIR/$tfile failed"
	rm $DIR/$tfile-* -f
	return 0
}
run_test 33a "fid seq shouldn't be reused after abort recovery"
test_33b() {
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x1311"
	createmany -o $DIR/$tfile-%d 10
	replay_barrier_nosync $SINGLEMDS
	fail_abort $SINGLEMDS
	createmany -o $DIR/$tfile--%d 10 ||
		error "createmany recreate $DIR/$tfile failed"
	rm $DIR/$tfile-* -f
	return 0
}
run_test 33b "test fid seq allocation"
test_34() {
	multiop_bg_pause $DIR/$tfile O_c ||
		error "multiop_bg_pause $DIR/$tfile failed"
	pid=$!
	rm -f $DIR/$tfile
	replay_barrier $SINGLEMDS
	fail_abort $SINGLEMDS
	kill -USR1 $pid || error "multiop $pid not running"
	wait $pid || error "multiop $pid failed"
	[ -e $DIR/$tfile ] && error "file $DIR/$tfile should not exist"
	sync
	return 0
}
run_test 34 "abort recovery before client does replay (test mds_cleanup_orphans)"
test_35() {
	touch $DIR/$tfile || error "touch $DIR/$tfile failed"
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x80000119"
	rm -f $DIR/$tfile &
	sleep 1
	sync
	sleep 1
	fail_abort $SINGLEMDS
	$CHECKSTAT -t file $DIR/$tfile &&
		error "$CHECKSTAT $DIR/$tfile attribute check should fail" ||
		true
}
run_test 35 "test recovery from llog for unlink op"
test_36() {
	replay_barrier $SINGLEMDS
	touch $DIR/$tfile
	checkstat $DIR/$tfile
	facet_failover $SINGLEMDS
	cancel_lru_locks mdc
	if do_facet $SINGLEMDS $LCTL dk | grep "stale lock .*cookie"; then
		error "cancel after replay failed"
	fi
}
run_test 36 "don't resend cancel"
test_37() {
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $tdir failed"
	rmdir $DIR/$tdir/$tfile 2>/dev/null
	multiop_bg_pause $DIR/$tdir/$tfile dD_c ||
		error "multiop_bg_pause $tfile failed"
	pid=$!
	rmdir $DIR/$tdir/$tfile
	replay_barrier $SINGLEMDS
	do_facet $SINGLEMDS dmesg -c >/dev/null
	fail_abort $SINGLEMDS
	kill -USR1 $pid || error "multiop $pid not running"
	do_facet $SINGLEMDS dmesg | grep "error unlinking orphan" &&
		error "error unlinking files"
	wait $pid || error "multiop $pid failed"
	sync
	return 0
}
run_test 37 "abort recovery before client does replay (test mds_cleanup_orphans for directories)"
test_38() {
	createmany -o $DIR/$tfile-%d 800 ||
		error "createmany -o $DIR/$tfile failed"
	unlinkmany $DIR/$tfile-%d 0 400 || error "unlinkmany $DIR/$tfile failed"
	replay_barrier $SINGLEMDS
	fail $SINGLEMDS
	unlinkmany $DIR/$tfile-%d 400 400 ||
		error "unlinkmany $DIR/$tfile 400 failed"
	sleep 2
	$CHECKSTAT -t file $DIR/$tfile-* &&
		error "$CHECKSTAT $DIR/$tfile-* attribute check should fail" ||
		true
}
run_test 38 "test recovery from unlink llog (test llog_gen_rec) "
test_39() {
	createmany -o $DIR/$tfile-%d 800 ||
		error "createmany -o $DIR/$tfile failed"
	replay_barrier $SINGLEMDS
	unlinkmany $DIR/$tfile-%d 0 400
	fail $SINGLEMDS
	unlinkmany $DIR/$tfile-%d 400 400 ||
		error "unlinkmany $DIR/$tfile 400 failed"
	sleep 2
	$CHECKSTAT -t file $DIR/$tfile-* &&
		error "$CHECKSTAT $DIR/$tfile-* attribute check should fail" ||
		true
}
run_test 39 "test recovery from unlink llog (test llog_gen_rec) "
count_ost_writes() {
    lctl get_param -n osc.*.stats | awk -vwrites=0 '/ost_write/ { writes += $2 } END { print writes; }'
}
test_41() {
	[ $OSTCOUNT -lt 2 ] && skip_env "needs >= 2 OSTs" && return
	local f=$MOUNT/$tfile
	$LFS setstripe -S $((128 * 1024)) -i 0 $f
	do_facet client dd if=/dev/zero of=$f bs=4k count=1 ||
		error "dd on client failed"
	cancel_lru_locks osc
	local mdtosc=$(get_mdtosc_proc_path $SINGLEMDS $ost2_svc)
	local osc2dev=$(do_facet $SINGLEMDS "lctl get_param -n devices" |
		grep $mdtosc | awk '{print $1}')
	[ -z "$osc2dev" ] && echo "OST: $ost2_svc" &&
		lctl get_param -n devices &&
		error "OST 2 $osc2dev does not exist"
	do_facet $SINGLEMDS $LCTL --device $osc2dev deactivate ||
		error "deactive device on $SINGLEMDS failed"
	do_facet client dd if=$f of=/dev/null bs=4k count=1 ||
		error "second dd on client failed"
	do_facet $SINGLEMDS $LCTL --device $osc2dev activate ||
		error "active device on $SINGLEMDS failed"
	return 0
}
run_test 41 "read from a valid osc while other oscs are invalid"
test_42() {
	blocks=$(df -P $MOUNT | tail -n 1 | awk '{ print $2 }')
	createmany -o $DIR/$tfile-%d 800 ||
		error "createmany -o $DIR/$tfile failed"
	replay_barrier ost1
	unlinkmany $DIR/$tfile-%d 0 400
	debugsave
	lctl set_param debug=-1
	facet_failover ost1
	echo "wait for MDS to timeout and recover"
	sleep $((TIMEOUT * 2))
	debugrestore
	unlinkmany $DIR/$tfile-%d 400 400 ||
		error "unlinkmany $DIR/$tfile 400 failed"
	$CHECKSTAT -t file $DIR/$tfile-* &&
		error "$CHECKSTAT $DIR/$tfile-* attribute check should fail" ||
		true
}
run_test 42 "recovery after ost failure"
test_43() {
	remote_ost_nodsh && skip "remote OST with nodsh" && return 0
	replay_barrier $SINGLEMDS
	do_facet ost1 "lctl set_param fail_loc=0x80000204"
	fail $SINGLEMDS
	sleep 10
	return 0
}
run_test 43 "mds osc import failure during recovery; don't LBUG"
test_44a() {
	local at_max_saved=0
	local mdcdev=$($LCTL dl |
		awk "/${FSNAME}-MDT0000-mdc-/ {if (\$2 == \"UP\") {print \$1}}")
	[ "$mdcdev" ] || error "${FSNAME}-MDT0000-mdc- not UP"
	[ $(echo $mdcdev | wc -w) -eq 1 ] ||
		{ $LCTL dl; error "looking for mdcdev=$mdcdev"; }
	if at_is_enabled; then
		at_max_saved=$(at_max_get mds)
		at_max_set 40 mds
	fi
	for i in $(seq 1 10); do
		echo "$i of 10 ($(date +%s))"
		do_facet $SINGLEMDS \
			"lctl get_param -n md[ts].*.mdt.timeouts | grep service"
		do_facet $SINGLEMDS "lctl set_param fail_loc=0x80000701"
		$LCTL --device $mdcdev recover
		$LFS df $MOUNT
	done
	do_facet $SINGLEMDS "lctl set_param fail_loc=0"
	[ $at_max_saved -ne 0 ] && at_max_set $at_max_saved mds
	return 0
}
run_test 44a "race in target handle connect"
test_44b() {
	local mdcdev=$($LCTL dl |
		awk "/${FSNAME}-MDT0000-mdc-/ {if (\$2 == \"UP\") {print \$1}}")
	[ "$mdcdev" ] || error "${FSNAME}-MDT0000-mdc not up"
	[ $(echo $mdcdev | wc -w) -eq 1 ] ||
		{ echo mdcdev=$mdcdev; $LCTL dl;
		  error "more than one ${FSNAME}-MDT0000-mdc"; }
	for i in $(seq 1 10); do
		echo "$i of 10 ($(date +%s))"
		do_facet $SINGLEMDS \
			"lctl get_param -n md[ts].*.mdt.timeouts | grep service"
		do_facet $SINGLEMDS "lctl set_param fail_loc=0x80000704"
		$LCTL --device $mdcdev recover
		df $MOUNT
	done
	return 0
}
run_test 44b "race in target handle connect"
test_44c() {
	replay_barrier $SINGLEMDS
	createmany -m $DIR/$tfile-%d 100 || error "failed to create directories"
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x80000712"
	fail_abort $SINGLEMDS
	unlinkmany $DIR/$tfile-%d 100 && error "unliked after fail abort"
	fail $SINGLEMDS
	unlinkmany $DIR/$tfile-%d 100 && error "unliked after fail"
	return 0
}
run_test 44c "race in target handle connect"
test_45() {
	local mdcdev=$($LCTL get_param -n devices |
		awk "/ ${FSNAME}-MDT0000-mdc-/ {print \$1}")
	[ "$mdcdev" ] || error "${FSNAME}-MDT0000-mdc not up"
	[ $(echo $mdcdev | wc -w) -eq 1 ] ||
		{ echo mdcdev=$mdcdev; $LCTL dl;
		  error "more than one ${FSNAME}-MDT0000-mdc"; }
	$LCTL --device $mdcdev recover ||
		error "$LCTL --device $mdcdev recover failed"
	multiop_bg_pause $DIR/$tfile O_c ||
		error "multiop_bg_pause $DIR/$tfile failed"
	pid=$!
	$LCTL --device $mdcdev deactivate ||
		error "$LCTL --device $mdcdev deactivate failed"
	kill -USR1 $pid || error "multiop $pid not running"
	wait $pid || error "multiop $pid failed"
	$LCTL --device $mdcdev activate ||
		error "$LCTL --device $mdcdev activate failed"
	sleep 1
	$CHECKSTAT -t file $DIR/$tfile ||
		error "$CHECKSTAT $DIR/$tfile attribute check failed"
	return 0
}
run_test 45 "Handle failed close"
test_46() {
	drop_reply "touch $DIR/$tfile"
	fail $SINGLEMDS
	local FID=$($LFS path2fid $tfile)
	$LCTL dk | grep -i "force closing file handle $FID" &&
		error "found force closing in dmesg"
	return 0
}
run_test 46 "Don't leak file handle after open resend (3325)"
test_47() {
	remote_ost_nodsh && skip "remote OST with nodsh" && return 0
	createmany -o $DIR/$tfile 20  ||
		error "createmany create $DIR/$tfile failed"
	fail ost1
	do_facet ost1 "lctl set_param fail_loc=0x80000204"
	client_up || error "client_up failed"
	sleep $((3 * TIMEOUT))
	createmany -o $DIR/$tfile 20 ||
		error "createmany recraete $DIR/$tfile failed"
	unlinkmany $DIR/$tfile 20 || error "unlinkmany $DIR/$tfile failed"
	return 0
}
run_test 47 "MDS->OSC failure during precreate cleanup (2824)"
test_48() {
	remote_ost_nodsh && skip "remote OST with nodsh" && return 0
	[ "$OSTCOUNT" -lt "2" ] && skip_env "needs >= 2 OSTs" && return
	replay_barrier $SINGLEMDS
	createmany -o $DIR/$tfile 20  ||
		error "createmany -o $DIR/$tfile failed"
	facet_failover $SINGLEMDS
	do_facet ost1 "lctl set_param fail_loc=0x80000216"
	client_up || error "client_up failed"
	sleep $((3 * TIMEOUT))
	createmany -o $DIR/$tfile 20 20 ||
		error "createmany recraete $DIR/$tfile failed"
	unlinkmany $DIR/$tfile 40 || error "unlinkmany $DIR/$tfile failed"
	return 0
}
run_test 48 "MDS->OSC failure during precreate cleanup (2824)"
test_50() {
	local mdtosc=$(get_mdtosc_proc_path $SINGLEMDS $ost1_svc)
	local oscdev=$(do_facet $SINGLEMDS "lctl get_param -n devices" |
		grep $mdtosc | awk '{print $1}')
	[ "$oscdev" ] || error "could not find OSC device on MDS"
	do_facet $SINGLEMDS $LCTL --device $oscdev recover ||
		error "OSC device $oscdev recovery failed"
	do_facet $SINGLEMDS $LCTL --device $oscdev recover ||
		error "second OSC device $oscdev recovery failed"
	sleep 5
}
run_test 50 "Double OSC recovery, don't LASSERT (3812)"
test_52() {
	[ "$MDS1_VERSION" -lt $(version_code 2.6.90) ] &&
		skip "MDS prior to 2.6.90 handle LDLM_REPLY_NET incorrectly"
	touch $DIR/$tfile || error "touch $DIR/$tfile failed"
	cancel_lru_locks mdc
	multiop_bg_pause $DIR/$tfile s_s || error "multiop $DIR/$tfile failed"
	mpid=$!
	lctl set_param -n ldlm.cancel_unused_locks_before_replay "0"
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x80000157"
	fail $SINGLEMDS || error "fail $SINGLEMDS failed"
	kill -USR1 $mpid
	wait $mpid || error "multiop_bg_pause pid failed"
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x0"
	lctl set_param fail_loc=0x0
	lctl set_param -n ldlm.cancel_unused_locks_before_replay "1"
	rm -f $DIR/$tfile
}
run_test 52 "time out lock replay (3764)"
test_53a() {
	[[ $(lctl get_param mdc.*.import |
	     grep "connect_flags:.*multi_mod_rpc") ]] ||
		{ skip "Need MDC with 'multi_mod_rpcs' feature"; return 0; }
	cancel_lru_locks mdc
	mkdir_on_mdt0 $DIR/${tdir}-1 || error "mkdir $DIR/${tdir}-1 failed"
	mkdir_on_mdt0 $DIR/${tdir}-2 || error "mkdir $DIR/${tdir}-2 failed"
	multiop $DIR/${tdir}-1/f O_c &
	close_pid=$!
	sleep 1
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x80000115"
	kill -USR1 $close_pid
	cancel_lru_locks mdc
	do_facet $SINGLEMDS "lctl set_param fail_loc=0"
	mcreate $DIR/${tdir}-2/f || error "mcreate $DIR/${tdir}-2/f failed"
	[ -d /proc/$close_pid ] || error "close_pid doesn't exist"
	replay_barrier_nodf $SINGLEMDS
	fail $SINGLEMDS
	wait $close_pid || error "close_pid $close_pid failed"
	$CHECKSTAT -t file $DIR/${tdir}-1/f ||
		error "$CHECKSTAT $DIR/${tdir}-1/f attribute check failed"
	$CHECKSTAT -t file $DIR/${tdir}-2/f ||
		error "$CHECKSTAT $DIR/${tdir}-2/f attribute check failed"
	rm -rf $DIR/${tdir}-*
}
run_test 53a "|X| close request while two MDC requests in flight"
test_53b() {
	cancel_lru_locks mdc
	mkdir_on_mdt0 $DIR/${tdir}-1 || error "mkdir $DIR/${tdir}-1 failed"
	mkdir_on_mdt0 $DIR/${tdir}-2 || error "mkdir $DIR/${tdir}-2 failed"
	multiop_bg_pause $DIR/${tdir}-1/f O_c ||
		error "multiop_bg_pause $DIR/${tdir}-1/f failed"
	close_pid=$!
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x80000107"
	mcreate $DIR/${tdir}-2/f &
	open_pid=$!
	sleep 1
	do_facet $SINGLEMDS "lctl set_param fail_loc=0"
	kill -USR1 $close_pid
	cancel_lru_locks mdc
	wait $close_pid || error "close_pid $close_pid failed"
	[ -d /proc/$open_pid ] || error "open_pid doesn't exist"
	replay_barrier_nodf $SINGLEMDS
	fail $SINGLEMDS
	wait $open_pid || error "open_pid failed"
	$CHECKSTAT -t file $DIR/${tdir}-1/f ||
		error "$CHECKSTAT $DIR/${tdir}-1/f attribute check failed"
	$CHECKSTAT -t file $DIR/${tdir}-2/f ||
		error "$CHECKSTAT $DIR/${tdir}-2/f attribute check failed"
	rm -rf $DIR/${tdir}-*
}
run_test 53b "|X| open request while two MDC requests in flight"
test_53c() {
	cancel_lru_locks mdc
	mkdir_on_mdt0 $DIR/${tdir}-1 || error "mkdir $DIR/${tdir}-1 failed"
	mkdir_on_mdt0 $DIR/${tdir}-2 || error "mkdir $DIR/${tdir}-2 failed"
	multiop $DIR/${tdir}-1/f O_c &
	close_pid=$!
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x80000107"
	mcreate $DIR/${tdir}-2/f &
	open_pid=$!
	sleep 1
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x80000115"
	kill -USR1 $close_pid
	cancel_lru_locks mdc
	[ -d /proc/$close_pid ] || error "close_pid doesn't exist"
	[ -d /proc/$open_pid ] || error "open_pid doesn't exists"
	replay_barrier_nodf $SINGLEMDS
	fail_nodf $SINGLEMDS
	wait $open_pid || error "open_pid failed"
	sleep 2
	[ -d /proc/$close_pid ] && error "close_pid should not exist"
	do_facet $SINGLEMDS "lctl set_param fail_loc=0"
	$CHECKSTAT -t file $DIR/${tdir}-1/f ||
		error "$CHECKSTAT $DIR/${tdir}-1/f attribute check failed"
	$CHECKSTAT -t file $DIR/${tdir}-2/f ||
		error "$CHECKSTAT $DIR/${tdir}-2/f attribute check failed"
	rm -rf $DIR/${tdir}-*
}
run_test 53c "|X| open request and close request while two MDC requests in flight"
test_53d() {
	[[ $(lctl get_param mdc.*.import |
	     grep "connect_flags:.*multi_mod_rpc") ]] ||
		{ skip "Need MDC with 'multi_mod_rpcs' feature"; return 0; }
	cancel_lru_locks mdc
	mkdir_on_mdt0 $DIR/${tdir}-1 || error "mkdir $DIR/${tdir}-1 failed"
	mkdir_on_mdt0 $DIR/${tdir}-2 || error "mkdir $DIR/${tdir}-2 failed"
	multiop $DIR/${tdir}-1/f O_c &
	close_pid=$!
	sleep 1
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x8000013b"
	kill -USR1 $close_pid
	cancel_lru_locks mdc
	do_facet $SINGLEMDS "lctl set_param fail_loc=0"
	mcreate $DIR/${tdir}-2/f || error "mcreate $DIR/${tdir}-2/f failed"
	[ -d /proc/$close_pid ] || error "close_pid doesn't exist"
	fail $SINGLEMDS
	wait $close_pid || error "close_pid failed"
	$CHECKSTAT -t file $DIR/${tdir}-1/f ||
		error "$CHECKSTAT $DIR/${tdir}-1/f attribute check failed"
	$CHECKSTAT -t file $DIR/${tdir}-2/f ||
		error "$CHECKSTAT $DIR/${tdir}-2/f attribute check failed"
	rm -rf $DIR/${tdir}-*
}
run_test 53d "close reply while two MDC requests in flight"
test_53e() {
	cancel_lru_locks mdc
	mkdir_on_mdt0 $DIR/${tdir}-1 || error "mkdir $DIR/${tdir}-1 failed"
	mkdir_on_mdt0 $DIR/${tdir}-2 || error "mkdir $DIR/${tdir}-2 failed"
	multiop $DIR/${tdir}-1/f O_c &
	close_pid=$!
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x119"
	mcreate $DIR/${tdir}-2/f &
	open_pid=$!
	sleep 1
	do_facet $SINGLEMDS "lctl set_param fail_loc=0"
	kill -USR1 $close_pid
	cancel_lru_locks mdc
	wait $close_pid || error "close_pid failed"
	[ -d /proc/$open_pid ] || error "open_pid doesn't exists"
	replay_barrier_nodf $SINGLEMDS
	fail $SINGLEMDS
	wait $open_pid || error "open_pid failed"
	$CHECKSTAT -t file $DIR/${tdir}-1/f ||
		error "$CHECKSTAT $DIR/${tdir}-1/f attribute check failed"
	$CHECKSTAT -t file $DIR/${tdir}-2/f ||
		error "$CHECKSTAT $DIR/${tdir}-2/f attribute check failed"
	rm -rf $DIR/${tdir}-*
}
run_test 53e "|X| open reply while two MDC requests in flight"
test_53f() {
	cancel_lru_locks mdc
	mkdir_on_mdt0 $DIR/${tdir}-1 || error "mkdir $DIR/${tdir}-1 failed"
	mkdir_on_mdt0 $DIR/${tdir}-2 || error "mkdir $DIR/${tdir}-2 failed"
	multiop $DIR/${tdir}-1/f O_c &
	close_pid=$!
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x119"
	mcreate $DIR/${tdir}-2/f &
	open_pid=$!
	sleep 1
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x8000013b"
	kill -USR1 $close_pid
	cancel_lru_locks mdc
	[ -d /proc/$close_pid ] || error "close_pid doesn't exist"
	[ -d /proc/$open_pid ] || error "open_pid doesn't exists"
	replay_barrier_nodf $SINGLEMDS
	fail_nodf $SINGLEMDS
	wait $open_pid || error "open_pid failed"
	sleep 2
	[ -d /proc/$close_pid ] && error "close_pid should not exist"
	do_facet $SINGLEMDS "lctl set_param fail_loc=0"
	$CHECKSTAT -t file $DIR/${tdir}-1/f ||
		error "$CHECKSTAT $DIR/${tdir}-1/f attribute check failed"
	$CHECKSTAT -t file $DIR/${tdir}-2/f ||
		error "$CHECKSTAT $DIR/${tdir}-2/f attribute check failed"
	rm -rf $DIR/${tdir}-*
}
run_test 53f "|X| open reply and close reply while two MDC requests in flight"
test_53g() {
	cancel_lru_locks mdc
	mkdir_on_mdt0 $DIR/${tdir}-1 || error "mkdir $DIR/${tdir}-1 failed"
	mkdir_on_mdt0 $DIR/${tdir}-2 || error "mkdir $DIR/${tdir}-2 failed"
	multiop $DIR/${tdir}-1/f O_c &
	close_pid=$!
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x119"
	mcreate $DIR/${tdir}-2/f &
	open_pid=$!
	sleep 1
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x80000115"
	kill -USR1 $close_pid
	cancel_lru_locks mdc
	do_facet $SINGLEMDS "lctl set_param fail_loc=0"
	[ -d /proc/$close_pid ] || error "close_pid doesn't exist"
	[ -d /proc/$open_pid ] || error "open_pid doesn't exists"
	replay_barrier_nodf $SINGLEMDS
	fail_nodf $SINGLEMDS
	wait $open_pid || error "open_pid failed"
	sleep 2
	[ -d /proc/$close_pid ] && error "close_pid should not exist"
	$CHECKSTAT -t file $DIR/${tdir}-1/f ||
		error "$CHECKSTAT $DIR/${tdir}-1/f attribute check failed"
	$CHECKSTAT -t file $DIR/${tdir}-2/f ||
		error "$CHECKSTAT $DIR/${tdir}-2/f attribute check failed"
	rm -rf $DIR/${tdir}-*
}
run_test 53g "|X| drop open reply and close request while close and open are both in flight"
test_53h() {
	cancel_lru_locks mdc
	mkdir_on_mdt0 $DIR/${tdir}-1 || error "mkdir $DIR/${tdir}-1 failed"
	mkdir_on_mdt0 $DIR/${tdir}-2 || error "mkdir $DIR/${tdir}-2 failed"
	multiop $DIR/${tdir}-1/f O_c &
	close_pid=$!
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x80000107"
	mcreate $DIR/${tdir}-2/f &
	open_pid=$!
	sleep 1
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x8000013b"
	kill -USR1 $close_pid
	cancel_lru_locks mdc
	sleep 1
	[ -d /proc/$close_pid ] || error "close_pid doesn't exist"
	[ -d /proc/$open_pid ] || error "open_pid doesn't exists"
	replay_barrier_nodf $SINGLEMDS
	fail_nodf $SINGLEMDS
	wait $open_pid || error "open_pid failed"
	sleep 2
	[ -d /proc/$close_pid ] && error "close_pid should not exist"
	do_facet $SINGLEMDS "lctl set_param fail_loc=0"
	$CHECKSTAT -t file $DIR/${tdir}-1/f ||
		error "$CHECKSTAT $DIR/${tdir}-1/f attribute check failed"
	$CHECKSTAT -t file $DIR/${tdir}-2/f ||
		error "$CHECKSTAT $DIR/${tdir}-2/f attribute check failed"
	rm -rf $DIR/${tdir}-*
}
run_test 53h "open request and close reply while two MDC requests in flight"
test_55() {
    do_facet $SINGLEMDS "lctl set_param fail_loc=0x8000012b"
    touch $DIR/$tfile &
    sleep 5
    do_facet $SINGLEMDS "lctl set_param fail_loc=0x0"
    rm $DIR/$tfile
    return 0
}
run_test 55 "let MDS_CHECK_RESENT return the original return code instead of 0"
test_56() {
    ln -s foo $DIR/$tfile
    replay_barrier $SINGLEMDS
    fail $SINGLEMDS
    sleep 10
}
run_test 56 "don't replay a symlink open request (3440)"
test_57() {
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x8000012c"
	touch $DIR/$tfile || error "touch $DIR/$tfile failed"
	replay_barrier $SINGLEMDS
	fail $SINGLEMDS
	wait_recovery_complete $SINGLEMDS || error "MDS recovery is not done"
	wait_mds_ost_sync || error "wait_mds_ost_sync failed"
	$CHECKSTAT -t file $DIR/$tfile ||
		error "$CHECKSTAT $DIR/$tfile attribute check failed"
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x0"
	rm $DIR/$tfile
}
run_test 57 "test recovery from llog for setattr op"
cleanup_58() {
	zconf_umount $(hostname) $MOUNT2
	trap - EXIT
}
test_58a() {
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x8000012c"
	createmany -o $DIR/$tdir/$tfile-%d 2500
	replay_barrier $SINGLEMDS
	fail $SINGLEMDS
	sleep 2
	$CHECKSTAT -t file $DIR/$tdir/$tfile-* >/dev/null ||
		error "$CHECKSTAT $DIR/$tfile-* attribute check failed"
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x0"
	unlinkmany $DIR/$tdir/$tfile-%d 2500 ||
		error "unlinkmany $DIR/$tfile failed"
	rmdir $DIR/$tdir
}
run_test 58a "test recovery from llog for setattr op (test llog_gen_rec)"
test_58b() {
	local orig
	local new
	trap cleanup_58 EXIT
	large_xattr_enabled &&
		orig="$(generate_string $(max_xattr_size))" || orig="bar"
	local sm_msg=$(printf "%.9s" $orig)
	mount_client $MOUNT2 || error "mount_client on $MOUNT2 failed"
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	touch $DIR/$tdir/$tfile || error "touch $DIR/$tdir/$tfile failed"
	replay_barrier $SINGLEMDS
	setfattr -n trusted.foo -v $orig $DIR/$tdir/$tfile
	fail $SINGLEMDS
	new=$(get_xattr_value trusted.foo $MOUNT2/$tdir/$tfile)
	[[ "$new" = "$orig" ]] ||
		error "xattr set ($sm_msg...) differs from xattr get ($new)"
	rm -f $DIR/$tdir/$tfile
	rmdir $DIR/$tdir
	cleanup_58
	wait_clients_import_state ${CLIENTS:-$HOSTNAME} "mgs" FULL
}
run_test 58b "test replay of setxattr op"
test_58c() {
	local orig
	local orig1
	local new
	trap cleanup_58 EXIT
	if large_xattr_enabled; then
		local xattr_size=$(max_xattr_size)
		orig="$(generate_string $((xattr_size / 2)))"
		orig1="$(generate_string $xattr_size)"
	else
		orig="bar"
		orig1="bar1"
	fi
	sleep $((TIMEOUT / 4))
	local sm_msg=$(printf "%.9s" $orig)
	local sm_msg1=$(printf "%.9s" $orig1)
	mount_client $MOUNT2 || error "mount_client on $MOUNT2 failed"
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	touch $DIR/$tdir/$tfile || error "touch $DIR/$tdir/$tfile failed"
	drop_request "setfattr -n trusted.foo -v $orig $DIR/$tdir/$tfile" ||
		error "drop_request for setfattr failed"
	new=$(get_xattr_value trusted.foo $MOUNT2/$tdir/$tfile)
	[[ "$new" = "$orig" ]] ||
		error "xattr set ($sm_msg...) differs from xattr get ($new)"
	drop_reint_reply "setfattr -n trusted.foo1 \
			  -v $orig1 $DIR/$tdir/$tfile" ||
		error "drop_reint_reply for setfattr failed"
	new=$(get_xattr_value trusted.foo1 $MOUNT2/$tdir/$tfile)
	[[ "$new" = "$orig1" ]] ||
		error "second xattr set ($sm_msg1...) differs xattr get ($new)"
	rm -f $DIR/$tdir/$tfile
	rmdir $DIR/$tdir
	cleanup_58
}
run_test 58c "resend/reconstruct setxattr op"
test_59() {
	remote_ost_nodsh && skip "remote OST with nodsh" && return 0
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	createmany -o $DIR/$tdir/$tfile-%d 200 ||
		error "createmany create files failed"
	sync
	unlinkmany $DIR/$tdir/$tfile-%d 200 ||
		error "unlinkmany $DIR/$tdir/$tfile failed"
	do_facet ost1 "lctl set_param fail_loc=0x507"
	fail ost1
	fail $SINGLEMDS
	do_facet ost1 "lctl set_param fail_loc=0x0"
	sleep 20
	rmdir $DIR/$tdir
}
run_test 59 "test log_commit_thread vs filter_destroy race"
test_60() {
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	createmany -o $DIR/$tdir/$tfile-%d 200 ||
		error "createmany create files failed"
	replay_barrier $SINGLEMDS
	unlinkmany $DIR/$tdir/$tfile-%d 0 100
	fail $SINGLEMDS
	unlinkmany $DIR/$tdir/$tfile-%d 100 100
	local no_ctxt=$(dmesg | grep "No ctxt")
	[ -z "$no_ctxt" ] || error "ctxt is not initialized in recovery"
}
run_test 60 "test llog post recovery init vs llog unlink"
test_61a() {
	remote_ost_nodsh && skip "remote OST with nodsh" && return 0
	local osts=$(osts_nodes)
	mkdir $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	createmany -o $DIR/$tdir/$tfile-%d 800 ||
		error "createmany create files failed"
	replay_barrier ost1
	unlinkmany $DIR/$tdir/$tfile-%d 800
	set_nodes_failloc $osts 0x80000221
	facet_failover ost1
	sleep 10
	fail ost1
	sleep 30
	set_nodes_failloc $osts 0x0
	$CHECKSTAT -t file $DIR/$tdir/$tfile-* &&
		error "$CHECKSTAT $DIR/$tdir/$tfile attribute check should fail"
	rmdir $DIR/$tdir
}
run_test 61a "test race llog recovery vs llog cleanup"
test_61b() {
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x8000013a"
	facet_failover $SINGLEMDS
	sleep 10
	fail $SINGLEMDS
	do_facet client dd if=/dev/zero of=$DIR/$tfile bs=4k count=1 ||
		error "dd failed"
}
run_test 61b "test race mds llog sync vs llog cleanup"
test_61c() {
	remote_ost_nodsh && skip "remote OST with nodsh" && return 0
	touch $DIR/$tfile || error "touch $DIR/$tfile failed"
	set_nodes_failloc $(osts_nodes) 0x80000222
	rm $DIR/$tfile
	sleep 10
	fail ost1
	set_nodes_failloc $(osts_nodes) 0x0
}
run_test 61c "test race mds llog sync vs llog cleanup"
test_61d() {
    stop mgs
    do_facet mgs "lctl set_param fail_loc=0x80000605"
    start mgs $(mgsdevname) $MGS_MOUNT_OPTS &&
	error "mgs start should have failed"
    do_facet mgs "lctl set_param fail_loc=0"
    start mgs $(mgsdevname) $MGS_MOUNT_OPTS || error "cannot restart mgs"
}
run_test 61d "error in llog_setup should cleanup the llog context correctly"
test_62() {
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	replay_barrier $SINGLEMDS
	createmany -o $DIR/$tdir/$tfile- 25 ||
		error "createmany create files failed"
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x80000707"
	fail $SINGLEMDS
	do_facet $SINGLEMDS "lctl set_param fail_loc=0"
	unlinkmany $DIR/$tdir/$tfile- 25 ||
		error "unlinkmany $DIR/$tdir/$tfile failed"
	return 0
}
run_test 62 "don't mis-drop resent replay"
AT_MAX_SET=0
at_cleanup () {
    local var
    local facet
    local at_new
    echo "Cleaning up AT ..."
    if [ -n "$ATOLDBASE" ]; then
        local at_history=$($LCTL get_param -n at_history)
        do_facet $SINGLEMDS "lctl set_param at_history=$at_history" || true
        do_facet ost1 "lctl set_param at_history=$at_history" || true
    fi
	if [ $AT_MAX_SET -ne 0 ]; then
		for facet in mds client ost; do
			var=AT_MAX_SAVE_${facet}
			echo restore AT on $facet to saved value ${!var}
			at_max_set ${!var} $facet
			at_new=$(at_max_get $facet)
			echo Restored AT value on $facet $at_new
			[ $at_new -eq ${!var} ] ||
			error "AT value not restored SAVED ${!var} NEW $at_new"
		done
	fi
}
at_start()
{
    local at_max_new=600
    local facet
    if [ $AT_MAX_SET -eq 0 ]; then
        for facet in mds client ost; do
            eval AT_MAX_SAVE_${facet}=$(at_max_get $facet)
        done
    fi
    local at_max
    for facet in mds client ost; do
        at_max=$(at_max_get $facet)
        if [ $at_max -ne $at_max_new ]; then
            echo "AT value on $facet is $at_max, set it by force temporarily to $at_max_new"
            at_max_set $at_max_new $facet
            AT_MAX_SET=1
        fi
    done
    if [ -z "$ATOLDBASE" ]; then
	ATOLDBASE=$(do_facet $SINGLEMDS "lctl get_param -n at_history")
        do_facet $SINGLEMDS "lctl set_param at_history=8" || true
        do_facet ost1 "lctl set_param at_history=8" || true
	sleep $TIMEOUT
    fi
}
test_65a()
{
    remote_ost_nodsh && skip "remote OST with nodsh" && return 0
    at_start || return 0
    $LCTL dk > /dev/null
    debugsave
    $LCTL set_param debug="other"
    REQ_DELAY=`lctl get_param -n mdc.${FSNAME}-MDT0000-mdc-*.timeouts |
               awk '/portal 12/ {print $5}'`
    REQ_DELAY=$((${REQ_DELAY} + ${REQ_DELAY} / 4 + 5))
    do_facet $SINGLEMDS lctl set_param fail_val=$((${REQ_DELAY} * 1000))
    do_facet $SINGLEMDS $LCTL set_param fail_loc=0x8000050a
    createmany -o $DIR/$tfile 10 > /dev/null
    unlinkmany $DIR/$tfile 10 > /dev/null
    $LCTL dk | grep -i "Early reply
    debugrestore
    lctl get_param -n mdc.${FSNAME}-MDT0000-mdc-*.timeouts | grep portal
    sleep 9
    lctl get_param -n mdc.${FSNAME}-MDT0000-mdc-*.timeouts | grep portal
}
run_test 65a "AT: verify early replies"
test_65b()
{
	remote_ost_nodsh && skip "remote OST with nodsh" && return 0
	at_start || return 0
	debugsave
	$LCTL set_param debug="other trace"
	$LCTL dk > /dev/null
	$LFS setstripe --stripe-index=0 --stripe-count=1 $DIR/$tfile ||
		error "$LFS setstripe failed for $DIR/$tfile"
	multiop $DIR/$tfile Ow1yc
	REQ_DELAY=`lctl get_param -n osc.${FSNAME}-OST0000-osc-*.timeouts |
		   awk '/portal 6/ {print $5}'`
	REQ_DELAY=$((${REQ_DELAY} + ${REQ_DELAY} / 4 + 5))
	do_facet ost1 lctl set_param fail_val=${REQ_DELAY}
	do_facet ost1 $LCTL set_param fail_loc=0x224
	rm -f $DIR/$tfile
	$LFS setstripe --stripe-index=0 --stripe-count=1 $DIR/$tfile ||
		error "$LFS setstripe failed"
	multiop $DIR/$tfile oO_CREAT:O_RDWR:O_SYNC:w4096c
	do_facet ost1 $LCTL set_param fail_loc=0
	$LCTL dk | grep -i "Early reply
	debugrestore
	lctl get_param -n osc.${FSNAME}-OST0000-osc-*.timeouts | grep portal
}
run_test 65b "AT: verify early replies on packed reply / bulk"
test_66a()
{
    remote_ost_nodsh && skip "remote OST with nodsh" && return 0
    at_start || return 0
    lctl get_param -n mdc.${FSNAME}-MDT0000-mdc-*.timeouts | grep "portal 12"
    do_facet $SINGLEMDS "$LCTL set_param fail_val=5000"
    do_facet $SINGLEMDS "$LCTL set_param fail_loc=0x8000050a"
    createmany -o $DIR/$tfile 20 > /dev/null
    unlinkmany $DIR/$tfile 20 > /dev/null
    lctl get_param -n mdc.${FSNAME}-MDT0000-mdc-*.timeouts | grep "portal 12"
    do_facet $SINGLEMDS "$LCTL set_param fail_val=10000"
    do_facet $SINGLEMDS "$LCTL set_param fail_loc=0x8000050a"
    createmany -o $DIR/$tfile 20 > /dev/null
    unlinkmany $DIR/$tfile 20 > /dev/null
    lctl get_param -n mdc.${FSNAME}-MDT0000-mdc-*.timeouts | grep "portal 12"
    do_facet $SINGLEMDS "$LCTL set_param fail_loc=0"
    sleep 9
    createmany -o $DIR/$tfile 20 > /dev/null
    unlinkmany $DIR/$tfile 20 > /dev/null
    lctl get_param -n mdc.${FSNAME}-MDT0000-mdc-*.timeouts | grep "portal 12"
    CUR=$(lctl get_param -n mdc.${FSNAME}-MDT0000-mdc-*.timeouts | awk '/portal 12/ {print $5}')
    WORST=$(lctl get_param -n mdc.${FSNAME}-MDT0000-mdc-*.timeouts | awk '/portal 12/ {print $7}')
    echo "Current MDT timeout $CUR, worst $WORST"
    [ $CUR -lt $WORST ] || error "Current $CUR should be less than worst $WORST"
}
run_test 66a "AT: verify MDT service time adjusts with no early replies"
test_66b()
{
	remote_ost_nodsh && skip "remote OST with nodsh" && return 0
	at_start || return 0
	ORIG=$(lctl get_param -n mdc.${FSNAME}-MDT0000*.timeouts |
		awk '/network/ {print $4}')
	$LCTL set_param fail_val=$(($ORIG + 5))
	$LCTL set_param fail_loc=0x50c
	touch $DIR/$tfile > /dev/null 2>&1
	$LCTL set_param fail_loc=0
	CUR=$(lctl get_param -n mdc.${FSNAME}-MDT0000*.timeouts |
		awk '/network/ {print $4}')
	WORST=$(lctl get_param -n mdc.${FSNAME}-MDT0000*.timeouts |
		awk '/network/ {print $6}')
	echo "network timeout orig $ORIG, cur $CUR, worst $WORST"
	[ $WORST -gt $ORIG ] ||
		error "Worst $WORST should be worse than orig $ORIG"
}
run_test 66b "AT: verify net latency adjusts"
test_67a()
{
    remote_ost_nodsh && skip "remote OST with nodsh" && return 0
    at_start || return 0
    CONN1=$(lctl get_param -n osc.*.stats | awk '/_connect/ {total+=$2} END {print total}')
    do_facet ost1 "$LCTL set_param fail_val=400"
    do_facet ost1 "$LCTL set_param fail_loc=0x50a"
    createmany -o $DIR/$tfile 20 > /dev/null
    unlinkmany $DIR/$tfile 20 > /dev/null
    do_facet ost1 "$LCTL set_param fail_loc=0"
    CONN2=$(lctl get_param -n osc.*.stats | awk '/_connect/ {total+=$2} END {print total}')
    ATTEMPTS=$(($CONN2 - $CONN1))
    echo "$ATTEMPTS osc reconnect attempts on gradual slow"
	[ $ATTEMPTS -gt 0 ] &&
		error_ignore bz13721 "AT should have prevented reconnect"
	return 0
}
run_test 67a "AT: verify slow request processing doesn't induce reconnects"
test_67b()
{
    remote_ost_nodsh && skip "remote OST with nodsh" && return 0
    at_start || return 0
    CONN1=$(lctl get_param -n osc.*.stats | awk '/_connect/ {total+=$2} END {print total}')
	local OST=$(ostname_from_index 0)
	local mdtosc=$(get_mdtosc_proc_path mds $OST)
	local last_id=$(do_facet $SINGLEMDS lctl get_param -n \
			osp.$mdtosc.prealloc_last_id)
	local next_id=$(do_facet $SINGLEMDS lctl get_param -n \
			osp.$mdtosc.prealloc_next_id)
	mkdir -p $DIR/$tdir/${OST} || error "mkdir $DIR/$tdir/${OST} failed"
	$LFS setstripe -i 0 -c 1 $DIR/$tdir/${OST} ||
		error "$LFS setstripe failed"
	echo "Creating to objid $last_id on ost $OST..."
    do_facet ost1 "$LCTL set_param fail_val=20000"
    do_facet ost1 "$LCTL set_param fail_loc=0x80000223"
    createmany -o $DIR/$tdir/${OST}/f $next_id $((last_id - next_id + 2))
    client_reconnect
    do_facet ost1 "lctl get_param -n ost.OSS.ost_create.timeouts"
    log "phase 2"
    CONN2=$(lctl get_param -n osc.*.stats | awk '/_connect/ {total+=$2} END {print total}')
    ATTEMPTS=$(($CONN2 - $CONN1))
    echo "$ATTEMPTS osc reconnect attempts on instant slow"
    do_facet ost1 "$LCTL set_param fail_loc=0x80000223"
    cp /etc/profile $DIR/$tfile || error "cp failed"
    do_facet ost1 "$LCTL set_param fail_loc=0"
    client_reconnect
    do_facet ost1 "lctl get_param -n ost.OSS.ost_create.timeouts"
    CONN3=$(lctl get_param -n osc.*.stats | awk '/_connect/ {total+=$2} END {print total}')
    ATTEMPTS=$(($CONN3 - $CONN2))
    echo "$ATTEMPTS osc reconnect attempts on 2nd slow"
    [ $ATTEMPTS -gt 0 ] && error "AT should have prevented reconnect"
    return 0
}
run_test 67b "AT: verify instant slowdown doesn't induce reconnects"
test_68 ()
{
    remote_ost_nodsh && skip "remote OST with nodsh" && return 0
    at_start || return 0
    local ldlm_enqueue_min=$(find /sys -name ldlm_enqueue_min)
    [ -z "$ldlm_enqueue_min" ] && skip "missing /sys/.../ldlm_enqueue_min" && return 0
    local ldlm_enqueue_min_r=$(do_facet ost1 "find /sys -name ldlm_enqueue_min")
    [ -z "$ldlm_enqueue_min_r" ] && skip "missing /sys/.../ldlm_enqueue_min in the ost1" && return 0
    local ENQ_MIN=$(cat $ldlm_enqueue_min)
    local ENQ_MIN_R=$(do_facet ost1 "cat $ldlm_enqueue_min_r")
	echo $TIMEOUT >> $ldlm_enqueue_min
	do_facet ost1 "echo $TIMEOUT >> $ldlm_enqueue_min_r"
	mkdir $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	$LFS setstripe --stripe-index=0 -c 1 $DIR/$tdir ||
		error "$LFS setstripe failed for $DIR/$tdir"
	$LCTL set_param fail_val=$(($TIMEOUT - 1))
	$LCTL set_param fail_loc=0x80000312
	cp /etc/profile $DIR/$tdir/${tfile}_1 || error "1st cp failed $?"
	$LCTL set_param fail_val=$((TIMEOUT * 5 / 4))
	$LCTL set_param fail_loc=0x80000312
	cp /etc/profile $DIR/$tdir/${tfile}_2 || error "2nd cp failed $?"
	$LCTL set_param fail_loc=0
	echo $ENQ_MIN >> $ldlm_enqueue_min
	do_facet ost1 "echo $ENQ_MIN_R >> $ldlm_enqueue_min_r"
	rm -rf $DIR/$tdir
	return 0
}
run_test 68 "AT: verify slowing locks"
at_cleanup
test_70a () {
	[ $CLIENTCOUNT -lt 2 ] &&
		{ skip "Need two or more clients, have $CLIENTCOUNT" && return; }
	echo "mount clients $CLIENTS ..."
	zconf_mount_clients $CLIENTS $MOUNT
	local clients=${CLIENTS//,/ }
	echo "Write/read files on $DIR ; clients $CLIENTS ... "
	for CLIENT in $clients; do
		do_node $CLIENT dd bs=1M count=10 if=/dev/zero \
			of=$DIR/${tfile}_${CLIENT} 2>/dev/null ||
				error "dd failed on $CLIENT"
	done
	local prev_client=$(echo $clients | sed 's/^.* \(.\+\)$/\1/')
	for C in ${CLIENTS//,/ }; do
		do_node $prev_client dd if=$DIR/${tfile}_${C} \
			of=/dev/null 2>/dev/null ||
			error "dd if=$DIR/${tfile}_${C} failed on $prev_client"
		prev_client=$C
	done
	ls $DIR
}
run_test 70a "check multi client t-f"
check_for_process () {
	local clients=$1
	shift
	local prog=$@
	killall_process $clients "$prog" -0
}
test_70b () {
	local clients=${CLIENTS:-$HOSTNAME}
	zconf_mount_clients $clients $MOUNT
	local duration=300
	[ "$SLOW" = "no" ] && duration=120
	[ "$FAILURE_MODE" = HARD ] && duration=900
	local elapsed
	local start_ts=$(date +%s)
	local cmd="rundbench 1 -t $duration"
	local pid=""
	if [ $MDSCOUNT -ge 2 ]; then
		test_mkdir -p -c$MDSCOUNT $DIR/$tdir
		$LFS setdirstripe -D -c$MDSCOUNT $DIR/$tdir
	fi
	do_nodesv $clients "set -x; MISSING_DBENCH_OK=$MISSING_DBENCH_OK \
		PATH=\$PATH:$LUSTRE/utils:$LUSTRE/tests/:$DBENCH_LIB \
		DBENCH_LIB=$DBENCH_LIB TESTSUITE=$TESTSUITE TESTNAME=$TESTNAME \
		MOUNT=$MOUNT DIR=$DIR/$tdir/\\\$(hostname) LCTL=$LCTL $cmd" &
	pid=$!
	while ! check_for_process $clients dbench; do
		elapsed=$(($(date +%s) - start_ts))
		if [ $elapsed -gt $duration ]; then
			killall_process $clients dbench
			error "dbench failed to start on $clients!"
		fi
		sleep 1
	done
	log "Started rundbench load pid=$pid ..."
	elapsed=$(($(date +%s) - start_ts))
	local num_failovers=0
	local fail_index=1
	while [ $elapsed -lt $duration ]; do
		if ! check_for_process $clients dbench; then
			error_noexit "dbench stopped on some of $clients!"
			killall_process $clients dbench
			break
		fi
		sleep 1
		replay_barrier mds$fail_index
		sleep 1
		num_failovers=$((num_failovers+1))
		log "$TESTNAME fail mds$fail_index $num_failovers times"
		fail mds$fail_index
		elapsed=$(($(date +%s) - start_ts))
		if [ $fail_index -ge $MDSCOUNT ]; then
			fail_index=1
		else
			fail_index=$((fail_index+1))
		fi
	done
	wait $pid || error "rundbench load on $clients failed!"
}
run_test 70b "dbench ${MDSCOUNT}mdts recovery; $CLIENTCOUNT clients"
random_fail_mdt() {
	local max_index=$1
	local duration=$2
	local monitor_pid=$3
	local elapsed
	local start_ts=$(date +%s)
	local num_failovers=0
	local fail_index
	elapsed=$(($(date +%s) - start_ts))
	while [ $elapsed -lt $duration ]; do
		fail_index=$((RANDOM%max_index+1))
		kill -0 $monitor_pid ||
			error "$monitor_pid stopped"
		sleep 120
		replay_barrier mds$fail_index
		sleep 10
		num_failovers=$((num_failovers+1))
		log "$TESTNAME fail mds$fail_index $num_failovers times"
		fail mds$fail_index
		elapsed=$(($(date +%s) - start_ts))
	done
}
cleanup_70c() {
	trap 0
	rm -f $DIR/replay-single.70c.lck
	rm -rf /$DIR/$tdir
}
test_70c () {
	local clients=${CLIENTS:-$HOSTNAME}
	local rc=0
	zconf_mount_clients $clients $MOUNT
	local duration=300
	[ "$SLOW" = "no" ] && duration=180
	[ "$FAILURE_MODE" = HARD ] && duration=600
	local elapsed
	local start_ts=$(date +%s)
	stack_trap cleanup_70c EXIT
	(
		while [ ! -e $DIR/replay-single.70c.lck ]; do
			test_mkdir -p -c$MDSCOUNT $DIR/$tdir || break
			if [ $MDSCOUNT -ge 2 ]; then
				$LFS setdirstripe -D -c$MDSCOUNT $DIR/$tdir ||
				error "set default dirstripe failed"
			fi
			cd $DIR/$tdir || break
			tar cf - /etc | tar xf - || error "tar failed in loop"
		done
	)&
	tar_70c_pid=$!
	echo "Started tar $tar_70c_pid"
	random_fail_mdt $MDSCOUNT $duration $tar_70c_pid
	kill -0 $tar_70c_pid || error "tar $tar_70c_pid stopped"
	touch $DIR/replay-single.70c.lck
	wait $tar_70c_pid || error "$?: tar failed"
	cleanup_70c
	true
}
run_test 70c "tar ${MDSCOUNT}mdts recovery"
cleanup_70d() {
	trap 0
	kill -9 $mkdir_70d_pid
}
test_70d () {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	local clients=${CLIENTS:-$HOSTNAME}
	local rc=0
	zconf_mount_clients $clients $MOUNT
	local duration=300
	[ "$SLOW" = "no" ] && duration=180
	[ "$FAILURE_MODE" = HARD ] && duration=900
	mkdir -p $DIR/$tdir
	local elapsed
	local start_ts=$(date +%s)
	trap cleanup_70d EXIT
	(
		while true; do
			$LFS mkdir -i0 -c2 $DIR/$tdir/test || {
				echo "mkdir fails"
				break
			}
			$LFS mkdir -i1 -c2 $DIR/$tdir/test1 || {
				echo "mkdir fails"
				break
			}
			touch $DIR/$tdir/test/a || {
				echo "touch fails"
				break;
			}
			mkdir $DIR/$tdir/test/b || {
				echo "mkdir fails"
				break;
			}
			rm -rf $DIR/$tdir/test || {
				echo "rmdir fails"
				ls -lR $DIR/$tdir
				break
			}
			touch $DIR/$tdir/test1/a || {
				echo "touch fails"
				break;
			}
			mkdir $DIR/$tdir/test1/b || {
				echo "mkdir fails"
				break;
			}
			rm -rf $DIR/$tdir/test1 || {
				echo "rmdir fails"
				ls -lR $DIR/$tdir/test1
				break
			}
		done
	)&
	mkdir_70d_pid=$!
	echo "Started  $mkdir_70d_pid"
	random_fail_mdt $MDSCOUNT $duration $mkdir_70d_pid
	kill -0 $mkdir_70d_pid || error "mkdir/rmdir $mkdir_70d_pid stopped"
	cleanup_70d
	true
}
run_test 70d "mkdir/rmdir striped dir ${MDSCOUNT}mdts recovery"
test_70e () {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	local clients=${CLIENTS:-$HOSTNAME}
	local rc=0
	lctl set_param debug=+ha
	zconf_mount_clients $clients $MOUNT
	local duration=300
	[ "$SLOW" = "no" ] && duration=180
	[ "$FAILURE_MODE" = HARD ] && duration=900
	mkdir -p $DIR/$tdir
	$LFS mkdir -i0 $DIR/$tdir/test_0
	$LFS mkdir -i0 $DIR/$tdir/test_1
	touch $DIR/$tdir/test_0/a
	touch $DIR/$tdir/test_1/b
	(
	while true; do
		mrename $DIR/$tdir/test_0/a $DIR/$tdir/test_1/b > /dev/null || {
			echo "a->b fails"
			break;
		}
		checkstat $DIR/$tdir/test_0/a && {
			echo "a still exists"
			break
		}
		checkstat $DIR/$tdir/test_1/b || {
			echo "b still  exists"
			break
		}
		touch $DIR/$tdir/test_0/a || {
			echo "touch a fails"
			break
		}
		mrename $DIR/$tdir/test_1/b $DIR/$tdir/test_0/a > /dev/null || {
			echo "a->a fails"
			break;
		}
	done
	)&
	rename_70e_pid=$!
	stack_trap "kill -9 $rename_70e_pid" EXIT
	echo "Started PID=$rename_70e_pid"
	random_fail_mdt 2 $duration $rename_70e_pid
	kill -0 $rename_70e_pid || error "rename $rename_70e_pid stopped"
}
run_test 70e "rename cross-MDT with random fails"
test_70f_write_and_read(){
	local srcfile=$1
	local stopflag=$2
	local client
	echo "Write/read files in: '$DIR/$tdir', clients: '$CLIENTS' ..."
	for client in ${CLIENTS//,/ }; do
		[ -f $stopflag ] || return
		local tgtfile=$DIR/$tdir/$tfile.$client
		do_node $client dd $DD_OPTS bs=1M count=10 if=$srcfile \
			of=$tgtfile 2>/dev/null ||
			error "dd $DD_OPTS bs=1M count=10 if=$srcfile " \
			      "of=$tgtfile failed on $client, rc=$?"
	done
	local prev_client=$(echo ${CLIENTS//,/ } | awk '{ print $NF }')
	local index=0
	for client in ${CLIENTS//,/ }; do
		[ -f $stopflag ] || return
		do_node $client $LCTL set_param ldlm.namespaces.*.lru_size=clear
		tgtfile=$DIR/$tdir/$tfile.$client
		local md5=$(do_node $prev_client "md5sum $tgtfile")
		[ ${checksum[$index]// */} = ${md5// */} ] ||
			error "$tgtfile: checksum doesn't match on $prev_client"
		index=$((index + 1))
		prev_client=$client
	done
}
test_70f_loop(){
	local srcfile=$1
	local stopflag=$2
	DD_OPTS=
	mkdir -p $DIR/$tdir || error "cannot create $DIR/$tdir directory"
	$LFS setstripe -c -1 $DIR/$tdir ||
		error "cannot $LFS setstripe $DIR/$tdir"
	touch $stopflag
	while [ -f $stopflag ]; do
		test_70f_write_and_read $srcfile $stopflag
		[ -n "$DD_OPTS" ] && DD_OPTS="" || DD_OPTS="oflag=direct"
	done
}
test_70f_cleanup() {
	trap 0
	rm -f $TMP/$tfile.stop
	do_nodes $CLIENTS rm -f $TMP/$tfile
	rm -f $DIR/$tdir/$tfile.*
}
test_70f() {
	[[ "$OST1_VERSION" -lt $(version_code 2.9.53) ]] &&
		skip "Need server version at least 2.9.53"
	echo "mount clients $CLIENTS ..."
	zconf_mount_clients $CLIENTS $MOUNT
	local srcfile=$TMP/$tfile
	local client
	local index=0
	trap test_70f_cleanup EXIT
	do_nodes $CLIENTS dd bs=1M count=10 if=/dev/urandom of=$srcfile \
		2>/dev/null || error "can't create $srcfile on $CLIENTS"
	for client in ${CLIENTS//,/ }; do
		checksum[$index]=$(do_node $client "md5sum $srcfile")
		index=$((index + 1))
	done
	local duration=120
	[ "$SLOW" = "no" ] && duration=60
	[ "$FAILURE_MODE" = HARD ] && duration=900
	local stopflag=$TMP/$tfile.stop
	test_70f_loop $srcfile $stopflag &
	local pid=$!
	local elapsed=0
	local num_failovers=0
	local start_ts=$SECONDS
	while [ $elapsed -lt $duration ]; do
		sleep 3
		replay_barrier ost1
		sleep 1
		num_failovers=$((num_failovers + 1))
		log "$TESTNAME failing OST $num_failovers times"
		fail ost1
		sleep 2
		elapsed=$((SECONDS - start_ts))
	done
	rm -f $stopflag
	wait $pid
	test_70f_cleanup
}
run_test 70f "OSS O_DIRECT recovery with $CLIENTCOUNT clients"
cleanup_71a() {
	trap 0
	kill -9 $mkdir_71a_pid
}
random_double_fail_mdt() {
	local max_index=$1
	local duration=$2
	local monitor_pid=$3
	local elapsed
	local start_ts=$(date +%s)
	local num_failovers=0
	local fail_index
	local second_index
	elapsed=$(($(date +%s) - start_ts))
	while [ $elapsed -lt $duration ]; do
		fail_index=$((RANDOM%max_index + 1))
		if [ $fail_index -eq $max_index ]; then
			second_index=1
		else
			second_index=$((fail_index + 1))
		fi
		kill -0 $monitor_pid ||
			error "$monitor_pid stopped"
		sleep 120
		replay_barrier mds$fail_index
		replay_barrier mds$second_index
		sleep 10
		num_failovers=$((num_failovers+1))
		log "fail mds$fail_index mds$second_index $num_failovers times"
		fail mds${fail_index},mds${second_index}
		elapsed=$(($(date +%s) - start_ts))
	done
}
test_71a () {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	local clients=${CLIENTS:-$HOSTNAME}
	local rc=0
	zconf_mount_clients $clients $MOUNT
	local duration=300
	[ "$SLOW" = "no" ] && duration=180
	[ "$FAILURE_MODE" = HARD ] && duration=900
	mkdir_on_mdt0 $DIR/$tdir
	local elapsed
	local start_ts=$(date +%s)
	trap cleanup_71a EXIT
	(
		while true; do
			$LFS mkdir -i0 -c2 $DIR/$tdir/test
			rmdir $DIR/$tdir/test
		done
	)&
	mkdir_71a_pid=$!
	echo "Started  $mkdir_71a_pid"
	random_double_fail_mdt 2 $duration $mkdir_71a_pid
	kill -0 $mkdir_71a_pid || error "mkdir/rmdir $mkdir_71a_pid stopped"
	cleanup_71a
	true
}
run_test 71a "mkdir/rmdir striped dir with 2 mdts recovery"
test_73a() {
	multiop_bg_pause $DIR/$tfile O_tSc ||
		error "multiop_bg_pause $DIR/$tfile failed"
	pid=$!
	rm -f $DIR/$tfile
	replay_barrier $SINGLEMDS
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x80000302"
	fail $SINGLEMDS
	kill -USR1 $pid
	wait $pid || error "multiop pid failed"
	[ -e $DIR/$tfile ] && error "file $DIR/$tfile should not exist"
	return 0
}
run_test 73a "open(O_CREAT), unlink, replay, reconnect before open replay, close"
test_73b() {
	multiop_bg_pause $DIR/$tfile O_tSc ||
		error "multiop_bg_pause $DIR/$tfile failed"
	pid=$!
	rm -f $DIR/$tfile
	replay_barrier $SINGLEMDS
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x80000157"
	fail $SINGLEMDS
	kill -USR1 $pid
	wait $pid || error "multiop pid failed"
	[ -e $DIR/$tfile ] && error "file $DIR/$tfile should not exist"
	return 0
}
run_test 73b "open(O_CREAT), unlink, replay, reconnect at open_replay reply, close"
test_74() {
	local clients=${CLIENTS:-$HOSTNAME}
	zconf_umount_clients $clients $MOUNT
	stop ost1
	facet_failover $SINGLEMDS
	zconf_mount_clients $clients $MOUNT
	mount_facet ost1
	touch $DIR/$tfile || error "touch $DIR/$tfile failed"
	rm $DIR/$tfile || error "rm $DIR/$tfile failed"
	clients_up || error "client evicted: $?"
	return 0
}
run_test 74 "Ensure applications don't fail waiting for OST recovery"
remote_dir_check_80() {
	local mdtidx=1
	local diridx
	local fileidx
	diridx=$($LFS getstripe -m $remote_dir) ||
		error "$LFS getstripe -m $remote_dir failed"
	[ $diridx -eq $mdtidx ] || error "$diridx != $mdtidx"
	createmany -o $remote_dir/f-%d 20 || error "creation failed"
	fileidx=$($LFS getstripe -m $remote_dir/f-1) ||
		error "$LFS getstripe -m $remote_dir/f-1 failed"
	[ $fileidx -eq $mdtidx ] || error "$fileidx != $mdtidx"
	return 0
}
test_80a() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	local MDTIDX=1
	local remote_dir=$DIR/$tdir/remote_dir
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	do_facet mds${MDTIDX} lctl set_param fail_loc=0x1701
	$LFS mkdir -i $MDTIDX $remote_dir &
	local CLIENT_PID=$!
	replay_barrier mds1
	fail mds${MDTIDX}
	wait $CLIENT_PID || error "remote creation failed"
	remote_dir_check_80 || error "remote dir check failed"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 80a "DNE: create remote dir, drop update rep from MDT0, fail MDT0"
test_80b() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	local MDTIDX=1
	local remote_dir=$DIR/$tdir/remote_dir
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	do_facet mds${MDTIDX} lctl set_param fail_loc=0x1701
	$LFS mkdir -i $MDTIDX $remote_dir &
	local CLIENT_PID=$!
	replay_barrier mds1
	replay_barrier mds2
	fail mds$((MDTIDX + 1))
	wait $CLIENT_PID || error "remote creation failed"
	remote_dir_check_80 || error "remote dir check failed"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 80b "DNE: create remote dir, drop update rep from MDT0, fail MDT1"
test_80c() {
	[[ "$mds1_FSTYPE" = zfs ]] &&
		[[ $MDS1_VERSION -lt $(version_code 2.12.51) ]] &&
		skip "requires LU-10143 fix on MDS"
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode"
	local MDTIDX=1
	local remote_dir=$DIR/$tdir/remote_dir
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	do_facet mds${MDTIDX} lctl set_param fail_loc=0x1701
	$LFS mkdir -i $MDTIDX $remote_dir &
	local CLIENT_PID=$!
	replay_barrier mds1
	replay_barrier mds2
	fail mds${MDTIDX}
	fail mds$((MDTIDX + 1))
	wait $CLIENT_PID || error "remote creation failed"
	remote_dir_check_80 || error "remote dir check failed"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 80c "DNE: create remote dir, drop update rep from MDT1, fail MDT[0,1]"
test_80d() {
	[[ "$mds1_FSTYPE" = zfs ]] &&
		[[ $MDS1_VERSION -lt $(version_code 2.12.51) ]] &&
		skip "requires LU-10143 fix on MDS"
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs"
	local MDTIDX=1
	local remote_dir=$DIR/$tdir/remote_dir
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	do_facet mds${MDTIDX} lctl set_param fail_loc=0x1701
	$LFS mkdir -i $MDTIDX $remote_dir &
	local CLIENT_PID=$!
	sleep 3
	replay_barrier mds1
	replay_barrier mds2
	fail mds${MDTIDX},mds$((MDTIDX + 1))
	wait $CLIENT_PID || error "remote creation failed"
	remote_dir_check_80 || error "remote dir check failed"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 80d "DNE: create remote dir, drop update rep from MDT1, fail 2 MDTs"
test_80e() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	local MDTIDX=1
	local remote_dir=$DIR/$tdir/remote_dir
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	do_facet mds$((MDTIDX + 1)) lctl set_param fail_loc=0x119
	$LFS mkdir -i $MDTIDX $remote_dir &
	local CLIENT_PID=$!
	sleep 3
	replay_barrier mds1
	fail mds${MDTIDX}
	wait $CLIENT_PID || error "remote creation failed"
	remote_dir_check_80 || error "remote dir check failed"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 80e "DNE: create remote dir, drop MDT1 rep, fail MDT0"
test_80f() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	local MDTIDX=1
	local remote_dir=$DIR/$tdir/remote_dir
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	do_facet mds$((MDTIDX + 1)) lctl set_param fail_loc=0x119
	$LFS mkdir -i $MDTIDX $remote_dir &
	local CLIENT_PID=$!
	replay_barrier mds2
	fail mds$((MDTIDX + 1))
	wait $CLIENT_PID || error "remote creation failed"
	remote_dir_check_80 || error "remote dir check failed"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 80f "DNE: create remote dir, drop MDT1 rep, fail MDT1"
test_80g() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	local MDTIDX=1
	local remote_dir=$DIR/$tdir/remote_dir
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	do_facet mds$((MDTIDX + 1)) lctl set_param fail_loc=0x119
	$LFS mkdir -i $MDTIDX $remote_dir &
	local CLIENT_PID=$!
	sleep 3
	replay_barrier mds1
	replay_barrier mds2
	fail mds${MDTIDX}
	fail mds$((MDTIDX + 1))
	wait $CLIENT_PID || error "remote creation failed"
	remote_dir_check_80 || error "remote dir check failed"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 80g "DNE: create remote dir, drop MDT1 rep, fail MDT0, then MDT1"
test_80h() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	local MDTIDX=1
	local remote_dir=$DIR/$tdir/remote_dir
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	do_facet mds$((MDTIDX + 1)) lctl set_param fail_loc=0x119
	$LFS mkdir -i $MDTIDX $remote_dir &
	local CLIENT_PID=$!
	sleep 3
	replay_barrier mds1
	replay_barrier mds2
	fail mds${MDTIDX},mds$((MDTIDX + 1))
	wait $CLIENT_PID || error "remote dir creation failed"
	remote_dir_check_80 || error "remote dir check failed"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 80h "DNE: create remote dir, drop MDT1 rep, fail 2 MDTs"
test_81a() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	local MDTIDX=1
	local remote_dir=$DIR/$tdir/remote_dir
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	$LFS mkdir -i $MDTIDX $remote_dir || error "lfs mkdir failed"
	touch $remote_dir || error "touch $remote_dir failed"
	do_facet mds${MDTIDX} lctl set_param fail_loc=0x1701
	rmdir $remote_dir &
	local CLIENT_PID=$!
	replay_barrier mds2
	fail mds$((MDTIDX + 1))
	wait $CLIENT_PID || error "rm remote dir failed"
	stat $remote_dir &>/dev/null && error "$remote_dir still exist!"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 81a "DNE: unlink remote dir, drop MDT0 update rep,  fail MDT1"
test_81b() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	local MDTIDX=1
	local remote_dir=$DIR/$tdir/remote_dir
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	$LFS mkdir -i $MDTIDX $remote_dir || error "lfs mkdir failed"
	do_facet mds${MDTIDX} lctl set_param fail_loc=0x1701
	rmdir $remote_dir &
	local CLIENT_PID=$!
	replay_barrier mds1
	fail mds${MDTIDX}
	wait $CLIENT_PID || error "rm remote dir failed"
	stat $remote_dir &>/dev/null && error "$remote_dir still exist!"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 81b "DNE: unlink remote dir, drop MDT0 update reply,  fail MDT0"
test_81c() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	local MDTIDX=1
	local remote_dir=$DIR/$tdir/remote_dir
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	$LFS mkdir -i $MDTIDX $remote_dir || error "lfs mkdir failed"
	do_facet mds${MDTIDX} lctl set_param fail_loc=0x1701
	rmdir $remote_dir &
	local CLIENT_PID=$!
	replay_barrier mds1
	replay_barrier mds2
	fail mds${MDTIDX}
	fail mds$((MDTIDX + 1))
	wait $CLIENT_PID || error "rm remote dir failed"
	stat $remote_dir &>/dev/null && error "$remote_dir still exist!"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 81c "DNE: unlink remote dir, drop MDT0 update reply, fail MDT0,MDT1"
test_81d() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	local MDTIDX=1
	local remote_dir=$DIR/$tdir/remote_dir
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	$LFS mkdir -i $MDTIDX $remote_dir || error "lfs mkdir failed"
	do_facet mds${MDTIDX} lctl set_param fail_loc=0x1701
	rmdir $remote_dir &
	local CLIENT_PID=$!
	replay_barrier mds1
	replay_barrier mds2
	fail mds${MDTIDX},mds$((MDTIDX + 1))
	wait $CLIENT_PID || error "rm remote dir failed"
	stat $remote_dir &>/dev/null && error "$remote_dir still exist!"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 81d "DNE: unlink remote dir, drop MDT0 update reply,  fail 2 MDTs"
test_81e() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	local MDTIDX=1
	local remote_dir=$DIR/$tdir/remote_dir
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	$LFS mkdir -i $MDTIDX $remote_dir || error "lfs mkdir failed"
	do_facet mds$((MDTIDX + 1)) lctl set_param fail_loc=0x119
	rmdir $remote_dir &
	local CLIENT_PID=$!
	do_facet mds$((MDTIDX + 1)) lctl set_param fail_loc=0
	replay_barrier mds1
	fail mds${MDTIDX}
	wait $CLIENT_PID || error "rm remote dir failed"
	stat $remote_dir &>/dev/null && error "$remote_dir still exist!"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 81e "DNE: unlink remote dir, drop MDT1 req reply, fail MDT0"
test_81f() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	local MDTIDX=1
	local remote_dir=$DIR/$tdir/remote_dir
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	$LFS mkdir -i $MDTIDX $remote_dir || error "lfs mkdir failed"
	do_facet mds$((MDTIDX + 1)) lctl set_param fail_loc=0x119
	rmdir $remote_dir &
	local CLIENT_PID=$!
	replay_barrier mds2
	fail mds$((MDTIDX + 1))
	wait $CLIENT_PID || error "rm remote dir failed"
	stat $remote_dir &>/dev/null && error "$remote_dir still exist!"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 81f "DNE: unlink remote dir, drop MDT1 req reply, fail MDT1"
test_81g() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	local MDTIDX=1
	local remote_dir=$DIR/$tdir/remote_dir
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	$LFS mkdir -i $MDTIDX $remote_dir || error "lfs mkdir failed"
	do_facet mds$((MDTIDX + 1)) lctl set_param fail_loc=0x119
	rmdir $remote_dir &
	local CLIENT_PID=$!
	replay_barrier mds1
	replay_barrier mds2
	fail mds${MDTIDX}
	fail mds$((MDTIDX + 1))
	wait $CLIENT_PID || error "rm remote dir failed"
	stat $remote_dir &>/dev/null && error "$remote_dir still exist!"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 81g "DNE: unlink remote dir, drop req reply, fail M0, then M1"
test_81h() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	local MDTIDX=1
	local remote_dir=$DIR/$tdir/remote_dir
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	$LFS mkdir -i $MDTIDX $remote_dir || error "lfs mkdir failed"
	do_facet mds$((MDTIDX + 1)) lctl set_param fail_loc=0x119
	rmdir $remote_dir &
	local CLIENT_PID=$!
	replay_barrier mds1
	replay_barrier mds2
	fail mds${MDTIDX},mds$((MDTIDX + 1))
	wait $CLIENT_PID || error "rm remote dir failed"
	stat $remote_dir &>/dev/null && error "$remote_dir still exist!"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 81h "DNE: unlink remote dir, drop request reply, fail 2 MDTs"
test_84a() {
    do_facet $SINGLEMDS "lctl set_param fail_loc=0x80000144"
    createmany -o $DIR/$tfile- 1 &
    PID=$!
    mds_evict_client
    wait $PID
    client_up || client_up || true
}
run_test 84a "stale open during export disconnect"
test_85a() {
	lctl set_param -n ldlm.cancel_unused_locks_before_replay "1"
	for i in $(seq 100); do
		echo "tag-$i" > $DIR/$tfile-$i
		grep -q "tag-$i" $DIR/$tfile-$i || error "f2-$i"
	done
	lov_id=$(lctl dl | grep "clilov")
	addr=$(echo $lov_id | awk '{print $4}' | awk -F '-' '{print $NF}')
	count=$(lctl get_param -n \
		ldlm.namespaces.*MDT0000*$addr.lock_unused_count)
	echo "before recovery: unused locks count = $count"
	fail $SINGLEMDS
	count2=$(lctl get_param -n \
		 ldlm.namespaces.*MDT0000*$addr.lock_unused_count)
	echo "after recovery: unused locks count = $count2"
	if [ $count2 -ge $count ]; then
		error "unused locks are not canceled"
	fi
}
run_test 85a "check the cancellation of unused locks during recovery(IBITS)"
test_85b() {
	rm -rf $DIR/$tdir
	mkdir $DIR/$tdir
	lctl set_param -n ldlm.cancel_unused_locks_before_replay "1"
	$LFS setstripe -c 1 -i 0 $DIR/$tdir
	for i in $(seq 100); do
		dd if=/dev/urandom of=$DIR/$tdir/$tfile-$i bs=4096 \
			count=32 >/dev/null 2>&1
	done
	cancel_lru_locks osc
	for i in $(seq 100); do
		dd if=$DIR/$tdir/$tfile-$i of=/dev/null bs=4096 \
			count=32 >/dev/null 2>&1
	done
	lov_id=$(lctl dl | grep "clilov")
	addr=$(echo $lov_id | awk '{print $4}' | awk -F '-' '{print $NF}')
	count=$(lctl get_param -n \
			  ldlm.namespaces.*OST0000*$addr.lock_unused_count)
	echo "before recovery: unused locks count = $count"
	[ $count -ne 0 ] || error "unused locks ($count) should be zero"
	fail ost1
	count2=$(lctl get_param \
		 -n ldlm.namespaces.*OST0000*$addr.lock_unused_count)
	echo "after recovery: unused locks count = $count2"
	if [ $count2 -ge $count ]; then
		error "unused locks are not canceled"
	fi
	rm -rf $DIR/$tdir
}
run_test 85b "check the cancellation of unused locks during recovery(EXTENT)"
test_86() {
        local clients=${CLIENTS:-$HOSTNAME}
        zconf_umount_clients $clients $MOUNT
        do_facet $SINGLEMDS lctl set_param mdt.${FSNAME}-MDT*.exports.clear=0
        remount_facet $SINGLEMDS
        zconf_mount_clients $clients $MOUNT
}
run_test 86 "umount server after clear nid_stats should not hit LBUG"
test_87a() {
	do_facet ost1 "lctl set_param -n obdfilter.${ost1_svc}.sync_journal 0"
	replay_barrier ost1
	$LFS setstripe -i 0 -c 1 $DIR/$tfile
	dd if=/dev/urandom of=$DIR/$tfile bs=1024k count=8 ||
		error "dd to $DIR/$tfile failed"
	cksum=$(md5sum $DIR/$tfile | awk '{print $1}')
	cancel_lru_locks osc
	fail ost1
	dd if=$DIR/$tfile of=/dev/null bs=1024k count=8 || error "Cannot read"
	cksum2=$(md5sum $DIR/$tfile | awk '{print $1}')
	if [ $cksum != $cksum2 ] ; then
		error "New checksum $cksum2 does not match original $cksum"
	fi
}
run_test 87a "write replay"
test_87b() {
	do_facet ost1 "lctl set_param -n obdfilter.${ost1_svc}.sync_journal 0"
	replay_barrier ost1
	$LFS setstripe -i 0 -c 1 $DIR/$tfile
	dd if=/dev/urandom of=$DIR/$tfile bs=1024k count=8 ||
		error "dd to $DIR/$tfile failed"
	sleep 1
	echo TESTTEST | dd of=$DIR/$tfile bs=1 count=8 seek=64
	cksum=$(md5sum $DIR/$tfile | awk '{print $1}')
	cancel_lru_locks osc
	fail ost1
	dd if=$DIR/$tfile of=/dev/null bs=1024k count=8 || error "Cannot read"
	cksum2=$(md5sum $DIR/$tfile | awk '{print $1}')
	if [ $cksum != $cksum2 ] ; then
		error "New checksum $cksum2 does not match original $cksum"
	fi
}
run_test 87b "write replay with changed data (checksum resend)"
test_88() {
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	mkdir -p $TMP/$tdir || error "mkdir $TMP/$tdir failed"
	$LFS setstripe -i 0 -c 1 $DIR/$tdir || error "$LFS setstripe failed"
	replay_barrier ost1
	replay_barrier $SINGLEMDS
	local OST=$(ostname_from_index 0)
	local mdtosc=$(get_mdtosc_proc_path $SINGLEMDS $OST)
	local last_id=$(do_facet $SINGLEMDS lctl get_param -n osp.$mdtosc.prealloc_last_id)
	local next_id=$(do_facet $SINGLEMDS lctl get_param -n osp.$mdtosc.prealloc_next_id)
	echo "before test: last_id = $last_id, next_id = $next_id"
	echo "Creating to objid $last_id on ost $OST..."
	createmany -o $DIR/$tdir/f-%d $next_id $((last_id - next_id + 2)) ||
		error "createmany create files to last_id failed"
	last_id=$(($last_id + 1))
	createmany -o $DIR/$tdir/f-%d $last_id 8 ||
		error "createmany create files with uncommitted objids failed"
    last_id2=$(do_facet $SINGLEMDS lctl get_param -n osp.$mdtosc.prealloc_last_id)
    next_id2=$(do_facet $SINGLEMDS lctl get_param -n osp.$mdtosc.prealloc_next_id)
    echo "before recovery: last_id = $last_id2, next_id = $next_id2" 
    local affected_mds1=$(affected_facets mds1)
    local affected_ost1=$(affected_facets ost1)
    shutdown_facet $SINGLEMDS
    shutdown_facet ost1
    reboot_facet $SINGLEMDS
    change_active $affected_mds1
    wait_for_facet $affected_mds1
    mount_facets $affected_mds1 || error "Restart of mds failed"
    reboot_facet ost1
    change_active $affected_ost1
    wait_for_facet $affected_ost1
    mount_facets $affected_ost1 || error "Restart of ost1 failed"
    clients_up
    last_id2=$(do_facet $SINGLEMDS lctl get_param -n osp.$mdtosc.prealloc_last_id)
    next_id2=$(do_facet $SINGLEMDS lctl get_param -n osp.$mdtosc.prealloc_next_id)
	echo "after recovery: last_id = $last_id2, next_id = $next_id2"
	for i in $(seq 8); do
		file_id=$(($last_id + 10 + $i))
		dd if=/dev/urandom of=$DIR/$tdir/f-$file_id bs=4096 count=128
	done
	ls -l $DIR/$tdir/* || error "can't get the status of precreated files"
	local file_id
	for i in $(seq 8); do
		file_id=$(($last_id + $i))
		dd if=/dev/urandom of=$DIR/$tdir/f-$file_id bs=4096 count=128
		cp -f $DIR/$tdir/f-$file_id $TMP/$tdir/
	done
	for i in $(seq 8); do
		file_id=$(($last_id + $i))
		cmp $TMP/$tdir/f-$file_id $DIR/$tdir/f-$file_id ||
			error "the content of file is modified!"
	done
	rm -fr $TMP/$tdir
}
run_test 88 "MDS should not assign same objid to different files "
test_89() {
	cancel_lru_locks osc
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	rm -f $DIR/$tdir/$tfile
	wait_mds_ost_sync || error "initial MDS-OST sync timed out"
	wait_delete_completed || error "initial wait delete timed out"
	local before=$(calc_osc_kbytes kbytesfree)
	local write_size=$(fs_log_size)
	$LFS setstripe -i 0 -c 1 $DIR/$tdir/$tfile
	(( $write_size >= 1024 )) || write_size=1024
	dd if=/dev/zero bs=${write_size}k count=10 of=$DIR/$tdir/$tfile
	sync
	ls -la $DIR/$tdir/$tfile
	stop ost1
	facet_failover $SINGLEMDS
	rm $DIR/$tdir/$tfile
	umount $MOUNT
	mount_facet ost1
	zconf_mount $(hostname) $MOUNT || error "mount fails"
	client_up || error "client_up failed"
	local target=$(get_osc_import_name client ost1)
	wait_import_state "FULL" "osc.${target}.ost_server_uuid" \
		$(max_recovery_time)
	wait_mds_ost_sync || error "MDS-OST sync timed out"
	wait_delete_completed || error "wait delete timed out"
	local after=$(calc_osc_kbytes kbytesfree)
	log "free_before: $before free_after: $after"
	(( $before <= $after + $(fs_log_size) )) ||
		error "kbytesfree $before > $after + margin $(fs_log_size)"
}
run_test 89 "no disk space leak on late ost connection"
cleanup_90 () {
	local facet=$1
	trap 0
	reboot_facet $facet
	change_active $facet
	wait_for_facet $facet
	mount_facet $facet || error "Restart of $facet failed"
	clients_up
}
test_90() {
	local dir=$DIR/$tdir
	local ostfail=$(get_random_entry $(get_facets OST))
	if [[ $FAILURE_MODE = HARD ]]; then
		local affected=$(affected_facets $ostfail);
		[[ "$affected" == $ostfail ]] ||
			skip "cannot use FAILURE_MODE=$FAILURE_MODE, affected: $affected"
	fi
	wait_osts_up
	mkdir $dir || error "mkdir $dir failed"
	echo "Create the files"
	$LFS setstripe -c $OSTCOUNT $dir/all ||
		error "setstripe failed to create $dir/all"
	for ((i = 0; i < $OSTCOUNT; i++)); do
		local f=$dir/f$i
		$LFS setstripe -i $i -c 1 $f ||
			error "$LFS setstripe failed to create $f"
		local uuid=$(ostuuid_from_index $i)
		for file in f$i all; do
			local found=$($LFS find --obd $uuid --name $file $dir)
			if [[ $dir/$file != $found ]]; then
				$LFS getstripe $dir/$file
				error "wrong stripe: $file, uuid: $uuid"
			fi
		done
	done
	local varsvc=${ostfail}_svc
	local obd=$(do_facet $ostfail lctl get_param \
		    -n obdfilter.${!varsvc}.uuid)
	local index=$(($(facet_number $ostfail) - 1))
	echo "Fail $ostfail $obd, display the list of affected files"
	shutdown_facet $ostfail || error "shutdown_facet $ostfail failed"
	trap "cleanup_90 $ostfail" EXIT INT
	echo "General Query: lfs find $dir"
	local list=$($LFS find $dir)
	echo "$list"
	for (( i=0; i<$OSTCOUNT; i++ )); do
		list_member "$list" $dir/f$i ||
			error_noexit "lfs find $dir: no file f$i"
	done
	list_member "$list" $dir/all ||
		error_noexit "lfs find $dir: no file all"
	echo "Querying files on shutdown $ostfail: lfs find --obd $obd"
    list=$($LFS find --obd $obd $dir)
    echo "$list"
    for file in all f$index; do
        list_member "$list" $dir/$file ||
            error_noexit "lfs find does not report the affected $obd for $file"
    done
    [[ $(echo $list | wc -w) -eq 2 ]] ||
        error_noexit "lfs find reports the wrong list of affected files ${
	echo "Check getstripe: $LFS getstripe -r --obd $obd"
	list=$($LFS getstripe -r --obd $obd $dir)
	echo "$list"
    for file in all f$index; do
        echo "$list" | grep $dir/$file ||
            error_noexit "lfs getsripe does not report the affected $obd for $file"
    done
    cleanup_90 $ostfail
}
run_test 90 "lfs find identifies the missing striped file segments"
test_93a() {
	[[ "$MDS1_VERSION" -ge $(version_code 2.6.90) ]] ||
		[[ "$MDS1_VERSION" -ge $(version_code 2.5.4) &&
		   "$MDS1_VERSION" -lt $(version_code 2.5.50) ]] ||
		skip "Need MDS version 2.5.4+ or 2.6.90+"
	cancel_lru_locks osc
	$LFS setstripe -i 0 -c 1 $DIR/$tfile ||
		error "$LFS setstripe  $DIR/$tfile failed"
	dd if=/dev/zero of=$DIR/$tfile bs=1024 count=1 ||
		error "dd to $DIR/$tfile failed"
	do_facet ost1 "$LCTL set_param fail_val=40"
	do_facet ost1 "$LCTL set_param fail_loc=0x715"
	fail ost1
}
run_test 93a "replay + reconnect"
test_93b() {
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.90) ]] ||
		skip "Need MDS version 2.7.90+"
	cancel_lru_locks mdc
	createmany -o $DIR/$tfile 20 ||
			error "createmany -o $DIR/$tfile failed"
	do_facet mds1 "$LCTL set_param fail_val=80"
	do_facet mds1 "$LCTL set_param fail_loc=0x715"
	fail mds1
}
run_test 93b "replay + reconnect on mds"
striped_dir_check_100() {
	local striped_dir=$DIR/$tdir/striped_dir
	local stripe_count=$($LFS getdirstripe -c $striped_dir)
	$LFS getdirstripe $striped_dir
	[ $stripe_count -eq 2 ] || error "$stripe_count != 2"
	createmany -o $striped_dir/f-%d 20 ||
		error "creation failed under striped dir"
}
test_100a() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	local striped_dir=$DIR/$tdir/striped_dir
	local MDTIDX=1
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	$LFS setdirstripe -i1 $DIR/$tdir/remote_dir
	do_facet mds$((MDTIDX+1)) lctl set_param fail_loc=0x1701
	$LFS setdirstripe -i0 -c2 $striped_dir &
	local CLIENT_PID=$!
	fail mds$((MDTIDX + 1))
	wait $CLIENT_PID || error "striped dir creation failed"
	striped_dir_check_100 || error "striped dir check failed"
	rm -rf $DIR/$tdir || error "rmdir failed"
}
run_test 100a "DNE: create striped dir, drop update rep from MDT1, fail MDT1"
test_100b() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	local striped_dir=$DIR/$tdir/striped_dir
	local MDTIDX=1
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	$LFS setdirstripe -i1 $DIR/$tdir/remote_dir
	do_facet mds$MDTIDX lctl set_param fail_loc=0x119
	$LFS mkdir -i0 -c2 $striped_dir &
	local CLIENT_PID=$!
	fail mds$MDTIDX
	wait $CLIENT_PID || error "striped dir creation failed"
	striped_dir_check_100 || error "striped dir check failed"
	rm -rf $DIR/$tdir || error "rmdir failed"
}
run_test 100b "DNE: create striped dir, fail MDT0"
test_100c() {
	(( $MDSCOUNT >= 2 )) || skip "needs >= 2 MDTs"
	[[ "$FAILURE_MODE" != "HARD" ||
	   "$(facet_host mds1)" != "$(facet_host mds2)" ]] ||
		skip "MDTs needs to be on diff hosts for HARD fail mode"
	local striped_dir=$DIR/$tdir/striped_dir
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	$LFS setdirstripe -i1 $DIR/$tdir/remote_dir
	replay_barrier mds2
	$LFS mkdir -i1 -c2 $striped_dir
	fail_abort mds2 abort_recov_mdt
	if (( $MDS1_VERSION >= $(version_code 2.15.54.138) )); then
		createmany -o $striped_dir/f-%d 20 ||
			error "createmany -o $DIR/$tfile failed"
	fi
	fail mds2
	(( $MDS1_VERSION >= $(version_code 2.15.52) &&
	   $MDS1_VERSION < $(version_code 2.15.54.138) )) &&
		fail_abort_cleanup && return 0
	striped_dir_check_100 || error "striped dir check failed"
}
run_test 100c "DNE: create striped dir, abort_recov_mdt mds2"
test_100d() {
	(( $MDSCOUNT > 1 )) || skip "needs > 1 MDTs"
	(( $MDS1_VERSION >= $(version_code 2.15.52.144) )) ||
		skip "Need MDS version 2.15.52.144+"
	test_mkdir -c $MDSCOUNT $DIR/$tdir || error "mkdir $tdir failed"
	$LFS setdirstripe -D -i -1 -c $MDSCOUNT $DIR/$tdir ||
		error "set $tdir default LMV failed"
	createmany -d $DIR/$tdir/s 100 || error "create subdir failed"
	local index=$((RANDOM % MDSCOUNT))
	local devname=$(mdtname_from_index $index)
	local mdt=mds$((index + 1))
	local count
	local log
	do_facet $mdt $LCTL --device $devname llog_print update_log
	log=$(do_facet $mdt "$LCTL --device $devname llog_print update_log |
		awk '/index/ { print \\\$4; exit }'")
	log=${log:1:-1}
	count=$(do_facet $mdt "$LCTL --device $devname llog_print update_log |
		grep -c index")
	(( count > 0 )) || error "no update logs found"
	stack_trap fail_abort_cleanup RETURN
	fail_abort $mdt || error "fail_abort $mdt failed"
	wait_update_facet $mdt "$LCTL --device $devname llog_print update_log |
		grep -c index" 0 60 || error "update logs not canceled"
}
run_test 100d "DNE: cancel update logs upon recovery abort"
test_100e() {
	(( MDSCOUNT > 1 )) || skip "needs >= 2 MDTs"
	(( MDS1_VERSION >= $(version_code 2.15.54.79) )) ||
		skip "Need MDS version 2.15.54.79+"
	[[ $FAILURE_MODE != "HARD" ||
	   "$(facet_host mds1)" != "$(facet_host mds2)" ]] ||
		skip "MDTs needs to be on diff hosts for HARD fail mode"
	local old
	local new
	local striped_dir=$DIR/$tdir/striped_dir
	mkdir $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	replay_barrier mds1
	replay_barrier mds2
	$LFS mkdir -i 0,1 $striped_dir
	old=$($LFS getdirstripe $striped_dir)
	echo $old
	fail mds1,mds2
	new=$($LFS getdirstripe $striped_dir)
	echo $new
	[ "$old" == "$new" ] ||
		error "$striped_dir layout mismatch"
	rm -rf $DIR/$tdir || error "rmdir failed"
}
run_test 100e "DNE: create striped dir on MDT0 and MDT1, fail MDT0, MDT1"
test_101() {
	mkdir -p $DIR/$tdir/d1
	mkdir -p $DIR/$tdir/d2
	touch $DIR/$tdir/file0
	num=1000
	replay_barrier $SINGLEMDS
	for i in $(seq $num) ; do
		echo test$i > $DIR/$tdir/d1/file$i
	done
	fail_abort $SINGLEMDS
	for i in $(seq $num) ; do
		touch $DIR/$tdir/d2/file$i
		test -s $DIR/$tdir/d2/file$i &&
			ls -al $DIR/$tdir/d2/file$i && error "file$i's size > 0"
	done
	rm -rf $DIR/$tdir
}
run_test 101 "Shouldn't reassign precreated objs to other files after recovery"
test_102a() {
	local idx
	local facet
	local num
	local i
	local pids pid
	[[ $(lctl get_param mdc.*.import |
	     grep "connect_flags:.*multi_mod_rpc") ]] ||
		{ skip "Need MDC with 'multi_mod_rpcs' feature"; return 0; }
	$LFS mkdir -c1 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	idx=$(printf "%04x" $($LFS getdirstripe -i $DIR/$tdir))
	facet="mds$((0x$idx + 1))"
	num=$($LCTL get_param -n \
		mdc.$FSNAME-MDT$idx-mdc-*.max_mod_rpcs_in_flight)
	[ -z "$num" ] && num=1
	echo "creating $num files ..."
	umask 0022
	for i in $(seq $num); do
		touch $DIR/$tdir/file-$i
	done
	do_facet $facet "$LCTL set_param fail_loc=0x159"
	echo "launch $num chmod in parallel ($(date +%H:%M:%S)) ..."
	for i in $(seq $num); do
		chmod 0600 $DIR/$tdir/file-$i &
		pids="$pids $!"
	done
	sleep 1
	do_facet $facet "$LCTL set_param fail_loc=0"
	for pid in $pids; do
		wait $pid || error "chmod failed"
	done
	echo "done ($(date +%H:%M:%S))"
	for i in $(seq $num); do
		checkstat -vp 0600 $DIR/$tdir/file-$i
	done
	rm -rf $DIR/$tdir
}
run_test 102a "check resend (request lost) with multiple modify RPCs in flight"
test_102b() {
	local idx
	local facet
	local num
	local i
	local pids pid
	[[ $(lctl get_param mdc.*.import |
	     grep "connect_flags:.*multi_mod_rpc") ]] ||
		{ skip "Need MDC with 'multi_mod_rpcs' feature"; return 0; }
	$LFS mkdir -c1 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	idx=$(printf "%04x" $($LFS getdirstripe -i $DIR/$tdir))
	facet="mds$((0x$idx + 1))"
	num=$($LCTL get_param -n \
		mdc.$FSNAME-MDT$idx-mdc-*.max_mod_rpcs_in_flight)
	[ -z "$num" ] && num=1
	echo "creating $num files ..."
	umask 0022
	for i in $(seq $num); do
		touch $DIR/$tdir/file-$i
	done
	do_facet $facet "$LCTL set_param fail_loc=0x15a"
	echo "launch $num chmod in parallel ($(date +%H:%M:%S)) ..."
	for i in $(seq $num); do
		chmod 0600 $DIR/$tdir/file-$i &
		pids="$pids $!"
	done
	sleep 1
	do_facet $facet "$LCTL set_param fail_loc=0"
	for pid in $pids; do
		wait $pid || error "chmod failed"
	done
	echo "done ($(date +%H:%M:%S))"
	for i in $(seq $num); do
		checkstat -vp 0600 $DIR/$tdir/file-$i
	done
	rm -rf $DIR/$tdir
}
run_test 102b "check resend (reply lost) with multiple modify RPCs in flight"
test_102c() {
	local idx
	local facet
	local num
	local i
	local pids pid
	[[ $(lctl get_param mdc.*.import |
	     grep "connect_flags:.*multi_mod_rpc") ]] ||
		{ skip "Need MDC with 'multi_mod_rpcs' feature"; return 0; }
	$LFS mkdir -c1 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	idx=$(printf "%04x" $($LFS getdirstripe -i $DIR/$tdir))
	facet="mds$((0x$idx + 1))"
	num=$($LCTL get_param -n \
		mdc.$FSNAME-MDT$idx-mdc-*.max_mod_rpcs_in_flight)
	[ -z "$num" ] && num=1
	echo "creating $num files ..."
	umask 0022
	for i in $(seq $num); do
		touch $DIR/$tdir/file-$i
	done
	replay_barrier $facet
	do_facet $facet "$LCTL set_param fail_loc=0x15a"
	echo "launch $num chmod in parallel ($(date +%H:%M:%S)) ..."
	for i in $(seq $num); do
		chmod 0600 $DIR/$tdir/file-$i &
		pids="$pids $!"
	done
	sleep 1
	do_facet $facet "$LCTL set_param fail_loc=0"
	fail $facet
	for pid in $pids; do
		wait $pid || error "chmod failed"
	done
	echo "done ($(date +%H:%M:%S))"
	for i in $(seq $num); do
		checkstat -vp 0600 $DIR/$tdir/file-$i
	done
	rm -rf $DIR/$tdir
}
run_test 102c "check replay w/o reconstruction with multiple mod RPCs in flight"
test_102d() {
	local idx
	local facet
	local num
	local i
	local pids pid
	[[ $(lctl get_param mdc.*.import |
	     grep "connect_flags:.*multi_mod_rpc") ]] ||
		{ skip "Need MDC with 'multi_mod_rpcs' feature"; return 0; }
	$LFS mkdir -c1 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	idx=$(printf "%04x" $($LFS getdirstripe -i $DIR/$tdir))
	facet="mds$((0x$idx + 1))"
	num=$($LCTL get_param -n \
		mdc.$FSNAME-MDT$idx-mdc-*.max_mod_rpcs_in_flight)
	[ -z "$num" ] && num=1
	echo "creating $num files ..."
	umask 0022
	for i in $(seq $num); do
		touch $DIR/$tdir/file-$i
	done
	do_facet $facet "$LCTL set_param fail_loc=0x15a"
	echo "launch $num chmod in parallel ($(date +%H:%M:%S)) ..."
	for i in $(seq $num); do
		chmod 0600 $DIR/$tdir/file-$i &
		pids="$pids $!"
	done
	sleep 1
	do_facet $facet "sync; sync; sync"
	do_facet $facet "$LCTL set_param fail_loc=0"
	fail $facet
	for pid in $pids; do
		wait $pid || error "chmod failed"
	done
	echo "done ($(date +%H:%M:%S))"
	for i in $(seq $num); do
		checkstat -vp 0600 $DIR/$tdir/file-$i
	done
	rm -rf $DIR/$tdir
}
run_test 102d "check replay & reconstruction with multiple mod RPCs in flight"
test_103() {
	remote_mds_nodsh && skip "remote MDS with nodsh"
	[[ "$MDS1_VERSION" -gt $(version_code 2.8.54) ]] ||
		skip "Need MDS version 2.8.54+"
	do_facet mds1 $LCTL set_param fail_loc=0x80000162
	mkdir -p $DIR/$tdir
	createmany -o $DIR/$tdir/t- 30 ||
		error "create files on remote directory failed"
	sync
	rm -rf $DIR/$tdir/t-*
	sync
	fail mds1
}
run_test 103 "Check otr_next_id overflow"
check_striped_dir_110()
{
	$CHECKSTAT -t dir $DIR/$tdir/striped_dir ||
			error "create striped dir failed"
	local stripe_count=$($LFS getdirstripe -c $DIR/$tdir/striped_dir)
	[ $stripe_count -eq $MDSCOUNT ] ||
		error "$stripe_count != 2 after recovery"
}
test_110a() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	mkdir -p $DIR/$tdir
	replay_barrier mds1
	$LFS mkdir -i1 -c$MDSCOUNT $DIR/$tdir/striped_dir
	fail mds1
	check_striped_dir_110 || error "check striped_dir failed"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 110a "DNE: create striped dir, fail MDT1"
test_110b() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	mkdir -p $DIR/$tdir
	replay_barrier mds1
	$LFS mkdir -i1 -c$MDSCOUNT $DIR/$tdir/striped_dir
	umount $MOUNT
	fail mds1
	zconf_mount $(hostname) $MOUNT
	client_up || return 1
	check_striped_dir_110 || error "check striped_dir failed"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 110b "DNE: create striped dir, fail MDT1 and client"
test_110c() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	mkdir -p $DIR/$tdir
	replay_barrier mds2
	$LFS mkdir -i1 -c$MDSCOUNT $DIR/$tdir/striped_dir
	fail mds2
	check_striped_dir_110 || error "check striped_dir failed"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 110c "DNE: create striped dir, fail MDT2"
test_110d() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	mkdir -p $DIR/$tdir
	replay_barrier mds2
	$LFS mkdir -i1 -c$MDSCOUNT $DIR/$tdir/striped_dir
	umount $MOUNT
	fail mds2
	zconf_mount $(hostname) $MOUNT
	client_up || return 1
	check_striped_dir_110 || error "check striped_dir failed"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 110d "DNE: create striped dir, fail MDT2 and client"
test_110e() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	mkdir -p $DIR/$tdir
	replay_barrier mds2
	$LFS mkdir -i1 -c$MDSCOUNT $DIR/$tdir/striped_dir
	umount $MOUNT
	replay_barrier mds1
	fail mds1,mds2
	zconf_mount $(hostname) $MOUNT
	client_up || return 1
	check_striped_dir_110 || error "check striped_dir failed"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 110e "DNE: create striped dir, uncommit on MDT2, fail client/MDT1/MDT2"
test_110f() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	mkdir -p $DIR/$tdir
	replay_barrier mds1
	replay_barrier mds2
	$LFS mkdir -i1 -c$MDSCOUNT $DIR/$tdir/striped_dir
	fail mds2,mds1
	check_striped_dir_110 || error "check striped_dir failed"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 110f "DNE: create striped dir, fail MDT1/MDT2"
test_110g() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	mkdir -p $DIR/$tdir
	replay_barrier mds1
	$LFS mkdir -i1 -c$MDSCOUNT $DIR/$tdir/striped_dir
	umount $MOUNT
	replay_barrier mds2
	fail mds1,mds2
	zconf_mount $(hostname) $MOUNT
	client_up || return 1
	check_striped_dir_110 || error "check striped_dir failed"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 110g "DNE: create striped dir, uncommit on MDT1, fail client/MDT1/MDT2"
test_111a() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	mkdir -p $DIR/$tdir
	$LFS mkdir -i1 -c2 $DIR/$tdir/striped_dir
	replay_barrier mds1
	rm -rf $DIR/$tdir/striped_dir
	fail mds1
	$CHECKSTAT -t dir $DIR/$tdir/striped_dir &&
			error "striped dir still exists"
	return 0
}
run_test 111a "DNE: unlink striped dir, fail MDT1"
test_111b() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	mkdir -p $DIR/$tdir
	$LFS mkdir -i1 -c2 $DIR/$tdir/striped_dir
	replay_barrier mds2
	rm -rf $DIR/$tdir/striped_dir
	umount $MOUNT
	fail mds2
	zconf_mount $(hostname) $MOUNT
	client_up || return 1
	$CHECKSTAT -t dir $DIR/$tdir/striped_dir &&
			error "striped dir still exists"
	return 0
}
run_test 111b "DNE: unlink striped dir, fail MDT2"
test_111c() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	mkdir -p $DIR/$tdir
	$LFS mkdir -i1 -c2 $DIR/$tdir/striped_dir
	replay_barrier mds1
	rm -rf $DIR/$tdir/striped_dir
	umount $MOUNT
	replay_barrier mds2
	fail mds1,mds2
	zconf_mount $(hostname) $MOUNT
	client_up || return 1
	$CHECKSTAT -t dir $DIR/$tdir/striped_dir &&
			error "striped dir still exists"
	return 0
}
run_test 111c "DNE: unlink striped dir, uncommit on MDT1, fail client/MDT1/MDT2"
test_111d() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	mkdir -p $DIR/$tdir
	$LFS mkdir -i1 -c2 $DIR/$tdir/striped_dir
	replay_barrier mds2
	rm -rf $DIR/$tdir/striped_dir
	umount $MOUNT
	replay_barrier mds1
	fail mds1,mds2
	zconf_mount $(hostname) $MOUNT
	client_up || return 1
	$CHECKSTAT -t dir $DIR/$tdir/striped_dir &&
			error "striped dir still exists"
	return 0
}
run_test 111d "DNE: unlink striped dir, uncommit on MDT2, fail client/MDT1/MDT2"
test_111e() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	mkdir -p $DIR/$tdir
	$LFS mkdir -i1 -c2 $DIR/$tdir/striped_dir
	replay_barrier mds2
	rm -rf $DIR/$tdir/striped_dir
	replay_barrier mds1
	fail mds1,mds2
	$CHECKSTAT -t dir $DIR/$tdir/striped_dir &&
			error "striped dir still exists"
	return 0
}
run_test 111e "DNE: unlink striped dir, uncommit on MDT2, fail MDT1/MDT2"
test_111f() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	mkdir -p $DIR/$tdir
	$LFS mkdir -i1 -c2 $DIR/$tdir/striped_dir
	replay_barrier mds1
	rm -rf $DIR/$tdir/striped_dir
	replay_barrier mds2
	fail mds1,mds2
	$CHECKSTAT -t dir $DIR/$tdir/striped_dir &&
			error "striped dir still exists"
	return 0
}
run_test 111f "DNE: unlink striped dir, uncommit on MDT1, fail MDT1/MDT2"
test_111g() {
	(( $MDSCOUNT >= 2 )) || skip "needs >= 2 MDTs"
	(( $MDS1_VERSION >= $(version_code 2.7.56) )) ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE != "HARD" ] ||
		[ "$(facet_host mds1)" != "$(facet_host mds2)" ]) ||
		skip "MDTs needs to be on diff hosts for HARD fail mode"
	mkdir -p $DIR/$tdir
	$LFS mkdir -i1 -c2 $DIR/$tdir/striped_dir
	$LFS df -i
	replay_barrier mds1
	replay_barrier mds2
	rm -rf $DIR/$tdir/striped_dir
	fail mds1,mds2
	$CHECKSTAT -t dir $DIR/$tdir/striped_dir &&
		error "striped dir still exists"
	return 0
}
run_test 111g "DNE: unlink striped dir, fail MDT1/MDT2"
test_112_rename_prepare() {
	mkdir_on_mdt0 $DIR/$tdir
	mkdir -p $DIR/$tdir/src_dir
	$LFS mkdir -i 1 $DIR/$tdir/src_dir/src_child ||
		error "create remote source failed"
	touch $DIR/$tdir/src_dir/src_child/a
	$LFS mkdir -i 2 $DIR/$tdir/tgt_dir ||
		error "create remote target dir failed"
	$LFS mkdir -i 3 $DIR/$tdir/tgt_dir/tgt_child ||
		error "create remote target child failed"
}
test_112_check() {
	find $DIR/$tdir/
	$CHECKSTAT -t dir $DIR/$tdir/src_dir/src_child &&
		error "src_child still exists after rename"
	$CHECKSTAT -t file $DIR/$tdir/tgt_dir/tgt_child/a ||
		error "missing file(a) after rename"
}
test_112a() {
	[ $MDSCOUNT -lt 4 ] && skip "needs >= 4 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	test_112_rename_prepare
	replay_barrier mds1
	mrename $DIR/$tdir/src_dir/src_child $DIR/$tdir/tgt_dir/tgt_child ||
		error "rename dir cross MDT failed!"
	fail mds1
	test_112_check
	rm -rf $DIR/$tdir || error "rmdir failed"
}
run_test 112a "DNE: cross MDT rename, fail MDT1"
test_112b() {
	[ $MDSCOUNT -lt 4 ] && skip "needs >= 4 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	test_112_rename_prepare
	replay_barrier mds2
	mrename $DIR/$tdir/src_dir/src_child $DIR/$tdir/tgt_dir/tgt_child ||
		error "rename dir cross MDT failed!"
	fail mds2
	test_112_check
	rm -rf $DIR/$tdir || error "rmdir failed"
}
run_test 112b "DNE: cross MDT rename, fail MDT2"
test_112c() {
	[ $MDSCOUNT -lt 4 ] && skip "needs >= 4 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	test_112_rename_prepare
	replay_barrier mds3
	mrename $DIR/$tdir/src_dir/src_child $DIR/$tdir/tgt_dir/tgt_child ||
		error "rename dir cross MDT failed!"
	fail mds3
	test_112_check
	rm -rf $DIR/$tdir || error "rmdir failed"
}
run_test 112c "DNE: cross MDT rename, fail MDT3"
test_112d() {
	[ $MDSCOUNT -lt 4 ] && skip "needs >= 4 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	test_112_rename_prepare
	replay_barrier mds4
	mrename $DIR/$tdir/src_dir/src_child $DIR/$tdir/tgt_dir/tgt_child ||
		error "rename dir cross MDT failed!"
	fail mds4
	test_112_check
	rm -rf $DIR/$tdir || error "rmdir failed"
}
run_test 112d "DNE: cross MDT rename, fail MDT4"
test_112e() {
	[ $MDSCOUNT -lt 4 ] && skip "needs >= 4 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	test_112_rename_prepare
	replay_barrier mds1
	replay_barrier mds2
	mrename $DIR/$tdir/src_dir/src_child $DIR/$tdir/tgt_dir/tgt_child ||
		error "rename dir cross MDT failed!"
	fail mds1,mds2
	test_112_check
	rm -rf $DIR/$tdir || error "rmdir failed"
}
run_test 112e "DNE: cross MDT rename, fail MDT1 and MDT2"
test_112f() {
	[ $MDSCOUNT -lt 4 ] && skip "needs >= 4 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	test_112_rename_prepare
	replay_barrier mds1
	replay_barrier mds3
	mrename $DIR/$tdir/src_dir/src_child $DIR/$tdir/tgt_dir/tgt_child ||
		error "rename dir cross MDT failed!"
	fail mds1,mds3
	test_112_check
	rm -rf $DIR/$tdir || error "rmdir failed"
}
run_test 112f "DNE: cross MDT rename, fail MDT1 and MDT3"
test_112g() {
	[ $MDSCOUNT -lt 4 ] && skip "needs >= 4 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	test_112_rename_prepare
	replay_barrier mds1
	replay_barrier mds4
	mrename $DIR/$tdir/src_dir/src_child $DIR/$tdir/tgt_dir/tgt_child ||
		error "rename dir cross MDT failed!"
	fail mds1,mds4
	test_112_check
	rm -rf $DIR/$tdir || error "rmdir failed"
}
run_test 112g "DNE: cross MDT rename, fail MDT1 and MDT4"
test_112h() {
	[ $MDSCOUNT -lt 4 ] && skip "needs >= 4 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	test_112_rename_prepare
	replay_barrier mds2
	replay_barrier mds3
	mrename $DIR/$tdir/src_dir/src_child $DIR/$tdir/tgt_dir/tgt_child ||
		error "rename dir cross MDT failed!"
	fail mds2,mds3
	test_112_check
	rm -rf $DIR/$tdir || error "rmdir failed"
}
run_test 112h "DNE: cross MDT rename, fail MDT2 and MDT3"
test_112i() {
	[ $MDSCOUNT -lt 4 ] && skip "needs >= 4 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	test_112_rename_prepare
	replay_barrier mds2
	replay_barrier mds4
	mrename $DIR/$tdir/src_dir/src_child $DIR/$tdir/tgt_dir/tgt_child ||
		error "rename dir cross MDT failed!"
	fail mds2,mds4
	test_112_check
	rm -rf $DIR/$tdir || error "rmdir failed"
}
run_test 112i "DNE: cross MDT rename, fail MDT2 and MDT4"
test_112j() {
	[ $MDSCOUNT -lt 4 ] && skip "needs >= 4 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	test_112_rename_prepare
	replay_barrier mds3
	replay_barrier mds4
	mrename $DIR/$tdir/src_dir/src_child $DIR/$tdir/tgt_dir/tgt_child ||
		error "rename dir cross MDT failed!"
	fail mds3,mds4
	test_112_check
	rm -rf $DIR/$tdir || error "rmdir failed"
}
run_test 112j "DNE: cross MDT rename, fail MDT3 and MDT4"
test_112k() {
	[ $MDSCOUNT -lt 4 ] && skip "needs >= 4 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	test_112_rename_prepare
	replay_barrier mds1
	replay_barrier mds2
	replay_barrier mds3
	mrename $DIR/$tdir/src_dir/src_child $DIR/$tdir/tgt_dir/tgt_child ||
		error "rename dir cross MDT failed!"
	fail mds1,mds2,mds3
	test_112_check
	rm -rf $DIR/$tdir || error "rmdir failed"
}
run_test 112k "DNE: cross MDT rename, fail MDT1,MDT2,MDT3"
test_112l() {
	[ $MDSCOUNT -lt 4 ] && skip "needs >= 4 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	test_112_rename_prepare
	replay_barrier mds1
	replay_barrier mds2
	replay_barrier mds4
	mrename $DIR/$tdir/src_dir/src_child $DIR/$tdir/tgt_dir/tgt_child ||
		error "rename dir cross MDT failed!"
	fail mds1,mds2,mds4
	test_112_check
	rm -rf $DIR/$tdir || error "rmdir failed"
}
run_test 112l "DNE: cross MDT rename, fail MDT1,MDT2,MDT4"
test_112m() {
	[ $MDSCOUNT -lt 4 ] && skip "needs >= 4 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	test_112_rename_prepare
	replay_barrier mds1
	replay_barrier mds3
	replay_barrier mds4
	mrename $DIR/$tdir/src_dir/src_child $DIR/$tdir/tgt_dir/tgt_child ||
		error "rename dir cross MDT failed!"
	fail mds1,mds3,mds4
	test_112_check
	rm -rf $DIR/$tdir || error "rmdir failed"
}
run_test 112m "DNE: cross MDT rename, fail MDT1,MDT3,MDT4"
test_112n() {
	[ $MDSCOUNT -lt 4 ] && skip "needs >= 4 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	test_112_rename_prepare
	replay_barrier mds2
	replay_barrier mds3
	replay_barrier mds4
	mrename $DIR/$tdir/src_dir/src_child $DIR/$tdir/tgt_dir/tgt_child ||
		error "rename dir cross MDT failed!"
	fail mds2,mds3,mds4
	test_112_check
	rm -rf $DIR/$tdir || error "rmdir failed"
}
run_test 112n "DNE: cross MDT rename, fail MDT2,MDT3,MDT4"
test_115() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[[ "$MDS1_VERSION" -ge $(version_code 2.7.56) ]] ||
		skip "Need MDS version at least 2.7.56"
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	local fail_index=0
	local index
	local i
	local j
	mkdir -p $DIR/$tdir
	for ((j=0;j<$((MDSCOUNT));j++)); do
		fail_index=$((fail_index+1))
		index=$((fail_index % MDSCOUNT))
		replay_barrier mds$((index + 1))
		for ((i=0;i<5;i++)); do
			test_mkdir -i$index -c$MDSCOUNT $DIR/$tdir/test_$i ||
				error "create striped dir $DIR/$tdir/test_$i"
		done
		fail mds$((index + 1))
		for ((i=0;i<5;i++)); do
			checkstat -t dir $DIR/$tdir/test_$i ||
				error "$DIR/$tdir/test_$i does not exist!"
		done
		rm -rf $DIR/$tdir/test_* ||
				error "rmdir fails"
	done
}
run_test 115 "failover for create/unlink striped directory"
test_116a() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[ "$MDS1_VERSION" -lt $(version_code 2.7.55) ] &&
		skip "Do not support large update log before 2.7.55" &&
		return 0
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	local fail_index=0
	mkdir_on_mdt0 $DIR/$tdir
	replay_barrier mds1
	do_facet mds1 "lctl set_param fail_loc=0x80001702"
	$LFS setdirstripe -i0 -c$MDSCOUNT $DIR/$tdir/striped_dir
	fail mds1
	$CHECKSTAT -t dir $DIR/$tdir/striped_dir ||
		error "stried_dir does not exists"
}
run_test 116a "large update log master MDT recovery"
test_116b() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[ "$MDS1_VERSION" -lt $(version_code 2.7.55) ] &&
		skip "Do not support large update log before 2.7.55" &&
		return 0
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	local fail_index=0
	mkdir_on_mdt0 $DIR/$tdir
	replay_barrier mds2
	do_facet mds2 "lctl set_param fail_loc=0x80001702"
	$LFS setdirstripe -i0 -c$MDSCOUNT $DIR/$tdir/striped_dir
	fail mds2
	$CHECKSTAT -t dir $DIR/$tdir/striped_dir ||
		error "stried_dir does not exists"
}
run_test 116b "large update log slave MDT recovery"
test_117() {
	[ $MDSCOUNT -lt 4 ] && skip "needs >= 4 MDTs" && return 0
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	local index
	local mds_indexs
	mkdir -p $DIR/$tdir
	$LFS setdirstripe -i0 -c$MDSCOUNT $DIR/$tdir/remote_dir
	$LFS setdirstripe -i1 -c$MDSCOUNT $DIR/$tdir/remote_dir_1
	sleep 2
	for ((index = 0; index < $((MDSCOUNT)); index++)); do
		replay_barrier mds$((index + 1))
		if [ -z $mds_indexs ]; then
			mds_indexs="${mds_indexs}mds$((index+1))"
		else
			mds_indexs="${mds_indexs},mds$((index+1))"
		fi
	done
	rm -rf $DIR/$tdir/remote_dir
	rm -rf $DIR/$tdir/remote_dir_1
	fail $mds_indexs
	rm -rf $DIR/$tdir || error "rmdir failed"
}
run_test 117 "DNE: cross MDT unlink, fail MDT1 and MDT2"
test_118() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[ "$MDS1_VERSION" -lt $(version_code 2.7.64) ] &&
		skip "Do not support large update log before 2.7.64" &&
		return 0
	mkdir -p $DIR/$tdir
	$LFS setdirstripe -c2 $DIR/$tdir/striped_dir ||
		error "setdirstripe fails"
	$LFS setdirstripe -c2 $DIR/$tdir/striped_dir1 ||
		error "setdirstripe fails 1"
	rm -rf $DIR/$tdir/striped_dir* || error "rmdir fails"
	do_facet mds1 "lctl set_param fail_loc=0x1705"
	$LFS setdirstripe -c2 $DIR/$tdir/striped_dir
	$LFS setdirstripe -c2 $DIR/$tdir/striped_dir1
	do_facet mds1 "lctl set_param fail_loc=0x0"
	replay_barrier mds1
	$LFS setdirstripe -c2 $DIR/$tdir/striped_dir
	$LFS setdirstripe -c2 $DIR/$tdir/striped_dir1
	fail mds1
	true
}
run_test 118 "invalidate osp update will not cause update log corruption"
test_119() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[ "$MDS1_VERSION" -lt $(version_code 2.7.64) ] &&
		skip "Do not support large update log before 2.7.64" &&
		return 0
	local stripe_count
	local hard_timeout=$(do_facet mds1 \
		"lctl get_param -n mdt.$FSNAME-MDT0000.recovery_time_hard")
	local clients=${CLIENTS:-$HOSTNAME}
	local time_min=$(recovery_time_min)
	mkdir_on_mdt0 $DIR/$tdir
	mkdir $DIR/$tdir/tmp
	rmdir $DIR/$tdir/tmp
	replay_barrier mds1
	mkdir $DIR/$tdir/dir_1
	for ((i = 0; i < 20; i++)); do
		$LFS setdirstripe -i0 -c2 $DIR/$tdir/stripe_dir-$i
	done
	stop mds1
	change_active mds1
	wait_for_facet mds1
	do_facet mds1 $LCTL set_param fail_loc=0x80000714
	do_facet mds1 $LCTL set_param fail_val=$((time_min + 5))
	mount_facet mds1 "-o recovery_time_hard=$time_min"
	wait_clients_import_state "$clients" mds1 FULL
	clients_up || clients_up || error "failover df: $?"
	do_facet mds1 $LCTL set_param \
		mdt.$FSNAME-MDT0000.recovery_time_hard=$hard_timeout
	for ((i = 0; i < 20; i++)); do
		stripe_count=$($LFS getdirstripe -c $DIR/$tdir/stripe_dir-$i)
		[ $stripe_count == 2 ] || {
			error "stripe_dir-$i creation replay fails"
			break
		}
	done
}
run_test 119 "timeout of normal replay does not cause DNE replay fails  "
test_120() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[ "$MDS1_VERSION" -lt $(version_code 2.7.64) ] &&
		skip "Do not support large update log before 2.7.64" &&
		return 0
	mkdir_on_mdt0 $DIR/$tdir
	replay_barrier_nosync mds1
	for ((i = 0; i < 20; i++)); do
		mkdir $DIR/$tdir/dir-$i || {
			error "create dir-$i fails"
			break
		}
		$LFS setdirstripe -i0 -c2 $DIR/$tdir/stripe_dir-$i || {
			error "create stripe_dir-$i fails"
			break
		}
	done
	stack_trap fail_abort_cleanup RETURN
	fail_abort mds1
	for ((i = 0; i < 20; i++)); do
		[ ! -e "$DIR/$tdir/dir-$i" ] || {
			error "dir-$i still exists"
			break
		}
		[ ! -e "$DIR/$tdir/stripe_dir-$i" ] || {
			error "stripe_dir-$i still exists"
			break
		}
	done
}
run_test 120 "DNE fail abort should stop both normal and DNE replay"
test_121() {
	[ "$MDS1_VERSION" -lt $(version_code 2.10.90) ] &&
		skip "Don't support it before 2.11" &&
		return 0
	local at_max_saved=$(at_max_get mds)
	touch $DIR/$tfile || error "touch $DIR/$tfile failed"
	cancel_lru_locks mdc
	multiop_bg_pause $DIR/$tfile s_s || error "multiop $DIR/$tfile failed"
	mpid=$!
	lctl set_param -n ldlm.cancel_unused_locks_before_replay "0"
	stop mds1
	change_active mds1
	wait_for_facet mds1
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x721 fail_val=0"
	at_max_set 0 mds
	mount_facet mds1
	wait_clients_import_state "$clients" mds1 FULL
	clients_up || clients_up || error "failover df: $?"
	kill -USR1 $mpid
	wait $mpid || error "multiop_bg_pause pid failed"
	do_facet $SINGLEMDS "lctl set_param fail_loc=0x0"
	lctl set_param -n ldlm.cancel_unused_locks_before_replay "1"
	at_max_set $at_max_saved mds
	rm -f $DIR/$tfile
}
run_test 121 "lock replay timed out and race"
test_130a() {
	[ "$MDS1_VERSION" -lt $(version_code 2.10.90) ] &&
		skip "Do not support Data-on-MDT before 2.11"
	replay_barrier $SINGLEMDS
	$LFS setstripe -E 1M -L mdt -E EOF -c 2 $DIR/$tfile
	fail $SINGLEMDS
	[ $($LFS getstripe -L $DIR/$tfile) == "mdt" ] ||
		error "Fail to replay DoM file creation"
}
run_test 130a "DoM file create (setstripe) replay"
test_130b() {
	[ "$MDS1_VERSION" -lt $(version_code 2.10.90) ] &&
		skip "Do not support Data-on-MDT before 2.11"
	mkdir_on_mdt0 $DIR/$tdir
	$LFS setstripe -E 1M -L mdt -E EOF -c 2 $DIR/$tdir
	replay_barrier $SINGLEMDS
	touch $DIR/$tdir/$tfile
	fail $SINGLEMDS
	[ $($LFS getstripe -L $DIR/$tdir/$tfile) == "mdt" ] ||
		error "Fail to replay DoM file creation"
}
run_test 130b "DoM file create (inherited) replay"
test_131a() {
	[ "$MDS1_VERSION" -lt $(version_code 2.10.90) ] &&
		skip "Do not support Data-on-MDT before 2.11"
	$LFS setstripe -E 1M -L mdt -E EOF -c 2 $DIR/$tfile
	replay_barrier $SINGLEMDS
	echo "dom_data" | dd of=$DIR/$tfile bs=8 count=1
	fail $SINGLEMDS
	[ $(cat $DIR/$tfile) == "dom_data" ] ||
		error "Wrong file content after failover"
}
run_test 131a "DoM file write lock replay"
test_131b() {
	[ "$MDS1_VERSION" -lt $(version_code 2.10.90) ] &&
		skip "Do not support Data-on-MDT before 2.11"
	$LFS setstripe -E 1M -L mdt -E EOF -c 2 $DIR/$tfile-2
	stack_trap "rm -f $DIR/$tfile-2"
	dd if=/dev/zero of=$DIR/$tfile-2 bs=64k count=2 ||
		error "can't dd"
	$LFS setstripe -E 1M -L mdt -E EOF -c 2 $DIR/$tfile
	replay_barrier $SINGLEMDS
	echo "dom_data" | dd of=$DIR/$tfile bs=8 count=1
	cancel_lru_locks mdc
	fail $SINGLEMDS
	[ $(cat $DIR/$tfile) == "dom_data" ] ||
		error "Wrong file content after failover"
}
run_test 131b "DoM file write replay"
test_132a() {
	[ "$MDS1_VERSION" -lt $(version_code 2.12.0) ] &&
		skip "Need MDS version 2.12.0 or later"
	$LFS setstripe -E 1M -c 1 -E EOF -c 2 $DIR/$tfile
	replay_barrier $SINGLEMDS
	dd if=/dev/urandom of=$DIR/$tfile bs=1M count=1 seek=1 ||
		error "dd to $DIR/$tfile failed"
	lfs getstripe $DIR/$tfile
	cksum=$(md5sum $DIR/$tfile | awk '{print $1}')
	$LFS getstripe -I2 $DIR/$tfile | grep -q lmm_objects ||
		error "Component
	fail $SINGLEMDS
	lfs getstripe $DIR/$tfile
	$LFS getstripe -I2 $DIR/$tfile | grep -q lmm_objects ||
		error "Component
	cksum2=$(md5sum $DIR/$tfile | awk '{print $1}')
	if [ $cksum != $cksum2 ] ; then
		error_noexit "New cksum $cksum2 does not match original $cksum"
	fi
}
run_test 132a "PFL new component instantiate replay"
test_133() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	([ $FAILURE_MODE == "HARD" ] &&
		[ "$(facet_host mds1)" == "$(facet_host mds2)" ]) &&
		skip "MDTs needs to be on diff hosts for HARD fail mode" &&
		return 0
	local remote_dir=$DIR/$tdir/remote_dir
	mkdir -p $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	$LFS mkdir -i 1 $remote_dir
	umount $MOUNT
	do_facet mds2 $LCTL set_param seq.srv*MDT0001.space=clear
	zconf_mount $(hostname) $MOUNT
	client_up || return 1
	do_facet mds1 $LCTL set_param fail_val=700 fail_loc=0x80000123
	cp /etc/hosts $remote_dir/file &
	local pid=$!
	sleep 1
	fail_nodf mds1
	wait $pid || error "cp failed"
	rm -rf $DIR/$tdir || error "rmdir failed"
	return 0
}
run_test 133 "check resend of ongoing requests for lwp during failover"
test_134() {
	[ $OSTCOUNT -lt 2 ] && skip "needs >= 2 OSTs" && return 0
	(( $MDS1_VERSION >= $(version_code 2.13.56) )) ||
		skip "need MDS version >= 2.13.56"
	pool_add pool_134
	pool_add_targets pool_134 1 1
	mkdir -p $DIR/$tdir/{A,B}
	$LFS setstripe -p pool_134 $DIR/$tdir/A
	$LFS setstripe -E EOF -p pool_134 $DIR/$tdir/B
	replay_barrier mds1
	touch $DIR/$tdir/A/$tfile || error "touch non-pfl file failed"
	touch $DIR/$tdir/B/$tfile || error "touch pfl failed"
	fail mds1
	[ -f $DIR/$tdir/A/$tfile ] || error "non-pfl file does not exist"
	[ -f $DIR/$tdir/B/$tfile ] || error "pfl file does not exist"
}
run_test 134 "replay creation of a file created in a pool"
test_135() {
	local PID
	local old_replay
	[[ $(facet_active ost1) == "ost1" ]] || fail ost1
	mkdir $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	$LFS setstripe -S $((128 * 1024)) -i 0 $DIR/$tdir
	touch $DIR/$tdir/file.{1..20}
	clients_up
	replay_barrier ost1
	old_replay=$($LCTL get_param ldlm.cancel_unused_locks_before_replay)
	$LCTL set_param ldlm.cancel_unused_locks_before_replay=0
	stack_trap "$LCTL set_param $old_replay" EXIT
	local old_debug=$($LCTL get_param -n debug)
	local old_debug_mb=$($LCTL get_param -n debug_mb)
	$LCTL set_param debug_mb=100 debug='+info +ha +dlmtrace'
	stack_trap "$LCTL set_param debug_mb=$old_debug_mb debug='$old_debug'"
	printf "%s\n" $DIR/$tdir/file.{1..20} |
		xargs -I{} -P20 dd if=/dev/urandom of={} bs=1K count=1 &> /dev/null
	stop ost1
	change_active ost1
	wait_for_facet ost1
	do_rpc_nodes $(facet_active_host ost1) \
		load_module ../libcfs/libcfs/libcfs
	do_facet ost1 "$LCTL set_param fail_loc=0x32d fail_val=20"
	do_facet ost1 "$LCTL set_param debug_mb=100 debug='+info +ha +dlmtrace'"
	mount_facet ost1
	(sync;sync;sync;echo "End of sync") & PID=$!
	wait_clients_import_state ${HOSTNAME} ost1 REPLAY_LOCKS
	kill -0 $PID || error "Unexpected sync success"
	shutdown_facet ost1
	reboot_facet ost1
	change_active ost1
	wait_for_facet ost1
	do_rpc_nodes $(facet_active_host ost1) \
		load_module ../libcfs/libcfs/libcfs
	do_facet ost1 "$LCTL set_param fail_loc=0"
	mount_facet ost1
	unmountoss
	mountoss
	clients_up || clients_up || error "$LFS df $MOUNT failed"
	wait $PID || error "Fail to sync"
	echo blah > $DIR/$tdir/file.test2
	rm -rf $DIR/$tdir
}
run_test 135 "Server failure in lock replay phase"
test_136() {
	(( $MDSCOUNT >= 3 )) || skip "needs > 2 MDTs"
	(( MDS1_VERSION >= $(version_code 2.15.53) )) ||
		skip "need MDS version >= 2.15.53 for LU-16536 fix"
	$LFS mkdir -i0 -c3 $DIR/$tdir || error "can't mkdir"
	$LFS getdirstripe $DIR/$tdir
	sync;sync;sync
	local mdts=$(mdts_nodes)
	do_nodes $mdts $LCTL set_param fail_loc=0x170b
	rmdir $DIR/$tdir &
	sleep 0.5
	stop mds2
	stop mds3
	stop mds1
	start mds1 $(mdsdevname 1) $MDS_MOUNT_OPTS || error "MDT1 start failed"
	start mds2 $(mdsdevname 2) $MDS_MOUNT_OPTS || error "MDT2 start failed"
	start mds3 $(mdsdevname 3) $MDS_MOUNT_OPTS || error "MDT3 star"
}
run_test 136 "MDS to disconnect all OSPs first, then cleanup ldlm"
check_striped_create_137() {
	local stripe_count
	cancel_lru_locks mdc
	$CHECKSTAT -t dir $DIR/$tdir/striped_dir/dir0 ||
		error "Create under striped dir failed"
	$LFS getdirstripe $DIR/$tdir/striped_dir/dir0
	stripe_count=$($LFS getdirstripe -c $DIR/$tdir/striped_dir/dir0)
	[ $stripe_count -eq 0 ] || error "$stripe_count != 0 after recovery"
	$CHECKSTAT -t dir $DIR/$tdir/striped_dir/dir1 ||
		error "Create under striped dir failed"
	$LFS getdirstripe $DIR/$tdir/striped_dir/dir1
	stripe_count=$($LFS getdirstripe -c $DIR/$tdir/striped_dir/dir1)
	[ $stripe_count -eq 0 ] || error "$stripe_count != 0 after recovery"
}
test_137a() {
	(( $MDSCOUNT >= 2 )) || skip "needs >= 2 MDTs"
	(( $MDS1_VERSION >= $(version_code v2_15_62-70-g668dfb53de) )) ||
		skip "Need MDS >= 2.15.62.70 for intent mkdir"
	[[ $FAILURE_MODE != "HARD" ]] ||
		[[ "$(facet_host mds1)" != "$(facet_host mds2)" ]] ||
		skip "MDTs needs to be on diff hosts for HARD fail mode"
	local save="$TMP/$TESTSUITE-$TESTNAME.parameters"
	save_lustre_params client "llite.*.intent_mkdir" > $save
	stack_trap "restore_lustre_params < $save; rm -f $save" EXIT
	$LCTL set_param llite.*.intent_mkdir=1
	mkdir -p $DIR/$tdir
	$LFS mkdir -i1 -c$MDSCOUNT $DIR/$tdir/striped_dir
	replay_barrier mds1
	mkdir $DIR/$tdir/striped_dir/dir0
	mkdir $DIR/$tdir/striped_dir/dir1
	fail mds1
	check_striped_create_137 || error "check striped dir0 failed"
	rm -rf $DIR/$tdir || error "rm -rf $DIR/$tdir failed"
}
run_test 137a "DNE: create under striped dir, fail MDT1"
test_137b() {
	(( $MDSCOUNT >= 2 )) || skip "needs >= 2 MDTs"
	(( $MDS1_VERSION >= $(version_code v2_15_62-70-g668dfb53de) )) ||
		skip "Need MDS version at least 2.15.62.70 for intent mkdir"
	[[ $FAILURE_MODE != "HARD" ]] ||
		[[ "$(facet_host mds1)" != "$(facet_host mds2)" ]] ||
		skip "MDTs needs to be on diff hosts for HARD fail mode"
	local save="$TMP/$TESTSUITE-$TESTNAME.parameters"
	save_lustre_params client "llite.*.intent_mkdir" > $save
	stack_trap "restore_lustre_params < $save; rm -f $save" EXIT
	$LCTL set_param llite.*.intent_mkdir=1
	mkdir -p $DIR/$tdir
	$LFS mkdir -i1 -c$MDSCOUNT $DIR/$tdir/striped_dir
	replay_barrier mds2
	mkdir $DIR/$tdir/striped_dir/dir0
	mkdir $DIR/$tdir/striped_dir/dir1
	fail mds2
	check_striped_create_137 ||
		error "check create under striped_dir failed"
	rm -rf $DIR/$tdir
}
run_test 137b "DNE: create under striped dir, fail MDT2"
test_137c() {
	(( $MDSCOUNT >= 2 )) || skip "needs >= 2 MDTs"
	(( $MDS1_VERSION >= $(version_code v2_15_62-70-g668dfb53de) )) ||
		skip "Need MDS version at least 2.15.62.70 for intent mkdir"
	[[ $FAILURE_MODE != "HARD" ]] ||
		[[ "$(facet_host mds1)" != "$(facet_host mds2)" ]] ||
		skip "MDTs needs to be on diff hosts for HARD fail mode"
	local save="$TMP/$TESTSUITE-$TESTNAME.parameters"
	save_lustre_params client "llite.*.intent_mkdir" > $save
	stack_trap "restore_lustre_params < $save; rm -f $save" EXIT
	$LCTL set_param llite.*.intent_mkdir=1
	mkdir -p $DIR/$tdir
	$LFS mkdir -i1 -c$MDSCOUNT $DIR/$tdir/striped_dir
	replay_barrier mds1
	replay_barrier mds2
	mkdir $DIR/$tdir/striped_dir/dir0
	mkdir $DIR/$tdir/striped_dir/dir1
	fail mds2,mds1
	check_striped_create_137 ||
		error "check create under striped_dir failed"
	rm -rf $DIR/$tdir
}
run_test 137c "DNE: create under striped dir, fail MDT1/MDT2"
test_200() {
	[[ -z $RCLIENTS ]] && skip "Need remote client"
	local rcli old
	rcli=$(echo $RCLIENTS | cut -d ' ' -f 1)
	echo "Selected \"$rcli\" from \"$RCLIENTS\""
	old=$(do_node $rcli "$LCTL get_param -n *.*.idle_timeout 2>/dev/null |
	      head -n 1")
	[[ -n $old ]] || error "Cannot determine current idle_timeout"
	if ((old == 0)); then
		do_node "$rcli" "$LCTL set_param *.*.idle_timeout=10"
		do_node "$rcli" "$LCTL set_param osc.*OST0000*.idle_timeout=0"
		stack_trap "do_node $rcli $LCTL set_param *.*.idle_timeout=$old"
	else
		do_node "$rcli" "$LCTL set_param osc.*OST0000*.idle_timeout=0"
		stack_trap "do_node $rcli $LCTL set_param osc.*OST0000*.idle_timeout=$old"
	fi
	wait_update "$rcli" \
		"$LCTL get_param osc.*OST0000*.import | \
		 awk 'BEGIN{ count=0 } /idle: 0/ { count+=1 } \
		      END { print count }'" \
		"0" "30"
	(( $? != 0 )) && error "OST0000 not idle after 30s"
	do_node "$rcli" "lctl set_param osc.*OST0000*.ping=1" ||
		error "OBD ping failed"
	declare -a conns
	conns=( $(do_node "$rcli" "$LCTL get_param *.*.import" |
		  awk '/connection_attempts:/{print $NF}' | xargs echo) )
	local saved_debug
	saved_debug=$(do_node "$rcli" \
		      "cat /sys/module/libcfs/parameters/libcfs_debug" \
		      2>/dev/null)
	[[ -z $saved_debug ]] && error "Failed to get existing debug"
	stack_trap "do_node $rcli $LCTL set_param debug=$saved_debug"
	do_node "$rcli" "$LCTL set_param debug=+info+rpctrace"
	local timeout delay
	timeout=$(do_node "$rcli" "$LCTL get_param -n timeout")
	(( timeout > 4 )) && delay=$((3 * timeout / 4)) || delay=3
	do_node "$rcli" "$LCTL clear"
	log "delay ping ${delay}s"
	do_node "$rcli" "$LCTL set_param fail_loc=0x80000535 fail_val=${delay}"
	do_node "$rcli" "lctl set_param osc.*OST0000*.ping=1"
	local logfile="$TMP/lustre-log-${TESTNAME}.log"
	local nsent expired
	local waited=0
	local begin=$SECONDS
	local max_wait=$((delay + 1))
	local reason=""
	local sleep=""
	while (( $waited <= $max_wait )); do
		[[ -z $sleep ]] || sleep $sleep
		sleep=1
		waited=$((SECONDS - begin))
		do_node "$rcli" "$LCTL dk" >> ${logfile}
		if ! grep -q 'fail_timeout id 535 sleeping for' $logfile; then
			reason="Did not hit fail_loc"
			continue
		fi
		if ! grep -q 'cfs_fail_timeout id 535 awake' $logfile; then
			reason="Delayed send did not wake"
			continue
		fi
		nsent=$(grep -c "ptl_send_rpc.*o400->.*OST0000" $logfile)
		if (( nsent <= 1 )); then
			reason="Did not send more than 1 obd ping"
			continue
		fi
		expired=$(grep "Request sent has timed out .* o400->" $logfile)
		if [[ -z $expired ]]; then
			reason="RPC did not time out"
			continue
		fi
		reason=""
		break
	done
	if [[ -n $reason ]]; then
		cat $logfile
		rm -f $logfile
		error "$reason"
	else
		echo "${expired}"
		rm -f $logfile
	fi
	declare -a conns2
	conns2=( $(do_node "$rcli" "$LCTL get_param *.*.import" |
		   awk '/connection_attempts:/{print $NF}' | xargs echo) )
	echo "conns: ${conns[*]}"
	echo "conns2: ${conns2[*]}"
	(( ${
		error "Expected ${
	local i
	for ((i = 0; i < ${
		if (( conns[i] != conns2[i] )); then
			error "New connection attempt ${conns[i]} -> ${conns2[i]}"
		fi
	done
	return 0
}
run_test 200 "Dropping one OBD_PING should not cause disconnect"
test_201() {
	(( MDS1_VERSION >= $(version_code 2.15.63) )) ||
		skip "MDS < 2.15.63 doesn't support parallel disconnect"
	(( MDSCOUNT >= 2 )) || skip_env "needs >= 2 MDTs"
	(( OSTCOUNT >= 2 )) || skip_env "needs >= 2 OSTs"
	do_nodes $(comma_list $(mdts_nodes)) "$LCTL set_param \
					      fail_loc=0x245 fail_val=8"
	do_nodes $(comma_list $(osts_nodes)) "$LCTL set_param \
					      fail_loc=0x245 fail_val=8"
	local start_time=$SECONDS
	stop mds2
	local duration=$((SECONDS - start_time))
	start mds2 $(mdsdevname 2) $MDS_MOUNT_OPTS ||
			error "mount mds2 failed"
	echo "Umount took $duration seconds"
	(( duration <= (20 + OSTCOUNT) )) || error "Cascading timeouts on disconnect"
}
run_test 201 "MDT umount cascading disconnects timeouts"
test_202() {
	local td=$DIR/$tdir
	local tf=$td/$tfile
	if ! do_facet $SINGLEMDS $LCTL get_param version | grep "ddn"; then
		(( $MDS1_VERSION >= $(version_code v2_16_50-35-gc66a7dea85) )) ||
		(( $MDS1_VERSION < $(version_code v2_15_55-64-g13557aa869) &&
		   $MDS1_VERSION >= $(version_code v2_15_6-RC1) )) ||
			skip "need MDS with LU-18435 fix for layout version"
	else
		(( $MDS1_VERSION >= $(version_code 2.14.0-ddn180) )) ||
		(( $MDS1_VERSION < $(version_code 2.14.0-ddn86-14-gf1bd967799) &&
		   $MDS1_VERSION >= $(version_code 2.14.0-ddn1) )) ||
		(( $MDS1_VERSION < $(version_code 2.12.9-ddn19-4-g3455e9100f) )) ||
			skip "need MDS with LU-18435 fix for layout version"
	fi
	mkdir_on_mdt0 $td || error "can't mkdir"
	$LFS setstripe -E128M -c1 -Eeof -c2 $td || error "can't setstripe"
	replay_barrier mds1
	touch $tf
	local before=$($LFS getstripe -v $tf|awk '/lcm_layout_gen:/{print $2}')
	fail mds1
	cancel_lru_locks mdc
	local after=$($LFS getstripe -v $tf|awk '/lcm_layout_gen:/{print $2}')
	(( $before == $after )) || error "layout gen changed: $before -> $after"
}
run_test 202 "pfl replay should recovery layout generation"
test_203() {
	mount_client $MOUNT2
	stack_trap "umount_client $MOUNT2"
	local start=$SECONDS
	do_facet mds1 "$LCTL set_param fail_loc=0x80002403 fail_val=2"
	echo "STAT"
	stat $MOUNT/$tfile &
	local PID=$!
	sleep 0.5
	echo "SETSTRIPE"
	$LFS setstripe -E 1MB -c -1 -E 2MB -c -1 -E 3MB -c -1 -E 4MB -c -1 \
		-E 5MB -c -1 -E 6MB -c -1 -E 7MB -c -1 -E 8MB -c -1 \
		-E 9MB -c -1 -E 10MB -c -1 -E 11MB -c -1 -E eof -c -1 \
		$MOUNT2/$tfile
	wait $PID
	do_facet mds1 "$LCTL set_param fail_loc=0 fail_val=0"
	(( SECONDS-start < TIMEOUT/2 )) ||
		error "took too long: $((SECONDS-start)) >= $((TIMEOUT/2))"
}
run_test 203 "resend can hit original request"
complete_test $SECONDS
check_and_cleanup_lustre
exit_status
