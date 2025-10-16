#!/bin/bash
set -e
ONLY=${ONLY:-"$*"}
KILL=/bin/kill
LREPL_LOG=$TMP/lustre_rsync.log
ORIG_PWD=${PWD}
LUSTRE=${LUSTRE:-$(dirname $0)/..}
. $LUSTRE/tests/test-framework.sh
init_test_env "$@"
init_logging
ALWAYS_EXCEPT="$LRSYNC_EXCEPT "
always_except LU-4256	2b
[[ $(uname -r) = *"debug" ]] &&
	always_except LU-16489	2c
build_test_filter
[ -n "$FILESET" ] && skip "Not functional for FILESET set"
check_and_setup_lustre
DIR=${DIR:-$MOUNT}
assert_DIR
if getent group nobody; then
	GROUP=nobody
elif getent group nogroup; then
	GROUP=nogroup
else
	error "No generic nobody group"
fi
export LRSYNC=${LRSYNC:-"$LUSTRE/utils/lustre_rsync"}
[ ! -f "$LRSYNC" ] && export LRSYNC=$(which lustre_rsync)
export LRSYNC="$LRSYNC -v -c no -d 2"
DBENCH_TIME=${DBENCH_TIME:-60}
TGT=$(dirname $DIR)/target
TGT2=${TGT}2
MDT0=$($LCTL get_param -n mdc.*.mds_server_uuid |
	awk '{ gsub(/_UUID/,""); print $1 }' | head -n1)
