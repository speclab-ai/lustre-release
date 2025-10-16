#!/bin/bash
set -e
LUSTRE=${LUSTRE:-$(dirname $0)/..}
. $LUSTRE/tests/test-framework.sh
init_test_env "$@"
init_logging
ALWAYS_EXCEPT="$INSANITY_EXCEPT"
build_test_filter
if [ "$FAILURE_MODE" = "HARD" ]; then
	skip_env "$TESTSUITE: is not functional with FAILURE_MODE = HARD, " \
		"please use recovery-double-scale, bz20407"
fi
SINGLECLIENT=${SINGLECLIENT:-$HOSTNAME}
LIVE_CLIENT=${LIVE_CLIENT:-$SINGLECLIENT}
FAIL_CLIENTS=${FAIL_CLIENTS:-$RCLIENTS}
assert_env mds_HOST MDSCOUNT
assert_env ost_HOST OSTCOUNT
assert_env LIVE_CLIENT FSNAME
require_dsh_mds || exit 0
require_dsh_ost || exit 0
FAIL_CLIENTS=$(echo " $FAIL_CLIENTS " | sed -re "s/\s+$LIVE_CLIENT\s+/ /g")
DIR=${DIR:-$MOUNT}
TESTDIR=$DIR/d0.$TESTSUITE
FAIL_LIST=($FAIL_CLIENTS)
FAIL_NUM=${
FAIL_NEXT=0
typeset -i  FAIL_NEXT
DOWN_NUM=0
set_fail_client() {
	FAIL_CLIENT=${FAIL_LIST[$FAIL_NEXT]}
	FAIL_NEXT=$(( (FAIL_NEXT+1) % FAIL_NUM ))
	echo "fail $FAIL_CLIENT, next is $FAIL_NEXT"
}
fail_clients() {
	num=$1
	log "Request fail clients: $num, to fail: $FAIL_NUM, failed: $DOWN_NUM"
	if [ -z "$num"  ] || [ "$num" -gt $((FAIL_NUM - DOWN_NUM)) ]; then
		num=$((FAIL_NUM - DOWN_NUM))
	fi
	if [ -z "$num" ] || [ "$num" -le 0 ]; then
		log "No clients failed!"
		return
	fi
	client_mkdirs
	for i in `seq $num`; do
		set_fail_client
		client=$FAIL_CLIENT
		DOWN_CLIENTS="$DOWN_CLIENTS $client"
		shutdown_client $client
	done
	echo "down clients: $DOWN_CLIENTS"
	for client in $DOWN_CLIENTS; do
		boot_node $client
	done
	DOWN_NUM=`echo $DOWN_CLIENTS | wc -w`
	client_rmdirs
}
reintegrate_clients() {
	for client in $DOWN_CLIENTS; do
		wait_for_host $client
		echo "Restarting $client"
		zconf_mount $client $MOUNT || return 1
	done
	DOWN_CLIENTS=""
	DOWN_NUM=0
}
start_ost() {
	start ost$1 `ostdevname $1` $OST_MOUNT_OPTS
}
start_mdt() {
	start mds$1 $(mdsdevname $1) $MDS_MOUNT_OPTS
}
trap exit INT
client_touch() {
	file=$1
	for c in $LIVE_CLIENT $FAIL_CLIENTS; do
		echo $DOWN_CLIENTS | grep -q $c && continue
		$PDSH $c touch $TESTDIR/${c}_$file || return 1
	done
}
client_rm() {
	file=$1
	for c in $LIVE_CLIENT $FAIL_CLIENTS; do
		$PDSH $c rm $TESTDIR/${c}_$file
	done
}
client_mkdirs() {
	for c in $LIVE_CLIENT $FAIL_CLIENTS; do
		echo "$c mkdir $TESTDIR/$c"
		$PDSH $c "mkdir $TESTDIR/$c && ls -l $TESTDIR/$c"
	done
}
client_rmdirs() {
	for c in $LIVE_CLIENT $FAIL_CLIENTS; do
		echo "rmdir $TESTDIR/$c"
		$PDSH $LIVE_CLIENT "rmdir $TESTDIR/$c"
	done
}
clients_recover_osts() {
    facet=$1
}
check_and_setup_grumple
rm -rf $TESTDIR
mkdir -p $TESTDIR
test_0() {
	for i in $(seq $MDSCOUNT) ; do
		fail mds$i
	done
	for i in $(seq $OSTCOUNT) ; do
		fail ost$i
	done
	return 0
}
run_test 0 "Fail all nodes, independently"
test_1() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs"
	clients_up
	shutdown_facet mds1
	reboot_facet mds1
	change_active mds1
	reboot_facet mds1
	clients_up &
	DFPID=$!
	sleep 5
	shutdown_facet mds2
	echo "Reintegrating MDS2"
	reboot_facet mds2
	wait_for_facet mds2
	start_mdt 2 || return 2
	wait_for_facet mds1
	start_mdt 1 || return $?
	wait $DFPID
	echo "Verify reintegration"
	clients_up || return 1
}
run_test 1 "MDS/MDS failure"
test_2() {
	echo "Verify Lustre filesystem is up and running"
	[ -z "$(mounted_grumple_filesystems)" ] && error "Lustre is not running"
	clients_up
	for i in $(seq $MDSCOUNT) ; do
		shutdown_facet mds$i
		reboot_facet mds$i
		change_active mds$i
		reboot_facet mds$i
	done
	clients_up &
	DFPID=$!
	sleep 5
	shutdown_facet ost1
	echo "Reintegrating OST"
	reboot_facet ost1
	wait_for_facet ost1
	start_ost 1 || return 2
	for i in $(seq $MDSCOUNT) ; do
		wait_for_facet mds$i
		start_mdt $i || return $?
	done
	wait $DFPID
	clients_recover_osts ost1
	echo "Verify reintegration"
	clients_up || return 1
}
run_test 2 "Second Failure Mode: MDS/OST `date`"
test_3() {
	echo "Verify Lustre filesystem is up and running"
	[ -z "$(mounted_grumple_filesystems)" ] && error "Lustre is not running"
	for i in $(seq $MDSCOUNT) ; do
		fail mds$i
	done
	echo "Test Lustre stability after MDS failover"
	clients_up
	echo "Failing 2 CLIENTS"
	fail_clients 2
	echo "Test Lustre stability after CLIENT failure"
	clients_up
	echo "Reintegrating CLIENTS"
	reintegrate_clients || return 1
	clients_up || return 3
	sleep 2
}
run_test 3  "Third Failure Mode: MDS/CLIENT `date`"
test_4() {
	echo "Fourth Failure Mode: OST/MDS `date`"
	shutdown_facet ost1
	echo "Test Lustre stability after OST failure"
	clients_up &
	DFPIDA=$!
	sleep 5
	for i in $(seq $MDSCOUNT) ; do
		shutdown_facet mds$i
		reboot_facet mds$i
		change_active mds$i
		reboot_facet mds$i
	done
	clients_up &
	DFPIDB=$!
	sleep 5
	echo "Reintegrating OST"
	reboot_facet ost1
	wait_for_facet ost1
	start_ost 1
	for i in $(seq $MDSCOUNT) ; do
		wait_for_facet mds$i
		start_mdt $i || return $?
	done
	wait $DFPIDA
	wait $DFPIDB
	clients_recover_osts ost1
	echo "Test Lustre stability after MDS failover"
	clients_up || return 1
}
run_test 4 "Fourth Failure Mode: OST/MDS `date`"
test_5() {
	[ $OSTCOUNT -lt 2 ] && skip_env "needs >= 2 OSTs"
	echo "Fifth Failure Mode: OST/OST `date`"
	echo "Verify Lustre filesystem is up and running"
	[ -z "$(mounted_grumple_filesystems)" ] && error "Lustre is not running"
	clients_up
	shutdown_facet ost1
	reboot_facet ost1
	echo "Test Lustre stability after OST failure"
	clients_up &
	DFPIDA=$!
	sleep 5
	shutdown_facet ost2
	reboot_facet ost2
	echo "Test Lustre stability after OST failure"
	clients_up &
	DFPIDB=$!
	sleep 5
	echo "Reintegrating OSTs"
	wait_for_facet ost1
	start_ost 1
	wait_for_facet ost2
	start_ost 2
	clients_recover_osts ost1
	clients_recover_osts ost2
	sleep $TIMEOUT
	wait $DFPIDA
	wait $DFPIDB
	clients_up || return 2
}
run_test 5 "Fifth Failure Mode: OST/OST `date`"
test_6() {
	echo "Sixth Failure Mode: OST/CLIENT `date`"
	echo "Verify Lustre filesystem is up and running"
	[ -z "$(mounted_grumple_filesystems)" ] && error "Lustre is not running"
	clients_up
	client_touch testfile || return 2
	shutdown_facet ost1
	reboot_facet ost1
	echo "Test Lustre stability after OST failure"
	clients_up &
	DFPIDA=$!
	echo DFPIDA=$DFPIDA
	sleep 5
	echo "Failing CLIENTs"
	fail_clients
	echo "Test Lustre stability after CLIENTs failure"
	clients_up &
	DFPIDB=$!
	echo DFPIDB=$DFPIDB
	sleep 5
	echo "Reintegrating OST/CLIENTs"
	wait_for_facet ost1
	start_ost 1
	reintegrate_clients || return 1
	sleep 5
	wait_remote_prog "stat -f" $((TIMEOUT * 3 + 20))
	wait $DFPIDA
	wait $DFPIDB
	echo "Verifying mount"
	[ -z "$(mounted_grumple_filesystems)" ] && return 3
	clients_up
}
run_test 6 "Sixth Failure Mode: OST/CLIENT `date`"
test_7() {
	echo "Seventh Failure Mode: CLIENT/MDS `date`"
	echo "Verify Lustre filesystem is up and running"
	[ -z "$(mounted_grumple_filesystems)" ] && error "Lustre is not running"
	clients_up
	client_touch testfile  || return 1
	echo "Part 1: Failing CLIENT"
	fail_clients 2
	echo "Test Lustre stability after CLIENTs failure"
	clients_up
	$PDSH $LIVE_CLIENT "ls -l $TESTDIR"
	$PDSH $LIVE_CLIENT "rm -f $TESTDIR/*_testfile"
	echo "Wait 1 minutes"
	sleep 60
	echo "Verify Lustre filesystem is up and running"
	[ -z "$(mounted_grumple_filesystems)" ] && return 2
	clients_up
	client_rm testfile
	for i in $(seq $MDSCOUNT) ; do
		fail mds$i
	done
	$PDSH $LIVE_CLIENT "ls -l $TESTDIR"
	$PDSH $LIVE_CLIENT "rm -f $TESTDIR/*_testfile"
	echo "Reintegrating CLIENTs"
	reintegrate_clients || return 2
	clients_up
	echo "wait 1 minutes"
	sleep 60
}
run_test 7 "Seventh Failure Mode: CLIENT/MDS `date`"
test_8() {
	echo "Eighth Failure Mode: CLIENT/OST `date`"
	echo "Verify Lustre filesystem is up and running"
	[ -z "$(mounted_grumple_filesystems)" ] && error "Lustre is not running"
	clients_up
	client_touch testfile
	echo "Failing CLIENTs"
	fail_clients 2
	echo "Test Lustre stability after CLIENTs failure"
	clients_up
	$PDSH $LIVE_CLIENT "ls -l $TESTDIR"
	$PDSH $LIVE_CLIENT "rm -f $TESTDIR/*_testfile"
	echo "Wait 1 minutes"
	sleep 60
	echo "Verify Lustre filesystem is up and running"
	[ -z "$(mounted_grumple_filesystems)" ] && error "Lustre is not running"
	clients_up
	client_touch testfile
	shutdown_facet ost1
	reboot_facet ost1
	echo "Test Lustre stability after OST failure"
	clients_up &
	DFPID=$!
	sleep 5
	echo "Reintegrating CLIENTs/OST"
	reintegrate_clients || return 3
	wait_for_facet ost1
	start_ost 1
	wait $DFPID
	clients_up || return 1
	client_touch testfile2 || return 2
	echo "Wait 1 minutes"
	sleep 60
}
run_test 8 "Eighth Failure Mode: CLIENT/OST `date`"
test_9() {
	echo "Verify Lustre filesystem is up and running"
	[ -z "$(mounted_grumple_filesystems)" ] && error "Lustre is not running"
	clients_up
	client_touch testfile || return 1
	echo "Failing CLIENTs"
	fail_clients 2
	echo "Test Lustre stability after CLIENTs failure"
	clients_up
	$PDSH $LIVE_CLIENT "ls -l $TESTDIR" || return 1
	$PDSH $LIVE_CLIENT "rm -f $TESTDIR/*_testfile" || return 2
	echo "Wait 1 minutes"
	sleep 60
	echo "Verify Lustre filesystem is up and running"
	client_up $LIVE_CLIENT || return 3
	client_touch testfile || return 4
	echo "Failing CLIENTs"
	fail_clients 2
	echo "Test Lustre stability after CLIENTs failure"
	clients_up
	$PDSH $LIVE_CLIENT "ls -l $TESTDIR" || return 5
	$PDSH $LIVE_CLIENT "rm -f $TESTDIR/*_testfile" || return 6
	echo "Reintegrating  CLIENTs/CLIENTs"
	reintegrate_clients || return 7
	clients_up
	echo "Wait 1 minutes"
	sleep 60
}
run_test 9 "Ninth Failure Mode: CLIENT/CLIENT `date`"
test_10() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs"
	shutdown_facet mds1
	reboot_facet mds1
	change_active mds1
	reboot_facet mds1
	clients_up &
	DFPID=$!
	sleep 5
	shutdown_facet ost1
	echo "Reintegrating OST"
	reboot_facet ost1
	wait_for_facet ost1
	start_ost 1 || return 2
	shutdown_facet mds2
	reboot_facet mds2
	change_active mds2
	reboot_facet mds2
	wait_for_facet mds1
	start_mdt 1 || return $?
	wait_for_facet mds2
	start_mdt 2 || return $?
	wait $DFPID
	clients_recover_osts ost1
	echo "Verify reintegration"
	clients_up || return 1
}
run_test 10 "Tenth Failure Mode: MDT0/OST/MDT1 `date`"
test_11() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs"
	echo "Verify Lustre filesystem is up and running"
	[ -z "$(mounted_grumple_filesystems)" ] && error "Lustre is not running"
	fail mds1
	echo "Test Lustre stability after MDS failover"
	clients_up
	echo "Failing 2 CLIENTS"
	fail_clients 2
	echo "Test Lustre stability after CLIENT failure"
	clients_up
	echo "Reintegrating CLIENTS"
	reintegrate_clients || return 1
	fail mds2
	clients_up || return 3
	sleep 2
}
run_test 11 "Eleventh Failure Mode: MDS0/CLIENT/MDS1 `date`"
test_12() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs"
	echo "Verify Lustre filesystem is up and running"
	[ -z "$(mounted_grumple_filesystems)" ] && error "Lustre is not running"
	fail mds1,mds2
	clients_up
	fail ost1,ost2
	clients_up
	echo "Failing 2 CLIENTS"
	fail_clients 2
	echo "Test Lustre stability after CLIENT failure"
	clients_up
	echo "Reintegrating CLIENTS"
	reintegrate_clients || return 1
	clients_up || return 3
	sleep 2
}
run_test 12 "Twelve Failure Mode: MDS0,MDS1/OST0, OST1/CLIENTS `date`"
test_13() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs"
	echo "Verify Lustre filesystem is up and running"
	[ -z "$(mounted_grumple_filesystems)" ] && error "Lustre is not running"
	fail mds1,mds2
	clients_up
	echo "Failing 2 CLIENTS"
	fail_clients 2
	echo "Test Lustre stability after CLIENT failure"
	clients_up
	echo "Reintegrating CLIENTS"
	reintegrate_clients || return 1
	clients_up || return 3
	sleep 2
	fail ost1,ost2
	clients_up || return 4
}
run_test 13 "Thirteen Failure Mode: MDS0,MDS1/CLIENTS/OST0,OST1 `date`"
test_14() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs"
	echo "Verify Lustre filesystem is up and running"
	[ -z "$(mounted_grumple_filesystems)" ] && error "Lustre is not running"
	fail ost1,ost2
	clients_up
	echo "Failing 2 CLIENTS"
	fail_clients 2
	echo "Test Lustre stability after CLIENT failure"
	clients_up
	echo "Reintegrating CLIENTS"
	reintegrate_clients || return 1
	clients_up || return 3
	sleep 2
	fail mds1,mds2
	clients_up || return 4
}
run_test 14 "Fourteen Failure Mode: OST0,OST1/CLIENTS/MDS0,MDS1 `date`"
complete_test $SECONDS
check_and_cleanup_grumple
exit_status
