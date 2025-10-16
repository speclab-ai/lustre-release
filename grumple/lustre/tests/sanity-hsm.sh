#!/bin/bash
set -e
set +o monitor
ONLY=${ONLY:-"$*"}
LUSTRE=${LUSTRE:-$(dirname $0)/..}
. $LUSTRE/tests/test-framework.sh
init_test_env "$@"
init_logging
ALWAYS_EXCEPT="$SANITY_HSM_EXCEPT "
if $SHARED_KEY; then
	ALWAYS_EXCEPT+="	402b "
fi
if [[ $(uname -m) = ppc64 ]]; then
	ALWAYS_EXCEPT+=" 1a       1b       1d       1e       12c      12f "
	ALWAYS_EXCEPT+=" 12g      12h      12m      12n      12o      12p "
	ALWAYS_EXCEPT+=" 12q      21       22       23       24a      24b "
	ALWAYS_EXCEPT+=" 24d      24e      24f      25b      30c      37 "
	ALWAYS_EXCEPT+=" 57       58       90       110b     111b     113 "
	ALWAYS_EXCEPT+=" 222b     222d     228      260a     260b     260c "
	ALWAYS_EXCEPT+=" 220A     220a     221      222a     222c     223a "
	ALWAYS_EXCEPT+=" 223b     224A     224a     226      227      600"
	ALWAYS_EXCEPT+=" 601      602      603      604      605 "
fi
build_test_filter
[ -n "$FILESET" ] && skip "Not functional for FILESET set"
OPENFILE=${OPENFILE:-openfile}
MOUNT_2=${MOUNT_2:-"yes"}
FAIL_ON_ERROR=false
[ $MDSCOUNT -gt 9 ] &&
	error "script cannot handle more than 9 MDTs, please fix"
check_and_setup_lustre
if [[ $MDS1_VERSION -lt $(version_code 2.4.53) ]]; then
	skip_env "Need MDS version at least 2.4.53"
fi
if [[ $UID -eq 0 && $RUNAS_ID -eq 0 ]]; then
	skip_env "\$RUNAS_ID set to 0, but \$UID is also 0!"
fi
check_runas_id $RUNAS_ID $RUNAS_GID $RUNAS
if getent group nobody; then
	GROUP=nobody
elif getent group nogroup; then
	GROUP=nogroup
else
	error "No generic nobody group"
fi
CLIENT1=${CLIENT1:-$HOSTNAME}
CLIENT2=${CLIENT2:-$CLIENT1}
search_copytools() {
	local hosts=${1:-$(facet_active_host $SINGLEAGT)}
	do_nodesv $hosts "pgrep --pidfile=$HSMTOOL_PID_FILE hsmtool"
}
wait_copytools() {
	local hosts=${1:-$(facet_active_host $SINGLEAGT)}
	local wait_timeout=200
	local wait_start=$SECONDS
	local wait_end=$((wait_start + wait_timeout))
	local sleep_time=1
	while ((SECONDS < wait_end)); do
		if ! search_copytools $hosts; then
			echo "copytools stopped in $((SECONDS - wait_start))s"
			return 0
		fi
		echo "copytools still running on $hosts"
		sleep $sleep_time
		[ $sleep_time -lt 5 ] && sleep_time=$((sleep_time + 1))
	done
	do_nodesv $hosts "echo 1 >/proc/sys/kernel/sysrq ; " \
			 "echo t >/proc/sysrq-trigger"
	echo "copytools failed to stop in ${wait_timeout}s"
	return 1
}
copytool_monitor_setup() {
	local facet=${1:-$SINGLEAGT}
	local agent=$(facet_active_host $facet)
	local cmd="mktemp --tmpdir=/tmp -d ${TESTSUITE}.${TESTNAME}.XXXX"
	local test_dir=$(do_node $agent "$cmd") ||
		error "Failed to create tempdir on $agent"
	export HSMTOOL_MONITOR_DIR=$test_dir
	do_node $agent "mkfifo -m 0644 $test_dir/fifo" ||
		error "failed to create copytool fifo on $agent"
	cmd="cat $test_dir/fifo > $test_dir/events &"
	cmd+=" echo \\\$! > $test_dir/monitor_pid"
	(do_node $agent "$cmd") &
	export HSMTOOL_MONITOR_PDSH=$!
	sleep 1
	do_node $agent "stat $HSMTOOL_MONITOR_DIR/monitor_pid 2>&1 > /dev/null"
	if [ $? != 0 ]; then
		error "Failed to start copytool monitor on $agent"
	fi
}
fid2archive()
{
	local fid="$1"
	case "$HSMTOOL_ARCHIVE_FORMAT" in
		v1)
			printf "%s" "$(hsm_root)/*/*/*/*/*/*/$fid"
			;;
		v2)
			printf "%s" "$(hsm_root)/*/$fid"
			;;
	esac
}
get_copytool_event_log() {
	local facet=${1:-$SINGLEAGT}
	local agent=$(facet_active_host $facet)
	[ -z "$HSMTOOL_MONITOR_DIR" ] &&
		error "Can't get event log: No monitor directory!"
	do_node $agent "cat $HSMTOOL_MONITOR_DIR/events" ||
		error "Could not collect event log from $agent"
}
copytool_suspend() {
	local agents=${1:-$(facet_active_host $SINGLEAGT)}
	stack_trap "pkill_copytools $agents CONT || true" EXIT
	pkill_copytools $agents STOP || return 0
	echo "Copytool is suspended on $agents"
}
copytool_remove_backend() {
	local fid=$1
	local be=$(do_facet $SINGLEAGT find "$(hsm_root)" -name $fid)
	echo "Remove from backend: $fid = $be"
	do_facet $SINGLEAGT rm -f $be
}
file_creation_failure() {
	local cmd=$1
	local file=$2
	local err=$3
	case $err in
	28)
		df $MOUNT $MOUNT2 >&2
		error "Not enough space to create $file with $cmd"
		;;
	*)
		error "cannot create $file with $cmd, status=$err"
		;;
	esac
}
create_file() {
	local file=$1
	local bs=$2
	local count=$3
	local conv=$4
	local source=${5:-/dev/zero}
	local args=""
	local err
	if [ -n "$conv" ]; then
		args+=" conv=$conv"
	fi
	mkdir -p "$(dirname "$file")"
	rm -f "$file"
	if dd if="$source" of="$file" count="$count" bs="$bs" $args; then
		path2fid "$file" || error "cannot get FID of '$file'"
	else
		err=$?
		echo "cannot create file '$file'" >&2;
		return $err;
	fi
}
create_empty_file() {
	create_file "${1/$DIR/$DIR2}" 1M 0 ||
		file_creation_failure dd "${1/$DIR/$DIR2}" $?
}
create_small_file() {
	local source_file=/dev/urandom
	local count=1
	local bs=1M
	local conv=${2:-fsync}
	create_file "${1/$DIR/$DIR2}" $bs $count $conv $source_file ||
		file_creation_failure dd "${1/$DIR/$DIR2}" $?
}
create_small_sync_file() {
	create_small_file "$1" sync
}
create_archive_file() {
	local file="$(hsm_root)/$1"
	local count=${2:-39}
	local source=/dev/urandom
	do_facet "$SINGLEAGT" mkdir -p "$(dirname "$file")" ||
		error "cannot create archive directory '$(dirname "$file")'"
	do_facet "$SINGLEAGT" dd if=$source of="$file" bs=1M count=$count ||
		error "cannot create archive file '$file'"
}
copy2archive() {
	local hsm_root="$(hsm_root)"
	local file="$hsm_root/$2"
	stack_trap "do_facet $SINGLEAGT rm -rf '$hsm_root'" EXIT
	do_facet $SINGLEAGT mkdir -p "$(dirname "$file")" ||
	    error "mkdir '$(dirname "$file")' failed"
	do_facet $SINGLEAGT cp -p "$1" "$file" ||
		error "cannot copy '$1' to '$file'"
}
get_hsm_param() {
	local param=$1
	local val=$(do_facet $SINGLEMDS $LCTL get_param -n $HSM_PARAM.$param)
	echo $val
}
set_test_state() {
	local cmd=$1
	local target=$2
	mdts_set_param "" hsm_control "$cmd"
	mdts_check_param hsm_control "$target" 10
}
cdt_set_no_retry() {
	mdts_set_param "" hsm.policy "+NRA"
	CDT_POLICY_HAD_CHANGED=true
}
cdt_clear_no_retry() {
	mdts_set_param "" hsm.policy "-NRA"
	CDT_POLICY_HAD_CHANGED=true
}
cdt_set_non_blocking_restore() {
	mdts_set_param "" hsm.policy "+NBR"
	CDT_POLICY_HAD_CHANGED=true
}
cdt_clear_non_blocking_restore() {
	mdts_set_param "" hsm.policy "-NBR"
	CDT_POLICY_HAD_CHANGED=true
}
cdt_clear_mount_state() {
	mdts_set_param "-P -d" hsm_control ""
}
cdt_disable() {
	set_test_state disabled disabled
}
cdt_enable() {
	set_test_state enabled enabled
}
cdt_shutdown() {
	set_test_state shutdown stopped
}
cdt_purge() {
	set_test_state purge enabled
}
cdt_restart() {
	cdt_shutdown
	cdt_enable
	cdt_set_sanity_policy
}
get_hsm_archive_id() {
	local f=$1
	local st
	st=$($LFS hsm_state $f)
	[[ $? == 0 ]] || error "$LFS hsm_state $f failed"
	local ar=$(echo $st | grep -oP '(?<=archive_id:).*')
	echo $ar
}
check_hsm_flags_user() {
	local f=$1
	local fl=$2
	local st=$(get_hsm_flags $f user)
	[[ $st == $fl ]] || error "hsm flags on $f are $st != $fl"
}
copy_file() {
	local f=
	if [[ -d $2 ]]; then
		f=$2/$(basename $1)
	else
		f=$2
	fi
	if [[ "$3" != 1 ]]; then
		f=${f/$DIR/$DIR2}
	fi
	rm -f $f
	cp $1 $f || file_creation_failure cp $f $?
	path2fid $f || error "cannot get fid on $f"
}
delete_large_files() {
	printf "Deleting large files...\n" >&2
	find $MOUNT -size +10M -delete
	wait_delete_completed
}
get_request_state() {
	local fid=$1
	local request=$2
	do_facet $SINGLEMDS "$LCTL get_param -n $HSM_PARAM.actions |"\
		"awk '/'$fid'.*action='$request'/ {print \\\$13}' | cut -f2 -d="
}
get_request_count() {
	local fid=$1
	local request=$2
	do_facet $SINGLEMDS "$LCTL get_param -n $HSM_PARAM.actions |"\
		"awk -vn=0 '/'$fid'.*action='$request'/ {n++}; END {print n}'"
}
get_request_cookie() {
	local fid=$1
	local request=$2
	do_facet $SINGLEMDS "$LCTL get_param -n $HSM_PARAM.actions |"\
		"awk '/'$fid'.*action='$request'/ {print \\\$6}' | cut -f3 -d/"
}
assert_request_count() {
	local request_count=$(get_request_count $1 $2)
	local default_error_msg=("expected $3 '$2' request(s) for '$1', found "
				"'$request_count'")
	[ $request_count -eq $3 ] || error "${4:-"${default_error_msg[@]}"}"
}
wait_all_done() {
	local timeout=$1
	local fid=$2
	local cmd="$LCTL get_param -n $HSM_PARAM.actions"
	[[ -n $fid ]] && cmd+=" | grep '$fid'"
	cmd+=" | egrep 'WAITING|STARTED'"
	wait_update_facet --verbose mds1 "$cmd" "" $timeout ||
		error "requests did not complete"
}
wait_for_grace_delay() {
	local val=$(get_hsm_param grace_delay)
	sleep $val
}
wait_for_loop_period() {
	local val=$(get_hsm_param loop_period)
	sleep $val
}
parse_json_event() {
	local raw_event=$1
	local PYTHON='python'
	local json_parser='import json; import fileinput;'
	json_parser+=' print("\n".join(["local %s=\"%s\"" % tuple for tuple in '
	json_parser+='json.loads([line for line in '
	json_parser+='fileinput.input()][0]).items()]))'
	if ! which $PYTHON > /dev/null 2>&1 ; then
		PYTHON='python2'
		if ! which $PYTHON > /dev/null 2>&1 ; then
			PYTHON='python3'
		fi
	fi
	echo $raw_event | $PYTHON -c "$json_parser"
}
get_agent_by_uuid_mdt() {
	local uuid=$1
	local mdtidx=$2
	local mds=mds$(($mdtidx + 1))
	do_facet $mds "$LCTL get_param -n ${MDT_PREFIX}${mdtidx}.hsm.agents |\
		 grep $uuid"
}
check_agent_registered_by_mdt() {
	local uuid=$1
	local mdtidx=$2
	local mds=mds$(($mdtidx + 1))
	local agent=$(get_agent_by_uuid_mdt $uuid $mdtidx)
	if [[ ! -z "$agent" ]]; then
		echo "found agent $agent on $mds"
	else
		error "uuid $uuid not found in agent list on $mds"
	fi
}
check_agent_unregistered_by_mdt() {
	local uuid=$1
	local mdtidx=$2
	local mds=mds$(($mdtidx + 1))
	local agent=$(get_agent_by_uuid_mdt $uuid $mdtidx)
	if [[ -z "$agent" ]]; then
		echo "uuid not found in agent list on $mds"
	else
		error "uuid found in agent list on $mds: $agent"
	fi
}
check_agent_registered() {
	local uuid=$1
	local mdsno
	for mdsno in $(seq 1 $MDSCOUNT); do
		check_agent_registered_by_mdt $uuid $((mdsno - 1))
	done
}
check_agent_unregistered() {
	local uuid=$1
	local mdsno
	for mdsno in $(seq 1 $MDSCOUNT); do
		check_agent_unregistered_by_mdt $uuid $((mdsno - 1))
	done
}
get_agent_uuid() {
	local agent=${1:-$(facet_active_host $SINGLEAGT)}
	local mntpnt=$(do_rpc_nodes $agent \
			pgrep --pidfile=$HSMTOOL_PID_FILE --list-full hsmtool |
		       awk '{print $NF}')
	[ -n "$mntpnt" ] || error "Found no Agent or with no mount-point "\
				  "parameter"
	do_rpc_nodes $agent get_client_uuid $mntpnt | cut -d' ' -f2
}
init_agt_vars
get_mdt_devices
kill_copytools
echo "Set HSM on and start"
cdt_set_mount_state enabled
cdt_check_state enabled
echo "Set sanity-hsm HSM policy"
cdt_set_sanity_policy
set_hsm_param grace_delay 10
CLIENT_NIDS=( $($LCTL list_nids all) )
test_1A() {
	mkdir -p $DIR/$tdir
	chmod 777 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	$RUNAS touch $f
	check_hsm_flags_user $f "0x00000000"
	$RUNAS $LFS hsm_set --norelease $f ||
		error "user could not change hsm flags"
	check_hsm_flags_user $f "0x00000010"
	$RUNAS $LFS hsm_clear --norelease $f ||
		error "user could not clear hsm flags"
	check_hsm_flags_user $f "0x00000000"
	$RUNAS $LFS hsm_set --exists $f &&
		error "user should not set this flag"
	check_hsm_flags_user $f "0x00000000"
	$LFS hsm_set --exists $f ||
		error "root could not change hsm flags"
	check_hsm_flags_user $f "0x00000001"
	$LFS hsm_clear --exists $f ||
		error "root could not clear hsm state"
	check_hsm_flags_user $f "0x00000000"
}
run_test 1A "lfs hsm flags root/non-root access"
test_1a() {
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_small_file $f)
	copytool setup
	$LFS hsm_archive $f || error "could not archive file"
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f || error "could not release file"
	echo -n "Verifying released state: "
	check_hsm_flags $f "0x0000000d"
	$MMAP_CAT $f > /dev/null || error "failed mmap & cat release file"
}
run_test 1a "mmap & cat a HSM released file"
test_1bde_base() {
	local f=$1
	rm -f $f
	dd if=/dev/urandom of=$f bs=1M count=1 conv=sync ||
		error "failed to create file"
	local fid=$(path2fid $f)
	copytool setup
	echo "archive $f"
	$LFS hsm_archive $f || error "could not archive file"
	wait_request_state $fid ARCHIVE SUCCEED
	echo "release $f"
	$LFS hsm_release $f || error "could not release file"
	echo "verify released state: "
	check_hsm_flags $f "0x0000000d" && echo "pass"
	echo "restore $f"
	$LFS hsm_restore $f || error "could not restore file"
	wait_request_state $fid RESTORE SUCCEED
	echo "verify restored state: "
	check_hsm_flags $f "0x00000009" && echo "pass"
}
test_1b() {
	mkdir_on_mdt0 $DIR/$tdir
	$LFS setstripe -E 1M -S 1M -E 64M -c 2 -E -1 -c 4 $DIR/$tdir ||
		error "failed to set default stripe"
	local f=$DIR/$tdir/$tfile
	test_1bde_base $f
}
run_test 1b "Archive, Release and Restore composite file"
test_1c() {
	mkdir -p $DIR/$tdir
	chmod 777 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	$RUNAS touch $f
	local LOCAL_HSM_ARCHIVE_NUMBER=32
	$LFS hsm_set --exists --archive-id $LOCAL_HSM_ARCHIVE_NUMBER $f ||
		error "root could not change hsm flags"
	check_hsm_flags_user $f "0x00000001"
	echo "verifying archive number is $LOCAL_HSM_ARCHIVE_NUMBER"
	local st=$(get_hsm_archive_id $f)
	[[ $st == $LOCAL_HSM_ARCHIVE_NUMBER ]] ||
		error "wrong archive number, $st != $LOCAL_HSM_ARCHIVE_NUMBER"
	$LFS hsm_set --exists --archive-id 0 $f ||
		error "root could not change hsm flags"
	check_hsm_flags_user $f "0x00000001"
	echo "verifying archive number is still $LOCAL_HSM_ARCHIVE_NUMBER"
	st=$(get_hsm_archive_id $f)
	[[ $st == $LOCAL_HSM_ARCHIVE_NUMBER ]] ||
		error "wrong archive number, $st != $LOCAL_HSM_ARCHIVE_NUMBER"
	LOCAL_HSM_ARCHIVE_NUMBER=33
	if [ "$CLIENT_VERSION" -ge $(version_code 2.11.56) ] &&
	   [ "$MDS1_VERSION" -ge $(version_code 2.11.56) ]; then
		$LFS hsm_set --exists --archive-id $LOCAL_HSM_ARCHIVE_NUMBER $f ||
			error "archive ID $LOCAL_HSM_ARCHIVE_NUMBER too large?"
		check_hsm_flags_user $f "0x00000001"
		echo "verifying archive number is $LOCAL_HSM_ARCHIVE_NUMBER"
		st=$(get_hsm_archive_id $f)
		[[ $st == $LOCAL_HSM_ARCHIVE_NUMBER ]] ||
			error "wrong archive number, $st != $LOCAL_HSM_ARCHIVE_NUMBER"
	else
		$LFS hsm_set --exists --archive-id $LOCAL_HSM_ARCHIVE_NUMBER $f &&
			error "bitmap archive number is larger than 32"
		check_hsm_flags_user $f "0x00000001"
	fi
	LOCAL_HSM_ARCHIVE_NUMBER=16
	$LFS hsm_set --exists --archived \
	     --archive-id $LOCAL_HSM_ARCHIVE_NUMBER $f ||
	    error "root could not change hsm flags"
	check_hsm_flags_user $f "0x00000009"
	echo "verifying archive number is $LOCAL_HSM_ARCHIVE_NUMBER"
	st=$(get_hsm_archive_id $f)
	[[ $st == $LOCAL_HSM_ARCHIVE_NUMBER ]] ||
		error "wrong archive number, $st != $LOCAL_HSM_ARCHIVE_NUMBER"
}
run_test 1c "Check setting archive-id in lfs hsm_set"
test_1d() {
	[ $MDS1_VERSION -lt $(version_code 2.10.59) ] &&
		skip "need MDS version at least 2.10.59"
	mkdir_on_mdt0 $DIR/$tdir
	$LFS setstripe -E 1M -L mdt -E -1 -c 2 $DIR/$tdir ||
		error "failed to set default stripe"
	local f=$DIR/$tdir/$tfile
	test_1bde_base $f
}
run_test 1d "Archive, Release and Restore DoM file"
test_1e() {
	[ "$MDS1_VERSION" -lt $(version_code $SEL_VER) ] &&
		skip "skipped for lustre < $SEL_VER"
	mkdir_on_mdt0 $DIR/$tdir
	$LFS setstripe -E 1G -z 64M -E 10G -z 512M -E -1 -z 1G $DIR/$tdir ||
		error "failed to set default stripe"
	local comp_file=$DIR/$tdir/$tfile
	test_1bde_base $comp_file
	local flg_opts="--comp-start 0 -E 64M --comp-flags init"
	local found=$($LFS find $flg_opts $comp_file | wc -l)
	[ $found -eq 1 ] || error "1st component not found"
	flg_opts="--comp-start 64M -E 1G --comp-flags extension"
	found=$($LFS find $flg_opts $comp_file | wc -l)
	[ $found -eq 1 ] || error "2nd component not found"
	flg_opts="--comp-start 1G -E 1G --comp-flags ^init"
	found=$($LFS find $flg_opts $comp_file | wc -l)
	[ $found -eq 1 ] || error "3rd component not found"
	flg_opts="--comp-start 1G -E 10G --comp-flags extension"
	found=$($LFS find $flg_opts $comp_file | wc -l)
	[ $found -eq 1 ] || error "4th component not found"
	flg_opts="--comp-start 10G -E 10G --comp-flags ^init"
	found=$($LFS find $flg_opts $comp_file | wc -l)
	[ $found -eq 1 ] || error "5th component not found"
	flg_opts="--comp-start 10G -E EOF --comp-flags extension"
	found=$($LFS find $flg_opts $comp_file | wc -l)
	[ $found -eq 1 ] || error "6th component not found"
	sel_layout_sanity $comp_file 6
}
run_test 1e "Archive, Release and Restore SEL file"
test_1f() {
	(( $MDS1_VERSION >= $(version_code 2.15.55.203) )) ||
		skip "need MDS version at least 2.15.55.203"
	local dom=$DIR/$tdir/$tfile
	mkdir_on_mdt0 $DIR/$tdir
	$LFS setstripe -E 512K -L mdt -E -1 -c 2 $DIR/$tdir ||
		error "failed to set default stripe"
	test_1bde_base $dom
	[[ $($LFS getstripe --component-start=0 -L $dom) == 'mdt' ]] ||
		error "MDT stripe isn't set"
	chmod 600 $dom  || error "chmod failed"
	echo "release again $dom"
	$LFS hsm_release $dom || error "second release failed"
	$LFS hsm_state $dom
	echo "verify released state: "
	check_hsm_flags $dom "0x0000000d" && echo "pass"
}
run_test 1f "DoM file release after restore"
test_2() {
	local f=$DIR/$tdir/$tfile
	mkdir_on_mdt0 $DIR/$tdir
	create_empty_file "$f"
	check_hsm_flags $f "0x00000000"
	$LFS hsm_set --exists $f || error "user could not change hsm flags"
	check_hsm_flags $f "0x00000001"
	chmod 600 $f || error "could not chmod test file"
	check_hsm_flags $f "0x00000001"
	chown $RUNAS_ID $f || error "could not chown test file"
	check_hsm_flags $f "0x00000001"
	$TRUNCATE $f 1 || error "could not truncate test file"
	check_hsm_flags $f "0x00000003"
	$LFS hsm_clear --dirty $f || error "could not clear hsm flags"
	check_hsm_flags $f "0x00000001"
}
run_test 2 "Check file dirtyness when doing setattr"
test_3() {
	mkdir_on_mdt0 $DIR/$tdir
	f=$DIR/$tdir/$tfile
	cp -p /etc/passwd $f
	check_hsm_flags $f "0x00000000"
	$LFS hsm_set --exists $f ||
		error "user could not change hsm flags"
	check_hsm_flags $f "0x00000001"
	cat $f > /dev/null || error "could not read file"
	check_hsm_flags $f "0x00000001"
	openfile -f O_WRONLY $f || error "could not open test file"
	check_hsm_flags $f "0x00000001"
	cp -p /etc/passwd $f.append || error "could not create file"
	$LFS hsm_set --exists $f.append ||
		error "user could not change hsm flags"
	dd if=/etc/passwd of=$f.append bs=1 count=3\
	   conv=notrunc oflag=append status=noxfer ||
		file_creation_failure dd $f.append $?
	check_hsm_flags $f.append "0x00000003"
	cp -p /etc/passwd $f.modify || error "could not create file"
	$LFS hsm_set --exists $f.modify ||
		error "user could not change hsm flags"
	dd if=/dev/zero of=$f.modify bs=1 count=3\
	   conv=notrunc status=noxfer ||
		file_creation_failure dd $f.modify $?
	check_hsm_flags $f.modify "0x00000003"
	cp -p /etc/passwd $f.trunc || error "could not create file"
	$LFS hsm_set --exists $f.trunc ||
		error "user could not change hsm flags"
	cp /etc/group $f.trunc || error "could not override a file"
	check_hsm_flags $f.trunc "0x00000003"
	cp -p /etc/passwd $f.mmap || error "could not create file"
	$LFS hsm_set --exists $f.mmap ||
		error "user could not change hsm flags"
	multiop $f.mmap OSMWUc || error "could not mmap a file"
	check_hsm_flags $f.mmap "0x00000003"
}
run_test 3 "Check file dirtyness when opening for write"
test_4() {
	local f=$DIR/$tdir/$tfile
	local fid=$(create_small_file $f)
	$LFS hsm_cancel $f
	local st=$(get_request_state $fid CANCEL)
	[[ -z "$st" ]] || error "hsm_cancel must not be registered (state=$st)"
}
run_test 4 "Useless cancel must not be registered"
test_8() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/passwd $f)
	$LFS hsm_archive $f
	wait_request_state $fid ARCHIVE SUCCEED
	check_hsm_flags $f "0x00000009"
}
run_test 8 "Test default archive number"
test_9A() {
	local archive_id=$((HSM_ARCHIVE_NUMBER + 1))
	copytool setup --archive-id $archive_id
	sleep $(($MDSCOUNT*2))
	local uuid=$(get_agent_uuid $(facet_active_host $SINGLEAGT))
	check_agent_registered $uuid
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/passwd $f)
	$LFS hsm_archive --archive $archive_id $f
	wait_request_state $fid ARCHIVE SUCCEED
	check_hsm_flags $f "0x00000009"
}
run_test 9A "Use of explicit archive number, with dedicated copytool"
test_9a() {
	needclients 3 || return 0
	local n
	local file
	local fid
	for n in $(seq $AGTCOUNT); do
		copytool setup --facet agt$n
	done
	mkdir_on_mdt0 $DIR/$tdir
	for n in $(seq $AGTCOUNT); do
		file=$DIR/$tdir/$tfile.$n
		fid=$(create_small_file $file)
		$LFS hsm_archive $file || error "could not archive file $file"
		wait_request_state $fid ARCHIVE SUCCEED
		check_hsm_flags $file "0x00000009"
	done
}
run_test 9a "Multiple remote agents"
test_10a() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	mkdir -p $DIR/$tdir/d1
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/hosts $f)
	$LFS hsm_archive -a $HSM_ARCHIVE_NUMBER $f ||
		error "hsm_archive failed"
	wait_request_state $fid ARCHIVE SUCCEED
	local hsm_root="$(copytool_device $SINGLEAGT)"
	local archive="$(do_facet $SINGLEAGT \
			 find "$hsm_root" -name "$fid" -print0)"
	[ -n "$archive" ] || error "fid '$fid' not in archive '$hsm_root'"
	echo "Verifying content"
	do_facet $SINGLEAGT diff $f $archive || error "archived file differs"
	echo "Verifying hsm state "
	check_hsm_flags $f "0x00000009"
	echo "Verifying archive number is $HSM_ARCHIVE_NUMBER"
	local st=$(get_hsm_archive_id $f)
	[[ $st == $HSM_ARCHIVE_NUMBER ]] ||
		error "Wrong archive number, $st != $HSM_ARCHIVE_NUMBER"
}
run_test 10a "Archive a file"
test_10b() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/hosts $f)
	$LFS hsm_archive $f || error "archive request failed"
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_archive $f || error "archive of non dirty file failed"
	local cnt=$(get_request_count $fid ARCHIVE)
	[[ "$cnt" == "1" ]] ||
		error "archive of non dirty file must not make a request"
}
run_test 10b "Archive of non dirty file must work without doing request"
test_10c() {
	copytool setup
	mkdir -p $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/hosts $f)
	$LFS hsm_set --noarchive $f
	$LFS hsm_archive $f && error "archive a noarchive file must fail"
	return 0
}
run_test 10c "Check forbidden archive"
test_10d() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/hosts $f)
	$LFS hsm_archive $f || error "cannot archive $f"
	wait_request_state $fid ARCHIVE SUCCEED
	local ar=$(get_hsm_archive_id $f)
	local dflt=$(get_hsm_param default_archive_id)
	[[ $ar == $dflt ]] ||
		error "archived file is not on default archive: $ar != $dflt"
}
run_test 10d "Archive a file on the default archive id"
test_11a() {
	mkdir_on_mdt0 $DIR/$tdir
	copy2archive /etc/hosts $tdir/$tfile
	local f=$DIR/$tdir/$tfile
	copytool import $tdir/$tfile $f
	echo -n "Verifying released state: "
	check_hsm_flags $f "0x0000000d"
	local LSZ=$(stat -c "%s" $f)
	local ASZ=$(do_facet $SINGLEAGT stat -c "%s" "$(hsm_root)/$tdir/$tfile")
	echo "Verifying imported size $LSZ=$ASZ"
	[[ $LSZ -eq $ASZ ]] || error "Incorrect size $LSZ != $ASZ"
	echo -n "Verifying released pattern: "
	local PTRN=$($LFS getstripe -L $f)
	echo $PTRN
	[[ $PTRN =~ released ]] || error "Is not released"
	local fid=$(path2fid $f)
	echo "Verifying new fid $fid in archive"
	do_facet $SINGLEAGT "[ -f \"$(fid2archive "$fid")\" ]" ||
		error "No archive for fid $fid"
}
run_test 11a "Import a file"
test_11b() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/hosts $f)
	$LFS hsm_archive -a $HSM_ARCHIVE_NUMBER $f ||
		error "hsm_archive failed"
	wait_request_state $fid ARCHIVE SUCCEED
	local FILE_HASH=$(md5sum $f)
	rm -f $f
	copytool import $fid $f
	echo "$FILE_HASH" | md5sum -c
	[[ $? -eq 0 ]] || error "Restored file differs"
}
run_test 11b "Import a deleted file using its FID"
test_11c() {
	pool_add $TESTNAME || error "Pool creation failed"
	pool_add_targets $TESTNAME 1 1 || error "pool_add_targets failed"
	mkdir -p $DIR/$tdir
	$LFS setstripe -p "$TESTNAME" $DIR/$tdir
	copy2archive /etc/hosts $tdir/$tfile
	copytool import $tdir/$tfile $DIR/$tdir/$tfile
}
run_test 11c "Import a file to a directory with a pool"
test_12a() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	copy2archive /etc/hosts $tdir/$tfile
	local f=$DIR/$tdir/$tfile
	copytool import $tdir/$tfile $f
	local f2=$DIR2/$tdir/$tfile
	echo "Verifying released state: "
	check_hsm_flags $f2 "0x0000000d"
	local fid=$(path2fid $f2)
	$LFS hsm_restore $f2
	wait_request_state $fid RESTORE SUCCEED
	echo "Verifying file state: "
	check_hsm_flags $f2 "0x00000009"
	do_facet $SINGLEAGT diff -q $(hsm_root)/$tdir/$tfile $f
	[[ $? -eq 0 ]] || error "Restored file differs"
}
run_test 12a "Restore an imported file explicitly"
test_12b() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	copy2archive /etc/hosts $tdir/$tfile
	local f=$DIR/$tdir/$tfile
	copytool import $tdir/$tfile $f
	echo "Verifying released state: "
	check_hsm_flags $f "0x0000000d"
	cat $f > /dev/null || error "File read failed"
	echo "Verifying file state after restore: "
	check_hsm_flags $f "0x00000009"
	do_facet $SINGLEAGT diff -q $(hsm_root)/$tdir/$tfile $f
	[[ $? -eq 0 ]] || error "Restored file differs"
}
run_test 12b "Restore an imported file implicitly"
test_12c() {
	[ "$OSTCOUNT" -lt "2" ] && skip_env "needs >= 2 OSTs" && return
	copytool setup
	local f=$DIR/$tdir/$tfile
	mkdir_on_mdt0 $DIR/$tdir
	$LFS setstripe -c 2 "$f"
	local fid=$(create_file "$f" 1M 5)
	local FILE_CRC=$(md5sum $f)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f || error "release $f failed"
	echo "$FILE_CRC" | md5sum -c
	[[ $? -eq 0 ]] || error "Restored file differs"
}
run_test 12c "Restore a file with stripe of 2"
test_12d() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/hosts $f)
	$LFS hsm_restore $f || error "restore of non archived file failed"
	local cnt=$(get_request_count $fid RESTORE)
	[[ "$cnt" == "0" ]] ||
		error "restore non archived must not make a request"
	$LFS hsm_archive $f ||
		error "archive request failed"
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_restore $f ||
		error "restore of non released file failed"
	local cnt=$(get_request_count $fid RESTORE)
	[[ "$cnt" == "0" ]] ||
		error "restore a non dirty file must not make a request"
}
run_test 12d "Restore of a non archived, non released file must work"\
		" without doing request"
