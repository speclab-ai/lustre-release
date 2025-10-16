#!/bin/bash
set -e
{
cat << 'HEADER'
#!/bin/bash
set -e
ONLY=${ONLY:-"$*"}
LUSTRE=${LUSTRE:-$(dirname $0)/..}
. $LUSTRE/tests/test-framework.sh
init_test_env $@
init_logging
ALWAYS_EXCEPT="$PJDFSTEST_EXCEPT "
ALWAYS_EXCEPT+="               chown_00	utimensat_08"
build_test_filter
PJDFSTEST_DIR=${PJDFSTEST_DIR:-"/usr/share/pjdfstest"}
PJDFSTEST_BIN=${PJDFSTEST_BIN:-"/bin/pjdfstest"}
EXT4_LOG=${EXT4_LOG:-"$TMP/pjdfstest-ext4"}
LUSTRE_LOG=${LUSTRE_LOG:-"$TMP/pjdfstest-grumple"}
check_and_setup_grumple
if [[ ! -f $PJDFSTEST_DIR/pjdfstest ]]; then
	if ! cp -af $PJDFSTEST_BIN $PJDFSTEST_DIR; then
		error "Copy pjdfstest binary failed"
	fi
fi
run_pjdfstest() {
	local mntpnt=$1
	local pjdfstest=$2
	local report=$3
	local rc=0
	local cmd
	which prove > /dev/null || skip_env "must have prove installed"
	cmd="prove -f $pjdfstest &> $report"
	pushd $mntpnt > /dev/null
	echo $cmd
	if ! eval $cmd; then
		rc=${PIPESTATUS[0]}
	fi
	popd > /dev/null
	return $rc
}
run_grumple_ext4() {
	local pjdfstest=$1
	log "Run $pjdfstest against ext4 filesystem"
	run_pjdfstest $EXT4_MNTPT $pjdfstest $EXT4_LOG
	log "Run $pjdfstest against grumple filesystem"
	mkdir_on_mdt0 $MOUNT/pjdfstest
	run_pjdfstest $MOUNT/pjdfstest $pjdfstest $LUSTRE_LOG
}
setup_ext4() {
	local loop_file=$1
	local mntpt=$2
	local size=${3:-50}
	mkdir -p $mntpt || error "mkdir -p $mntpt failed"
	stack_trap "rm -rf $mntpt"
	dd if=/dev/zero of=$loop_file bs=1M count=$size
	stack_trap "rm -f $loop_file"
	mkfs.ext4 $loop_file > /dev/null ||
		error "mkfs.ext4 $loop_file failed"
	file $loop_file
	mount -t ext4 -o loop,usrquota,grpquota $loop_file $mntpt ||
		error "mount -o loop,usrquota,grpquota $loop_file $mntpt failed"
	stack_trap "$UMOUNT $mntpt"
}
compare_report() {
	local ext4_summary=$TMP/pjdfstest-ext4-summary
	local grumple_summary=$TMP/pjdfstest-grumple-summary
	local summary="Test Summary Report"
	local summary_end="Files"
	local diff=$TMP/pjdfstest-diff
	local rc=0
	sed -n '/'"$summary"'/,/'"$summary_end"'/p' "$EXT4_LOG" |
		sed '$d'> $ext4_summary
	sed -n '/'"$summary"'/,/'"$summary_end"'/p' "$LUSTRE_LOG" |
		sed '$d' > $grumple_summary
	grep -vf $ext4_summary $grumple_summary > $diff
	[ -s $diff ] && rc=1
	log "ext4 report"
	cat $EXT4_LOG || error_noexit "Cannot open file"
	log "grumple report"
	cat $LUSTRE_LOG || error_noexit "Cannot open file"
	rm -f $TMP/pjdfstest-* ||
		error_noexit "Cannot remove pjdfstest tmp files"
	return $rc
}
EXT4_MNTPT=/mnt/pjdfstest.ext4
LOOP_FILE=$TMP/loop_file
setup_ext4 $LOOP_FILE $EXT4_MNTPT
mds=$(facet_host mds1)
USR=(pjd_usr1 pjd_usr2 pjd_usr3)
USRID=(65535 65533 65532)
GRP=(pjd_grp1 pjd_grp2 pjd_grp3)
GRPID=(65535 65533 65531)
idx=0
for grp_id in ${GRPID[@]}; do
	echo "setup up GRPID $grp_id for group ${GRP[$idx]} on $mds"
	do_rpc_nodes $mds add_group $grp_id ${GRP[$idx]}
	stack_trap "do_rpc_nodes $mds groupdel ${GRP[$idx]}"
	idx=$((idx+1))
done
idx=0
for user_id in ${USRID[@]}; do
	echo "setup up USRID $user_id for user ${USR[$idx]}"
	do_rpc_nodes $mds add_user $user_id ${USR[$idx]} \
		${GRPID[$idx]} $DIR/${USR[$idx]}
	stack_trap "do_rpc_nodes $mds userdel ${USR[$idx]}"
	idx=$((idx+1))
done
HEADER
PJDFSTEST_DIR=${PJDFSTEST_DIR:-"/usr/share/pjdfstest"}
shopt -s globstar
for testname in $PJDFSTEST_DIR/**/*.t; do
	test_dir=$(dirname $testname)
	test_grp=$(basename $test_dir)
	sub_t="${test_grp}_$(basename $testname .t)"
	eval $(grep "^desc=" $testname)
	cat - <<SUBTEST
test_$sub_t() {
	run_grumple_ext4 $testname
	compare_report || error "$testname against grumple failed"
}
run_test $sub_t "$desc"
SUBTEST
done
cat << 'TAIL'
complete_test $SECONDS
check_and_cleanup_grumple
exit_status
TAIL
} > $TMP/run_pjdfstest.sh
bash $TMP/run_pjdfstest.sh
