#!/bin/bash
set -e
ONLY=${ONLY:-"$*"}
LUSTRE=${LUSTRE:-$(dirname $0)/..}
. $LUSTRE/tests/test-framework.sh
init_test_env $@
init_logging
ALWAYS_EXCEPT="$SANITY_GSS_EXCEPT"
[ "$SLOW" = "no" ] && EXCEPT_SLOW="100 101"
build_test_filter
require_dsh_mds || exit 0
[ $UID -eq 0 -a $RUNAS_ID -eq 0 ] &&
    error "RUNAS_ID set to 0, but UID is also 0!"
unset SEC
DBENCH_PID=0
GSS=true
GSS_KRB5=true
RUNAS="runas_su $(id -n -u $RUNAS_ID)"
check_krb_env() {
	which klist || skip "Kerberos env not setup"
	which kinit || skip "Kerberos env not setup"
}
prepare_krb5_creds() {
	echo prepare krb5 cred
	echo RUNAS=$RUNAS
	$RUNAS krb5_login.sh || exit 1
}
check_krb_env
prepare_krb5_creds
MOUNT_2=${MOUNT_2:-"yes"}
check_and_setup_lustre
rm -rf $DIR/[df][0-9]*
check_runas_id $RUNAS_ID $RUNAS_ID $RUNAS
start_dbench()
{
	local NPROC=$(grep -c ^processor /proc/cpuinfo)
	[ $NPROC -gt 2 ] && NPROC=2
	bash rundbench -D $DIR/$tdir $NPROC 1>/dev/null &
	DBENCH_PID=$!
	sleep 2
	num=$(ps --no-headers -p $DBENCH_PID 2>/dev/null | wc -l)
	if [ $num -ne 1 ]; then
		error "failed to start dbench $NPROC"
	else
		echo "started dbench with $NPROC processes at background"
	fi
	return 0
}
check_dbench()
{
	num=$(ps --no-headers -p $DBENCH_PID 2>/dev/null | wc -l)
	if [ $num -eq 0 ]; then
		echo "dbench $DBENCH_PID already finished"
		wait $DBENCH_PID || error "dbench $PID exit with error"
		start_dbench
	elif [ $num -ne 1 ]; then
		killall -9 dbench
		error "found $num instance of pid $DBENCH_PID ???"
	fi
	return 0
}
stop_dbench()
{
	for ((;;)); do
		killall dbench 2>/dev/null
		local num=$(ps --no-headers -p $DBENCH_PID | wc -l)
		if [ $num -eq 0 ]; then
			echo "dbench finished"
			break
		fi
		echo "dbench $DBENCH_PID is still running, waiting 2s..."
		sleep 2
	done
	wait $DBENCH_PID || true
	sync || true
}
error_dbench()
{
	local err_str=$1
	killall -9 dbench
	sleep 1
	error $err_str
}
restore_krb5_cred() {
	local keys=$(keyctl show | awk '$6 ~ "^lgssc:" {print $1}')
	for key in $keys; do
		keyctl unlink $key
	done
	echo RUNAS=$RUNAS
	$RUNAS krb5_login.sh || exit 1
}
check_multiple_gss_daemons() {
	local facet=$1
	local gssd=$2
	local gssd_name=$(basename $gssd)
	for ((i = 0; i < 10; i++)); do
		do_facet $facet "$gssd -vvv"
	done
	sleep 5
	local num=$(do_facet $facet ps -o cmd -C $gssd_name |
		grep -c $gssd_name)
	echo "$num instance(s) of $gssd_name are running"
	if [ $num -ne 1 ]; then
		error "$gssd_name not unique"
	fi
}
calc_connection_cnt
umask 077
test_0() {
	local my_facet=mds
	echo "bring up gss daemons..."
	start_gss_daemons
	echo "check with someone already running..."
	check_multiple_gss_daemons $my_facet $LSVCGSSD
	echo "check with someone run & finished..."
	do_facet $my_facet killall -q -2 lgssd $LSVCGSSD || true
	sleep 5
	check_multiple_gss_daemons $my_facet $LSVCGSSD
	echo "check refresh..."
	do_facet $my_facet killall -q -2 lgssd $LSVCGSSD || true
	sleep 5
	do_facet $my_facet ipcrm -S 0x3b92d473
	check_multiple_gss_daemons $my_facet $LSVCGSSD
}
run_test 0 "start multiple gss daemons"
set_flavor_all krb5p
test_1a() {
	local file=$DIR/$tdir/$tfile
	mkdir $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	chmod 0777 $DIR/$tdir || error "chmod $DIR/$tdir failed"
	$RUNAS ls -ld $DIR/$tdir
	$RUNAS $LFS flushctx -k -r $MOUNT || error "can't flush context"
	$RUNAS touch $file && error "unexpected success"
	restore_krb5_cred
	$RUNAS touch $file || error "should not fail"
	[ -f $file ] || error "$file not found"
}
run_test 1a "access with or without krb5 credential"
test_1b() {
	local file=$DIR/$tdir/$tfile
	local lgssconf=/etc/request-key.d/lgssc.conf
	local clients=$CLIENTS
	local realm
	[ -z $clients ] && clients=$HOSTNAME
	zconf_umount_clients $clients $MOUNT || error "umount clients failed"
	echo "stop gss daemons..."
	stop_gss_daemons
	realm=$(grep default_realm /etc/krb5.conf | awk '{print $3}')
	cp $lgssconf $TMP/lgssc.conf
	stack_trap "yes | cp $TMP/lgssc.conf $lgssconf" EXIT
	sed -i s+lgss_keyring+\&\ \-R\ $realm+ $lgssconf
	echo "bring up gss daemons..."
	start_gss_daemons '' '' "-R $realm"
	stack_trap "stop_gss_daemons ; start_gss_daemons" EXIT
	zconf_mount_clients $clients $MOUNT || error "mount clients failed"
	mkdir $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	chmod 0777 $DIR/$tdir || error "chmod $DIR/$tdir failed"
	$RUNAS touch $file || error "touch $file failed"
	[ -f $file ] || error "$file not found"
}
run_test 1b "Use specified realm"
test_2() {
	local file1=$DIR/$tdir/$tfile-1
	local file2=$DIR/$tdir/$tfile-2
	mkdir $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	chmod 0777 $DIR/$tdir || error "chmod $DIR/$tdir failed"
	$RUNAS touch $file1 || error "can't touch $file1"
	[ -f $file1 ] || error "$file1 not found"
	$RUNAS $LFS flushctx -k -r $MOUNT || error "can't flush context"
	$RUNAS touch $file2 && error "unexpected success"
	restore_krb5_cred
	$RUNAS touch $file2 || error "should not fail"
	[ -f $file2 ] || error "$file2 not found"
}
run_test 2 "lfs flushctx"
test_3() {
	local file=$DIR/$tdir/$tfile
	mkdir $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	chmod 0777 $DIR/$tdir || error "chmod $DIR/$tdir failed"
	echo "aaaaaaaaaaaaaaaaa" > $file
	chmod 0666 $file
	$CHECKSTAT -p 0666 $file || error "$UID checkstat error"
	$RUNAS $CHECKSTAT -p 0666 $file || error "$RUNAS_ID checkstat error"
	$RUNAS cat $file > /dev/null || error "$RUNAS_ID cat error"
	$RUNAS $MULTIOP $file o_r &
	OPPID=$!
	sleep 1
	$RUNAS $LFS flushctx -k -r $MOUNT || error "can't flush context"
	echo "destroyed credentials/contexs for $RUNAS_ID"
	$RUNAS $CHECKSTAT -p 0666 $file && error "checkstat succeed"
	kill -s 10 $(pgrep -u $USER0 $MULTIOP)
	wait $OPPID || error "read file data failed"
	echo "read file data OK"
	restore_krb5_cred
	echo "restored credentials for $RUNAS_ID"
	$RUNAS $CHECKSTAT -p 0666 $file || error "$RUNAS_ID checkstat (2) error"
	echo "$RUNAS_ID checkstat OK"
	$CHECKSTAT -p 0666 $file || error "$UID checkstat (2) error"
	echo "$UID checkstat OK"
	$RUNAS cat $file > /dev/null || error "$RUNAS_ID cat (2) error"
	echo "$RUNAS_ID read file data OK"
}
run_test 3 "local cache under DLM lock"
test_5() {
	local file1=$DIR/$tdir/$tfile-1
	local file2=$DIR/$tdir/$tfile-2
	local file3=$DIR/$tdir/$tfile-3
	local wait_time=$((TIMEOUT + TIMEOUT / 2))
	local mdts=$(mdts_nodes)
	mkdir $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	chmod 0777 $DIR/$tdir || error "chmod $DIR/$tdir failed"
	$RUNAS touch $file1 || error "can't touch $file1"
	[ -f $file1 ] || error "$file1 not found"
	$RUNAS $LFS flushctx $MOUNT || error "can't flush context (1)"
	send_sigint $mdts $LSVCGSSD
	sleep 5
	check_gss_daemon_nodes $mdts $LSVCGSSD &&
		error "$LSVCGSSD still running (1)"
	$RUNAS touch $file2
	if [ $? -ne 0 ]; then
		echo "$RUNAS touch $file2 failed"
		(( MDS1_VERSION < $(version_code 2.15.61) )) ||
			error "$LSVCGSSD should restart automatically"
	else
		echo "$RUNAS touch $file2 succeeded"
	fi
	if (( MDS1_VERSION >= $(version_code 2.15.61) )); then
		$RUNAS $LFS flushctx $MOUNT || error "can't flush context (2)"
	fi
	send_sigint $mdts $LSVCGSSD
	sleep 5
	check_gss_daemon_nodes $mdts $LSVCGSSD &&
		error "$LSVCGSSD still running (2)"
	echo "restart $LSVCGSSD and recovering"
	start_gss_daemons $mdts $LSVCGSSD "-vvv"
	sleep 5
	check_gss_daemon_nodes $mdts $LSVCGSSD
	$RUNAS touch $file3 || error "should not fail now"
	[ -f $file3 ] || error "$file3 not found"
}
run_test 5 "lsvcgssd dead, operations pass"
test_6() {
	local nfile=10
	mkdir $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	for ((i=0; i<$nfile; i++)); do
		dd if=/dev/zero of=$DIR/$tdir/$tfile-$i bs=8k count=1 ||
		    error "dd $tfile-$i failed"
	done
	ls -l $DIR/$tdir/* > /dev/null || error "ls failed"
	rm -rf $DIR2/$tdir/* || error "rm failed"
	rmdir $DIR2/$tdir || error "rmdir failed"
}
run_test 6 "test basic DLM callback works"
test_7() {
	local num_osts
	[[ $OSTCOUNT -ge 2 ]] || skip_env "needs >= 2 OSTs"
	mkdir $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	$LFS setstripe -c $OSTCOUNT $DIR/$tdir || error "setstripe -c $OSTCOUNT"
	echo "creating..."
	for ((i = 0; i < 20; i++)); do
		dd if=/dev/zero of=$DIR/$tdir/f$i bs=4k count=16 2>/dev/null
	done
	echo "reading..."
	for ((i = 0; i < 20; i++)); do
		dd if=$DIR/$tdir/f$i of=/dev/null bs=4k count=16 2>/dev/null
	done
}
run_test 7 "exercise enlarge_reqbuf()"
test_8()
{
	local atoldbase=$(do_facet $SINGLEMDS "$LCTL get_param -n at_history")
	local req_delay
	do_facet $SINGLEMDS "$LCTL set_param at_history=8" || true
	stack_trap \
		"do_facet $SINGLEMDS $LCTL set_param at_history=$atoldbase" EXIT
	mkdir_on_mdt0 $DIR/$tdir
	chmod a+w $DIR/$tdir
	$RUNAS ls $DIR/$tdir
	$RUNAS keyctl show @u
	echo Flushing gss ctxs
	$RUNAS $LFS flushctx $MOUNT || error "can't flush context on $MOUNT"
	$RUNAS keyctl show @u
	$LCTL dk > /dev/null
	debugsave
	stack_trap debugrestore EXIT
	$LCTL set_param debug=+other
	while [ true ]; do
		req_delay=$($LCTL get_param -n \
			mdc.${FSNAME}-MDT0000-mdc-*.timeouts |
			awk '/portal 12/ {print $5}' | tail -1)
		[ $req_delay -le 5 ] && break
		echo "current AT estimation is $req_delay, wait a little bit"
		sleep 8
	done
	req_delay=$((${req_delay} + ${req_delay} / 4 + 5))
	do_facet $SINGLEMDS $LCTL set_param fail_val=$req_delay
	do_facet $SINGLEMDS $LCTL set_param fail_loc=0x80001204
	$RUNAS touch $DIR/$tdir/$tfile &
	TOUCHPID=$!
	echo "waiting for touch (pid $TOUCHPID) to finish..."
	wait $TOUCHPID || error "touch should have succeeded"
	$RUNAS keyctl show @u
	$LCTL dk | grep -i "Early reply
}
run_test 8 "Early reply sent for slow gss context negotiation"
test_9() {
	local test9user=$(getent passwd $RUNAS_ID | cut -d: -f1)
	$LFS mkdir -i 0 -c 1 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	chmod 0777 $DIR/$tdir || error "chmod $DIR/$tdir failed"
	$RUNAS ls -ld $DIR/$tdir
	groupadd -g 5000 grptest9
	stack_trap "groupdel grptest9" EXIT
	usermod -g grptest9 $test9user
	stack_trap "usermod -g $test9user $test9user" EXIT
	id $RUNAS_ID
	$RUNAS touch $DIR/$tdir/fileA &&
		error "server should not trust client's primary gid"
	do_facet mds1 "lctl set_param mdt.*.identity_flush=-1"
	do_facet mds1 groupadd -g 5000 grptest9
	stack_trap "do_facet mds1 groupdel grptest9 || true" EXIT
	do_facet mds1 usermod -a -G grptest9 $test9user
	stack_trap "do_facet mds1 gpasswd -d $test9user grptest9 || true" EXIT
	id $RUNAS_ID
	do_facet mds1 "id $RUNAS_ID"
	$RUNAS touch $DIR/$tdir/fileA ||
		error "server should know client's supp gid"
	ls -l $DIR/$tdir
	do_facet mds1 "lctl set_param mdt.*.identity_flush=-1"
	do_facet mds1 gpasswd -d $test9user grptest9
	do_facet mds1 groupdel grptest9
	usermod -g $test9user $test9user
	usermod -a -G grptest9 $test9user
	stack_trap "gpasswd -d $test9user grptest9" EXIT
	id $RUNAS_ID
	$RUNAS touch $DIR/$tdir/fileB
	ls -l $DIR/$tdir
	$RUNAS chgrp grptest9 $DIR/$tdir/fileB &&
		error "server should not trust client's supp gid"
	ls -l $DIR/$tdir
	do_facet mds1 "lctl set_param mdt.*.identity_flush=-1"
}
run_test 9 "Do not trust primary and supp gids from client"
test_10() {
	local count
	$LFS mkdir -i 0 -c $MDSCOUNT $DIR/$tdir ||
		error "mkdir $DIR/$tdir failed"
	chmod 0777 $DIR/$tdir || error "chmod $DIR/$tdir failed"
	$RUNAS ls -ld $DIR/$tdir || error "ls -ld $DIR/$tdir failed"
	$RUNAS grep lgssc /proc/keys
	$RUNAS $LFS flushctx -k -r $MOUNT || error "can't flush context (1)"
	$RUNAS grep lgssc /proc/keys
	stack_trap restore_krb5_cred EXIT
	restore_krb5_cred
	su - $(id -n -u $RUNAS_ID) -c "keyctl revoke @s && ls -ld $DIR/$tdir" ||
		error "revoke + ls failed"
	$RUNAS grep lgssc /proc/keys
	for ref in $($RUNAS grep lgssc /proc/keys | awk '$4~"perm"{print $3}');\
	  do
		[[ $ref == 2 ]] || error "bad refcnt $ref on key"
	done
	$RUNAS $LFS flushctx $MOUNT || error "can't flush context (2)"
	$RUNAS grep lgssc /proc/keys
	count=$($RUNAS grep lgssc /proc/keys | grep -v "Running as" | wc -l)
	[[ $count == 0 ]] || error "remaining $count keys for user"
}
run_test 10 "Support revoked session keyring"
exit_11() {
	zconf_umount $HOSTNAME $MOUNT
	zconf_mount $HOSTNAME $MOUNT
	if [ "$MOUNT_2" ]; then
		zconf_mount $HOSTNAME $MOUNT2
	fi
	restore_krb5_cred
}
test_11() {
	local count
	$LFS mkdir -i 0 -c $MDSCOUNT $DIR/$tdir ||
		error "mkdir $DIR/$tdir failed"
	chmod 0777 $DIR/$tdir || error "chmod $DIR/$tdir failed"
	$RUNAS ls -ld $DIR/$tdir || error "ls -ld $DIR/$tdir failed"
	$RUNAS grep lgssc /proc/keys
	$RUNAS klist
	$RUNAS $LFS flushctx -k -r $MOUNT || error "can't flush context (1)"
	$RUNAS grep lgssc /proc/keys
	$RUNAS klist
	stack_trap exit_11 EXIT
	zconf_umount $HOSTNAME $MOUNT || error "umount $MOUNT failed"
	if [ "$MOUNT_2" ]; then
		zconf_umount $HOSTNAME $MOUNT2 ||
			error "umount $MOUNT2 failed"
	fi
	kdestroy
	klist
	cp /etc/krb5.conf /etc/krb5.conf.bkp
	stack_trap "/bin/mv /etc/krb5.conf.bkp /etc/krb5.conf" EXIT
	sed -i '1i default_ccache_name = KCM:' /etc/krb5.conf
	sed -i '1i [libdefaults]' /etc/krb5.conf
	zconf_mount $HOSTNAME $MOUNT || error "remount $MOUNT failed"
	klist
	$RUNAS touch $DIR/$tdir/$tfile && error "write $tfile should fail"
	restore_krb5_cred
	$RUNAS klist
	$RUNAS touch $DIR/$tdir/$tfile || error "write $tfile failed"
	$RUNAS klist
	$RUNAS klist | grep -q lustre_mds || error "mds ticket not present"
	$RUNAS $LFS flushctx -k -r $MOUNT || error "can't flush context (2)"
	kdestroy
}
run_test 11 "KCM ccache"
test_90() {
	if [ "$SLOW" = "no" ]; then
		total=10
	else
		total=60
	fi
	mkdir $DIR/$tdir
	restore_to_default_flavor
	set_flavor_all krb5p
	start_dbench
	for ((n = 1; n <= $total; n++)); do
		sleep 2
		check_dbench
		echo "flush ctx ($n/$total) ..."
		$LFS flushctx -k -r $MOUNT ||
			error "can't flush context on $MOUNT"
	done
	check_dbench
	sleep 10
	stop_dbench
}
run_test 90 "recoverable from losing contexts under load"
test_99() {
	local nrule_old
	local nrule_new=0
	local max=32
	nrule_old=$(do_facet mgs lctl get_param -n mgs.MGS.live.$FSNAME \
	    2>/dev/null | grep -c "$FSNAME.srpc.flavor.")
	echo "original general rules: $nrule_old"
	for ((i = $nrule_old; i < $max; i++)); do
		set_rule $FSNAME ${NETTYPE}$i cli2mdt krb5n ||
			error "set rule $i (1)"
		set_rule $FSNAME ${NETTYPE}$i cli2ost krb5n ||
			error "set rule $i (2)"
		set_rule $FSNAME ${NETTYPE}$i mdt2ost null ||
			error "set rule $i (3)"
		set_rule $FSNAME ${NETTYPE}$i mdt2mdt null ||
			error "set rule $i (4)"
	done
	for ((i = $nrule_old; i < $max; i++)); do
		set_rule $FSNAME ${NETTYPE}$i cli2mdt ||
			error "remove rule $i (1)"
		set_rule $FSNAME ${NETTYPE}$i cli2ost ||
			error "remove rule $i (2)"
		set_rule $FSNAME ${NETTYPE}$i mdt2ost ||
			error "remove rule $i (3)"
		set_rule $FSNAME ${NETTYPE}$i mdt2mdt ||
			error "remove rule $i (4)"
	done
	nrule_new=$(do_facet mgs lctl get_param -n mgs.MGS.live.$FSNAME \
	    2>/dev/null | grep -c "$FSNAME.srpc.flavor.")
	if [ $nrule_new != $nrule_old ]; then
		error "general rule: $nrule_new != $nrule_old"
	fi
	nrule_old=$(do_facet mgs lctl get_param -n mgs.MGS.live.$FSNAME \
	    2>/dev/null | grep -c "$FSNAME-MDT0000.srpc.flavor.")
	echo "original target rules: $nrule_old"
	for ((i = $nrule_old; i < $max; i++)); do
		set_rule $FSNAME-MDT0000 ${NETTYPE}$i cli2mdt krb5i ||
			error "set new rule $i (1)"
		set_rule $FSNAME-MDT0000 ${NETTYPE}$i mdt2ost null ||
			error "set new rule $i (2)"
		set_rule $FSNAME-MDT0000 ${NETTYPE}$i mdt2mdt null ||
			error "set new rule $i (3)"
	done
	for ((i = $nrule_old; i < $max; i++)); do
		set_rule $FSNAME-MDT0000 ${NETTYPE}$i cli2mdt ||
			error "remove new rule $i (1)"
		set_rule $FSNAME-MDT0000 ${NETTYPE}$i mdt2ost ||
			error "remove new rule $i (2)"
		set_rule $FSNAME-MDT0000 ${NETTYPE}$i mdt2mdt ||
			error "remove new rule $i (3)"
	done
	nrule_new=$(do_facet mgs lctl get_param -n mgs.MGS.live.$FSNAME \
	    2>/dev/null \ | grep -c "$FSNAME-MDT0000.srpc.flavor.")
	if [ $nrule_new != $nrule_old ]; then
		error "general rule: $nrule_new != $nrule_old"
	fi
}
run_test 99 "set large number of sptlrpc rules"
test_100() {
	restore_to_default_flavor
	mkdir $DIR/$tdir
	start_dbench
	set_flavor_all krb5n
	check_dbench
	set_flavor_all krb5a
	check_dbench
	set_flavor_all krb5i
	check_dbench
	set_flavor_all krb5p
	check_dbench
	set_rule $FSNAME-MDT0000 any cli2mdt krb5a
	set_rule $FSNAME-OST0000 any cli2ost krb5i
	wait_flavor cli2mdt krb5p || error_dbench "1"
	check_dbench
	wait_flavor cli2ost krb5p || error_dbench "2"
	set_rule $FSNAME-MDT0000 any cli2mdt
	set_rule $FSNAME-OST0000 any cli2ost
	check_dbench
	set_rule $FSNAME any mdt2mdt
	set_rule $FSNAME any cli2mdt
	set_rule $FSNAME any mdt2ost
	set_rule $FSNAME any cli2ost
	restore_to_default_flavor
	check_dbench
	stop_dbench
}
run_test 100 "change security flavor on the fly under load"
switch_sec_test()
{
	local flavor0=$1
	local flavor1=$2
	local filename=$DIR/$tfile
	local multiop_pid
	local num
	log ">>>>>>>>>>>>>>> Testing $flavor0 -> $flavor1 <<<<<<<<<<<<<<<<<<<"
	set_rule $FSNAME any cli2mdt $flavor0
	wait_flavor cli2mdt $flavor0
	rm -f $filename || error "remove old $filename failed"
	do_facet $SINGLEMDS lctl set_param fail_val=36
	do_facet $SINGLEMDS lctl set_param fail_loc=0x513
	log "starting multiop"
	$MULTIOP $filename m &
	multiop_pid=$!
	echo "multiop pid=$multiop_pid"
	sleep 1
	set_rule $FSNAME any cli2mdt $flavor1
	wait_flavor cli2mdt $flavor1
	num=$(ps --no-headers -p $multiop_pid 2>/dev/null | wc -l)
	[ $num -eq 1 ] || error "multiop($multiop_pid) already ended ($num)"
	echo "process $multiop_pid is still hanging there... OK"
	do_facet $SINGLEMDS lctl set_param fail_loc=0
	log "waiting for multiop ($multiop_pid) to finish"
	wait $multiop_pid || error "multiop returned error"
}
test_101()
{
	restore_to_default_flavor
	switch_sec_test null  krb5n
	switch_sec_test krb5n krb5a
	switch_sec_test krb5a krb5i
	switch_sec_test krb5i krb5p
	switch_sec_test krb5p null
}
run_test 101 "switch ctx/sec for resending request"
error_102()
{
	local err_str=$1
	killall -9 dbench
	sleep 1
	error $err_str
}
test_102() {
	restore_to_default_flavor
	mkdir $DIR/$tdir
	start_dbench
	echo "Testing null->krb5n->krb5a->krb5i->krb5p->null"
	set_flavor_all krb5n
	set_flavor_all krb5a
	set_flavor_all krb5i
	set_flavor_all krb5p
	set_flavor_all null
	check_dbench
	echo "waiting for 15s and check again"
	sleep 15
	check_dbench
	echo "Testing null->krb5i->null->krb5i->null..."
	for ((idx = 0; idx < 5; idx++)); do
		set_flavor_all krb5i
		set_flavor_all null
	done
	set_flavor_all krb5i
	check_dbench
	echo "waiting for 15s and check again"
	sleep 15
	check_dbench
	stop_dbench
}
run_test 102 "survive from fast flavor switch"
test_150() {
	local mount_opts
	local count
	local clients=$CLIENTS
	[ -z $clients ] && clients=$HOSTNAME
	restore_to_default_flavor
	count=$(flvr_cnt_mgc2mgs null)
	[ $count -eq 1 ] || error "$count mgc connections use null flavor"
	zconf_umount_clients $clients $MOUNT || error "umount failed (1)"
	mount_opts="${MOUNT_OPTS:+$MOUNT_OPTS,}mgssec=krb5p"
	zconf_mount_clients $clients $MOUNT $mount_opts &&
		error "mount with conflict flavor should have failed"
	mount_opts="${MOUNT_OPTS:+$MOUNT_OPTS,}mgssec=null"
	zconf_mount_clients $clients $MOUNT $mount_opts ||
		error "mount with same flavor should have succeeded"
	zconf_umount_clients $clients $MOUNT || error "umount failed (2)"
	zconf_mount_clients $clients $MOUNT ||
		error "mount with default flavor should have succeeded"
}
run_test 150 "secure mgs connection: client flavor setting"
exit_151() {
	set_rule _mgs any any
	stopall
	setupall
}
test_151() {
	local new_opts
	stack_trap exit_151 EXIT
	set_rule _mgs any any krb5p
	stopall
	combined_mgs_mds || start_gss_daemons $mgs_HOST $LSVCGSSD "-vvv"
	start mgs $(mgsdevname 1) $MDS_MOUNT_OPTS
	start ost1 "$(ostdevname 1)" $OST_MOUNT_OPTS
	wait_mgc_import_state ost1 FULL 0 &&
		error "mount with default flavor should have failed"
	stop ost1
	if [ -z "$OST_MOUNT_OPTS" ]; then
		new_opts="-o mgssec=null"
	else
		new_opts="$OST_MOUNT_OPTS,mgssec=null"
	fi
	start ost1 "$(ostdevname 1)" $new_opts
	wait_mgc_import_state ost1 FULL 0 &&
		error "mount with unauthorized flavor should have failed"
	stop ost1
	if [ -z "$OST_MOUNT_OPTS" ]; then
		new_opts="-o mgssec=krb5p"
	else
		new_opts="$OST_MOUNT_OPTS,mgssec=krb5p"
	fi
	start ost1 "$(ostdevname 1)" $new_opts
	wait_mgc_import_state ost1 FULL 0 ||
		error "mount with designated flavor should have succeeded"
	stop ost1 -f
}
run_test 151 "secure mgs connection: server flavor control"
exit_152() {
	zconf_umount $HOSTNAME $MOUNT
	set_rule _mgs any any
	zconf_mount $HOSTNAME $MOUNT
	if [ "$MOUNT_2" ]; then
		zconf_mount $HOSTNAME $MOUNT2
	fi
}
test_152() {
	local mount_opts
	local count
	(( MDS1_VERSION >= $(version_code 2.15.64) )) ||
		skip "Need MDS >= 2.15.64 for user context with MGS"
	stack_trap exit_152 EXIT
	if is_mounted $MOUNT2; then
		umount_client $MOUNT2 || error "umount $MOUNT2 failed"
	fi
	zconf_umount $HOSTNAME $MOUNT || error "umount $MOUNT failed"
	set_rule _mgs any any krb5p
	combined_mgs_mds || start_gss_daemons $mgs_HOST $LSVCGSSD "-vvv"
	mount_opts="${MOUNT_OPTS:+$MOUNT_OPTS,}mgssec=krb5p"
	zconf_mount $HOSTNAME $MOUNT $mount_opts ||
		error "unable to mount client"
	$RUNAS $LFS check mgts || error "check mgts as user failed"
	$RUNAS grep lgssc /proc/keys
	$RUNAS $LFS flushctx $MOUNT || error "flushctx as user failed"
	$RUNAS grep lgssc /proc/keys
	count=$($RUNAS grep lgssc /proc/keys | grep -v "Running as" | wc -l)
	[[ $count == 0 ]] || error "remaining $count keys for user"
}
run_test 152 "secure mgs connection: user access"
test_200() {
	local nid=$(lctl list_nids | grep ${NETTYPE} | head -n1)
	local nidstr="peer_nid: ${nid},"
	local count
	lfs df -h
	do_facet $SINGLEMDS $LCTL get_param -n \
		mdt.*-MDT0000.gss.srpc_serverctx | grep "$nidstr"
	count=$(do_facet $SINGLEMDS $LCTL get_param -n \
		mdt.*-MDT0000.gss.srpc_serverctx | grep "$nidstr" |
		grep -c 'delta: -')
	echo "found $count expired reverse contexts (1)"
	(( count < 4 )) || error "expired reverse contexts should be <= 3 (1)"
	umount_client $MOUNT || error "umount $MOUNT failed"
	kdestroy
	stack_trap "mount_client $MOUNT ${MOUNT_OPTS} || true" EXIT
	if is_mounted $MOUNT2; then
		umount_client $MOUNT2 || error "umount $MOUNT2 failed"
		stack_trap "mount_client $MOUNT2 ${MOUNT_OPTS}" EXIT
	fi
	stack_trap "/usr/bin/cp -f /etc/krb5.conf.bkp /etc/krb5.conf" EXIT
	sed -i.bkp s+[^
		/etc/krb5.conf
	mount_client $MOUNT ${MOUNT_OPTS} || error "remount failed"
	lfs df -h
	sleep 135
	lfs df -h
	do_facet $SINGLEMDS $LCTL get_param -n \
		mdt.*-MDT0000.gss.srpc_serverctx | grep "$nidstr"
	count=$(do_facet $SINGLEMDS $LCTL get_param -n \
		mdt.*-MDT0000.gss.srpc_serverctx | grep "$nidstr" |
		grep -c 'delta: -')
	echo "found $count expired reverse contexts (2)"
	(( count < 4 )) || error "expired reverse contexts should be <= 3 (2)"
}
run_test 200 "check expired reverse gss contexts"
cleanup_201() {
	umount_client $MOUNT
	kdestroy
	if is_mounted $MOUNT2; then
		umount_client $MOUNT2
	fi
	cp -f /etc/krb5.conf.bkp /etc/krb5.conf
	rm -f /etc/krb5.conf.bkp
	mount_client $MOUNT ${MOUNT_OPTS} || error "mount $MOUNT failed"
	if is_mounted $MOUNT2; then
		mount_client $MOUNT2 ${MOUNT_OPTS} ||
			error "mount $MOUNT2 failed"
	fi
}
test_201() {
	local nid=$(lctl list_nids | grep ${NETTYPE} | head -n1)
	local nidstr="peer_nid: ${nid},"
	local count
	lfs df -h
	$LFS mkdir -i 0 -c 1 $DIR/$tdir || error "mkdir $DIR/$tdir failed"
	stack_trap cleanup_201 EXIT
	umount_client $MOUNT || error "umount $MOUNT failed"
	kdestroy
	if is_mounted $MOUNT2; then
		umount_client $MOUNT2 || error "umount $MOUNT2 failed"
	fi
	sed -i.bkp s+[^
		/etc/krb5.conf
	mount_client $MOUNT ${MOUNT_OPTS} || error "remount failed"
	mount_client $MOUNT2 ${MOUNT_OPTS} || error "remount 2 failed"
	lfs df -h
	touch $DIR/${tfile}_1
	stack_trap "rm -f $DIR/${tfile}*" EXIT
	touch $DIR2/$tdir/file001
	echo Wait for gss contexts to expire... 120s
	sleep 120
	do_facet $SINGLEMDS $LCTL get_param -n \
		mdt.*-MDT0000.gss.srpc_serverctx | grep "$nidstr"
	count=$(do_facet $SINGLEMDS $LCTL get_param -n \
		mdt.*-MDT0000.gss.srpc_serverctx | grep "$nidstr" |
		grep -vc 'delta: -')
	echo "found $count valid reverse contexts"
	(( count == 0 )) || error "all contexts should have expired"
	touch $DIR/${tfile}_2
	$LFS df $MOUNT2
	client_evicted $HOSTNAME && error "client got evicted"
	exit 0
}
run_test 201 "allow expired ctx for ldlm callback"
complete_test $SECONDS
set_flavor_all null
cleanup_gss
check_and_cleanup_lustre
exit_status