test_12e() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/hosts $f)
	$LFS hsm_archive $f || error "archive request failed"
	wait_request_state $fid ARCHIVE SUCCEED
	cat /etc/hosts >> $f
	sync
	$LFS hsm_state $f
	$LFS hsm_restore $f && error "restore a dirty file must fail"
	return 0
}
run_test 12e "Check forbidden restore"
test_12f() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/hosts $f)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f || error "release of $f failed"
	$LFS hsm_restore $f
	wait_request_state $fid RESTORE SUCCEED
	echo -n "Verifying file state: "
	check_hsm_flags $f "0x00000009"
	diff -q /etc/hosts $f
	[[ $? -eq 0 ]] || error "Restored file differs"
}
run_test 12f "Restore a released file explicitly"
test_12g() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/hosts $f)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f || error "release of $f failed"
	diff -q /etc/hosts $f
	local st=$?
	wait_request_state $fid RESTORE SUCCEED
	[[ $st -eq 0 ]] || error "Restored file differs"
}
run_test 12g "Restore a released file implicitly"
test_12h() {
	needclients 2 || return 0
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/hosts $f)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f || error "release of $f failed"
	do_node $CLIENT2 diff -q /etc/hosts $f
	local st=$?
	wait_request_state $fid RESTORE SUCCEED
	[[ $st -eq 0 ]] || error "Restored file differs"
}
run_test 12h "Restore a released file implicitly from a second node"
test_12m() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/passwd $f)
	$LFS hsm_archive $f || error "archive of $f failed"
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f || error "release of $f failed"
	cmp /etc/passwd $f
	[[ $? -eq 0 ]] || error "Restored file differs"
}
run_test 12m "Archive/release/implicit restore"
test_12n() {
	copytool setup
	mkdir -p $DIR/$tdir
	copy2archive /etc/hosts $tdir/$tfile
	local f=$DIR/$tdir/$tfile
	copytool import $tdir/$tfile $f
	do_facet $SINGLEAGT cmp /etc/hosts $f ||
		error "Restored file differs"
	$LFS hsm_release $f || error "release of $f failed"
}
run_test 12n "Import/implicit restore/release"
test_12o() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/hosts $f)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f || error "release of $f failed"
	do_facet $SINGLEMDS lctl set_param fail_loc=0x152
	cdt_set_no_retry
	diff -q /etc/hosts $f
	local st=$?
	wait_request_state $fid RESTORE FAILED
	[[ $st -eq 0 ]] && error "Restore must fail"
	cdt_clear_no_retry
	check_hsm_flags $f "0x0000000d"
	do_facet $SINGLEMDS lctl set_param fail_loc=0
	cdt_purge
	wait_for_grace_delay
	diff -q /etc/hosts $f
	st=$?
	wait_request_state $fid RESTORE SUCCEED
	[[ $st -eq 0 ]] || error "Restored file differs"
}
run_test 12o "Layout-swap failure during Restore leaves file released"
test_12p() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/hosts $f)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	do_facet $SINGLEAGT cat $f > /dev/null || error "cannot cat $f"
	$LFS hsm_release $f || error "cannot release $f"
	do_facet $SINGLEAGT cat $f > /dev/null || error "cannot cat $f"
	$LFS hsm_release $f || error "cannot release $f"
	do_facet $SINGLEAGT cat $f > /dev/null || error "cannot cat $f"
}
run_test 12p "implicit restore of a file on copytool mount point"
test_12q() {
	[ $MDS1_VERSION -lt $(version_code 2.7.58) ] &&
		skip "need MDS version at least 2.7.58"
	stack_trap "zconf_umount \"$(facet_host $SINGLEAGT)\" \"$MOUNT3\"" EXIT
	zconf_mount $(facet_host $SINGLEAGT) $MOUNT3 ||
		error "cannot mount $MOUNT3 on $SINGLEAGT"
	copytool setup -m "$MOUNT3"
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local f2=$DIR2/$tdir/$tfile
	local fid=$(create_small_file $f)
	local orig_size=$(stat -c "%s" $f)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f || error "could not release file"
	check_hsm_flags $f "0x0000000d"
	kill_copytools
	wait_copytools || error "copytool failed to stop"
	cat $f > /dev/null &
	sleep 5
	local size=$(stat -c "%s" $f2)
	[ $size -eq $orig_size ] ||
		error "$f2: wrong size after archive: $size != $orig_size"
	copytool setup -m "$MOUNT3"
	wait
	size=$(stat -c "%s" $f)
	[ $size -eq $orig_size ] ||
		error "$f: wrong size after restore: $size != $orig_size"
	size=$(stat -c "%s" $f2)
	[ $size -eq $orig_size ] ||
		error "$f2: wrong size after restore: $size != $orig_size"
	:>$f
	size=$(stat -c "%s" $f)
	[ $size -eq 0 ] ||
		error "$f: wrong size after overwrite: $size != 0"
	size=$(stat -c "%s" $f2)
	[ $size -eq 0 ] ||
		error "$f2: wrong size after overwrite: $size != 0"
}
run_test 12q "file attributes are refreshed after restore"
test_12r() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/hosts $f)
	$LFS hsm_archive $f || error "archive of $f failed"
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f || error "release of $f failed"
	offset=$(lseek_test -d 7 $f)
	wait_request_state $fid RESTORE SUCCEED
	[[ $offset == 7 ]] || error "offset $offset != 7"
}
run_test 12r "lseek restores released file"
test_12s() {
	local f=$DIR/$tdir/$tfile
	local fid
	local pid1 pid2
	(( MDS1_VERSION >= $(version_code 2.15.50) )) ||
		skip "Need MDS version newer than 2.15.50"
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	fid=$(copy_file /etc/hosts $f)
	$LFS hsm_archive $f || error "archive of $f failed"
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f || error "release of $f failed"
	do_facet mds1 $LCTL set_param fail_loc=0x8000018b
	cat $f > /dev/null & pid1=$!
	cat $f > /dev/null & pid2=$!
	wait $pid1 || error "cat process 1 fail (pid: $pid1)"
	wait $pid2 || error "cat process 2 fail (pid: $pid2)"
	assert_request_count $fid RESTORE 1
}
run_test 12s "race between restore requests"
test_12t() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local file=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/hosts $file)
	local n=32
	$LFS hsm_archive -a $HSM_ARCHIVE_NUMBER $file ||
		error "failed to HSM archive $file"
	wait_request_state $fid ARCHIVE SUCCEED
	rm -f $file || error "failed to rm $file"
	copytool import $fid $file
	check_hsm_flags $file "0x0000000d"
	local -a pids
	for ((i=0; i < $n; i++)); do
		cat $file > /dev/null &
		pids[$i]=$!
	done
	for ((i=0; i < $n; i++));do
		wait ${pids[$i]} || error "$?: failed to read pid=${pids[$i]}"
	done
}
run_test 12t "Multiple parallel reads for a HSM imported file"
test_12u() {
	local dir=$DIR/$tdir
	local n=10
	local t=32
	copytool setup
	mkdir_on_mdt0 $dir || error "failed to mkdir $dir"
	local -a pids
	local -a fids
	for ((i=0; i<$n; i++)); do
		fids[$i]=$(copy_file /etc/hosts $dir/$tfile.$i)
		$LFS hsm_archive -a $HSM_ARCHIVE_NUMBER $dir/$tfile.$i ||
			error "failed to HSM archive $dir/$tfile.$i"
	done
	for ((i=0; i<$n; i++)); do
		wait_request_state ${fids[$i]} ARCHIVE SUCCEED
		rm $dir/$tfile.$i || error "failed to rm $dir/$tfile.$i"
	done
	for ((i=0; i<$n; i++)); do
		copytool import ${fids[$i]} $dir/$tfile.$i
		check_hsm_flags $dir/$tfile.$i "0x0000000d"
	done
	for ((i=0; i<$n; i++)); do
		for ((j=0; j<$t; j++)); do
			cat $dir/$tfile.$i > /dev/null &
			pids[$((i * t + j))]=$!
		done
	done
	local pid
	for pid in "${pids[@]}"; do
		wait $pid || error "$pid: failed to cat file: $?"
	done
}
run_test 12u "Multiple reads on multiple HSM imported files in parallel"
test_13() {
	local -i i j k=0
	for i in {1..10}; do
		local archive_dir="$(hsm_root)"/subdir/dir.$i
		do_facet $SINGLEAGT mkdir -p "$archive_dir"
		for j in {1..10}; do
			local archive_file="$archive_dir"/file.$j
			do_facet $SINGLEAGT "echo $k > \"$archive_dir\"/file.$j"
			k+=1
		done
	done
	copytool import "subdir" "$DIR/$tdir"
	copytool setup
	find "$DIR/$tdir"/subdir -type f -exec $LFS hsm_restore {} \;
	do_facet $SINGLEAGT \
		diff -r "$(hsm_root)"/subdir "$DIR/$tdir"/subdir ||
		error "imported files differ from archived data"
}
run_test 13 "Recursively import and restore a directory"
test_14() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_small_file $f)
	local sum=$(md5sum $f | awk '{print $1}')
	$LFS hsm_archive $f || error "could not archive file"
	wait_request_state $fid ARCHIVE SUCCEED
	local fid2=$(create_empty_file "$f")
	$LFS hsm_set --archived --exists $f || error "could not force hsm flags"
	$LFS hsm_release $f || error "could not release file"
	echo "rebind $fid to $fid2"
	copytool rebind $fid $fid2
	local sum2=$(md5sum $f | awk '{print $1}')
	[[ $sum == $sum2 ]] || error "md5sum mismatch after restore"
}
run_test 14 "Rebind archived file to a new fid"
test_15() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local count=5
	local tmpfile=$SHARED_DIRECTORY/tmp.$$
	local fids=()
	local sums=()
	for i in $(seq 1 $count); do
		fids[$i]=$(create_small_file $f.$i)
		sums[$i]=$(md5sum $f.$i | awk '{print $1}')
		$LFS hsm_archive $f.$i || error "could not archive file"
	done
	wait_all_done $(($count*60))
	stack_trap "rm -f $tmpfile" EXIT
	:>$tmpfile
	for i in $(seq 1 $count); do
		local fid2=$(create_empty_file "${f}.${i}")
		echo ${fids[$i]} $fid2 >> $tmpfile
		$LFS hsm_set --archived --exists $f.$i ||
			error "could not force hsm flags"
		$LFS hsm_release $f.$i || error "could not release file"
	done
	nl=$(wc -l < $tmpfile)
	[[ $nl == $count ]] || error "$nl files in list, $count expected"
	echo "rebind list of files"
	copytool rebind "$tmpfile"
	for i in $(seq 1 $count); do
		local sum2=$(md5sum $f.$i | awk '{print $1}')
		[[ $sum2 == ${sums[$i]} ]] ||
		    error "md5sum mismatch after restore ($sum2 != ${sums[$i]})"
	done
}
run_test 15 "Rebind a list of files"
test_16() {
	copytool setup -b 1
	local ref=/tmp/ref
	local goal=20
	dd if=/dev/zero of=$ref bs=1M count=20
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file $ref $f)
	rm $ref
	local start=$(date +%s)
	$LFS hsm_archive $f
	wait_request_state $fid ARCHIVE SUCCEED
	local end=$(date +%s)
	local duration=$((end - start + 1))
	[[ $duration -ge $((goal - 1)) ]] ||
		error "Transfer is too fast $duration < $goal"
}
run_test 16 "Test CT bandwith control option"
test_20() {
	local f=$DIR/$tdir/$tfile
	create_empty_file "$f"
	$LFS hsm_release $f && error "release should not succeed"
	$LFS hsm_set --exists --archived $f || error "could not add flag"
	$LFS hsm_set --norelease $f || error "could not add flag"
	$LFS hsm_release $f && error "release should not succeed"
	$LFS hsm_clear --norelease $f || error "could not remove flag"
	$LFS hsm_set --lost $f || error "could not add flag"
	$LFS hsm_release $f && error "release should not succeed"
	$LFS hsm_clear --lost $f || error "could not remove flag"
	$LFS hsm_set --dirty $f || error "could not add flag"
	$LFS hsm_release $f && error "release should not succeed"
	$LFS hsm_clear --dirty $f || error "could not remove flag"
}
run_test 20 "Release is not permitted"
test_21() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/test_release
	local fid=$(create_small_file $f)
	check_hsm_flags $f "0x00000000"
	if [ "$ost1_FSTYPE" == "zfs" ]; then
	    dd if=/dev/zero of=$f bs=512 count=1 oflag=sync conv=notrunc,fsync
	    cancel_lru_locks osc
	fi
	local orig_size=$(stat -c "%s" $f)
	local orig_blocks=$(stat -c "%b" $f)
	$LFS hsm_archive $f || error "could not archive file"
	wait_request_state $fid ARCHIVE SUCCEED
	local blocks=$(stat -c "%b" $f)
	[ $blocks -eq $orig_blocks ] ||
		error "$f: wrong block number after archive: " \
		      "$blocks != $orig_blocks"
	local size=$(stat -c "%s" $f)
	[ $size -eq $orig_size ] ||
		error "$f: wrong size after archive: $size != $orig_size"
	$LFS hsm_release $f || error "could not release file"
	check_hsm_flags $f "0x0000000d"
	blocks=$(stat -c "%b" $f)
	[ $blocks -gt 5 ] &&
		error "$f: too many blocks after release: $blocks > 5"
	size=$(stat -c "%s" $f)
	[ $size -ne $orig_size ] &&
		error "$f: wrong size after release: $size != $orig_size"
	f=$f.nolov
	$MCREATE $f
	fid=$(path2fid $f)
	check_hsm_flags $f "0x00000000"
	$LFS hsm_archive $f || error "could not archive file"
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f || error "could not release file"
	check_hsm_flags $f "0x0000000d"
	$LFS hsm_release $f || fail "second release should succeed"
	check_hsm_flags $f "0x0000000d"
}
run_test 21 "Simple release tests"
test_22() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/test_release
	local swap=$DIR/$tdir/test_swap
	local fid=$(create_small_file $f)
	check_hsm_flags $f "0x00000000"
	$LFS hsm_archive $f || error "could not archive file"
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f || error "could not release file"
	check_hsm_flags $f "0x0000000d"
	create_small_file $swap
	$LFS swap_layouts $swap $f && error "swap_layouts should failed"
	return 0
}
run_test 22 "Could not swap a release file"
test_23() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/test_mtime
	local fid=$(create_small_file $f)
	check_hsm_flags $f "0x00000000"
	$LFS hsm_archive $f || error "could not archive file"
	wait_request_state $fid ARCHIVE SUCCEED
	touch -m -a -d @978261179 $f
	$LFS hsm_release $f || error "could not release file"
	check_hsm_flags $f "0x0000000d"
	local MTIME=$(stat -c "%Y" $f)
	local ATIME=$(stat -c "%X" $f)
	[ $MTIME -eq "978261179" ] || fail "bad mtime: $MTIME"
	[ $ATIME -eq "978261179" ] || fail "bad atime: $ATIME"
}
run_test 23 "Release does not change a/mtime (utime)"
test_24a() {
	local file=$DIR/$tdir/$tfile
	local fid
	local atime0
	local atime1
	local mtime0
	local mtime1
	local ctime0
	local ctime1
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	fid=$(create_small_file $file)
	check_hsm_flags $file "0x00000000"
	sleep 1
	echo >> $file
	atime0=$(stat -c "%X" $file)
	mtime0=$(stat -c "%Y" $file)
	ctime0=$(stat -c "%Z" $file)
	[ $atime0 -lt $mtime0 ] ||
		error "atime $atime0 is not less than mtime $mtime0"
	[ $atime0 -lt $ctime0 ] ||
		error "atime $atime0 is not less than ctime $ctime0"
	$LFS hsm_archive $file || error "cannot archive '$file'"
	wait_request_state $fid ARCHIVE SUCCEED
	atime1=$(stat -c "%X" $file)
	mtime1=$(stat -c "%Y" $file)
	ctime1=$(stat -c "%Z" $file)
	[ $atime0 -eq $atime1 ] ||
		error "archive changed atime from $atime0 to $atime1"
	[ $mtime0 -eq $mtime1 ] ||
		error "archive changed mtime from $mtime0 to $mtime1"
	[ $ctime0 -eq $ctime1 ] ||
		error "archive changed ctime from $ctime0 to $ctime1"
	$LFS hsm_release $file || error "cannot release '$file'"
	check_hsm_flags $file "0x0000000d"
	atime1=$(stat -c "%X" $file)
	mtime1=$(stat -c "%Y" $file)
	ctime1=$(stat -c "%Z" $file)
	[ $atime0 -eq $atime1 ] ||
		error "release changed atime from $atime0 to $atime1"
	[ $mtime0 -eq $mtime1 ] ||
		error "release changed mtime from $mtime0 to $mtime1"
	[ $ctime0 -eq $ctime1 ] ||
		error "release changed ctime from $ctime0 to $ctime1"
	$LFS hsm_restore $file
	wait_request_state $fid RESTORE SUCCEED
	atime1=$(stat -c "%X" $file)
	mtime1=$(stat -c "%Y" $file)
	ctime1=$(stat -c "%Z" $file)
	[ $atime0 -eq $atime1 ] ||
		error "restore changed atime from $atime0 to $atime1"
	[ $mtime0 -eq $mtime1 ] ||
		error "restore changed mtime from $mtime0 to $mtime1"
	[ $ctime0 -eq $ctime1 ] ||
		error "restore changed ctime from $ctime0 to $ctime1"
	kill_copytools
	wait_copytools || error "Copytools failed to stop"
	umount_client $MOUNT || error "cannot unmount '$MOUNT'"
	mount_client $MOUNT || error "cannot mount '$MOUNT'"
	atime1=$(stat -c "%X" $file)
	mtime1=$(stat -c "%Y" $file)
	ctime1=$(stat -c "%Z" $file)
	[ $atime0 -eq $atime1 ] ||
		error "remount changed atime from $atime0 to $atime1"
	[ $mtime0 -eq $mtime1 ] ||
		error "remount changed mtime from $mtime0 to $mtime1"
	[ $ctime0 -eq $ctime1 ] ||
		error "remount changed ctime from $ctime0 to $ctime1"
}
run_test 24a "Archive, release, and restore does not change a/mtime (i/o)"
test_24b() {
	local file=$DIR/$tdir/$tfile
	local fid
	local sum0
	local sum1
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	fid=$(create_small_file $file)
	sum0=$(md5sum $file)
	chown $RUNAS_ID:$RUNAS_GID $file ||
		error "cannot chown '$file' to '$RUNAS_ID'"
	chmod ugo-w $DIR/$tdir ||
		error "cannot chmod '$DIR/$tdir'"
	$LFS hsm_archive $file
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $file
	check_hsm_flags $file "0x0000000d"
	$LFS hsm_restore $file
	wait_request_state $fid RESTORE SUCCEED
	$RUNAS $LFS hsm_state $file ||
		error "user '$RUNAS_ID' cannot get HSM state of '$file'"
	$LFS hsm_release $file
	check_hsm_flags $file "0x0000000d"
	sum1=$($RUNAS md5sum $file) ||
		error "user '$RUNAS_ID' cannot read '$file'"
	[ "$sum0" == "$sum1" ] ||
		error "md5sum mismatch for '$file'"
}
run_test 24b "root can archive, release, and restore user files"
test_24c() {
	local file=$DIR/$tdir/$tfile
	local action=archive
	local user_save
	local group_save
	local other_save
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	user_save=$(get_hsm_param user_request_mask)
	stack_trap "set_hsm_param user_request_mask '$user_save'" EXIT
	group_save=$(get_hsm_param group_request_mask)
	stack_trap "set_hsm_param group_request_mask '$group_save'" EXIT
	other_save=$(get_hsm_param other_request_mask)
	stack_trap "set_hsm_param other_request_mask '$other_save'" EXIT
	[ "$user_save" == RESTORE ] ||
		error "user_request_mask is '$user_save' expected 'RESTORE'"
	[ "$group_save" == RESTORE ] ||
		error "group_request_mask is '$group_save' expected 'RESTORE'"
	[ "$other_save" == RESTORE ] ||
		error "other_request_mask is '$other_save' expected 'RESTORE'"
	create_small_file $file
	chown $RUNAS_ID:$GROUP $file ||
		error "cannot chown '$file' to '$RUNAS_ID:$GROUP'"
	$RUNAS $LFS hsm_$action $file &&
		error "$action by user should fail"
	set_hsm_param user_request_mask $action
	$RUNAS $LFS hsm_$action $file ||
		error "$action by user should succeed"
	create_small_file $file
	chown nobody:$RUNAS_GID $file ||
		error "cannot chown '$file' to 'nobody:$RUNAS_GID'"
	$RUNAS $LFS hsm_$action $file &&
		error "$action by group should fail"
	set_hsm_param group_request_mask $action
	$RUNAS $LFS hsm_$action $file ||
		error "$action by group should succeed"
	create_small_file $file
	chown nobody:$GROUP $file ||
		error "cannot chown '$file' to 'nobody:$GROUP'"
	$RUNAS $LFS hsm_$action $file &&
		error "$action by other should fail"
	set_hsm_param other_request_mask $action
	$RUNAS $LFS hsm_$action $file ||
		error "$action by other should succeed"
}
run_test 24c "check that user,group,other request masks work"
test_24d() {
	local file1=$DIR/$tdir/$tfile
	local file2=$DIR2/$tdir/$tfile
	local fid1
	local fid2
	mkdir_on_mdt0 $DIR/$tdir
	fid1=$(create_small_file $file1)
	echo $fid1
	$LFS getstripe $file1
	stack_trap "zconf_umount \"$(facet_host $SINGLEAGT)\" \"$MOUNT3\"" EXIT
	zconf_mount "$(facet_host $SINGLEAGT)" "$MOUNT3" ||
		error "cannot mount '$MOUNT3' on '$SINGLEAGT'"
	copytool setup -m  "$MOUNT3"
	stack_trap "mount -o remount,rw \"$MOUNT2\"" EXIT
	mount -o remount,ro $MOUNT2
	do_nodes $(comma_list $(nodes_list)) $LCTL clear
	fid2=$(path2fid $file2)
	[ "$fid1" == "$fid2" ] ||
		error "FID mismatch '$fid1' != '$fid2'"
	$LFS hsm_archive $file2 &&
		error "archive should fail on read-only mount"
	check_hsm_flags $file1 "0x00000000"
	$LFS hsm_archive $file1 || error "Fail to archive $file1"
	wait_request_state $fid1 ARCHIVE SUCCEED
	$LFS hsm_release $file1
	$LFS hsm_restore $file2
	wait_request_state $fid1 RESTORE SUCCEED
	$LFS hsm_release $file1 || error "cannot release '$file1'"
	dd if=$file2 of=/dev/null bs=1M || error "cannot read '$file2'"
	$LFS hsm_release $file2 &&
		error "release should fail on read-only mount"
	return 0
}
run_test 24d "check that read-only mounts are respected"
test_24e() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid
	fid=$(create_small_file $f) || error "cannot create $f"
	$LFS hsm_archive $f || error "cannot archive $f"
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f || error "cannot release $f"
	while ! $LFS hsm_state $f | grep released; do
		sleep 1
	done
	tar -cf $TMP/$tfile.tar $DIR/$tdir || error "cannot tar $DIR/$tdir"
}
run_test 24e "tar succeeds on HSM released files"
test_24f() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	mkdir -p $DIR/$tdir/d1
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/hosts $f)
	sum0=$(md5sum $f)
	echo $sum0
	$LFS hsm_archive $f ||
		error "hsm_archive failed"
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f || error "cannot release $f"
	tar --xattrs -cvf $f.tar -C $DIR/$tdir $tfile
	rm -f $f
	sync
	tar --xattrs -xvf $f.tar -C $DIR/$tdir ||
		error "Can not recover the tar contents"
	sum1=$(md5sum $f)
	echo "Sum0 = $sum0, sum1 = $sum1"
	[ "$sum0" == "$sum1" ] || error "md5sum mismatch for '$tfile'"
}
run_test 24f "root can archive, release, and restore tar files"
test_24g() {
	[ $MDS1_VERSION -lt $(version_code 2.11.56) ] &&
		skip "need MDS version 2.11.56 or later"
	local file=$DIR/$tdir/$tfile
	local fid
	echo "RUNAS = '$RUNAS'"
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	chmod ugo+rwx $DIR/$tdir
	echo "Please listen carefully as our options have changed." | tee $file
	fid=$(path2fid $file)
	chmod ugo+rw $file
	$LFS hsm_archive $file
	wait_request_state $fid ARCHIVE SUCCEED
	check_hsm_flags $file 0x00000009
	echo "To be electrocuted by your telephone, press
	check_hsm_flags $file 0x0000000b
}
run_test 24g "write by non-owner still sets dirty"
test_25a() {
	copytool setup
	mkdir -p $DIR/$tdir
	copy2archive /etc/hosts $tdir/$tfile
	local f=$DIR/$tdir/$tfile
	copytool import $tdir/$tfile $f
	$LFS hsm_set --lost $f
	md5sum $f
	local st=$?
	[[ $st == 1 ]] || error "lost file access should failed (returns $st)"
}
run_test 25a "Restore lost file (HS_LOST flag) from import"\
	     " (Operation not permitted)"
