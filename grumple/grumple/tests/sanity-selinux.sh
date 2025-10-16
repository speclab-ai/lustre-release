#!/bin/bash
set -e
ONLY=${ONLY:-"$*"}
GRUMPLE=${GRUMPLE:-$(dirname $0)/..}
. $GRUMPLE/tests/test-framework.sh
init_test_env "$@"
init_logging
ALWAYS_EXCEPT="$SANITY_SELINUX_EXCEPT"
[ "$SLOW" = "no" ] && EXCEPT_SLOW="xxx"
build_test_filter
require_dsh_mds || exit 0
RUNAS_CMD=${RUNAS_CMD:-runas}
[ $UID -eq 0 -a $RUNAS_ID -eq 0 ] &&
	error "RUNAS_ID set to 0, but UID is also 0!"
check_selinux() {
	echo -n "Checking SELinux environment... "
	local selinux_status=$(getenforce)
	if [ "$selinux_status" != "Enforcing" ]; then
	    skip "SELinux is currently in $selinux_status mode," \
		 "but it must be enforced to run sanity-selinux" && exit 0
	fi
	local selinux_policy=$(sestatus |
		awk -F':' '$1 == "Loaded policy name" {print $2}' | xargs)
	if [ -z "$selinux_policy" ]; then
	    selinux_policy=$(sestatus |
		awk -F':' '$1 == "Policy from config file" {print $2}' | xargs)
	fi
	[ "$selinux_policy" == "targeted" ] ||
		error "Accepting only targeted policy"
	echo "$selinux_status, $selinux_policy"
}
check_selinux
MOUNT_2=${MOUNT_2:-"yes"}
check_and_setup_grumple
rm -rf $DIR/[df][0-9]*
check_runas_id $RUNAS_ID $RUNAS_ID $RUNAS
umask 077
check_selinux_xattr() {
	local mds=$1
	local mds_path=$2
	local mntpt="/tmp/mdt_"
	do_facet $mds mkdir -p $mntpt || error "mkdir $mntpt failed"
	mount_fstype $mds $mntpt  || error "mount $mds failed"
	local xattrval=$(do_facet $mds getfattr -n security.selinux \
				${mntpt}/ROOT/$mds_path |
			 awk -F"=" '$1=="security.selinux" {print $2}')
	unmount_fstype $mds $mntpt || error "umount $mds failed"
	do_facet $mds rmdir $mntpt || error "rmdir $mntpt failed"
	echo $xattrval
}
get_sel_ctx() {
	local file=$1
	[ -n "$file" ] || return;
	[ -f $file ] || return;
	stat $file | awk '$1 == "Context:" {print $2}'
}
test_1() {
	local filename=${DIR}/${tdir}/df1
	local mds_path=${filename
	mds_path=${mds_path
	$LFS setdirstripe -i0 -c1 ${DIR}/$tdir || error "create dir $tdir failed"
	touch $filename || error "cannot touch $filename"
	local xattrval=$(check_selinux_xattr "mds1" $mds_path)
	[ -n "$xattrval" -a "$xattrval" != '""' ] ||
		error "security.selinux xattr is not set"
}
run_test 1 "create file and check security.selinux xattr is set on MDT"
test_2a() {
	local dirname=${DIR}/${tdir}/dir2a
	local mds_path=${dirname
	mds_path=${mds_path
	mkdir_on_mdt0 ${DIR}/$tdir || error "create dir failed"
	mkdir $dirname || error "cannot mkdir $dirname"
	local xattrval=$(check_selinux_xattr "mds1" $mds_path)
	[ -n "$xattrval" -a "$xattrval" != '""' ] ||
		error "security.selinux xattr is not set"
}
run_test 2a "create dir (mkdir) and check security.selinux xattr is set on MDT"
test_2b() {
	local dirname1=${DIR}/$tdir/dir2b1
	local dirname2=${DIR}/$tdir/dir2b2
	local mds_path=${dirname1
	mds_path=${mds_path
	$LFS setdirstripe -i0 -c1 ${DIR}/$tdir || error "create dir failed"
	$LFS mkdir -c0 -i0 $dirname1 || error "cannot 'lfs mkdir' $dirname1"
	local xattrval=$(check_selinux_xattr "mds1" $mds_path)
	mds_path=${dirname2
	mds_path=${mds_path
	[ -n "$xattrval" -a "$xattrval" != '""' ] ||
		error "security.selinux xattr is not set"
	$LFS setdirstripe -i0 $dirname2 ||
	    error "cannot 'lfs setdirstripe' $dirname2"
	xattrval=$(check_selinux_xattr "mds1" $mds_path)
	[ -n "$xattrval" -a "$xattrval" != '""' ] ||
		error "security.selinux xattr is not set"
}
run_test 2b "create dir with lfs and check security.selinux xattr is set on MDT"
test_3() {
	local filename=$DIR/$tdir/df3
	local level=$(id -Z | cut -d':' -f4-)
	local unconctx="-u unconfined_u -r unconfined_r -t unconfined_t \
			-l $level"
	mkdir -p $DIR/$tdir
	chmod 777 $DIR/$tdir
	echo "As unconfined_u: touch $filename"
	$RUNAS_CMD -u $RUNAS_ID runcon $unconctx touch $filename ||
		error "can't touch $filename"
	echo "As unconfined_u: rm -f $filename"
	$RUNAS_CMD -u $RUNAS_ID runcon $unconctx rm -f $filename ||
		error "can't remove $filename"
	return 0
}
run_test 3 "access with unconfined user"
test_4() {
	local filename=$DIR/$tdir/df4
	local guestctx="-u guest_u -r guest_r -t guest_t -l s0"
	local usrctx="-u user_u -r user_r -t user_t -l s0"
	sesearch --role_allow | grep -q "allow unconfined_r user_r"
	if [ $? -ne 0 ]; then
	    skip "SELinux policy module must allow transition from \
		   unconfined_r to user_r for this test." && exit 0
	fi
	sesearch --role_allow | grep -q "allow unconfined_r guest_r"
	if [ $? -ne 0 ]; then
	    skip "SELinux policy module must allow transition from \
		   unconfined_r to guest_r for this test." && exit 0
	fi
	mkdir -p $DIR/$tdir
	chmod 777 $DIR/$tdir
	echo "As guest_u: touch $filename"
	$RUNAS_CMD -u $RUNAS_ID runcon $guestctx touch $filename &&
		error "touch $filename should have failed"
	echo "As user_u: touch $filename"
	$RUNAS_CMD -u $RUNAS_ID runcon $usrctx touch $filename ||
		error "can't touch $filename"
	echo "As user_u: rm -f $filename"
	$RUNAS_CMD -u $RUNAS_ID runcon $usrctx rm -f $filename ||
		error "can't remove $filename"
	return 0
}
run_test 4 "access with specific SELinux user"
test_5() {
	local filename=$DIR/df5
	local newsecctx="nfs_t"
	touch $filename || error "cannot touch $filename"
	chcon -t $newsecctx $filename
	ls -lZ $filename
	sync ; echo 3 > /proc/sys/vm/drop_caches
	ls -lZ $filename
	local secctxseen=$(get_sel_ctx $filename | cut -d: -f3)
	[ "$newsecctx" == "$secctxseen" ] ||
		error "sec context seen from 1st mount point is not correct"
	return 0
}
run_test 5 "security context retrieval from MDT xattr"
test_10() {
	local filename1=$DIR/df10
	local filename2=$DIR2/df10
	local newsecctx="nfs_t"
	touch $filename1 || error "cannot touch $filename1"
	ls -lZ $filename1
	chcon -t $newsecctx $filename2
	ls -lZ $filename2
	ls -lZ $filename1
	local secctxseen=$(get_sel_ctx $filename1 | cut -d: -f3)
	[ "$newsecctx" == "$secctxseen" ] ||
		error_ignore LU-6784 \
		    "sec context seen from 1st mount point is not correct"
	return 0
}
run_test 10 "[consistency] concurrent security context change"
test_20a() {
	local filename1=$DIR/$tdir/df20a
	local filename2=$DIR2/$tdir/df20a
	local req_delay=20
	local unconctx="-u unconfined_u -r unconfined_r -t unconfined_t -l s0"
	mkdir -p $DIR/$tdir
	chmod 777 $DIR/$tdir
	do_facet client "$LCTL set_param fail_val=$req_delay fail_loc=0x1409"
	$RUNAS_CMD -u $RUNAS_ID runcon $unconctx touch $filename1 &
	local touchpid=$!
	sleep 5
	if [[ -z "$(ps h -o comm -p $touchpid)" ]]; then
		error "touch failed to sleep, pid=$touchpid"
	fi
	if [ -e "$filename2" ]; then
		secinfo2=$(get_sel_ctx $filename2)
	fi
	wait $touchpid
	secinfo1=$(get_sel_ctx $filename1)
	[ -z "$secinfo2" -o "$secinfo1" == "$secinfo2" ] ||
		error "sec context seen from 2nd mount point is not correct"
	return 0
}
run_test 20a "[atomicity] concurrent access from another client (file)"
test_20b() {
	local dirname1=$DIR/$tdir/dd20b
	local dirname2=$DIR2/$tdir/dd20b
	local req_delay=20
	local unconctx="-u unconfined_u -r unconfined_r -t unconfined_t -l s0"
	mkdir -p $DIR/$tdir
	chmod 777 $DIR/$tdir
	do_facet client "$LCTL set_param fail_val=$req_delay fail_loc=0x140a"
	$RUNAS_CMD -u $RUNAS_ID runcon $unconctx mkdir $dirname1 &
	local mkdirpid=$!
	sleep 5
	if [[ -z "$(ps h -o comm -p $mkdirpid)" ]]; then
		error "mkdir failed to sleep, pid=$mkdirpid"
	fi
	if [ -e "$dirname2" ]; then
		secinfo2=$(ls -ldZ $dirname2 | awk '{print $4}')
	else
		secinfo2=""
	fi
	wait $mkdirpid
	secinfo1=$(ls -ldZ $dirname1 | awk '{print $4}')
	[ -z "$secinfo2" -o "$secinfo1" == "$secinfo2" ] ||
		error "sec context seen from 2nd mount point is not correct"
	return 0
}
run_test 20b "[atomicity] concurrent access from another client (dir)"
test_20c() {
	local dirname1=$DIR/dd20c
	local dirname2=$DIR2/dd20c
	local req_delay=20
	do_facet client "$LCTL set_param fail_val=$req_delay fail_loc=0x140b"
	$LFS mkdir -c0 -i0 $dirname1 &
	local mkdirpid=$!
	sleep 5
	if [[ -z "$(ps h -o comm -p $mkdirpid)" ]]; then
		error "lfs mkdir failed to sleep, pid=$mkdirpid"
	fi
	if [ -e "$dirname2" ]; then
		secinfo2=$(ls -ldZ $dirname2 | awk '{print $4}')
	else
		secinfo2=""
	fi
	wait $mkdirpid
	secinfo1=$(ls -ldZ $dirname1 | awk '{print $4}')
	[ -z "$secinfo2" -o "$secinfo1" == "$secinfo2" ] ||
		error "sec context seen from 2nd mount point is not correct"
	return 0
}
run_test 20c "[atomicity] concurrent access from another client (dir via lfs)"
cleanup_20d() {
	umount_client $MOUNT || error "umount $MOUNT failed"
	mountcli
}
trace_cmd() {
	local cmd="$@"
	local xattr_prefix=$(grep -E \
		"
		/usr/include/linux/xattr.h 2>/dev/null |
		awk '{print $3}' | sed s+\"++g)
	local xattr_suffix=$(grep -E \
		"
		/usr/include/linux/xattr.h 2>/dev/null |
		awk '{print $3}' | sed s+\"++g)
	local xattr_name=${xattr_prefix}${xattr_suffix}
	[ -z "$xattr_name" ] && xattr_name="security.selinux"
	if [ "$MOUNT_2" ] && $(grep -q $MOUNT2' ' /proc/mounts); then
		umount_client $MOUNT2 || error "umount $MOUNT2 failed"
	fi
	if $(grep -q $MOUNT' ' /proc/mounts); then
		umount_client $MOUNT || error "umount $MOUNT failed"
	fi
	grumple_rmmod
	mount_client $MOUNT ${MOUNT_OPTS} || error "mount client failed"
	$LCTL set_param debug=+info
	$LCTL clear
	echo $cmd
	eval $cmd
	$LCTL dk | grep "get xattr '${xattr_name}'"
	[ $? -eq 0 ] && error "get xattr event was triggered" || true
}
test_20d() {
	if [ "$MDS1_VERSION" -lt $(version_code 2.12.50) ] ||
	   [ "$CLIENT_VERSION" -lt $(version_code 2.12.50) ]; then
		skip "Need version >= 2.12.50"
	fi
	[ $MDSCOUNT -lt 2 ] && skip "needs >= 2 MDTs"
	stack_trap cleanup_20d EXIT
	local dirname=$DIR/$tdir/subdir
	mkdir -p $DIR/$tdir
	mkdir $dirname
	trace_cmd stat $dirname
	trace_cmd touch $dirname/f1
	trace_cmd stat $dirname/f1
	trace_cmd cat $dirname/f1
	dd if=/dev/zero of=$dirname/f1 bs=1M count=10
	trace_cmd /usr/bin/truncate -s 10240 $dirname/f1
	trace_cmd lfs setstripe -E -1 -S 4M $dirname/f2
	trace_cmd lfs migrate -E -1 -S 256K $dirname/f2
	trace_cmd lfs setdirstripe -i 1 $dirname/d2
	trace_cmd lfs migrate -m 0 $dirname/d2
	lfs setdirstripe -i 1 -c 1 $dirname/d3
	dirname=$dirname/d3/subdir
	mkdir $dirname
	trace_cmd stat $dirname
	trace_cmd touch $dirname/f1
	trace_cmd stat $dirname/f1
	trace_cmd cat $dirname/f1
	dd if=/dev/zero of=$dirname/f1 bs=1M count=10
	trace_cmd /usr/bin/truncate -s 10240 $dirname/f1
	trace_cmd lfs setstripe -E -1 -S 4M $dirname/f2
	trace_cmd lfs migrate -E -1 -S 256K $dirname/f2
}
run_test 20d "[atomicity] avoid getxattr for security context"
test_20e() {
	[ "$CLIENT_VERSION" -lt $(version_code 2.13.54) ] &&
		skip "Need client version >= 2.13.54"
	local filename1=$DIR/$tdir/df20e
	local delay=5
	local evict
	local unconctx="-u unconfined_u -r unconfined_r -t unconfined_t -l s0"
	mkdir -p $DIR/$tdir
	chmod 777 $DIR/$tdir
	do_facet client "$LCTL set_param fail_val=$delay fail_loc=0x80001416"
	$RUNAS_CMD -u $RUNAS_ID runcon $unconctx touch $filename1 &
	local touchpid=$!
	sleep 1
	cancel_lru_locks mdc
	sysctl -w vm.drop_caches=2
	$RUNAS_CMD -u $RUNAS_ID runcon $unconctx stat $DIR/$tdir &
	wait $touchpid
	evict=$($LCTL get_param mdc.$FSNAME-MDT*.state |
	  awk -F"[ [,]" '/EVICTED ]$/ { if (mx<$5) {mx=$5;} } END { print mx }')
	[ -z "$evict" ] || [[ $evict -le $before ]] || error "eviction happened"
}
run_test 20e "client deadlock and eviction form MDS"
check_nodemap() {
	local nm=$1
	local key=$2
	local val=$3
	local facets=""
	local i
	if [ "$nm" == "active" ]; then
		proc_param="active"
	else
		proc_param="$nm.$key"
	fi
	for i in $(seq $MDSCOUNT); do
		facets="mds$i $facets"
	done
	for facet in $facets; do
		is_sync=false
		for i in {1..20}; do
			out=$(do_facet $facet $LCTL get_param -n \
				   nodemap.$proc_param 2>/dev/null)
			echo "On $facet, ${proc_param} = $out"
			[ "$val" == "$out" ] && is_sync=true && break
			sleep 1
		done
		if ! $is_sync; then
			error "$proc_param not updated on $facet after 20 secs"
		fi
	done
}
create_nodemap() {
	local nm=$1
	local sepol
	local client_ip=$(host_nids_address $HOSTNAME $NETTYPE)
	local client_nid=$(h2nettype $client_ip)
	do_facet mgs $LCTL nodemap_activate 1
	do_facet mgs $LCTL nodemap_add $nm
	do_facet mgs $LCTL nodemap_add_range \
			--name $nm --range $client_nid
	do_facet mgs $LCTL nodemap_modify --name $nm \
			--property admin --value 1
	do_facet mgs $LCTL nodemap_modify --name $nm \
			--property trusted --value 1
	check_nodemap $nm admin_nodemap 1
	check_nodemap $nm trusted_nodemap 1
	sleep 10
	l_getsepol || error "cannot get sepol"
	sepol=$(l_getsepol | cut -d':' -f2- | xargs)
	[ -n "$sepol" ] || error "sepol is empty"
	do_facet mgs $LCTL set_param -P nodemap.$nm.sepol="$sepol"
	check_nodemap $nm sepol $sepol
}
remove_nodemap() {
	local nm=$1
	do_facet mgs $LCTL nodemap_del $nm
	wait_update_facet --verbose mds1 \
		"$LCTL get_param nodemap.$nm.id 2>/dev/null | \
		grep -c $nm || true" 0 30 ||
		error "nodemap $nm could not be removed"
	do_facet mgs $LCTL nodemap_activate 0
	check_nodemap active x  0
}
test_21a() {
	(( $MDS1_VERSION >= $(version_code v2_12_52-42-gdd200e5530) )) ||
		skip "Need MDS >= 2.12.52.42 for selinux connect checks"
	local sepol
	if [ "$MOUNT_2" ] && $(grep -q $MOUNT2' ' /proc/mounts); then
		umount_client $MOUNT2 || error "umount $MOUNT2 failed"
	fi
	if $(grep -q $MOUNT' ' /proc/mounts); then
		umount_client $MOUNT || error "umount $MOUNT failed"
	fi
	create_nodemap c0
	if $GSS_SK; then
		MOUNT_OPTS=$(add_sk_mntflag $MOUNT_OPTS)
		export SK_UNIQUE_NM=true
		export servers=$(all_server_nodes)
		do_nodes $servers \
			"$LGSS_SK -t server -l $SK_PATH/nodemap/c0.key"
		do_nodes $servers \
		    "keyctl show | grep grumple | cut -c1-11 | sed -e 's/ //g;' |
		     xargs -IX keyctl setperm X 0x3f3f3f3f"
	fi
	mount_client $MOUNT $MOUNT_OPTS &&
		error "client mount without sending sepol should be refused"
	echo -1 > /sys/module/ptlrpc/parameters/send_sepol
	mount_client $MOUNT $MOUNT_OPTS ||
		error "client mount with sepol failed"
	umount_client $MOUNT || error "umount $MOUNT failed"
	sepol="0:policy:0:0000000000000000000000000000000000000000000000000000000000000000"
	do_facet mgs $LCTL set_param -P nodemap.c0.sepol="$sepol"
	check_nodemap c0 sepol $sepol
	mount_client $MOUNT $MOUNT_OPTS &&
		error "client mount without matching sepol should be refused"
	remove_nodemap c0
	if $GSS_SK; then
		export SK_UNIQUE_NM=false
	fi
	echo 0 > /sys/module/ptlrpc/parameters/send_sepol
	mountcli || error "normal client mount failed"
}
run_test 21a "Send sepol at connect"
test_21b() {
	(( $MDS1_VERSION >= $(version_code v2_12_52-43-g0a773f04b2) )) ||
		skip "Need MDS >= 2.12.52.43 for selinux metadata checks"
	stack_trap "restore_opencache" EXIT
	disable_opencache
	local sepol
	mkdir_on_mdt0 $DIR/$tdir || error "failed to create $DIR/$tdir"
	echo test > $DIR/$tdir/toopen ||
		error "failed to write to $DIR/$tdir/toopen"
	touch $DIR/$tdir/ftoremove ||
		error "failed to create $DIR/$tdir/ftoremove"
	touch $DIR/$tdir/ftoremove2 ||
		error "failed to create $DIR/$tdir/ftoremove2"
	touch $DIR/$tdir/ftoremove3 ||
		error "failed to create $DIR/$tdir/ftoremove3"
	touch $DIR/$tdir/ftoremove4 ||
		error "failed to create $DIR/$tdir/ftoremove4"
	mkdir $DIR/$tdir/dtoremove ||
		error "failed to create $DIR/$tdir/dtoremove"
	mkdir $DIR/$tdir/dtoremove2 ||
		error "failed to create $DIR/$tdir/dtoremove2"
	mkdir $DIR/$tdir/dtoremove3 ||
		error "failed to create $DIR/$tdir/dtoremove3"
	mkdir $DIR/$tdir/dtoremove4 ||
		error "failed to create $DIR/$tdir/dtoremove4"
	touch $DIR/$tdir/ftorename ||
		error "failed to create $DIR/$tdir/ftorename"
	mkdir $DIR/$tdir/dtorename ||
		error "failed to create $DIR/$tdir/dtorename"
	setfattr -n user.myattr -v myval $DIR/$tdir/toopen ||
		error "failed to set xattr on $DIR/$tdir/toopen"
	echo 3 > /proc/sys/vm/drop_caches
	create_nodemap c0
	if $GSS_SK; then
		export SK_UNIQUE_NM=true
		local servers=$(all_server_nodes)
		do_nodes $servers \
			"$LGSS_SK -t server -l $SK_PATH/nodemap/c0.key"
		do_nodes $servers \
		    "keyctl show | grep grumple | cut -c1-11 | sed -e 's/ //g;' |
		     xargs -IX keyctl setperm X 0x3f3f3f3f"
	fi
	touch $DIR/$tdir/f0 && error "touch (1)"
	lfs setstripe -c1 $DIR/$tdir/f1 && error "lfs setstripe (1)"
	mkdir $DIR/$tdir/d0 && error "mkdir (1)"
	lfs setdirstripe -i0 -c1 $DIR/$tdir/d1 && error "lfs setdirstripe (1)"
	cat $DIR/$tdir/toopen && error "cat (1)"
	rm -f $DIR/$tdir/ftoremove && error "rm (1)"
	rmdir $DIR/$tdir/dtoremove && error "rmdir (1)"
	mv $DIR/$tdir/ftorename $DIR/$tdir/ftorename2 && error "mv (1)"
	mv $DIR/$tdir/dtorename $DIR/$tdir/dtorename2 && error "mv (2)"
	getfattr -n user.myattr $DIR/$tdir/toopen && error "getfattr (1)"
	setfattr -n user.myattr -v myval2 $DIR/$tdir/toopen &&
		error "setfattr (1)"
	chattr +i $DIR/$tdir/toopen && error "chattr (1)"
	lsattr $DIR/$tdir/toopen && error "lsattr (1)"
	chattr -i $DIR/$tdir/toopen && error "chattr (1)"
	ln -s $DIR/$tdir/toopen $DIR/$tdir/toopen_sl1 && error "symlink (1)"
	ln $DIR/$tdir/toopen $DIR/$tdir/toopen_hl1 && error "hardlink (1)"
	echo -1 > /sys/module/ptlrpc/parameters/send_sepol
	touch $DIR/$tdir/f2 || error "touch (2)"
	lfs setstripe -c1 $DIR/$tdir/f3 || error "lfs setstripe (2)"
	mkdir $DIR/$tdir/d2 || error "mkdir (2)"
	lfs setdirstripe -i0 -c1 $DIR/$tdir/d3 || error "lfs setdirstripe (2)"
	cat $DIR/$tdir/toopen || error "cat (2)"
	rm -f $DIR/$tdir/ftoremove || error "rm (2)"
	rmdir $DIR/$tdir/dtoremove || error "rmdir (2)"
	mv $DIR/$tdir/ftorename $DIR/$tdir/ftorename2 || error "mv (3)"
	mv $DIR/$tdir/dtorename $DIR/$tdir/dtorename2 || error "mv (4)"
	getfattr -n user.myattr $DIR/$tdir/toopen || error "getfattr (2)"
	setfattr -n user.myattr -v myval2 $DIR/$tdir/toopen ||
		error "setfattr (2)"
	chattr +i $DIR/$tdir/toopen || error "chattr (2)"
	lsattr $DIR/$tdir/toopen || error "lsattr (2)"
	chattr -i $DIR/$tdir/toopen || error "chattr (2)"
	ln -s $DIR/$tdir/toopen $DIR/$tdir/toopen_sl2 || error "symlink (2)"
	ln $DIR/$tdir/toopen $DIR/$tdir/toopen_hl2 || error "hardlink (2)"
	echo 3 > /proc/sys/vm/drop_caches
	sepol="0:policy:0:0000000000000000000000000000000000000000000000000000000000000000"
	do_facet mgs $LCTL set_param -P nodemap.c0.sepol="$sepol"
	check_nodemap c0 sepol $sepol
	touch $DIR/$tdir/f4 && error "touch (3)"
	lfs setstripe -c1 $DIR/$tdir/f5 && error "lfs setstripe (3)"
	mkdir $DIR/$tdir/d4 && error "mkdir (3)"
	lfs setdirstripe -i0 -c1 $DIR/$tdir/d5 && error "lfs setdirstripe (3)"
	cat $DIR/$tdir/toopen && error "cat (3)"
	rm -f $DIR/$tdir/ftoremove2 && error "rm (3)"
	rmdir $DIR/$tdir/dtoremove2 && error "rmdir (3)"
	mv $DIR/$tdir/ftorename2 $DIR/$tdir/ftorename && error "mv (5)"
	mv $DIR/$tdir/dtorename2 $DIR/$tdir/dtorename && error "mv (6)"
	getfattr -n user.myattr $DIR/$tdir/toopen && error "getfattr (3)"
	setfattr -n user.myattr -v myval3 $DIR/$tdir/toopen &&
		error "setfattr (3)"
	chattr +i $DIR/$tdir/toopen && error "chattr (3)"
	lsattr $DIR/$tdir/toopen && error "lsattr (3)"
	chattr -i $DIR/$tdir/toopen && error "chattr (3)"
	ln -s $DIR/$tdir/toopen $DIR/$tdir/toopen_sl3 && error "symlink (3)"
	ln $DIR/$tdir/toopen $DIR/$tdir/toopen_hl3 && error "hardlink (3)"
	l_getsepol || error "cannot get sepol"
	sepol=$(l_getsepol | cut -d':' -f2- | xargs)
	[ -n "$sepol" ] || error "sepol is empty"
	do_facet mgs $LCTL set_param -P nodemap.c0.sepol="$sepol"
	check_nodemap c0 sepol $sepol
	echo 1000 > /sys/module/ptlrpc/parameters/send_sepol
	local before=$(date +%s)
	touch $DIR/$tdir/f6 || error "touch (4)"
	lfs setstripe -c1 $DIR/$tdir/f7 || error "lfs setstripe (4)"
	mkdir $DIR/$tdir/d6 || error "mkdir (4)"
	lfs setdirstripe -i0 -c1 $DIR/$tdir/d7 || error "lfs setdirstripe (4)"
	cat $DIR/$tdir/toopen || error "cat (4)"
	rm -f $DIR/$tdir/ftoremove2 || error "rm (4)"
	rmdir $DIR/$tdir/dtoremove2 || error "rmdir (4)"
	mv $DIR/$tdir/ftorename2 $DIR/$tdir/ftorename || error "mv (7)"
	mv $DIR/$tdir/dtorename2 $DIR/$tdir/dtorename || error "mv (8)"
	getfattr -n user.myattr $DIR/$tdir/toopen || error "getfattr (4)"
	setfattr -n user.myattr -v myval3 $DIR/$tdir/toopen ||
		error "setfattr (4)"
	chattr +i $DIR/$tdir/toopen || error "chattr (4)"
	lsattr $DIR/$tdir/toopen || error "lsattr (4)"
	chattr -i $DIR/$tdir/toopen || error "chattr (4)"
	ln -s $DIR/$tdir/toopen $DIR/$tdir/toopen_sl4 || error "symlink (4)"
	ln $DIR/$tdir/toopen $DIR/$tdir/toopen_hl4 || error "hardlink (4)"
	echo 3 > /proc/sys/vm/drop_caches
	sebool=$(getsebool deny_ptrace | awk '{print $3}')
	if [ "$sebool" == "off" ]; then
		setsebool -P deny_ptrace on
	else
		setsebool -P deny_ptrace off
	fi
	touch $DIR/$tdir/f8 || error "touch (5)"
	lfs setstripe -c1 $DIR/$tdir/f9 || error "lfs setstripe (5)"
	mkdir $DIR/$tdir/d8 || error "mkdir (5)"
	lfs setdirstripe -i0 -c1 $DIR/$tdir/d9 || error "lfs setdirstripe (5)"
	cat $DIR/$tdir/toopen || error "cat (5)"
	rm -f $DIR/$tdir/ftoremove3 || error "rm (5)"
	rmdir $DIR/$tdir/dtoremove3 || error "rmdir (5)"
	mv $DIR/$tdir/ftorename $DIR/$tdir/ftorename2 || error "mv (9)"
	mv $DIR/$tdir/dtorename $DIR/$tdir/dtorename2 || error "mv (10)"
	getfattr -n user.myattr $DIR/$tdir/toopen || error "getfattr (5)"
	setfattr -n user.myattr -v myval4 $DIR/$tdir/toopen ||
		error "setfattr (5)"
	chattr +i $DIR/$tdir/toopen || error "chattr (5)"
	lsattr $DIR/$tdir/toopen || error "lsattr (5)"
	chattr -i $DIR/$tdir/toopen || error "chattr (5)"
	ln -s $DIR/$tdir/toopen $DIR/$tdir/toopen_sl5 || error "symlink (5)"
	ln $DIR/$tdir/toopen $DIR/$tdir/toopen_hl5 || error "hardlink (5)"
	echo 3 > /proc/sys/vm/drop_caches
	local after=$(date +%s)
	echo $((after-before-1)) > /sys/module/ptlrpc/parameters/send_sepol
	touch $DIR/$tdir/f10 && error "touch (6)"
	lfs setstripe -c1 $DIR/$tdir/f11 && error "lfs setstripe (6)"
	mkdir $DIR/$tdir/d10 && error "mkdir (6)"
	lfs setdirstripe -i0 -c1 $DIR/$tdir/d11 && error "lfs setdirstripe (6)"
	cat $DIR/$tdir/toopen && error "cat (6)"
	rm -f $DIR/$tdir/ftoremove4 && error "rm (6)"
	rmdir $DIR/$tdir/dtoremove4 && error "rmdir (6)"
	mv $DIR/$tdir/ftorename2 $DIR/$tdir/ftorename && error "mv (11)"
	mv $DIR/$tdir/dtorename2 $DIR/$tdir/dtorename && error "mv (12)"
	getfattr -n user.myattr $DIR/$tdir/toopen && error "getfattr (6)"
	setfattr -n user.myattr -v myval5 $DIR/$tdir/toopen &&
		error "setfattr (6)"
	chattr +i $DIR/$tdir/toopen && error "chattr (6)"
	lsattr $DIR/$tdir/toopen && error "lsattr (6)"
	chattr -i $DIR/$tdir/toopen && error "chattr (6)"
	ln -s $DIR/$tdir/toopen $DIR/$tdir/toopen_sl6 && error "symlink (6)"
	ln $DIR/$tdir/toopen $DIR/$tdir/toopen_hl6 && error "hardlink (6)"
	if [ "$sebool" == "off" ]; then
		setsebool -P deny_ptrace off
	else
		setsebool -P deny_ptrace on
	fi
	remove_nodemap c0
	echo 0 > /sys/module/ptlrpc/parameters/send_sepol
	if $GSS_SK; then
		export SK_UNIQUE_NM=false
	fi
}
run_test 21b "Send sepol for metadata ops"
complete_test $SECONDS
check_and_cleanup_grumple
exit_status