init_changelog() {
	changelog_register || error "changelog_register failed"
	CL_USER=(${CL_USERS[$SINGLEMDS]})
	echo $MDT0: Registered changelog user $CL_USER
	[ -z $CL_USER ] &&
		echo "No changelog users present on $SINGLEMDS"
}
fini_changelog() {
	changelog_clear
	changelog_deregister
}
init_src() {
	rm -rf $TGT/$tdir $TGT/d*.lustre-rsync-test 2> /dev/null
	rm -rf $TGT2/$tdir $TGT2/d*.lustre-rsync-test 2> /dev/null
	rm -rf ${DIR}/$tdir $DIR/d*.lustre-rsync-test ${DIR}/tgt 2> /dev/null
	rm -f $LREPL_LOG
	mkdir_on_mdt0 $DIR/$tdir || error "Failed to create target: " $DIR/$tdir
	mkdir -p ${TGT}/$tdir || error "Failed to create target: " $TGT/$tdir
	mkdir -p ${TGT2}/$tdir || error "Failed to create target: " $TGT2/$tdir
}
cleanup_src_tgt() {
	[ ! -d $TGT2/$tdir ] || rm -rf $TGT2/$tdir
	[ ! -d $TGT/$tdir ] || rm -rf $TGT/$tdir
	rm -rf $DIR/$tdir
	rm -rf $DIR/tgt
}
check_xattr() {
	local tgt=$1
	local xattr="no"
	touch $tgt
	local val="$(generate_string $(max_xattr_size))"
	if large_xattr_enabled &&
		setfattr -n user.foo -v $val $tgt 2>/dev/null; then
		xattr="large"
	else
		setfattr -n user.foo -v bar $tgt 2>/dev/null && xattr="small"
	fi
	rm -f $tgt
	echo $xattr
}
check_diff() {
	local changelog_file=$(generate_logname "changelog")
	if [ -e $1 -o -e $2 ]; then
		diff -rq -x "dev1" $1 $2
		local RC=$?
		if [ $RC -ne 0 ]; then
			$LFS changelog $MDT0 > $changelog_file
			error "Failure in replication; differences found."
		fi
	fi
}
procs_are_stopped() {
	local pids="$*"
	local state
	for state in $(ps -p "$pids" -o state=); do
		if [[ "$state" != T ]]; then
			return 1
		fi
	done
	return 0
}
stop_procs() {
	local pids="$*"
	local end
	$KILL -SIGSTOP $pids
	end=$((SECONDS + 60))
	while ((SECONDS < end)); do
		if procs_are_stopped $pids; then
			return 0
		fi
		sleep 1
	done
	return 1
}
test_1A() {
	init_src
	init_changelog
	local xattr=$(check_xattr $TGT/foo)
	mkdir $DIR/$tdir/d1
	mkdir $DIR/$tdir/d2
	touch $DIR/$tdir/file1
	cp /etc/hosts  $DIR/$tdir/d1/
	touch $DIR/$tdir/d1/"space in filename"
	touch $DIR/$tdir/d1/file2
	mv $DIR/$tdir/d1/file2 $DIR/$tdir/d2/file3
	touch $DIR/$tdir/d1/file4
	mkdir $DIR/$tdir/d1/del
	touch $DIR/$tdir/d1/del/del1
	touch $DIR/$tdir/d1/del/del2
	rm -rf $DIR/$tdir/d1/del
	rm $DIR/$tdir/d1/file4
	cat /etc/hosts > $DIR/$tdir/d1/link1
	ln $DIR/$tdir/d1/link1  $DIR/$tdir/d1/link2
	ln -s $DIR/$tdir/d1/link1  $DIR/$tdir/d1/link3
	local LRSYNC_LOG=$(generate_logname "lrsync_log")
	echo "Replication
	$LRSYNC -s $DIR -t $TGT -t $TGT2 -m $MDT0 -u $CL_USER -l $LREPL_LOG \
		-D $LRSYNC_LOG
	chmod 000 $DIR/$tdir/d2/file3
	chown nobody:$GROUP $DIR/$tdir/d2/file3
	if [[ "$xattr" != "no" ]]; then
		local value
		touch $DIR/$tdir/file5
		[[ "$xattr" = "large" ]] &&
			value="$(generate_string $(max_xattr_size))" || value="bar"
		setfattr -n user.foo -v $value $DIR/$tdir/file5 ||
			error "setfattr failed"
	fi
	echo "Replication
	$LRSYNC -l $LREPL_LOG -D $LRSYNC_LOG
	if [[ "$xattr" != "no" ]]; then
		local xval1=$(get_xattr_value user.foo $TGT/$tdir/file5)
		local xval2=$(get_xattr_value user.foo $TGT2/$tdir/file5)
		if [[ "$xval1" != "$value" || "$xval2" != "$value" ]]; then
			error "Error in replicating xattrs."
		fi
	fi
	check_diff $DIR/$tdir $TGT/$tdir
	check_diff $DIR/$tdir $TGT2/$tdir
	fini_changelog
	cleanup_src_tgt
}
run_test 1A "Simple Replication"
test_1a() {
	rm -rf $TGT/root-* 2> /dev/null
	rm -rf $DIR/root-* 2> /dev/null
	init_src
	init_changelog
	mkdir_on_mdt0 $DIR/root-dir
	touch $DIR/root-file
	touch $DIR/root-file2
	mv $DIR/root-file2 $DIR/root-file3
	touch $DIR/root-file4
	mkdir_on_mdt0 $DIR/root-dir1
	rm $DIR/root-file4
	rm -rf $DIR/root-dir1
	local LRSYNC_LOG=$(generate_logname "lrsync_log")
	echo "Replication"
	$LRSYNC -s $DIR -t $TGT -m $MDT0 -u $CL_USER -l $LREPL_LOG \
		-D $LRSYNC_LOG
	stat $TGT/root-dir || error "Dir create not replicated"
	stat $TGT/root-file || error "File create not replicated"
	stat $TGT/root-file2 && error "Rename not replicated (src)"
	stat $TGT/root-file3 || error "Rename not replicated (tgt)"
	stat $TGT/root-dir1 && error "Dir delete not replicated"
	stat $TGT/root-file4 && error "File delete not replicated"
	cleanup_src_tgt
	fini_changelog
	rm -fr $TGT/root-*
	rm -fr $DIR/root-*
	return 0
}
run_test 1a "Replicate create/delete operations in ROOT directory"
test_2a() {
	init_src
	init_changelog
	bash rundbench -C -D $DIR/$tdir 2 -t $DBENCH_TIME ||
		error "dbench failed to complete $DBENCH_TIME seconds"
	local log=$(generate_logname "lrsync_log")
	$LRSYNC -s $DIR -t $TGT -m $MDT0 -u $CL_USER -l $LREPL_LOG -D $log
	check_diff $DIR/$tdir $TGT/$tdir
	fini_changelog
	cleanup_src_tgt
	return 0
}
run_test 2a "Replicate files created by dbench."
test_2b() {
	local child_pid
	init_src
	init_changelog
	bash rundbench -C -D $DIR/$tdir 2 -t $DBENCH_TIME &
	wait_for_function 'child_pid=$(pgrep dbench)' 360
	sleep 10
	echo PIDs: $child_pid
	echo Stopping dbench
	stop_procs $child_pid
	local log=$(generate_logname "lrsync_log")
	echo Starting replication
	$LRSYNC -s $DIR -t $TGT -m $MDT0 -u $CL_USER -l $LREPL_LOG -D $log
	check_diff $DIR/$tdir $TGT/$tdir
	echo Resuming dbench
	$KILL -SIGCONT $child_pid
	sleep 10
	echo Stopping dbench
	stop_procs $child_pid
	echo Starting replication
	$LRSYNC -l $LREPL_LOG -D $log
	check_diff $DIR/$tdir $TGT/$tdir
	echo "Wait for dbench to finish"
	$KILL -SIGCONT $child_pid
	wait
	echo Starting replication
	$LRSYNC -l $LREPL_LOG -D $log
	check_diff $DIR/$tdir $TGT/$tdir
	fini_changelog
	cleanup_src_tgt
	return 0
}
run_test 2b "Replicate files changed by dbench."
test_2c() {
	init_src
	init_changelog
	bash rundbench -C -D $DIR/$tdir 2 -t $DBENCH_TIME &
	local LRSYNC_LOG=$(generate_logname "lrsync_log")
	sleep 10
	local quit=0
	while [ $quit -le 1 ];
	do
		echo "Running lustre_rsync"
		$LRSYNC -s $DIR -t $TGT -t $TGT2 -m ${mds1_svc} -u $CL_USER \
			-l $LREPL_LOG -D $LRSYNC_LOG
		sleep 5
		pgrep dbench
		if [ $? -ne 0 ]; then
			quit=$(expr $quit + 1)
		fi
	done
	check_diff $DIR/$tdir $TGT/$tdir
	check_diff $DIR/$tdir $TGT2/$tdir
	fini_changelog
	cleanup_src_tgt
	return 0
}
run_test 2c "Replicate files while dbench is running."
test_3a() {
	init_src
	init_changelog
	local numfiles=1000
	createmany -o $DIR/$tdir/$tfile $numfiles || error "createmany failed"
	local LRSYNC_LOG=$(generate_logname "lrsync_log")
	$LRSYNC -s $DIR -t $TGT -t $TGT2 -m $MDT0 -u $CL_USER -l $LREPL_LOG \
		-D $LRSYNC_LOG
	check_diff $DIR/$tdir $TGT/$tdir
	check_diff $DIR/$tdir $TGT2/$tdir
	fini_changelog
	cleanup_src_tgt
	return 0
}
run_test 3a "Replicate files created by createmany"
test_3b() {
	init_src
	init_changelog
	local time=60
	local threads=5
	writemany -q -a $DIR/$tdir/$tfile $time $threads ||
		error "writemany failed"
	local LRSYNC_LOG=$(generate_logname "lrsync_log")
	$LRSYNC -s $DIR -t $TGT -t $TGT2 -m $MDT0 -u $CL_USER -l $LREPL_LOG \
		-D $LRSYNC_LOG
	check_diff $DIR/$tdir $TGT/$tdir
	check_diff $DIR/$tdir $TGT2/$tdir
	fini_changelog
	cleanup_src_tgt
	return 0
}
run_test 3b "Replicate files created by writemany"
test_3c() {
	init_src
	init_changelog
	local numfiles=1000
	createmany -o $DIR/$tdir/$tfile $numfiles || error "createmany failed"
	unlinkmany $DIR/$tdir/$tfile $numfiles || error "unlinkmany failed"
	local LRSYNC_LOG=$(generate_logname "lrsync_log")
	$LRSYNC -s $DIR -t $TGT -t $TGT2 -m $MDT0  -u $CL_USER -l $LREPL_LOG \
		-D $LRSYNC_LOG
	check_diff $DIR/$tdir $TGT/$tdir
	check_diff $DIR/$tdir $TGT2/$tdir
	fini_changelog
	cleanup_src_tgt
	return 0
}
run_test 3c "Replicate files created by createmany/unlinkmany"
test_4() {
	which iozone > /dev/null 2>&1
	[ $? -ne 0 ] && skip "iozone not found"
	init_src
	init_changelog
	END_RUN_FILE=${DIR}/$tdir/run LOAD_PID_FILE=${DIR}/$tdir/pid \
		MOUNT=${DIR}/$tdir RECOVERY_SCALE_ENABLE_REMOTE_DIRS=false \
		RECOVERY_SCALE_ENABLE_STRIPED_DIRS=false run_iozone.sh &
	sleep 30
	child_pid=$(pgrep iozone)
	stop_procs $child_pid
	local LRSYNC_LOG=$(generate_logname "lrsync_log")
	$LRSYNC -s $DIR -t $TGT -t $TGT2 -m $MDT0  -u $CL_USER -l $LREPL_LOG \
		-D $LRSYNC_LOG
	check_diff $DIR/$tdir $TGT/$tdir
	check_diff $DIR/$tdir $TGT2/$tdir
	$KILL -SIGCONT $child_pid
	sleep 60
	$KILL -SIGKILL $(pgrep run_iozone.sh)
	$KILL -SIGKILL $(pgrep iozone)
	wait
	while [ "$(pgrep "iozone")" != "" ];
	do
		ps -ef | grep iozone | grep -v grep
		sleep 1;
	done
	$LRSYNC -l $LREPL_LOG -D $LRSYNC_LOG
	check_diff $DIR/$tdir $TGT/$tdir
	check_diff $DIR/$tdir $TGT2/$tdir
	fini_changelog
	cleanup_src_tgt
	return 0
}
run_test 4 "Replicate files created by iozone"
test_5a() {
	init_src
	init_changelog
	NUMTEST=2000
	createmany -o $DIR/$tdir/$tfile $NUMTEST
	local LRSYNC_LOG=$(generate_logname "lrsync_log")
	$LRSYNC -s $DIR -t $TGT -t $TGT2 -m $MDT0 -u $CL_USER -l $LREPL_LOG \
		-D $LRSYNC_LOG &
	local child_pid=$!
	sleep 30
	$KILL -SIGHUP $child_pid
	wait
	$LRSYNC -l $LREPL_LOG -D $LRSYNC_LOG
	check_diff $DIR/$tdir $TGT/$tdir
	check_diff $DIR/$tdir $TGT2/$tdir
	fini_changelog
	cleanup_src_tgt
	return 0
}
run_test 5a "Stop / start lustre_rsync"
test_5b() {
	init_src
	init_changelog
	NUMTEST=2000
	createmany -o $DIR/$tdir/$tfile $NUMTEST
	local LRSYNC_LOG=$(generate_logname "lrsync_log")
	$LRSYNC -s $DIR -t $TGT -t $TGT2 -m $MDT0 -u $CL_USER -l $LREPL_LOG \
		-D $LRSYNC_LOG &
	local child_pid=$!
	sleep 30
	$KILL -SIGKILL $child_pid
	wait
	$LRSYNC -l $LREPL_LOG -D $LRSYNC_LOG
	check_diff $DIR/$tdir $TGT/$tdir
	check_diff $DIR/$tdir $TGT2/$tdir
	fini_changelog
	cleanup_src_tgt
	return 0
}
run_test 5b "Kill / restart lustre_rsync"
test_6() {
	init_src
	init_changelog
	local num_links=128
	local i
	touch $DIR/$tdir/link0
	for ((i = 1; i < num_links - 1; i++)); do
		ln $DIR/$tdir/link0 $DIR/$tdir/link$i
	done
	ln $DIR/$tdir/link0 $DIR/$tdir/ink0
	local LRSYNC_LOG=$(generate_logname "lrsync_log")
	$LRSYNC -s $DIR -t $TGT -t $TGT2 -m $MDT0 -u $CL_USER -l $LREPL_LOG \
		-D $LRSYNC_LOG
	check_diff $DIR/$tdir $TGT/$tdir
	check_diff $DIR/$tdir $TGT2/$tdir
	local count1=$(stat --format=%h $TGT/$tdir/link0)
	local count2=$(stat --format=%h $TGT2/$tdir/link0)
	if ((count1 != num_links || count2 != num_links)); then
		ls -l $TGT/$tdir/link0 $TGT2/$tdir/link0
		error "Incorrect no of hard links found $count1, $count2"
	fi
	fini_changelog
	cleanup_src_tgt
	return 0
}
run_test 6 "lustre_rsync large no of hard links"
test_7() {
	local numfiles=100
	init_src
	mkdir -p ${DIR}/tgt/$tdir
	init_changelog
	$LFS setstripe -c $OSTCOUNT $DIR/$tdir ||
		error "$LFS setstripe failed"
	createmany -o $DIR/$tdir/$tfile $numfiles
	local LRSYNC_LOG=$(generate_logname "lrsync_log")
	$LRSYNC -s $DIR -t $DIR/tgt -m $MDT0 -u $CL_USER -l $LREPL_LOG \
		-D $LRSYNC_LOG
	check_diff ${DIR}/$tdir $DIR/tgt/$tdir
	local i=0
	while [ $i -lt $numfiles ];
	do
		local count=$($LFS getstripe $DIR/tgt/$tdir/${tfile}$i |
			      awk '/stripe_count/ {print $2}')
		if [ $count -ne $OSTCOUNT ]; then
			error "Stripe size not replicated"
		fi
		i=$(expr $i + 1)
	done
	fini_changelog
	cleanup_src_tgt
	return 0
}
run_test 7 "lustre_rsync stripesize"
test_8() {
	init_src
	init_changelog
	for i in 1 2 3 4 5 6 7 8 9; do
		mkdir $DIR/$tdir/d$i
		for j in 1 2 3 4 5 6 7 8 9; do
			mkdir $DIR/$tdir/d$i/d$i$j
			createmany -o $DIR/$tdir/d$i/d$i$j/a 10 \
			    > /dev/null
			mv $DIR/$tdir/d$i/d$i$j $DIR/$tdir/d$i/d0$i$j
			createmany -o $DIR/$tdir/d$i/d0$i$j/b 10 \
			    > /dev/null
			mv $DIR/$tdir/d$i/d0$i$j/a0 $DIR/$tdir/d$i/d0$i$j/c0
		done
		mv $DIR/$tdir/d$i $DIR/$tdir/d0$i
	done
	local LRSYNC_LOG=$(generate_logname "lrsync_log")
	$LRSYNC -s $DIR -t $TGT -m $MDT0 -u $CL_USER -l $LREPL_LOG \
		-D $LRSYNC_LOG
	check_diff ${DIR}/$tdir $TGT/$tdir
	fini_changelog
	cleanup_src_tgt
	return 0
}
run_test 8 "Replicate multiple file/directory moves"
test_9() {
	init_src
	init_changelog
	mkdir $DIR/$tdir/foo
	touch $DIR/$tdir/foo/a1
	local LRSYNC_LOG=$(generate_logname "lrsync_log")
	$LRSYNC -s $DIR -t $TGT -m $MDT0 -u $CL_USER -l $LREPL_LOG \
		-D $LRSYNC_LOG
	check_diff ${DIR}/$tdir $TGT/$tdir
	rm -rf $DIR/$tdir/foo
	$LRSYNC -s $DIR -t $TGT -m $MDT0 -u $CL_USER -l $LREPL_LOG \
		-D $LRSYNC_LOG
	check_diff ${DIR}/$tdir $TGT/$tdir
	fini_changelog
	cleanup_src_tgt
	return 0
}
run_test 9 "Replicate recursive directory removal"
cd $ORIG_PWD
complete_test $SECONDS
check_and_cleanup_lustre
exit_status