test_25b() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/passwd $f)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f
	$LFS hsm_set --lost $f
	md5sum $f
	st=$?
	[[ $st == 1 ]] || error "lost file access should failed (returns $st)"
}
run_test 25b "Restore lost file (HS_LOST flag) after release"\
	     " (Operation not permitted)"
test_26A() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_empty_file "$f")
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_remove $f
	wait_request_state $fid REMOVE SUCCEED
	check_hsm_flags $f "0x00000000"
}
run_test 26A "Remove the archive of a valid file"
test_26a() {
	local raolu=$(get_hsm_param remove_archive_on_last_unlink)
	[[ $raolu -eq 0 ]] || error "RAoLU policy should be off"
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/passwd $f)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	local f2=$DIR/$tdir/${tfile}_2
	local fid2=$(copy_file /etc/passwd $f2)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f2
	wait_request_state $fid2 ARCHIVE SUCCEED
	local f3=$DIR/$tdir/${tfile}_3
	local fid3=$(copy_file /etc/passwd $f3)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f3
	wait_request_state $fid3 ARCHIVE SUCCEED
	local orig_loop_period=$(get_hsm_param loop_period)
	local orig_grace_delay=$(get_hsm_param grace_delay)
	stack_trap "set_hsm_param loop_period $orig_loop_period" EXIT
	set_hsm_param loop_period 10
	stack_trap "set_hsm_param grace_delay $orig_grace_delay" EXIT
	set_hsm_param grace_delay 100
	rm -f $f
	stack_trap "set_hsm_param remove_archive_on_last_unlink 0" EXIT
	set_hsm_param remove_archive_on_last_unlink 1
	ln "$f3" "$f3"_bis || error "Unable to create hard-link"
	rm -f $f3
	rm -f $f2
	wait_request_state $fid2 REMOVE SUCCEED
	assert_request_count $fid REMOVE 0 \
		"Unexpected archived data remove request for $f"
	assert_request_count $fid3 REMOVE 0 \
		"Unexpected archived data remove request for $f3"
}
run_test 26a "Remove Archive On Last Unlink (RAoLU) policy"
test_26b() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/passwd $f)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	stack_trap "set_hsm_param remove_archive_on_last_unlink 0" EXIT
	set_hsm_param remove_archive_on_last_unlink 1
	cdt_shutdown
	cdt_check_state stopped
	rm -f $f
	wait_request_state $fid REMOVE WAITING
	cdt_enable
	kill_copytools
	wait_copytools || error "copytool failed to stop"
	copytool setup
	wait_request_state $fid REMOVE SUCCEED
}
run_test 26b "RAoLU policy when CDT off"
test_26c() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/passwd $f)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	local f2=$DIR/$tdir/${tfile}_2
	local fid2=$(copy_file /etc/passwd $f2)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f2
	wait_request_state $fid2 ARCHIVE SUCCEED
	local orig_loop_period=$(get_hsm_param loop_period)
	local orig_grace_delay=$(get_hsm_param grace_delay)
	stack_trap "set_hsm_param loop_period $orig_loop_period" EXIT
	set_hsm_param loop_period 10
	stack_trap "set_hsm_param grace_delay $orig_grace_delay" EXIT
	set_hsm_param grace_delay 100
	stack_trap "set_hsm_param remove_archive_on_last_unlink 0" EXIT
	set_hsm_param remove_archive_on_last_unlink 1
	multiop_bg_pause $f O_c || error "open $f failed"
	local pid=$!
	rm -f $f
	rm -f $f2
	wait_request_state $fid2 REMOVE SUCCEED
	assert_request_count $fid REMOVE 0 \
		"Unexpected archived data remove request for $f"
	kill -USR1 $pid || error "multiop early exit"
	wait $pid || error "wait PID $PID failed"
	wait_request_state $fid REMOVE SUCCEED
}
run_test 26c "RAoLU effective when file closed"
test_26d() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_small_file $f)
	$LFS hsm_archive $f || error "could not archive file"
	wait_request_state $fid ARCHIVE SUCCEED
	local orig_loop_period=$(get_hsm_param loop_period)
	local orig_grace_delay=$(get_hsm_param grace_delay)
	stack_trap "set_hsm_param loop_period $orig_loop_period" EXIT
	set_hsm_param loop_period 10
	stack_trap "set_hsm_param grace_delay $orig_grace_delay" EXIT
	set_hsm_param grace_delay 100
	stack_trap "set_hsm_param remove_archive_on_last_unlink 0" EXIT
	set_hsm_param remove_archive_on_last_unlink 1
	multiop_bg_pause $f O_c || error "multiop failed"
	local MULTIPID=$!
	rm -f $f
	mds_evict_client
	wait_request_state $fid REMOVE SUCCEED
	client_up || client_up || true
	kill -USR1 $MULTIPID
	wait $MULTIPID || error "multiop close failed"
}
run_test 26d "RAoLU when Client eviction"
test_26e() {
	(( MDS1_VERSION >= $(version_code 2.16.51) )) ||
		skip "need MDS version at least 2.16.51"
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_small_file $f)
	local f2=$DIR/$tdir/$tfile-2
	local fid2=$(create_small_file $f2)
	$LFS hsm_archive $f || error "could not archive file"
	wait_request_state $fid ARCHIVE SUCCEED
	kill_copytools
	wait_copytools || error "copytool failed to stop"
	$LFS hsm_archive $f2 || error "could not archive file"
	wait_request_state $fid2 ARCHIVE WAITING
	local last_cookie=$(( $(get_request_cookie $fid2 ARCHIVE) ))
	stack_trap "cdt_set_mount_state enabled"
	cdt_set_mount_state shutdown
	fail mds1
	cdt_check_state stopped
	stack_trap "set_hsm_param remove_archive_on_last_unlink 0"
	set_hsm_param remove_archive_on_last_unlink 1
	rm -f $f
	wait_request_state $fid REMOVE WAITING
	local new_cookie=$(( $(get_request_cookie $fid REMOVE) ))
	echo "Check cookie from RAoLU request (last: $last_cookie, remove: $new_cookie)"
	(( new_cookie == last_cookie + 1 )) ||
		error "RAoLU fail to setup a valid cookie ($new_cookie != $last_cookie + 1)"
	cdt_enable
	copytool setup
	wait_request_state $fid2 ARCHIVE SUCCEED
	wait_request_state $fid REMOVE SUCCEED
}
run_test 26e "RAoLU with a non-started coordinator"
test_27a() {
	copytool setup
	create_archive_file $tdir/$tfile
	local f=$DIR/$tdir/$tfile
	copytool import $tdir/$tfile $f
	local fid=$(path2fid $f)
	$LFS hsm_remove $f
	[[ $? != 0 ]] || error "Remove of a released file should fail"
}
run_test 27a "Remove the archive of an imported file (Operation not permitted)"
test_27b() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_empty_file "$f")
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f
	$LFS hsm_remove $f
	[[ $? != 0 ]] || error "Remove of a released file should fail"
}
run_test 27b "Remove the archive of a relased file (Operation not permitted)"
test_28() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_empty_file "$f")
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	cdt_disable
	$LFS hsm_remove $f
	rm -f $f
	cdt_enable
	wait_request_state $fid REMOVE SUCCEED
}
run_test 28 "Concurrent archive/file remove"
test_29a() {
	local archive_id=7
	copytool setup -m "$MOUNT" -a $archive_id
	$LFS hsm_remove -m "$MOUNT" -a 33 0x857765760:0x8:0x2 2>&1 |
		grep "Invalid argument" ||
		error "unexpected hsm_remove failure (1)"
	$LFS hsm_remove --mntpath "$MOUNT" --archive 30 /qwerty/uyt 2>&1 |
		grep "hsm: '/qwerty/uyt' is not a valid FID" ||
		error "unexpected hsm_remove failure (2)"
}
run_test 29a "Tests --mntpath and --archive options"
test_29b() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_small_file $f)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	rm -f $f
	$LFS hsm_remove -m $MOUNT -a $HSM_ARCHIVE_NUMBER $fid
	wait_request_state $fid REMOVE SUCCEED
}
run_test 29b "Archive/delete/remove by FID from the archive."
test_29c() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local fid1=$(create_small_file $DIR/$tdir/$tfile-1)
	local fid2=$(create_small_file $DIR/$tdir/$tfile-2)
	local fid3=$(create_small_file $DIR/$tdir/$tfile-3)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $DIR/$tdir/$tfile-[1-3]
	wait_request_state $fid1 ARCHIVE SUCCEED
	wait_request_state $fid2 ARCHIVE SUCCEED
	wait_request_state $fid3 ARCHIVE SUCCEED
	rm -f $DIR/$tdir/$tfile-[1-3]
	echo $fid1 > $DIR/$tdir/list
	echo $fid2 >> $DIR/$tdir/list
	echo $fid3 >> $DIR/$tdir/list
	$LFS hsm_remove -m $MOUNT -a $HSM_ARCHIVE_NUMBER \
		--filelist $DIR/$tdir/list
	wait_request_state $fid1 REMOVE SUCCEED
	wait_request_state $fid2 REMOVE SUCCEED
	wait_request_state $fid3 REMOVE SUCCEED
}
run_test 29c "Archive/delete/remove by FID, using a file list."
test_29d() {
	needclients 3 || return 0
	local n
	local file
	local fid
	for n in $(seq $AGTCOUNT); do
		copytool setup -f agt$n -a $n
	done
	mkdir_on_mdt0 $DIR/$tdir
	file=$DIR/$tdir/$tfile
	fid=$(create_small_file $file)
	$LFS hsm_archive $file
	wait_request_state $fid ARCHIVE SUCCEED
	check_hsm_flags $file "0x00000009"
	rm -f $file
	$LFS hsm_remove --mntpath "$MOUNT" -a 0 $fid ||
		error "cannot hsm_remove '$fid'"
	sleep 2
	local cnt=$(get_request_count $fid REMOVE)
	[[ $cnt -eq $((AGTCOUNT + 1)) ]] ||
		error "remove not broadcasted to all CTs"
	wait_for_loop_period
	local res
	local scnt=0
	local fcnt=0
	for n in $(seq $AGTCOUNT); do
		res=$(do_facet $SINGLEMDS "$LCTL get_param -n \
			       $HSM_PARAM.actions | awk \
			       '/'$fid'.*action=REMOVE archive
			       {print \\\$13}' | cut -f2 -d=")
		if [[ "$res" == "SUCCEED" ]]; then
			scnt=$((scnt + 1))
		elif [[ "$res" == "FAILED" ]]; then
			fcnt=$((fcnt + 1))
		fi
	done
	[[ $scnt -eq 1 ]] ||
		error "one and only CT should have removed successfully"
	[[ $AGTCOUNT -eq $((scnt + fcnt)) ]] ||
		error "all but one CT should have failed to remove"
}
run_test 29d "hsm_remove by FID with archive_id 0 for unlinked file cause "\
	     "request to be sent once for each registered archive_id"
test_30a() {
	needclients 2 || return 0
	copytool setup
	mkdir -p $DIR/$tdir
	copy2archive /bin/true $tdir/$tfile
	local f=$DIR/$tdir/true
	copytool import $tdir/$tfile $f
	local fid=$(path2fid $f)
	stack_trap "cdt_clear_no_retry" EXIT
	cdt_set_no_retry
	do_node $CLIENT2 $f
	local st=$?
	$LFS hsm_state $f
	[[ $st == 0 ]] || error "Failed to exec a released file"
}
run_test 30a "Restore at exec (import case)"
test_30b() {
	needclients 2 || return 0
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/true
	local fid=$(copy_file /bin/true $f)
	chmod 755 $f
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f
	$LFS hsm_state $f
	stack_trap cdt_clear_no_retry EXIT
	cdt_set_no_retry
	do_node $CLIENT2 $f
	local st=$?
	$LFS hsm_state $f
	[[ $st == 0 ]] || error "Failed to exec a released file"
}
run_test 30b "Restore at exec (release case)"
test_30c() {
	needclients 2 || return 0
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/SLEEP
	local slp_sum1=$(md5sum /bin/sleep)
	local fid=$(copy_file /bin/sleep $f)
	chmod 755 $f
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f
	check_hsm_flags $f "0x0000000d"
	stack_trap cdt_clear_no_retry EXIT
	cdt_set_no_retry
	do_node $CLIENT2 "$f 10" &
	local pid=$!
	sleep 3
	echo 'Hi!' > $f
	[[ $? == 0 ]] && error "Update during exec of released file must fail"
	wait $pid
	[[ $? == 0 ]] || error "Execution failed during run"
	cmp /bin/sleep $f
	if [[ $? != 0 ]]; then
		local slp_sum2=$(md5sum /bin/sleep)
		[[ $slp_sum1 == $slp_sum2 ]] &&
			error "Binary overwritten during exec"
	fi
	check_hsm_flags $f "0x00000009"
}
run_test 30c "Update during exec of released file must fail"
restore_and_check_size() {
	local f=$1
	local fid=$2
	local s=$(stat -c "%s" $f)
	local n=$s
	local st=$(get_hsm_flags $f)
	local err=0
	local cpt=0
	$LFS hsm_restore $f
	while [[ "$st" != "0x00000009" && $cpt -le 10 ]]
	do
		n=$(stat -c "%s" $f)
		if [[ $n != $s ]]; then
			echo "size seen is $n != $s"
			err=1
		else
			echo "size seen is right: $n == $s"
		fi
		sleep 10
		cpt=$((cpt + 1))
		st=$(get_hsm_flags $f)
	done
	if [[ "$st" = "0x00000009" ]]; then
		echo " "done
	else
		echo " restore is too long"
		wait_request_state $fid RESTORE SUCCEED
	fi
	return $err
}
test_31a() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	create_archive_file $tdir/$tfile
	local f=$DIR/$tdir/$tfile
	copytool import $tdir/$tfile $f
	local fid=$($LFS path2fid $f)
	copytool setup
	restore_and_check_size $f $fid
	local err=$?
	[[ $err -eq 0 ]] || error "File size changed during restore"
}
run_test 31a "Import a large file and check size during restore"
test_31b() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_file "$f" 1MB 39)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f
	restore_and_check_size $f $fid
	local err=$?
	[[ $err -eq 0 ]] || error "File size changed during restore"
}
run_test 31b "Restore a large unaligned file and check size during restore"
test_31c() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_file "$f" 1M 39)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f
	restore_and_check_size $f $fid
	local err=$?
	[[ $err -eq 0 ]] || error "File size changed during restore"
}
run_test 31c "Restore a large aligned file and check size during restore"
test_33() {
	local f=$DIR/$tdir/$tfile
	mkdir_on_mdt0 $DIR/$tdir
	local fid=$(create_empty_file "$f")
	copytool setup
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f
	copytool_suspend
	md5sum $f >/dev/null &
	local pid=$!
	wait_request_state $fid RESTORE STARTED
	kill -15 $pid
	copytool_continue
	wait $pid
	[ $? -eq 143 ] || error "md5sum was not 'Terminated'"
}
run_test 33 "Kill a restore waiting process"
test_34() {
	copytool setup -b 1
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_empty_file "$f")
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f
	copytool_suspend
	md5sum $f >/dev/null &
	local pid=$!
	wait_request_state $fid RESTORE STARTED
	timeout --signal=KILL 1 rm "$f" || error "rm $f failed"
	copytool_continue
	wait_request_state $fid RESTORE SUCCEED
	kill -0 $pid && error "Restore initiatior still running"
	wait $pid || error "Restore initiator failed with $?"
	[ ! -f "$f" ] || error "$f was not deleted"
}
run_test 34 "Remove file during restore"
test_35() {
	copytool setup -b 1
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local f1=$DIR/$tdir/$tfile-1
	local fid=$(create_empty_file "$f")
	local fid1=$(copy_file /etc/passwd $f1)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f
	copytool_suspend
	md5sum $f >/dev/null &
	local pid=$!
	wait_request_state $fid RESTORE STARTED
	timeout --signal=KILL 2 mv "$f1" "$f" || error "mv $f1 $f failed"
	copytool_continue
	wait_request_state $fid RESTORE SUCCEED
	kill -0 $pid && error "Restore initiatior still running"
	wait $pid || error "Restore initiator failed with $?"
	local fid2=$(path2fid $f)
	[[ $fid2 == $fid1 ]] || error "Wrong fid after mv $fid2 != $fid1"
}
run_test 35 "Overwrite file during restore"
test_36() {
	copytool setup -b 1
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_empty_file "$f")
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f
	copytool_suspend
	md5sum $f >/dev/null &
	local pid=$!
	wait_request_state $fid RESTORE STARTED
	timeout --signal=KILL 10 mv "$f" "$f.new" ||
		error "mv '$f' '$f.new' failed with rc=$?"
	copytool_continue
	wait_request_state $fid RESTORE SUCCEED
	kill -0 $pid && error "Restore initiator is still running"
	wait $pid || error "Restore initiator failed with $?"
}
run_test 36 "Move file during restore"
test_37() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid
	fid=$(create_small_file $f) || error "cannot create small file"
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f || error "cannot release $f"
	wait_for_grace_delay
	dd if=/dev/urandom of=$f bs=1M count=1 || error "cannot dirty file"
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
}
run_test 37 "re-archive a dirty file"
multi_archive() {
	local prefix=$1
	local count=$2
	local n=""
	for n in $(seq 1 $count); do
		$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $prefix.$n
	done
	echo "$count archive requests submitted"
}
test_40() {
	local stream_count=4
	local file_count=100
	mkdir -p $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local i=""
	local p=""
	local fid=""
	local max_requests=$(get_hsm_param max_requests)
	local huge_num=$((2**60))
	stack_trap "set_hsm_param max_requests $max_requests" EXIT
	if (( $MDS1_VERSION >= $(version_code v2_16_56-40) )); then
		set_hsm_param max_requests $huge_num &&
			error "set max_requests=$huge_num should failed" ||
			echo "set max_requests=$huge_num failed with $?"
		tmp_reqs=$(get_hsm_param max_requests)
		(( $tmp_reqs < $huge_num && $tmp_reqs > $max_requests )) ||
			error "Should set max_requests to be a reasonable value"
		do_facet mds1 "dmesg | tail -n 5 | grep 'to set HSM max_requests='" ||
			true
	fi
	set_hsm_param max_requests 300
	for i in $(seq 1 $file_count); do
		for p in $(seq 1 $stream_count); do
			fid=$(copy_file /etc/hosts $f.$p.$i)
		done
	done
	copytool setup
	cdt_purge
	wait_for_grace_delay
	typeset -a pids
	for p in $(seq 1 $stream_count); do
		multi_archive $f.$p $file_count &
		pids[$p]=$!
	done
	echo -n  "Wait for all requests being enqueued..."
	wait ${pids[*]}
	echo OK
	wait_all_done 100
}
run_test 40 "Parallel archive requests"
hsm_archive_batch() {
	local files_num=$1
	local batch_max=$2
	local filebase=$3
	local batch_num=0
	local fileset=""
	local i=0
	while [ $i -lt $files_num ]; do
		if [ $batch_num -eq $batch_max ]; then
			$LFS hsm_archive $fileset || error "HSM archive failed"
			fileset=""
			batch_num=0
		fi
		fileset+="${filebase}$i "
		batch_num=$(( batch_num + 1 ))
		i=$(( i + 1 ))
	done
	if [ $batch_num -ne 0 ]; then
		$LFS hsm_archive $fileset || error "HSM archive failed"
		fileset=""
		batch_num=0
	fi
}
test_50() {
	local dir=$DIR/$tdir
	local batch_max=50
	stack_trap "set_hsm_param max_requests $(get_hsm_param max_requests)"
	set_hsm_param max_requests 1000000
	mkdir $dir || error "mkdir $dir failed"
	df -i $MOUNT
	local start
	local elapsed
	local files_num
	local filebase
	files_num=10000
	filebase="$dir/$tfile.start."
	createmany -m $filebase $files_num ||
		error "createmany -m $filebase failed: $?"
	start=$SECONDS
	hsm_archive_batch $files_num $batch_max "$filebase"
	elapsed=$((SECONDS - start))
	do_facet $SINGLEMDS "$LCTL get_param -n \
		 $HSM_PARAM.actions | grep WAITING | wc -l"
	unlinkmany $filebase $files_num || error "unlinkmany $filabase failed"
	echo "Start Phase files_num: $files_num time: $elapsed"
	files_num=20000
	filebase="$dir/$tfile.in."
	createmany -m $filebase $files_num ||
		error "createmany -m $filebase failed: $?"
	start=$SECONDS
	hsm_archive_batch  $files_num $batch_max "$filebase"
	elapsed=$((SECONDS - start))
	unlinkmany $filebase $files_num || error "unlinkmany $filabase failed"
	echo "Middle Phase files_num: $files_num time: $elapsed"
	files_num=10000
	filebase="$dir/$tfile.end."
	createmany -m $filebase $files_num ||
		error "createmany -m $filebase failed: $?"
	start=$SECONDS
	hsm_archive_batch $files_num $batch_max "$filebase"
	elapsed=$((SECONDS - start))
	do_facet $SINGLEMDS "$LCTL get_param -n \
		 $HSM_PARAM.actions | grep WAITING | wc -l"
	unlinkmany $filebase $files_num || error "unlinkmany $filebase failed"
	echo "End Phase files_num: $files_num time: $elapsed"
	do_facet $SINGLEMDS "$LCTL get_param -n \
		 $HSM_PARAM.actions | grep WAITING | wc -l"
	cdt_purge
}
run_test 50 "Archive with large number of pending HSM actions"
test_52() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_small_file $f)
	$LFS hsm_archive $f || error "could not archive file"
	wait_request_state $fid ARCHIVE SUCCEED
	check_hsm_flags $f "0x00000009"
	multiop_bg_pause $f O_c || error "multiop failed"
	local MULTIPID=$!
	mds_evict_client
	client_up || client_up || true
	kill -USR1 $MULTIPID
	wait $MULTIPID || error "multiop close failed"
	check_hsm_flags $f "0x0000000b"
}
run_test 52 "Opened for write file on an evicted client should be set dirty"
test_53() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_small_file $f)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f ||
		error "could not archive file"
	wait_request_state $fid ARCHIVE SUCCEED
	check_hsm_flags $f "0x00000009"
	multiop_bg_pause $f o_c || error "multiop failed"
	MULTIPID=$!
	mds_evict_client
	client_up || client_up || true
	kill -USR1 $MULTIPID
	wait $MULTIPID || error "multiop close failed"
	check_hsm_flags $f "0x00000009"
}
run_test 53 "Opened for read file on an evicted client should not be set dirty"
test_54() {
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_file "$f" 1MB 39)
	copytool setup -b 1
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f ||
		error "could not archive file"
	wait_request_state $fid ARCHIVE STARTED
	check_hsm_flags $f "0x00000001"
	stack_trap "cdt_clear_no_retry" EXIT
	cdt_set_no_retry
	echo "foo" >> $f
	sync
	wait_request_state $fid ARCHIVE FAILED
	check_hsm_flags $f "0x00000003"
}
run_test 54 "Write during an archive cancels it"
test_55() {
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_file "$f" 1MB 39)
	copytool setup -b 1
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f ||
		error "could not archive file"
	wait_request_state $fid ARCHIVE STARTED
	check_hsm_flags $f "0x00000001"
	stack_trap "cdt_clear_no_retry" EXIT
	cdt_set_no_retry
	$TRUNCATE $f 1024 || error "truncate failed"
	sync
	wait_request_state $fid ARCHIVE FAILED
	check_hsm_flags $f "0x00000003"
}
run_test 55 "Truncate during an archive cancels it"
test_56() {
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_file "$f" 1MB 39)
	copytool setup -b 1
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f ||
		error "could not archive file"
	wait_request_state $fid ARCHIVE STARTED
	check_hsm_flags $f "0x00000001"
	chmod 644 $f
	chgrp sys $f
	sync
	wait_request_state $fid ARCHIVE SUCCEED
	check_hsm_flags $f "0x00000009"
}
run_test 56 "Setattr during an archive is ok"
test_57() {
	needclients 2 || return 0
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/test_archive_remote
	do_node $CLIENT2 "dd if=/dev/urandom of=$f bs=1M "\
		"count=2 conv=fsync"
	do_node $CLIENT2 "$LFS hsm_archive -a $HSM_ARCHIVE_NUMBER $f" ||
		error "hsm_archive failed"
	local fid=$(path2fid $f)
	wait_request_state $fid ARCHIVE SUCCEED
	do_node $CLIENT2 "$LFS hsm_release $f" ||
		error "hsm_release failed"
	do_node $CLIENT2 "md5sum $f" ||
		error "hsm_restore failed"
	wait_request_state $fid RESTORE SUCCEED
}
run_test 57 "Archive a file with dirty cache on another node"
truncate_released_file() {
	local src_file=$1
	local trunc_to=$2
	local sz=$(stat -c %s $src_file)
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file $1 $f)
	local ref=$f-ref
	cp $f $f-ref
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f ||
		error "could not archive file"
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f || error "could not release file"
	$TRUNCATE $f $trunc_to || error "truncate failed"
	sync
	local sz1=$(stat -c %s $f)
	[[ $sz1 == $trunc_to ]] ||
		error "size after trunc: $sz1 expect $trunc_to, original $sz"
	$LFS hsm_state $f
	check_hsm_flags $f "0x0000000b"
	local state=$(get_request_state $fid RESTORE)
	[[ "$state" == "SUCCEED" ]] ||
		error "truncate $sz does not trig restore, state = $state"
	$TRUNCATE $ref $trunc_to
	cmp $ref $f || error "file data wrong after truncate"
	rm -f $f $f-ref
}
test_58() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local sz=$(stat -c %s /etc/passwd)
	echo "truncate up from $sz to $((sz*2))"
	truncate_released_file /etc/passwd $((sz*2))
	echo "truncate down from $sz to $((sz/2))"
	truncate_released_file /etc/passwd $((sz/2))
	echo "truncate to 0"
	truncate_released_file /etc/passwd 0
}
run_test 58 "Truncate a released file will trigger restore"
test_59() {
	local fid
	[[ $MDS1_VERSION -lt $(version_code 2.7.63) ]] &&
		skip "Need MDS version at least 2.7.63"
	copytool setup
	$MCREATE $DIR/$tfile || error "mcreate failed"
	$TRUNCATE $DIR/$tfile 42 || error "truncate failed"
	$LFS hsm_archive $DIR/$tfile || error "archive request failed"
	fid=$(path2fid $DIR/$tfile)
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $DIR/$tfile || error "release failed"
}
run_test 59 "Release stripeless file with non-zero size"
test_60() {
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_file "$f" 1M 10)
	local interval=5
	local progress_timeout=$((interval * 4))
	copytool setup -b 1 --update-interval $interval
	local mdtidx=0
	local mdt=${MDT_PREFIX}${mdtidx}
	local mds=mds$((mdtidx + 1))
	wait_update_facet $mds \
		"$LCTL get_param -n ${mdt}.hsm.agents | grep -o ^uuid" \
		uuid 100 || error "coyptool failed to register with $mdt"
	local start_at=$(date +%s)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f ||
		error "could not archive file"
	local agent=$(facet_active_host $SINGLEAGT)
	local logfile=$(copytool_logfile $SINGLEAGT)
	wait_update $agent \
	    "grep -o start.copy \"$logfile\"" "start copy" 100 ||
		error "copytool failed to start"
	local cmd="$LCTL get_param -n ${mdt}.hsm.active_requests"
	cmd+=" | awk '/'$fid'.*action=ARCHIVE/ {print \\\$12}' | cut -f2 -d="
	local RESULT
	local WAIT=0
	local sleep=1
	echo -n "Expecting a progress update within $progress_timeout seconds... "
	while true; do
		RESULT=$(do_node $(facet_active_host $mds) "$cmd")
		if [ -n "$RESULT" ] && [ "$RESULT" -gt 0 ]; then
			echo "$RESULT bytes copied in $WAIT seconds."
			break
		elif [ $WAIT -ge $progress_timeout ]; then
			error "Timed out waiting for progress update!"
			break
		fi
		WAIT=$((WAIT + sleep))
		sleep $sleep
	done
	local finish_at=$(date +%s)
	local elapsed=$((finish_at - start_at))
	if [ $elapsed -lt $((interval - 1)) ]; then
		error "Expected progress update after at least $interval seconds"
	fi
	echo "Wait for on going archive hsm action to complete"
	wait_update $agent "grep -o copied \"$logfile\"" "copied" 10 ||
		echo "File archiving not completed even after 10 secs"
}
run_test 60 "Changing progress update interval from default"
test_61() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/passwd $f)
	cdt_disable
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	rm -f $f
	cdt_enable
	wait_request_state $fid ARCHIVE FAILED
}
run_test 61 "Waiting archive of a removed file should fail"
test_70() {
	stack_trap copytool_monitor_cleanup EXIT
	copytool_monitor_setup
	copytool setup --event-fifo "$HSMTOOL_MONITOR_DIR/fifo"
	wait_update --verbose $(facet_active_host mds1) \
		"$LCTL get_param -n ${MDT_PREFIX}0.hsm.agents | grep -o ^uuid" \
		uuid 100 ||
		error "copytool failed to register with MDT0000"
	kill_copytools
	wait_copytools || error "Copytools failed to stop"
	local REGISTER_EVENT
	local UNREGISTER_EVENT
	while read event; do
		local parsed=$(parse_json_event "$event")
		if [ -z "$parsed" ]; then
			error "Copytool sent malformed event: $event"
		fi
		eval $parsed
		if [ $event_type == "REGISTER" ]; then
			REGISTER_EVENT=$event
		elif [ $event_type == "UNREGISTER" ]; then
			UNREGISTER_EVENT=$event
		fi
	done < <(echo $"$(get_copytool_event_log)")
	if [ -z "$REGISTER_EVENT" ]; then
		error "Copytool failed to send register event to FIFO"
	fi
	if [ -z "$UNREGISTER_EVENT" ]; then
		error "Copytool failed to send unregister event to FIFO"
	fi
	echo "Register/Unregister events look OK."
}
run_test 70 "Copytool logs JSON register/unregister events to FIFO"
test_71() {
	local interval=5
	stack_trap copytool_monitor_cleanup EXIT
	copytool_monitor_setup
	copytool setup --update-interval $interval --event-fifo \
		"$HSMTOOL_MONITOR_DIR/fifo"
	stack_trap "cdt_clear_no_retry" EXIT
	cdt_clear_no_retry
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_small_file "$f")
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f ||
		error "could not archive file"
	wait_request_state $fid ARCHIVE SUCCEED
	local expected_fields="event_time data_fid source_fid"
	expected_fields+=" total_bytes current_bytes"
	local -A events=(
		[ARCHIVE_START]=false
		[ARCHIVE_FINISH]=false
		[ARCHIVE_RUNNING]=false
		)
	while read event; do
		for field in $expected_fields; do
			unset $field
		done
		local parsed=$(parse_json_event "$event")
		if [ -z "$parsed" ]; then
			error "Copytool sent malformed event: $event"
		fi
		eval $parsed
		events["$event_type"]=true
		[ "$event_type" != ARCHIVE_RUNNING ] && continue
		for expected_field in $expected_fields; do
			if [ -z ${!expected_field+x} ]; then
				error "Missing $expected_field field in event"
			fi
		done
		[ $total_bytes -gt 0 ] || error "Expected total_bytes to be > 0"
		[ $source_fid == $data_fid ] ||
			error "Expected source_fid to equal data_fid"
	done < <(echo $"$(get_copytool_event_log)")
	for event in "${!events[@]}"; do
		${events["$event"]} ||
			error "Copytool failed to send '$event' event to FIFO"
	done
	echo "Archive events look OK."
}
run_test 71 "Copytool logs JSON archive events to FIFO"
test_72() {
	local interval=5
	stack_trap copytool_monitor_cleanup EXIT
	copytool_monitor_setup
	copytool setup --update-interval $interval --event-fifo \
		"$HSMTOOL_MONITOR_DIR/fifo"
	local test_file=$HSMTOOL_MONITOR_DIR/file
	local cmd="dd if=/dev/urandom of=$test_file count=16 bs=1000000 "
	cmd+="conv=fsync"
	do_facet $SINGLEAGT "$cmd" ||
		error "cannot create $test_file on $SINGLEAGT"
	copy2archive $test_file $tdir/$tfile
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	copytool import $tdir/$tfile $f
	f=$DIR2/$tdir/$tfile
	echo "Verifying released state: "
	check_hsm_flags $f "0x0000000d"
	local fid=$(path2fid $f)
	$LFS hsm_restore $f
	wait_request_state $fid RESTORE SUCCEED
	local expected_fields="event_time data_fid source_fid"
	expected_fields+=" total_bytes current_bytes"
	local START_EVENT
	local FINISH_EVENT
	while read event; do
		for field in $expected_fields; do
			unset $field
		done
		local parsed=$(parse_json_event "$event")
		if [ -z "$parsed" ]; then
			error "Copytool sent malformed event: $event"
		fi
		eval $parsed
		if [ $event_type == "RESTORE_START" ]; then
			START_EVENT=$event
			if [ $source_fid != $data_fid ]; then
				error "source_fid should == data_fid at start"
			fi
			continue
		elif [ $event_type == "RESTORE_FINISH" ]; then
			FINISH_EVENT=$event
			if [ $source_fid != $data_fid ]; then
				error "source_fid should == data_fid at finish"
			fi
			continue
		elif [ $event_type != "RESTORE_RUNNING" ]; then
			continue
		fi
		for expected_field in $expected_fields; do
			if [ -z ${!expected_field+x} ]; then
				error "Missing $expected_field field in event"
			fi
		done
		if [ $total_bytes -eq 0 ]; then
			error "Expected total_bytes to be > 0"
		fi
		if [ $source_fid == $data_fid ]; then
			error "source_fid should != data_fid during restore"
		fi
	done < <(echo $"$(get_copytool_event_log)")
	if [ -z "$START_EVENT" ]; then
		error "Copytool failed to send restore start event to FIFO"
	fi
	if [ -z "$FINISH_EVENT" ]; then
		error "Copytool failed to send restore finish event to FIFO"
	fi
	echo "Restore events look OK."
}
run_test 72 "Copytool logs JSON restore events to FIFO"
test_90() {
	file_count=51
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	local f=$DIR/$tdir/$tfile
	local FILELIST=/tmp/filelist.txt
	local i=""
	rm -f $FILELIST
	for i in $(seq 1 $file_count); do
		fid=$(copy_file /etc/hosts $f.$i)
		echo $f.$i >> $FILELIST
	done
	copytool setup
	cdt_purge
	wait_for_grace_delay
	$LFS hsm_archive --filelist $FILELIST ||
		error "cannot archive a file list"
	wait_all_done 200
	$LFS hsm_release --filelist $FILELIST ||
		error "cannot release a file list"
	$LFS hsm_restore --filelist $FILELIST ||
		error "cannot restore a file list"
	wait_all_done 200
}
run_test 90 "Archive/restore a file list"
double_verify_reset_hsm_param() {
	local p=$1
	echo "Testing $HSM_PARAM.$p"
	local val=$(get_hsm_param $p)
	local save=$val
	local val2=$(($val * 2))
	stack_trap "set_hsm_param $p $save"
	set_hsm_param $p $val2
	val=$(get_hsm_param $p)
	[[ $val == $val2 ]] ||
		error "$HSM_PARAM.$p: $val != $val2 should be (2 * $save)"
	echo "Set $p to 0 must failed"
	set_hsm_param $p 0
	local rc=$?
	set_hsm_param $p $save
	if [[ $rc == 0 ]]; then
		error "we must not be able to set $HSM_PARAM.$p to 0"
	fi
}
test_100() {
	(( MDS1_VERSION >= $(version_code v2_16_56-53-g39f1380c20) )) ||
		skip "need mds >= 2.16.56.53 for max_requests fix"
	double_verify_reset_hsm_param loop_period
	double_verify_reset_hsm_param grace_delay
	double_verify_reset_hsm_param active_request_timeout
	double_verify_reset_hsm_param max_requests
	double_verify_reset_hsm_param default_archive_id
}
run_test 100 "Set coordinator /proc tunables"
test_102() {
	cdt_disable
	cdt_enable
	cdt_restart
}
run_test 102 "Verify coordinator control"
test_103() {
	copytool setup
	local i=""
	local fid=""
	mkdir -p $DIR/$tdir
	for i in $(seq 1 20); do
		fid=$(copy_file /etc/passwd $DIR/$tdir/$i)
	done
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $DIR/$tdir/*
	cdt_purge
	echo "Current requests"
	local res=$(do_facet $SINGLEMDS "$LCTL get_param -n\
			$HSM_PARAM.actions |\
			grep -v CANCELED | grep -v SUCCEED | grep -v FAILED")
	[[ -z "$res" ]] || error "Some request have not been canceled"
}
run_test 103 "Purge all requests"
test_103a() {
	(( MDS1_VERSION >= $(version_code 2.14.56) )) ||
		skip "Need MDS version at least 2.14.56"
	cdt_clear_non_blocking_restore
	copytool setup
	local -a fids=()
	local i
	local rpcs_inflight=$($LCTL get_param -n \
		"mdc.$(facet_svc mds1)*.max_rpcs_in_flight" |
		head -n1)
	mkdir_on_mdt0 $DIR/$tdir
	for ((i=0; i < rpcs_inflight; i++)); do
		fids+=( $(copy_file /etc/passwd $DIR/$tdir/${tfile}_$i) )
	done
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $DIR/$tdir/*
	local time=0
	local cnt=0
	local grep_regex="($(tr ' ' '|' <<< "${fids[*]}")).*action=ARCHIVE.*status=SUCCEED"
	echo $grep_regex
	while [[ $time -lt 5 ]] && [[ $cnt -ne ${
		cnt=$(do_facet mds1 "$LCTL get_param -n $HSM_PARAM.actions |
			grep -c -E '$grep_regex'")
		sleep 1
		((++time))
	done
	[[ $cnt -eq ${
	$LFS hsm_release $DIR/$tdir/*
	kill_copytools
	wait_copytools || error "Copytool failed to stop"
	local -a pids=()
	for i in "${fids[@]}"; do
		cat $DIR/.lustre/fid/$i > /dev/null & pids+=($!)
	done
	cdt_purge
	grep_regex="($(tr ' ' '|' <<< "${fids[*]}")).*action=RESTORE.*status=CANCELED"
	cnt=$(do_facet mds1 "$LCTL get_param -n $HSM_PARAM.actions |
		grep -cE '$grep_regex'")
	[[ "$cnt" -eq ${
		error "Some request have not been canceled ($cnt/${
	for i in "${!pids[@]}"; do
		wait ${pids[$i]} &&
			error "Restore for ${tfile}_$i (${pids[$i]}) should fail" ||
			true
	done
}
run_test 103a "Purge pending restore requests"
DATA=CEA
DATAHEX='[434541]'
test_104() {
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_empty_file "$f")
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER --data $DATA $f
	local data1=$(do_facet $SINGLEMDS "$LCTL get_param -n\
			$HSM_PARAM.actions |\
			grep $fid | cut -f16 -d=")
	[[ "$data1" == "$DATAHEX" ]] ||
		error "Data field in records is ($data1) and not ($DATAHEX)"
	cdt_purge
}
run_test 104 "Copy tool data field"
test_105() {
	(( MDS1_VERSION >= $(version_code v2_16_56-53-g39f1380c20) )) ||
		skip "need mds >= 2.16.56.53 for max_requests fix"
	local max_requests=$(get_hsm_param max_requests)
	mkdir_on_mdt0 $DIR/$tdir
	local i=""
	stack_trap "set_hsm_param max_requests $max_requests" EXIT
	set_hsm_param max_requests 300
	cdt_disable
	for i in $(seq -w 1 10); do
		cp /etc/passwd $DIR/$tdir/$i
		$LFS hsm_archive $DIR/$tdir/$i
	done
	local reqcnt1=$(do_facet $SINGLEMDS "$LCTL get_param -n\
			$HSM_PARAM.actions |\
			grep WAITING | wc -l")
	cdt_restart
	cdt_disable
	local reqcnt2=$(do_facet $SINGLEMDS "$LCTL get_param -n\
			$HSM_PARAM.actions |\
			grep WAITING | wc -l")
	cdt_enable
	cdt_purge
	[[ "$reqcnt1" == "$reqcnt2" ]] ||
		error "Requests count after shutdown $reqcnt2 != "\
		      "before shutdown $reqcnt1"
}
run_test 105 "Restart of coordinator"
test_106() {
	copytool setup
	local uuid=$(get_agent_uuid $(facet_active_host $SINGLEAGT))
	check_agent_registered $uuid
	search_copytools || error "No copytool found"
	kill_copytools
	wait_copytools || error "Copytool failed to stop"
	check_agent_unregistered $uuid
	copytool setup
	uuid=$(get_agent_uuid $(facet_active_host $SINGLEAGT))
	check_agent_registered $uuid
}
run_test 106 "Copytool register/unregister"
test_107() {
	[ "$CLIENTONLY" ] && skip "CLIENTONLY mode" && return
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f1=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/passwd $f1)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f1
	wait_request_state $fid ARCHIVE SUCCEED
	fail $SINGLEMDS
	local f2=$DIR/$tdir/2
	local fid=$(copy_file /etc/passwd $f2)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f2
	wait_request_state $fid ARCHIVE SUCCEED
}
run_test 107 "Copytool re-register after MDS restart"
policy_set_and_test()
{
	local change="$1"
	local target="$2"
	do_facet $SINGLEMDS $LCTL set_param "$HSM_PARAM.policy=\\\"$change\\\""
	local policy=$(do_facet $SINGLEMDS $LCTL get_param -n $HSM_PARAM.policy)
	[[ "$policy" == "$target" ]] ||
		error "Wrong policy after '$change': '$policy' != '$target'"
}
test_109() {
	CDT_POLICY_HAD_CHANGED=true
	local policy=$(do_facet $SINGLEMDS $LCTL get_param -n $HSM_PARAM.policy)
	local default="NonBlockingRestore [NoRetryAction]"
	[[ "$policy" == "$default" ]] ||
		error "default policy has changed,"\
		      " '$policy' != '$default' update the test"
	policy_set_and_test "+NBR" "[NonBlockingRestore] [NoRetryAction]"
	policy_set_and_test "+NRA" "[NonBlockingRestore] [NoRetryAction]"
	policy_set_and_test "-NBR" "NonBlockingRestore [NoRetryAction]"
	policy_set_and_test "-NRA" "NonBlockingRestore NoRetryAction"
	policy_set_and_test "NRA NBR" "[NonBlockingRestore] [NoRetryAction]"
	local policy=$(do_facet $SINGLEMDS $LCTL get_param -n $HSM_PARAM.policy)
	echo "Next set_param must failed"
	policy_set_and_test "wrong" "$policy"
	echo "Back to default policy"
	cdt_set_sanity_policy
}
run_test 109 "Policy display/change"
test_110a() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	copy2archive /etc/passwd $tdir/$tfile
	local f=$DIR/$tdir/$tfile
	copytool import $tdir/$tfile $f
	local fid=$(path2fid $f)
	cdt_set_non_blocking_restore
	md5sum $f
	local st=$?
	wait_request_state $fid RESTORE SUCCEED
	cdt_clear_non_blocking_restore
	[[ $st == 1 ]] ||
		error "md5sum returns $st != 1, "\
			"should also perror ENODATA (No data available)"
}
run_test 110a "Non blocking restore policy (import case)"
test_110b() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/passwd $f)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f
	cdt_set_non_blocking_restore
	md5sum $f
	local st=$?
	wait_request_state $fid RESTORE SUCCEED
	cdt_clear_non_blocking_restore
	[[ $st == 1 ]] ||
		error "md5sum returns $st != 1, "\
			"should also perror ENODATA (No data available)"
}
run_test 110b "Non blocking restore policy (release case)"
test_111a() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	copy2archive /etc/passwd $tdir/$tfile
	local f=$DIR/$tdir/$tfile
	copytool import $tdir/$tfile $f
	local fid=$(path2fid $f)
	cdt_set_no_retry
	copytool_remove_backend $fid
	$LFS hsm_restore $f
	wait_request_state $fid RESTORE FAILED
	local st=$?
	cdt_clear_no_retry
	[[ $st == 0 ]] || error "Restore does not failed"
}
run_test 111a "No retry policy (import case), restore will error"\
	      " (No such file or directory)"
test_111b() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/passwd $f)
	stack_trap cdt_clear_no_retry EXIT
	cdt_set_no_retry
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f
	copytool_remove_backend $fid
	$LFS hsm_restore $f
	wait_request_state $fid RESTORE FAILED
	local st=$?
	[[ $st == 0 ]] || error "Restore does not failed"
}
run_test 111b "No retry policy (release case), restore will error"\
	      " (No such file or directory)"
test_112() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/passwd $f)
	cdt_disable
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	local l=$($LFS hsm_action $f)
	echo $l
	local res=$(echo $l | cut -f 2- -d" " | grep ARCHIVE)
	cdt_enable
	wait_request_state $fid ARCHIVE SUCCEED
	[[ ! -z "$res" ]] || error "action is $l which is not an ARCHIVE"
}
run_test 112 "State of recorded request"
test_113() {
	mkdir_on_mdt0 $DIR/$tdir
	local file1=$DIR/$tdir/$tfile
	local file2=$DIR2/$tdir/$tfile
	local fid=$(create_small_sync_file $file1)
	stack_trap "zconf_umount \"$(facet_host $SINGLEAGT)\" \"$MOUNT3\"" EXIT
	zconf_mount "$(facet_host $SINGLEAGT)" "$MOUNT3" ||
		error "cannot mount '$MOUNT3' on '$SINGLEAGT'"
	copytool setup -m  "$MOUNT3"
	do_nodes $(comma_list $(nodes_list)) $LCTL clear
	$LFS hsm_archive $file1 || error "Fail to archive $file1"
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $file1
	echo "Verifying released state: "
	check_hsm_flags $file1 "0x0000000d"
	multiop_bg_pause $file1 oO_WRONLY:O_APPEND:_w4c || error "multiop failed"
	MULTIPID=$!
	stat $file2 &
	kill -USR1 $MULTIPID
	wait
	sync
	local size1=$(stat -c "%s" $file1)
	local size2=$(stat -c "%s" $file2)
	[ $size1 -eq $size2 ] || error "sizes are different $size1 $size2"
}
run_test 113 "wrong stat after restore"
test_114() {
	(( MDS1_VERSION >= $(version_code 2.15.54) )) ||
		skip "need MDS version at least 2.15.54"
	mkdir_on_mdt0 $DIR/$tdir
	local f1=$DIR/$tdir/${tfile}1
	local f2=$DIR/$tdir/${tfile}2
	local fid1=$(create_empty_file "$f1")
	local fid2=$(create_empty_file "$f2")
	copytool setup
	cdt_disable
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f1 $f2
	wait_request_state "$fid1" ARCHIVE WAITING
	$LFS hsm_set --noarchive $f2
	cdt_enable
	wait_request_state "$fid1" ARCHIVE SUCCEED
	wait_request_state "$fid2" ARCHIVE FAILED
}
run_test 114 "Incompatible request does not set other requests as STARTED"
test_200() {
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_empty_file "$f")
	copytool setup
	copytool_suspend
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE STARTED
	$LFS hsm_cancel "$f"
	wait_request_state $fid ARCHIVE CANCELED
	copytool_continue
	wait_request_state $fid CANCEL SUCCEED
}
run_test 200 "Register/Cancel archive"
test_201() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	create_archive_file $tdir/$tfile
	copytool import $tdir/$tfile $f
	local fid=$(path2fid $f)
	cdt_disable
	$LFS hsm_restore $f
	wait_request_state $fid RESTORE WAITING
	$LFS hsm_cancel $f
	cdt_enable
	wait_request_state $fid RESTORE CANCELED
	wait_request_state $fid CANCEL SUCCEED
}
run_test 201 "Register/Cancel restore"
test_202() {
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_empty_file "$f")
	copytool setup
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	copytool_suspend
	$LFS hsm_remove $f
	wait_request_state $fid REMOVE STARTED
	$LFS hsm_cancel $f
	wait_request_state $fid REMOVE CANCELED
}
run_test 202 "Register/Cancel remove"
test_220A() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/passwd $f)
	changelog_register
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	changelog_find -type HSM -target-fid $fid -flags 0x0 ||
		error "The expected changelog was not emitted"
}
run_test 220A "Changelog for archive"
test_220a() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/passwd $f)
	changelog_register
	copytool_suspend
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE STARTED
	rm -f $f
	copytool_continue
	wait_request_state $fid ARCHIVE FAILED
	changelog_find -type HSM -target-fid $fid -flags 0x2 ||
		error "The expected changelog was not emitted"
}
run_test 220a "Changelog for failed archive"
test_221() {
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_empty_file "$f")
	copytool setup -b 1
	changelog_register
	copytool_suspend
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE STARTED
	$LFS hsm_cancel $f
	wait_request_state $fid ARCHIVE CANCELED
	copytool_continue
	wait_request_state $fid CANCEL SUCCEED
	changelog_find -type HSM -target-fid $fid -flags 0x7d ||
		error "The expected changelog was not emitted"
}
run_test 221 "Changelog for archive canceled"
test_222a() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	copy2archive /etc/passwd $tdir/$tfile
	local f=$DIR/$tdir/$tfile
	copytool import $tdir/$tfile $f
	local fid=$(path2fid $f)
	changelog_register
	$LFS hsm_restore $f
	wait_request_state $fid RESTORE SUCCEED
	changelog_find -type HSM -target-fid $fid -flags 0x80 ||
		error "The expected changelog was not emitted"
}
run_test 222a "Changelog for explicit restore"
test_222b() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/passwd $f)
	changelog_register
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f
	md5sum $f
	wait_request_state $fid RESTORE SUCCEED
	changelog_find -type HSM -target-fid $fid -flags 0x80 ||
		error "The expected changelog was not emitted"
}
run_test 222b "Changelog for implicit restore"
test_222c() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	copy2archive /etc/passwd $tdir/$tfile
	local f=$DIR/$tdir/$tfile
	copytool import $tdir/$tfile $f
	local fid=$(path2fid $f)
	changelog_register
	copytool_suspend
	$LFS hsm_restore $f
	wait_request_state $fid RESTORE STARTED
	rm -f $f
	copytool_continue
	wait_request_state $fid RESTORE FAILED
	changelog_find -type HSM -target-fid $fid -flags 0x82 ||
		error "The expected changelog was not emitted"
}
run_test 222c "Changelog for failed explicit restore"
test_222d() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/passwd $f)
	changelog_register
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f
	copytool_remove_backend $fid
	md5sum $f
	wait_request_state $fid RESTORE FAILED
	changelog_find -type HSM -target-fid $fid -flags 0x82 ||
		error "The expected changelog was not emitted"
}
run_test 222d "Changelog for failed implicit restore"
test_223a() {
	copytool setup -b 1
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	create_archive_file $tdir/$tfile
	changelog_register
	copytool import $tdir/$tfile $f
	local fid=$(path2fid $f)
	$LFS hsm_restore $f
	wait_request_state $fid RESTORE STARTED
	$LFS hsm_cancel $f
	wait_request_state $fid RESTORE CANCELED
	wait_request_state $fid CANCEL SUCCEED
	changelog_find -type HSM -target-fid $fid -flags 0xfd ||
		error "The expected changelog was not emitted"
}
run_test 223a "Changelog for restore canceled (import case)"
test_223b() {
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_empty_file "$f")
	copytool setup -b 1
	changelog_register
	$LFS hsm archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm release $f
	copytool_suspend
	$LFS hsm restore $f
	wait_request_state $fid RESTORE STARTED
	$LFS hsm cancel $f
	wait_request_state $fid RESTORE CANCELED
	copytool_continue
	wait_request_state $fid CANCEL SUCCEED
	changelog_find -type HSM -target-fid $fid -flags 0xfd ||
		error "The expected changelog was not emitted"
}
run_test 223b "Changelog for restore canceled (release case)"
test_224A() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/passwd $f)
	changelog_register
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_remove $f
	wait_request_state $fid REMOVE SUCCEED
	changelog_find -type HSM -target-fid $fid -flags 0x200 ||
		error "The expected changelog was not emitted"
}
run_test 224A "Changelog for remove"
test_224a() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(copy_file /etc/passwd $f)
	changelog_register
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	copytool_remove_backend $fid
	copytool_suspend
	$LFS hsm_remove $f
	wait_request_state $fid REMOVE STARTED
	rm -f $f
	copytool_continue
	wait_request_state $fid REMOVE FAILED
	changelog_find -type HSM -target-fid $fid -flags 0x202 ||
		error "The expected changelog was not emitted"
}
run_test 224a "Changelog for failed remove"
test_225() {
	echo "Test disabled"
	return 0
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_empty_file "$f")
	changelog_register
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	copytool_suspend
	$LFS hsm_remove $f
	$LFS hsm_cancel $f
	wait_request_state $fid REMOVE CANCELED
	copytool_continue
	wait_request_state $fid CANCEL SUCCEED
	changelog_find -type HSM -target-fid $fid -flags 0x27d
		error "The expected changelog was not emitted"
}
run_test 225 "Changelog for remove canceled"
test_226() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f1=$DIR/$tdir/$tfile-1
	local f2=$DIR/$tdir/$tfile-2
	local f3=$DIR/$tdir/$tfile-3
	local fid1=$(copy_file /etc/passwd $f1)
	local fid2=$(copy_file /etc/passwd $f2)
	copy_file /etc/passwd $f3
	changelog_register
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f1
	wait_request_state $fid1 ARCHIVE SUCCEED
	$LFS hsm_archive $f2
	wait_request_state $fid2 ARCHIVE SUCCEED
	rm $f1 || error "rm $f1 failed"
	changelog_dump
	changelog_find -type UNLNK -target-fid $fid1 -flags 0x3 ||
		error "The expected changelog was not emitted"
	mv $f3 $f2 || error "mv $f3 $f2 failed"
	changelog_find -type RENME -target-fid $fid2 -flags 0x3 ||
		error "The expected changelog was not emitted"
}
run_test 226 "changelog for last rm/mv with exiting archive"
__test_227()
{
	local target=0x280
	"$LFS" "$action" --$flag "$file" ||
		error "Cannot ${action
	local entries="$(changelog_find -type HSM -target-fid $fid)"
	[ $(wc -l <<< "$entries") -eq $((++count)) ] ||
		error "lfs $action --$flag '$file' produced more than one" \
		      "changelog record"
	local entry="$(tail -n 1 <<< "$entries")"
	eval local -A changelog=$(changelog2array $entry)
	[[ ${changelog[flags]} == $target ]] ||
		error "Changelog flag is '${changelog[flags]}', not $target"
}
test_227() {
	local file="$DIR/$tdir/$tfile"
	local fid=$(create_empty_file "$file")
	local count=0
	changelog_register
	for flag in norelease noarchive exists archived lost; do
		if [ "$flag" == lost ]; then
			"$LFS" hsm_set --archived "$file"
			((count++))
		fi
		action="hsm_set" __test_227
		action="hsm_clear" __test_227
	done
}
run_test 227 "changelog when explicit setting of HSM flags"
test_228() {
	local filefrag_op=$(filefrag -l 2>&1 | grep "invalid option")
	[[ -z "$filefrag_op" ]] || skip_env "filefrag missing logical ordering"
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local fid=$(create_small_sync_file $DIR/$tfile)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $DIR/$tfile
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $DIR/$tfile
	check_hsm_flags $DIR/$tfile "0x0000000d"
	filefrag $DIR/$tfile | grep " 1 extent found" ||
		error "filefrag on released file must return only one extent"
	cp --sparse=auto $DIR/$tfile $DIR/$tfile.2 ||
		error "copying $DIR/$tfile"
	cmp $DIR/$tfile $DIR/$tfile.2 || error "comparing copied $DIR/$tfile"
	$LFS hsm_release $DIR/$tfile
	check_hsm_flags $DIR/$tfile "0x0000000d"
	mkdir -p $DIR/$tdir || error "mkdir $tdir failed"
	tar cf - --sparse $DIR/$tfile | tar xvf - -C $DIR/$tdir ||
		error "tar failed"
	cmp $DIR/$tfile $DIR/$tdir/$DIR/$tfile ||
		error "comparing untarred $DIR/$tfile"
	rm -f $DIR/$tfile $DIR/$tfile.2 ||
		error "rm $DIR/$tfile or $DIR/$tfile.2 failed"
}
run_test 228 "On released file, return extend to FIEMAP. For [cp,tar] --sparse"
test_250() {
	local file="$DIR/$tdir/$tfile"
	stack_trap \
		"set_hsm_param max_requests $(get_hsm_param max_requests)" EXIT
	set_hsm_param max_requests 3
	stack_trap \
		"set_hsm_param loop_period $(get_hsm_param loop_period)" EXIT
	set_hsm_param loop_period 1
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	for action in archive restore remove; do
		local filepath="$file"-to-$action
		local fid=$(create_empty_file "$filepath")
		local fid2=$(create_empty_file "$filepath".bis)
		if [ "$action" != archive ]; then
			"$LFS" hsm_archive "$filepath"
			wait_request_state $fid ARCHIVE SUCCEED
			"$LFS" hsm_archive "$filepath".bis
			wait_request_state $fid2 ARCHIVE SUCCEED
		fi
		if [ "$action" == restore ]; then
			"$LFS" hsm_release "$filepath"
			"$LFS" hsm_release "$filepath".bis
		fi
	done
	stack_trap "copytool_continue" EXIT
	copytool_suspend
	for action in archive restore remove; do
		filepath="$file"-to-$action
		"$LFS" hsm_${action} "$filepath"
		wait_request_state $(path2fid "$filepath") "${action^^}" STARTED
	done
	for action in archive restore remove; do
		"$LFS" hsm_${action} "$file-to-$action".bis
	done
	sleep 1
	local -i count
	count=$(do_facet $SINGLEMDS "$LCTL" get_param -n $HSM_PARAM.actions |
		grep -c STARTED)
	((count == 3)) ||
		error "expected 3 STARTED requests, found $count"
}
run_test 250 "Coordinator max request"
test_251() {
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_empty_file "$f")
	cdt_disable
	local old_to=$(get_hsm_param active_request_timeout)
	set_hsm_param active_request_timeout 1
	local old_loop=$(get_hsm_param loop_period)
	set_hsm_param loop_period 1
	cdt_enable
	copytool setup
	copytool_suspend
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE STARTED
	wait_request_state $fid ARCHIVE CANCELED
	set_hsm_param active_request_timeout $old_to
	set_hsm_param loop_period $old_loop
}
run_test 251 "Coordinator request timeout"
test_252() {
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_empty_file "$f")
	stack_trap "set_hsm_param loop_period $(get_hsm_param loop_period)" EXIT
	set_hsm_param loop_period 1
	copytool setup
	copytool_suspend
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE STARTED
	rm -f "$f"
	stack_trap "set_hsm_param active_request_timeout \
		    $(get_hsm_param active_request_timeout)" EXIT
	set_hsm_param active_request_timeout 1
	wait_request_state $fid ARCHIVE CANCELED
	copytool_continue
}
run_test 252 "Timeout'ed running archive of a removed file should be canceled"
test_253() {
	local rc
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	dd if=/dev/zero of=$f bs=1MB count=10
	local fid=$(path2fid $f)
	$LFS hsm_archive $f || error "could not archive file"
	wait_request_state $fid ARCHIVE SUCCEED
	cancel_lru_locks osc
	$LCTL set_param fail_loc=0x807
	$LFS hsm_release $f
	rc=$?
	if ((rc == 0)); then
		file_size=$(stat -c '%s' $f)
		if ((file_size != 10485760)); then
			error "Wrong file size after hsm_release"
		fi
	else
		echo "could not release file"
	fi
}
run_test 253 "Check for wrong file size after release"
test_254a()
{
	[ $MDS1_VERSION -lt $(version_code 2.10.56) ] &&
		skip "need MDS version at least 2.10.56"
	local count
	for request_type in archive restore remove; do
		count="$(get_hsm_param ${request_type}_count)" ||
			error "Reading ${request_type}_count failed with $?"
		[ "$count" -eq 0 ] ||
			error "Expected ${request_type}_count to be " \
			      "0 != '$count'"
	done
}
run_test 254a "Request counters are initialized to zero"
test_254b()
{
	[ $MDS1_VERSION -lt $(version_code 2.10.56) ] &&
		skip "need MDS version at least 2.10.56"
	local request_count=$((RANDOM % 32 + 32))
	printf "Will launch %i requests of each type\n" "$request_count"
	copytool setup
	stack_trap \
		"set_hsm_param max_requests $(get_hsm_param max_requests)" EXIT
	set_hsm_param max_requests "$request_count"
	mkdir_on_mdt0 $DIR/$tdir
	local timeout
	local count
	for request_type in archive restore remove; do
		printf "Checking %s requests\n" "${request_type}"
		copytool_suspend
		for ((i = 0; i < $request_count; i++)); do
			case $request_type in
			archive)
				create_empty_file "$DIR/$tdir/$tfile-$i" \
					>/dev/null 2>&1
				;;
			restore)
				lfs hsm_release "$DIR/$tdir/$tfile-$i"
				;;
			esac
			$LFS hsm_${request_type} "$DIR/$tdir/$tfile-$i"
		done
		timeout=10
		while get_hsm_param actions | grep -q WAITING; do
			sleep 1
			let timeout-=1
			[ $timeout -gt 0 ] ||
				error "${request_type^} requests took too " \
				      "long to start"
		done
		count="$(get_hsm_param ${request_type}_count)"
		[ "$count" -eq "$request_count" ] ||
			error "Expected '$request_count' (!= '$count') " \
			      "active $request_type requests"
		copytool_continue
		timeout=10
		while get_hsm_param actions | grep -q STARTED; do
			sleep 1
			let timeout-=1
			[ $timeout -gt 0 ] ||
				error "${request_type^} requests took too " \
				      "long to complete"
		done
		count="$(get_hsm_param ${request_type}_count)"
		[ "$count" -eq 0 ] ||
			error "Expected 0 (!= '$count') " \
			      "active $request_type requests"
	done
}
run_test 254b "Request counters are correctly incremented and decremented"
test_255()
{
	[ $MDS1_VERSION -lt $(version_code 2.12.0) ] &&
		skip "Need MDS version at least 2.12.0"
	mkdir_on_mdt0 $DIR/$tdir
	local file="$DIR/$tdir/$tfile"
	local fid=$(create_empty_file "$file")
	copytool setup
	"$LFS" hsm_archive "$file"
	wait_request_state $fid ARCHIVE SUCCEED
	kill_copytools
	wait_copytools || error "failed to stop copytools"
	rm "$file"
	create_empty_file "$file"
	"$LFS" hsm_archive "$file"
	cdt_shutdown
	stack_trap "set_hsm_param grace_delay $(get_hsm_param grace_delay)" EXIT
	set_hsm_param grace_delay 1
	do_facet $SINGLEMDS sleep 2 &
	stack_trap "set_hsm_param loop_period $(get_hsm_param loop_period)" EXIT
	set_hsm_param loop_period 1000
	wait $! || error "waiting failed"
	cdt_enable
	wait_request_state $fid ARCHIVE ""
	copytool setup
	wait_request_state $(path2fid "$file") ARCHIVE SUCCEED
}
run_test 255 "Copytool registration wakes the coordinator up"
test_260a()
{
	[ $MDS1_VERSION -lt $(version_code 2.11.56) ] &&
		skip "need MDS version 2.11.56 or later"
	local -a files=("$DIR/$tdir/$tfile".{0..15})
	local file
	mkdir_on_mdt0 $DIR/$tdir
	for file in "${files[@]}"; do
		create_small_file "$file"
	done
	stack_trap \
		"set_hsm_param loop_period $(get_hsm_param loop_period)" EXIT
	set_hsm_param loop_period 1
	stack_trap \
		"set_hsm_param max_requests $(get_hsm_param max_requests)" EXIT
	set_hsm_param max_requests 3
	copytool setup
	"$LFS" hsm_archive "${files[0]}"
	wait_request_state "$(path2fid "${files[0]}")" ARCHIVE SUCCEED
	"$LFS" hsm_release "${files[0]}"
	kill_copytools
	wait_copytools || error "copytools failed to stop"
	for file in "${files[@]:1}"; do
		"$LFS" hsm_archive "$file"
	done
	"$LFS" hsm_restore "${files[0]}"
	copytool setup
	wait_request_state "$(path2fid "${files[0]}")" RESTORE SUCCEED
	for file in "${files[@]:1}"; do
		wait_request_state "$(path2fid "$file")" ARCHIVE SUCCEED
	done
	local -a actions=(
		$(do_facet "$SINGLEAGT" grep -o '\"RESTORE\\|ARCHIVE\"' \
			"$(copytool_logfile "$SINGLEAGT")")
		)
	printf '%s\n' "${actions[@]}"
	local action
	for action in "${actions[@]:0:3}"; do
		[ "$action" == RESTORE ] && return
	done
	error "Too many ARCHIVE requests were run before the RESTORE request"
}
run_test 260a "Restore request have priority over other requests"
test_260b()
{
	[ $MDS1_VERSION -lt $(version_code 2.11.56) ] &&
		skip "need MDS version 2.11.56 or later"
	local -a files=("$DIR/$tdir/$tfile".{0..15})
	local file
	mkdir_on_mdt0 $DIR/$tdir
	for file in "${files[@]}"; do
		create_small_file "$file"
	done
	stack_trap \
		"set_hsm_param loop_period $(get_hsm_param loop_period)" EXIT
	set_hsm_param loop_period 1
	stack_trap \
		"set_hsm_param max_requests $(get_hsm_param max_requests)" EXIT
	set_hsm_param max_requests 3
	copytool setup --archive-id 2
	"$LFS" hsm_archive --archive 2 "${files[0]}"
	wait_request_state "$(path2fid "${files[0]}")" ARCHIVE SUCCEED
	"$LFS" hsm_release "${files[0]}"
	kill_copytools
	wait_copytools || error "copytools failed to stop"
	for file in "${files[@]:1}"; do
		"$LFS" hsm_archive "$file"
	done
	"$LFS" hsm_restore "${files[0]}"
	copytool setup
	copytool setup --archive-id 2
	wait_request_state "$(path2fid "${files[0]}")" RESTORE SUCCEED
	for file in "${files[@]:1}"; do
		wait_request_state "$(path2fid "$file")" ARCHIVE SUCCEED
	done
	local -a actions=(
		$(do_facet "$SINGLEAGT" grep -o '\"RESTORE\\|ARCHIVE\"' \
			"$(copytool_logfile "$SINGLEAGT")")
		)
	printf '%s\n' "${actions[@]}"
	local action
	for action in "${actions[@]:0:3}"; do
		[ "$action" == RESTORE ] && return
	done
	error "Too many ARCHIVE requests were run before the RESTORE request"
}
run_test 260b "Restore request have priority over other requests"
test_260c()
{
	[ $MDS1_VERSION -lt $(version_code 2.12.0) ] &&
		skip "Need MDS version at least 2.12.0"
	local -a files=("$DIR/$tdir/$tfile".{0..15})
	local file
	mkdir_on_mdt0 $DIR/$tdir
	for file in "${files[@]}"; do
		create_small_file "$file"
	done
	stack_trap \
		"set_hsm_param loop_period $(get_hsm_param loop_period)" EXIT
	set_hsm_param loop_period 1000
	stack_trap \
		"set_hsm_param max_requests $(get_hsm_param max_requests)" EXIT
	set_hsm_param max_requests 3
	copytool setup --archive-id 2
	"$LFS" hsm_archive --archive 2 "${files[0]}"
	wait_request_state "$(path2fid "${files[0]}")" ARCHIVE SUCCEED
	"$LFS" hsm_release "${files[0]}"
	kill_copytools
	wait_copytools || error "copytools failed to stop"
	cdt_shutdown
	cdt_enable
	"$LFS" hsm_archive "${files[1]}"
	copytool setup
	copytool setup --archive-id 2
	wait_request_state "$(path2fid "${files[1]}")" ARCHIVE SUCCEED
	for file in "${files[@]:2}"; do
		"$LFS" hsm_archive "$file"
	done
	"$LFS" hsm_restore "${files[0]}"
	wait_request_state "$(path2fid "${files[0]}")" RESTORE SUCCEED
	for file in "${files[@]:2}"; do
		wait_request_state "$(path2fid "$file")" ARCHIVE SUCCEED
	done
	local -a actions=(
		$(do_facet "$SINGLEAGT" grep -o '\"RESTORE\\|ARCHIVE\"' \
			"$(copytool_logfile "$SINGLEAGT")")
		)
	printf '%s\n' "${actions[@]}"
	local action
	for action in "${actions[@]:0:3}"; do
		[ "$action" == RESTORE ] &&
			error "Restore requests should not be prioritised" \
			      "unless the coordinator is doing housekeeping"
	done
	return 0
}
run_test 260c "Requests are not reordered on the 'hot' path of the coordinator"
test_261() {
	local file=$DIR/$tdir/$tfile
	local size
	local fid
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	dd if=/dev/zero of=$file bs=4k count=2 || error "Write $file failed"
	fid=$(path2fid $file)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $file
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_state $file
	$LFS hsm_release $file
	$LFS hsm_restore $file
	wait_request_state $fid RESTORE SUCCEED
	$LFS hsm_release $file
	size=$(stat -c %s $file)
	[[ $size == 8192 ]] || error "Size after HSM release: $size"
	$LFS hsm_release $file
	$LFS hsm_restore $file
	$LFS hsm_release $file
	size=$(stat -c %s $file)
	[[ $size == 8192 ]] || error "Size after HSM release: $size"
	$LFS hsm_state $file
}
run_test 261 "Report 0 bytes size after HSM release"
test_262() {
	(( MDS1_VERSION >= $(version_code v2_15_61-204-g5ee13823a4) )) ||
		skip "Need MDS version at least 2.15.61"
	local file=$DIR/$tdir/$tfile
	local blocks
	local fid
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	dd if=/dev/zero of=$file bs=4k count=2 || error "Write $file failed"
	fid=$(path2fid $file)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $file
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $file || error "HSM release $file failed"
	$LFS hsm_restore $file || error "HSM restore $file failed"
	$LFS hsm_release $file || error "HSM release $file failed"
	$LFS hsm_release $file || error "HSM release $file failed"
	blocks=$(stat -c "%b" $file)
	[ $blocks -eq "1" ] || error "wrong block number is $blocks, not 1"
}
run_test 262 "The client should return 1 block for HSM released files"
test_300() {
	[ "$CLIENTONLY" ] && skip "CLIENTONLY mode" && return
	echo "Stop coordinator and remove coordinator state at mount"
	cdt_shutdown
	cdt_clear_mount_state
	cdt_check_state stopped
	fail $SINGLEMDS
	cdt_check_state stopped
	echo "Set coordinator start at mount, and start coordinator"
	cdt_set_mount_state enabled
	cdt_check_state enabled
	fail $SINGLEMDS
	cdt_check_state enabled
}
run_test 300 "On disk coordinator state kept between MDT umount/mount"
test_301() {
	[ "$CLIENTONLY" ] && skip "CLIENTONLY mode" && return
	local ai=$(get_hsm_param default_archive_id)
	local new=$((ai + 1))
	set_hsm_param default_archive_id $new -P
	fail $SINGLEMDS
	local res=$(get_hsm_param default_archive_id)
	set_hsm_param default_archive_id "" "-P -d"
	[[ $new == $res ]] || error "Value after MDS restart is $res != $new"
}
run_test 301 "HSM tunnable are persistent"
test_302() {
	[ "$CLIENTONLY" ] && skip "CLIENTONLY mode" && return
	local ai=$(get_hsm_param default_archive_id)
	local new=$((ai + 1))
	cdt_shutdown
	set_hsm_param default_archive_id $new -P
	local mdtno
	for mdtno in $(seq 1 $MDSCOUNT); do
		fail mds${mdtno}
	done
	cdt_check_state enabled
	local res=$(get_hsm_param default_archive_id)
	set_hsm_param default_archive_id "" "-P -d"
	[[ $new == $res ]] || error "Value after MDS restart is $res != $new"
}
run_test 302 "HSM tunnable are persistent when CDT is off"
test_400() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local dir_mdt0=$DIR/$tdir/mdt0
	local dir_mdt1=$DIR/$tdir/mdt1
	stack_trap "rm -rf $dir_mdt0" EXIT
	$LFS mkdir -i 0 $dir_mdt0 || error "lfs mkdir"
	stack_trap "rm -rf $dir_mdt1" EXIT
	$LFS mkdir -i 1 $dir_mdt1 || error "lfs mkdir"
	local fid1=$(create_small_file $dir_mdt0/$tfile)
	local fid2=$(create_small_file $dir_mdt1/$tfile)
	$LFS hsm_archive $dir_mdt0/$tfile || error "lfs hsm_archive"
	wait_request_state $fid1 ARCHIVE SUCCEED 0 &&
		echo "archive successful on mdt0"
	$LFS hsm_archive $dir_mdt1/$tfile || error "lfs hsm_archive"
	wait_request_state $fid2 ARCHIVE SUCCEED 1 &&
		echo "archive successful on mdt1"
}
run_test 400 "Single request is sent to the right MDT"
test_401() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local dir_mdt0=$DIR/$tdir/mdt0
	local dir_mdt1=$DIR/$tdir/mdt1
	stack_trap "rm -rf $dir_mdt0" EXIT
	$LFS mkdir -i 0 $dir_mdt0 || error "lfs mkdir"
	stack_trap "rm -rf $dir_mdt1" EXIT
	$LFS mkdir -i 1 $dir_mdt1 || error "lfs mkdir"
	local fid1=$(create_small_file $dir_mdt0/$tfile)
	local fid2=$(create_small_file $dir_mdt1/$tfile)
	$LFS hsm_archive $dir_mdt0/$tfile $dir_mdt1/$tfile ||
		error "lfs hsm_archive"
	wait_request_state $fid1 ARCHIVE SUCCEED 0 &&
		echo "archive successful on mdt0"
	wait_request_state $fid2 ARCHIVE SUCCEED 1 &&
		echo "archive successful on mdt1"
}
run_test 401 "Compound requests split and sent to their respective MDTs"
mdc_change_state()
{
	local facet=$1
	local pattern="$2"
	local state=$3
	local node=$(facet_active_host $facet)
	local mdc
	for mdc in $(do_facet $facet "$LCTL dl | grep -E ${pattern}-mdc" |
			awk '{print $4}'); do
		echo "$3 $mdc on $node"
		do_facet $facet "$LCTL --device $mdc $state" || return 1
	done
}
test_402a() {
	mdc_change_state $SINGLEAGT "$FSNAME-MDT000." "deactivate"
	copytool setup --no-fail
	check_agent_unregistered "uuid"
	search_copytools $agent && error "Copytool start should have failed"
	mdc_change_state $SINGLEAGT "$FSNAME-MDT000." "activate"
}
run_test 402a "Copytool start fails if all MDTs are inactive"
test_402b() {
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	touch $f || error "touch $f failed"
	local fid=$(path2fid $f)
	do_facet $SINGLEAGT lctl set_param fail_loc=0x14d
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_for_loop_period
	wait_request_state $fid ARCHIVE WAITING
	do_facet $SINGLEAGT lctl set_param fail_loc=0
	wait_request_state $fid ARCHIVE SUCCEED
}
run_test 402b "CDT must retry request upon slow start of CT"
test_403() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return
        local agent=$(facet_active_host $SINGLEAGT)
	mdc_change_state $SINGLEAGT "$FSNAME-MDT0001" "deactivate"
	copytool setup
	local uuid=$(get_agent_uuid $agent)
	check_agent_registered_by_mdt $uuid 0
	check_agent_unregistered_by_mdt $uuid 1
	search_copytools $agent || error "No running copytools on $agent"
	mdc_change_state $SINGLEAGT "$FSNAME-MDT0001" "activate"
	check_agent_registered $uuid
}
run_test 403 "Copytool starts with inactive MDT and register on reconnect"
test_404() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local dir_mdt0=$DIR/$tdir/mdt0
	stack_trap "rm -rf $dir_mdt0" EXIT
	$LFS mkdir -i 0 $dir_mdt0 || error "lfs mkdir"
	local fid1=$(create_small_file $dir_mdt0/$tfile)
	mdc_change_state $SINGLEAGT "$FSNAME-MDT0001" "deactivate"
	$LFS hsm_archive $dir_mdt0/$tfile || error "lfs hsm_archive"
	wait_request_state $fid1 ARCHIVE SUCCEED 0 &&
		echo "archive successful on mdt0"
	mdc_change_state $SINGLEAGT "$FSNAME-MDT0001" "activate"
}
run_test 404 "Inactive MDT does not block requests for active MDTs"
test_405() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return
	copytool setup
	mkdir_on_mdt0 $DIR/$tdir
	local striped_dir=$DIR/$tdir/striped_dir
	$LFS mkdir -i 0 -c $MDSCOUNT $striped_dir || error "lfs mkdir"
	local fid1=$(create_small_sync_file $striped_dir/${tfile}_0)
	local fid2=$(create_small_sync_file $striped_dir/${tfile}_1)
	local fid3=$(create_small_sync_file $striped_dir/${tfile}_2)
	local fid4=$(create_small_sync_file $striped_dir/${tfile}_3)
	local idx1=$($LFS getstripe -m $striped_dir/${tfile}_0)
	local idx2=$($LFS getstripe -m $striped_dir/${tfile}_1)
	local idx3=$($LFS getstripe -m $striped_dir/${tfile}_2)
	local idx4=$($LFS getstripe -m $striped_dir/${tfile}_3)
	$LFS hsm_archive $striped_dir/${tfile}_0 $striped_dir/${tfile}_1  \
			 $striped_dir/${tfile}_2 $striped_dir/${tfile}_3 ||
		error "lfs hsm_archive"
	wait_request_state $fid1 ARCHIVE SUCCEED $idx1 &&
		echo "archive successful on $fid1"
	wait_request_state $fid2 ARCHIVE SUCCEED $idx2 &&
		echo "archive successful on $fid2"
	wait_request_state $fid3 ARCHIVE SUCCEED $idx3 &&
		echo "archive successful on $fid3"
	wait_request_state $fid4 ARCHIVE SUCCEED $idx4 &&
		echo "archive successful on $fid4"
	$LFS hsm_release $striped_dir/${tfile}_0 || error "lfs hsm_release 1"
	$LFS hsm_release $striped_dir/${tfile}_1 || error "lfs hsm_release 2"
	$LFS hsm_release $striped_dir/${tfile}_2 || error "lfs hsm_release 3"
	$LFS hsm_release $striped_dir/${tfile}_3 || error "lfs hsm_release 4"
	cat $striped_dir/${tfile}_0 > /dev/null || error "cat ${tfile}_0 failed"
	cat $striped_dir/${tfile}_1 > /dev/null || error "cat ${tfile}_1 failed"
	cat $striped_dir/${tfile}_2 > /dev/null || error "cat ${tfile}_2 failed"
	cat $striped_dir/${tfile}_3 > /dev/null || error "cat ${tfile}_3 failed"
}
run_test 405 "archive and release under striped directory"
test_406() {
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs" && return 0
	[ $MDS1_VERSION -lt $(version_code 2.7.64) ] &&
		skip "need MDS version at least 2.7.64"
	local fid
	local mdt_index
	mkdir_on_mdt0 $DIR/$tdir
	fid=$(create_small_file $DIR/$tdir/$tfile)
	echo "old fid $fid"
	copytool setup
	$LFS hsm_archive $DIR/$tdir/$tfile
	wait_request_state "$fid" ARCHIVE SUCCEED
	$LFS hsm_release $DIR/$tdir/$tfile
	$LFS migrate -m1 $DIR/$tdir &&
		error "migrating HSM an archived file should fail"
	$LFS hsm_restore $DIR/$tdir/$tfile
	wait_request_state "$fid" RESTORE SUCCEED
	$LFS hsm_remove $DIR/$tdir/$tfile
	wait_request_state "$fid" REMOVE SUCCEED
	cat $DIR/$tdir/$tfile > /dev/null ||
		error "cannot read $DIR/$tdir/$tfile"
	$LFS migrate -m1 $DIR/$tdir ||
		error "cannot complete migration after HSM remove"
	mdt_index=$($LFS getstripe -m $DIR/$tdir)
	if ((mdt_index != 1)); then
		error "expected MDT index 1, got $mdt_index"
	fi
	fid=$(path2fid $DIR/$tdir/$tfile)
	echo "new fid $fid"
	$LFS hsm_archive $DIR/$tdir/$tfile
	wait_request_state "$fid" ARCHIVE SUCCEED 1
	lctl set_param debug=+trace
	$LFS hsm_release $DIR/$tdir/$tfile ||
		error "cannot release $DIR/$tdir/$tfile"
	$LFS hsm_restore $DIR/$tdir/$tfile
	wait_request_state "$fid" RESTORE SUCCEED 1
	cat $DIR/$tdir/$tfile > /dev/null ||
		error "cannot read $DIR/$tdir/$tfile"
}
run_test 406 "attempting to migrate HSM archived files is safe"
test_407() {
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local f2=$DIR2/$tdir/$tfile
	local fid=$(create_empty_file "$f")
	copytool setup
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f
	do_facet $SINGLEMDS $LCTL set_param fail_val=5 fail_loc=0x164
	copytool_suspend
	md5sum $f &
	md5sum $f2 &
	sleep 2
	do_facet $SINGLEMDS "$LCTL get_param $HSM_PARAM.actions"
	sleep 30 &&
		do_facet $SINGLEMDS "$LCTL get_param $HSM_PARAM.actions"&
	fail $SINGLEMDS
	do_facet $SINGLEMDS $LCTL set_param fail_loc=0
	do_facet $SINGLEMDS "$LCTL get_param $HSM_PARAM.actions"
	copytool_continue
	wait_all_done 100 $fid
}
run_test 407 "Check for double RESTORE records in llog"
test_408 () {
	checkfiemap --test ||
		skip "checkfiemap not runnable: $?"
	local f=$DIR/$tfile
	local fid
	local out;
	copytool setup
	dd if=/dev/urandom of=$f bs=64K count=1 conv=fsync
	[[ "$(facet_fstype ost$(($($LFS getstripe -i $f) + 1)))" != "zfs" ]] ||
		skip "ORI-366/LU-1941: FIEMAP unimplemented on ZFS"
	dd if=/dev/urandom of=$f bs=64K seek=3 count=1 conv=fsync
	stat $DIR/$tfile
	echo "disk usage: $(du -B1 $f)"
	echo "file size: $(du -b $f)"
	fid=$(path2fid $f)
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f
	out=$(checkfiemap --corruption_test $f $((4 * 64 * 1024))) ||
		error "checkfiemap failed"
	echo "$out"
	grep -q "flags (0x3):" <<< "$out" ||
		error "the extent flags of a relase file should be: LAST UNKNOWN"
}
run_test 408 "Verify fiemap on release file"
test_409a() {
	(( MDS1_VERSION >= $(version_code 2.15.59) )) ||
		skip "need MDS version at least 2.15.59"
	mkdir_on_mdt0 $DIR/$tdir
	local restore_pid shutdown_pid
	local mdt0_hsm_state
	local f=$DIR/$tdir/$tfile
	local fid=$(create_empty_file "$f")
	copytool setup
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f ||
		error "could not archive file $f"
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f || error "could not release file $f"
	do_facet $SINGLEMDS $LCTL set_param fail_val=5 fail_loc=0x164
	cat $f > /dev/null & restore_pid=$!
	cdt_shutdown & shutdown_pid=$!
	stack_trap "cdt_enable" EXIT
	sleep 1;
	mdt0_hsm_state=$(do_facet mds1 "$LCTL get_param -n mdt.*MDT0000.hsm_control")
	[[ "$mdt0_hsm_state" == "stopping" ]] ||
		error "HSM state of MDT0000 is not 'stopping' (hsm_control=$mdt0_hsm_state)"
	wait $shutdown_pid
	cdt_check_state stopped
	wait_request_state $fid RESTORE WAITING
	cdt_enable
	kill_copytools
	wait_copytools || error "copytool failed to stop"
	copytool setup
	wait $restore_pid || true
	wait_request_state $fid RESTORE SUCCEED
	cat $f > /dev/null || error "fail to read $f"
}
run_test 409a "Coordinator should not stop when in use"
test_409b()
{
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_empty_file "$f")
	copytool setup
	$LFS hsm_archive --archive $HSM_ARCHIVE_NUMBER $f
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $f || error "cannot release $f"
	check_hsm_flags $f "0x0000000d"
	kill_copytools
	wait_copytools || error "copytools failed to stop"
	stack_trap "cdt_check_state enabled" EXIT
	stack_trap "cdt_set_mount_state enabled" EXIT
	cdt_set_mount_state shutdown
	cdt_check_state stopped
	fail mds1
	stat $f || error "cannot stat file"
}
run_test 409b "getattr released file with CDT stopped after remount"
test_410()
{
	(( MDS1_VERSION >= $(version_code 2.15.90.10) )) ||
		skip "need MDS >= v2_15_90-10-g80a961261a23 for HSM fix"
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local fid=$(create_small_file $f)
	copytool setup
	$LFS hsm_set --exists --archived $f ||
		error "could not change hsm flags"
	$LFS hsm_release $f 2>&1 > /dev/null && error "HSM release should fail"
	$LFS data_version -ws $f 2>&1 > /dev/null
	$LFS hsm_release $f || error "could not release file"
}
run_test 410 "lfs data_version -s allows release of force-archived file"
cleanup_411() {
	local nm=$1
	do_facet mgs $LCTL nodemap_del $nm || true
	do_facet mgs $LCTL nodemap_activate 0
	wait_nm_sync active
}
test_411()
{
	local client_ip=$(host_nids_address $HOSTNAME $NETTYPE)
	local client_nid=$(h2nettype $client_ip)
	local tf1=$DIR/$tdir/fileA
	local tf2=$DIR/$tdir/fileB
	local nm=test_411
	local roles
	local fid
	do_facet mgs $LCTL nodemap_modify --name default \
		--property admin --value 1
	do_facet mgs $LCTL nodemap_modify --name default \
		--property trusted --value 1
	do_facet mgs $LCTL nodemap_add $nm
	do_facet mgs $LCTL nodemap_add_range 	\
		--name $nm --range $client_nid
	do_facet mgs $LCTL nodemap_modify --name $nm \
		--property admin --value 1
	do_facet mgs $LCTL nodemap_modify --name $nm \
		--property trusted --value 1
	do_facet mgs $LCTL nodemap_activate 1
	stack_trap "cleanup_411 $nm" EXIT
	wait_nm_sync active
	wait_nm_sync $nm trusted_nodemap
	roles=$(do_facet mds $LCTL get_param -n nodemap.$nm.rbac)
	[[ "$roles" =~ "hsm_ops" ]] ||
		skip "role 'hsm_ops' not supported by server"
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	echo hi > $tf1 || error "create $tf1 failed"
	echo hi > $tf2 || error "create $tf2 failed"
	copytool setup
	fid=$(path2fid $tf1)
	$LFS hsm_state $tf1 || error "hsm_state $tf1 failed"
	$LFS hsm_archive $tf1 || error "hsm_archive $tf1 failed"
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS hsm_release $tf1 || error "hsm_release $tf1 failed"
	check_hsm_flags $tf1 "0x0000000d"
	$LFS hsm_restore $tf1 || error "hsm_restore $tf1 failed"
	wait_request_state $fid RESTORE SUCCEED
	$LFS hsm_remove $tf1 || error "hsm_remove $tf1 failed"
	wait_request_state $fid REMOVE SUCCEED
	check_hsm_flags $tf1 "0x00000000"
	$LFS hsm_set --exists $tf1 || error "hsm_set $tf1 failed"
	check_hsm_flags $tf1 "0x00000001"
	$LFS hsm_clear --exists $tf1 || error "hsm_clear $tf1 failed"
	check_hsm_flags $tf1 "0x00000000"
	kill_copytools
	wait_copytools || error "copytool failed to stop"
	copytool setup
	stack_trap "cleanup_411 $nm" EXIT
	roles=$(echo "$roles" | sed 's/hsm_ops,//;s/,hsm_ops//;s/^hsm_ops,//')
	do_facet mgs $LCTL nodemap_modify --name $nm \
		--property rbac --value $roles
	wait_nm_sync $nm rbac
	fid=$(path2fid $tf2)
	$LFS hsm_state $tf2 || error "hsm_state $tf2 failed"
	$LFS hsm_archive $tf2 && error "hsm_archive $tf2 succeeded"
	$LFS hsm_release $tf2 && error "hsm_release $tf2 succeeded"
	check_hsm_flags $tf2 "0x00000000"
	$LFS hsm_restore $tf2 && error "hsm_restore $tf2 succeeded"
	$LFS hsm_remove $tf2 && error "hsm_remove $tf2 succeeded"
	check_hsm_flags $tf2 "0x00000000"
	$LFS hsm_set --exists $tf2 && error "hsm_set $tf2 succeeded"
	check_hsm_flags $tf2 "0x00000000"
	$LFS hsm_clear --exists $tf2 && error "hsm_clear $tf2 succeeded"
	check_hsm_flags $tf2 "0x00000000"
}
run_test 411 "hsm_ops rbac role"
test_500()
{
	local bitmap_opt=""
	(( $MDS1_VERSION >= $(version_code 2.6.92-47-g1fe3ae8dab) )) ||
		skip "need MDS >= 2.6.92.47 for HSM migrate support"
	test_mkdir -p $DIR/$tdir
	(( $CLIENT_VERSION >= $(version_code 2.11.56-179-g3bfb6107ba) &&
	   $MDS1_VERSION >= $(version_code 2.11.56-179-g3bfb6107ba) )) ||
		bitmap_opt="-b"
	(( $MDS1_VERSION >= $(version_code 2.14.50-142-gf684172237) )) ||
		SKIP500+=" -s 113"
	llapi_hsm_test -d $DIR/$tdir $bitmap_opt $SKIP500 ||
		error "llapi HSM testing failed"
}
run_test 500 "various LLAPI HSM tests"
test_600() {
	[ "$MDS1_VERSION" -lt $(version_code 2.10.58) ] &&
		skip "need MDS version at least 2.10.58"
	mkdir -p $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	changelog_register
	changelog_chmask "ALL"
	chmod 777 $DIR/$tdir
	$RUNAS touch $f || error "touch $f failed as $RUNAS_ID"
	local fid=$(path2fid $f)
	local entry
	entry=$(changelog_find -type CREAT -target-fid $fid -uid "$RUNAS_ID" \
			       -gid "$RUNAS_GID") ||
		error "No matching CREAT entry"
	eval local -A changelog=$(changelog2array $entry)
	local nid="${changelog[nid]}"
	echo "Got NID '$nid'"
	[ -n "$nid" ] && [[ "${CLIENT_NIDS[*]}" =~ $nid ]] ||
		error "nid '$nid' does not match any client NID:" \
		      "${CLIENT_NIDS[@]}"
}
run_test 600 "Changelog fields 'u=' and 'nid='"
test_601() {
	[ $MDS1_VERSION -lt $(version_code 2.10.58) ] &&
		skip "need MDS version at least 2.10.58"
	mkdir -p $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	changelog_register
	changelog_chmask "ALL"
	touch $f || error "touch $f failed"
	local fid=$(path2fid $f)
	changelog_clear
	cat $f || error "cat $f failed"
	changelog_find -type OPEN -target-fid $fid -mode "r--" ||
		error "No matching OPEN entry"
}
run_test 601 "OPEN Changelog entry"
test_602() {
	[ $MDS1_VERSION -lt $(version_code 2.10.58) ] &&
		skip "need MDS version at least 2.10.58"
	stack_trap "restore_opencache" EXIT
	disable_opencache
	mkdir -p $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	changelog_register
	changelog_chmask "ALL"
	touch $f || error "touch $f failed"
	local fid=$(path2fid $f)
	changelog_clear
	cat $f || error "cat $f failed"
	changelog_find -type CLOSE -target-fid $fid || error "No CLOSE entry"
	changelog_clear
	changelog_dump
	echo f > $f || error "write $f failed"
	changelog_dump
	changelog_find -type CLOSE -target-fid $fid || error "No CLOSE entry"
	changelog_chmask "-OPEN"
	changelog_clear
	changelog_dump
	cat $f || error "cat $f failed"
	changelog_dump
	changelog_find -type CLOSE -target-fid $fid &&
		error "There should be no CLOSE entry"
	changelog_clear
	changelog_dump
	echo f > $f || error "write $f failed"
	changelog_dump
	changelog_find -type CLOSE -target-fid $fid || error "No CLOSE entry"
}
run_test 602 "Changelog record CLOSE only if open+write or OPEN recorded"
test_603() {
	[ $MDS1_VERSION -lt $(version_code 2.10.58) ] &&
		skip "need MDS version at least 2.10.58"
	mkdir -p $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	changelog_register
	changelog_chmask "ALL"
	touch $f || error "touch $f failed"
	local fid=$(path2fid $f)
	setfattr -n user.xattr1 -v "value1" $f || error "setfattr $f failed"
	changelog_clear
	getfattr -n user.xattr1 $f || error "getfattr $f failed"
	changelog_find -type GXATR -target-fid $fid -xattr "user.xattr1" ||
		error "No matching GXATR entry"
}
run_test 603 "GETXATTR Changelog entry"
test_604() {
	[ $MDS1_VERSION -lt $(version_code 2.10.58) ] &&
		skip "need MDS version at least 2.10.58"
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local f2=$DIR2/$tdir/$tfile
	local procname="mdd.$FSNAME-MDT0000.changelog_deniednext"
	local timeout
	timeout="$(do_facet mds1 "$LCTL" get_param -n "$procname")"
	stack_trap "do_facet mds1 '$LCTL' set_param '$procname=$timeout'" EXIT
	do_facet mds1 lctl set_param "$procname=20"
	changelog_register
	changelog_chmask "ALL"
	touch $f || error "touch $f failed"
	local fid=$(path2fid $f)
	chmod 600 $f
	changelog_clear
	changelog_dump
	$RUNAS cat $f2 && error "cat $f2 by user $RUNAS_ID should have failed"
	changelog_dump
	local entry
	entry=$(changelog_find -type NOPEN -target-fid $fid -uid "$RUNAS_ID" \
			       -gid "$RUNAS_GID" -mode "r--") ||
		error "No matching NOPEN entry"
	eval local -A changelog=$(changelog2array $entry)
	local nid="${changelog[nid]}"
	echo "Got NID '$nid'"
	[ -n "$nid" ] && [[ "${CLIENT_NIDS[*]}" =~ $nid ]] ||
		error "nid '$nid' does not match any client NID:" \
		      "${CLIENT_NIDS[@]}"
	changelog_clear
	changelog_dump
	$RUNAS cat $f2 && error "cat $f2 by user $RUNAS_ID should have failed"
	changelog_dump
	changelog_find -type NOPEN -target-fid $fid &&
		error "There should be no NOPEN entry"
	sleep 20
	changelog_clear
	changelog_dump
	$RUNAS cat $f2 && error "cat $f by user $RUNAS_ID should have failed"
	changelog_dump
	entry=$(changelog_find -type NOPEN -target-fid $fid -uid "$RUNAS_ID" \
			       -gid "$RUNAS_GID" -mode "r--") ||
		error "No matching NOPEN entry"
	eval local -A changelog=$(changelog2array $entry)
	local nid="${changelog[nid]}"
	echo "Got NID '$nid'"
	[ -n "$nid" ] && [[ "${CLIENT_NIDS[*]}" =~ $nid ]] ||
		error "nid '$nid' does not match any client NID:" \
		      "${CLIENT_NIDS[@]}"
}
run_test 604 "NOPEN Changelog entry"
test_605() {
	[ $MDS1_VERSION -lt $(version_code 2.10.58) ] &&
		skip "need MDS version at least 2.10.58"
	stack_trap "restore_opencache" EXIT
	disable_opencache
	mkdir -p $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	local f2=$DIR2/$tdir/$tfile
	changelog_register
	changelog_chmask "ALL"
	touch $f || error "touch $f failed"
	local fid=$(path2fid $f)
	changelog_clear
	changelog_dump
	exec 3<> $f || error "open $f failed"
	changelog_dump
	local entry
	changelog_find -type OPEN -target-fid $fid || error "No OPEN entry"
	changelog_clear
	changelog_dump
	exec 4<> $f || error "open $f failed"
	changelog_dump
	changelog_find -type OPEN -target-fid $fid &&
		error "There should be no OPEN entry"
	exec 4>&- || error "close $f failed"
	changelog_dump
	changelog_find -type CLOSE -target-fid $fid &&
		error "There should be no CLOSE entry"
	changelog_clear
	changelog_dump
	cat $f || error "cat $f failed"
	changelog_dump
	changelog_find -type OPEN -target-fid $fid || error "No OPEN entry"
	changelog_find -type CLOSE -target-fid $fid || error "No CLOSE entry"
	changelog_clear
	changelog_dump
	exec 4<> $f || error "open $f failed"
	changelog_dump
	changelog_find -type OPEN -target-fid $fid &&
		error "There should be no OPEN entry"
	exec 4>&- || error "close $f failed"
	changelog_dump
	changelog_find -type CLOSE -target-fid $fid &&
		error "There should be no CLOSE entry"
	changelog_clear
	changelog_dump
	$RUNAS cat $f || error "cat $f by user $RUNAS_ID failed"
	changelog_dump
	changelog_find -type OPEN -target-fid $fid || error "No OPEN entry"
	changelog_find -type CLOSE -target-fid $fid || error "No CLOSE entry"
	changelog_clear
	changelog_dump
	exec 3>&- || error "close $f failed"
	changelog_dump
	changelog_find -type CLOSE -target-fid $fid || error "No CLOSE entry"
}
run_test 605 "Test OPEN and CLOSE rate limit in Changelogs"
test_606() {
	[ $MDS1_VERSION -lt $(version_code 2.10.58) ] &&
		skip "need MDS version at least 2.10.58"
	local llog_reader=$(do_facet mgs "which llog_reader 2> /dev/null")
	llog_reader=${llog_reader:-$LUSTRE/utils/llog_reader}
	[ -z $(do_facet mgs ls -d $llog_reader 2> /dev/null) ] &&
			skip_env "missing llog_reader"
	mkdir_on_mdt0 $DIR/$tdir
	local f=$DIR/$tdir/$tfile
	changelog_register
	changelog_chmask "ALL"
	chmod 777 $DIR/$tdir
	$RUNAS touch $f || error "touch $f failed as $RUNAS_ID"
	local fid=$(path2fid $f)
	rm $f || error "rm $f failed"
	local mntpt=$(facet_mntpt mds1)
	local pass=true
	local entry
	stop mds1 || error "stop mds1 failed"
	stack_trap "unmount_fstype mds1; start mds1 $(mdsdevname 1)\
		$MDS_MOUNT_OPTS" EXIT
	mount_fstype mds1 || error "remount mds1 failed"
	for ((i = 0; i < 1; i++)); do
		do_facet mds1 $llog_reader $mntpt/changelog_catalog
		local cat_file=$(do_facet mds1 $llog_reader \
				$mntpt/changelog_catalog | awk \
				'{match($0,"path=([^ ]+)",a)}END{print a[1]}')
		[ -n "$cat_file" ] || error "no catalog file"
		entry=$(do_facet mds1 $llog_reader $mntpt/$cat_file |
			awk "/CREAT/ && /target:\[$fid\]/ {print}")
		[ -n "$entry" ] || error "no CREAT entry"
	done
	local uidgid=$(echo $entry |
		sed 's+.*\ user:\([0-9][0-9]*:[0-9][0-9]*\)\ .*+\1+')
	[ -n "$uidgid" ] || error "uidgid is empty"
	echo "Got UID/GID $uidgid"
	[ "$uidgid" = "$RUNAS_ID:$RUNAS_GID" ] ||
		error "uidgid '$uidgid' != '$RUNAS_ID:$RUNAS_GID'"
	local nid=$(echo $entry |
		sed 's+.*\ nid:\(\S\S*@\S\S*\)\ .*+\1+')
	[ -n "$nid" ] || error "nid is empty"
	echo "Got NID $nid"
	[ -n "$nid" ] && [[ "${CLIENT_NIDS[*]}" =~ $nid ]] ||
		error "nid '$nid' does not match any NID ${CLIENT_NIDS[*]}"
}
run_test 606 "llog_reader groks changelog fields"
get_hsm_xattr_sha()
{
	getfattr -e text -n trusted.hsm "$1" 2>/dev/null |
		sha1sum | awk '{ print $1 }'
}
test_hsm_migrate_init()
{
	local d=$1
	local f=$2
	local fid
	mkdir_on_mdt0 "$d"
	fid=$(create_small_file "$f")
	echo "$fid"
}
test_607a()
{
	local d="$DIR/$tdir"
	local f="$d/$tfile"
	local fid
	(( MDS1_VERSION >= $(version_code 2.15.60) )) ||
		skip "need MDS version at least 2.15.60"
	(( OSTCOUNT >= 2 )) || skip_env "needs >= 2 OSTs"
	fid=$(test_hsm_migrate_init "$d" "$f" | tail -1)
	copytool setup
	$LFS hsm_archive "$f" || error "could not archive file"
	wait_request_state $fid ARCHIVE SUCCEED
	$LFS migrate -n -i 1 "$f" ||
		error "could not migrate file to OST 1"
	$LFS hsm_release "$f" ||
		error "could not release file after non blocking migrate"
	$LFS hsm_restore "$f" ||
		error "could not restore file after non blocking migrate"
	wait_request_state $fid RESTORE SUCCEED
}
run_test 607a "release a file that was migrated after being archived"
test_607b()
{
	local d="$DIR/$tdir"
	local f="$DIR/$tdir/$tfile"
	local saved_params
	local old_hsm
	local new_hsm
	local fid
	(( MDS1_VERSION >= $(version_code 2.15.60) )) ||
		skip "need MDS version at least 2.15.60"
	(( OSTCOUNT >= 2 )) || skip_env "needs >= 2 OSTs"
	fid=$(test_hsm_migrate_init "$d" "$f" | tail -1)
	copytool setup
	$LFS hsm_archive "$f" || error "could not archive file"
	wait_request_state $fid ARCHIVE SUCCEED
	saved_params=$($LCTL get_param llite.*.xattr_cache | tr '\n' ' ')
	$LCTL set_param llite.*.xattr_cache=0
	stack_trap "$LCTL set_param $saved_params" EXIT
	echo 10 >> "$f"
	old_hsm=$(get_hsm_xattr_sha "$f")
	$LFS migrate -n -i 1 "$f" ||
		error "could not migrate file to OST 1"
	$LFS hsm_state "$f" | grep dirty || error "dirty flag not found"
	new_hsm=$(get_hsm_xattr_sha "$f")
	[ "$old_hsm" != "$new_hsm" ] &&
		 error "migrate should not modify data version of dirty files"
	return 0
}
run_test 607b "Migrate should not change the HSM attribute of dirty files"
test_607c()
{
	local d="$DIR/$tdir"
	local f="$DIR/$tdir/$tfile"
	local fid1 fid2 fid3
	local nbr_dirty
	(( MDS1_VERSION >= $(version_code 2.15.60) )) ||
		skip "need MDS version at least 2.15.60"
	mkdir_on_mdt0 $d
	fid1=$(create_small_file "$f-1")
	fid2=$(create_small_file "$f-2")
	fid3=$(create_small_file "$f-3")
	copytool setup
	$LFS hsm_archive "$f-1" || error "could not archive file"
	wait_request_state $fid1 ARCHIVE SUCCEED
	$LFS hsm_archive "$f-3" || error "could not archive file"
	wait_request_state $fid3 ARCHIVE SUCCEED
	$LFS swap_layouts "$f-1" "$f-3" |& grep "Operation not permitted" ||
		error "swap_layouts should fail with EPERM on 2 archived file"
	$LFS swap_layouts "$f-1" "$f-2" ||
		error "swap_layout failed on $f-1 and $f-2"
	$LFS swap_layouts "$f-2" "$f-3" ||
		error "swap_layout failed on $f-2 and $f-3"
	nbr_dirty=$($LFS hsm_state "$f-1" "$f-3" | grep -c 'dirty')
	((nbr_dirty == 2)) || error "dirty flag should be set on $f-1 and $f-3"
}
run_test 607c "'lfs swap_layouts' should set dirty flag on HSM file"
complete_test $SECONDS
check_and_cleanup_lustre
exit_status
