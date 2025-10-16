#!/bin/bash
set -e
LUSTRE=${LUSTRE:-$(dirname $0)/..}
. $LUSTRE/tests/test-framework.sh
init_test_env "$@"
init_logging
ALWAYS_EXCEPT="$OBDFILTER_SURVEY_EXCEPT "
 if [[ $mds1_FSTYPE == zfs ]] &&
    (( $(zfs_version_code mds1) >= $(version_code 2.2.7) )); then
	always_except LU-18889 1a 1b 1c 2a 2b 3a
fi
build_test_filter
[ "$SLOW" = no ] && { nobjhi=1; thrhi=4; }
nobjhi=${nobjhi:-1}
thrhi=${thrhi:-16}
size=${size:-1024}
thrlo=${thrlo:-$(( thrhi / 2))}
if [[ -x "$OBDSURVEY" ]]; then
	echo "OBDSURVEY=$OBDSURVEY"
elif [[ -x $LUSTRE/../lustre-iokit/obdfilter-survey/obdfilter-survey ]]; then
	echo "LUSTRE=$LUSTRE"
	OBDSURVEY="$LUSTRE/../lustre-iokit/obdfilter-survey/obdfilter-survey"
else
	OBDSURVEY=${OBDSURVEY:-$(which obdfilter-survey)}
	echo "OBDSURVEY==$OBDSURVEY"
fi
check_and_setup_lustre
minsize=$(min_ost_size)
if [ $(( size * 1024 )) -ge $minsize  ]; then
    size=$((minsize * 10 / 1024 / 12 ))
    echo min kbytesavail: $minsize using size=${size} MBytes per obd instance
fi
get_targets () {
	local targets
	local target
	local dev
	local nid
	local osc
	for osc in $($LCTL get_param -N osc.${FSNAME}-*osc-*); do
		nid=$($LCTL get_param $osc.import |
			awk '/current_connection:/ {sub(/@.*/,""); \
			sub(/"/,""); print $2}')
		dev=$(echo $osc | sed -e 's/^osc\.//' -e 's/-osc.*//')
		target=$dev
		! local_node && [ "$1" == "disk" ] || target=$nid:$target
		targets="$targets $target"
	done
	echo $targets
}
obdflter_survey_targets () {
	local case=$1
	local targets
	case $case in
		disk)    targets=$(get_targets $case);;
		network) targets=$(host_nids_address $(osts_nodes) $NETTYPE);;
		*) error "unknown obdflter-survey case!" ;;
	esac
	echo $targets
}
obdflter_survey_run () {
	local case=$1
	rm -f ${TMP}/obdfilter_survey*
	local targets=$(obdflter_survey_targets $case)
	local cmd="NETTYPE=$NETTYPE LCTL=$LCTL thrlo=$thrlo nobjhi=$nobjhi thrhi=$thrhi size=$size case=$case rslt_loc=${TMP} targets=\"$targets\" $OBDSURVEY"
	echo + $cmd
	eval $cmd
	local rc=$?
	cat ${TMP}/obdfilter_survey*
	[ $rc = 0 ] || error "$OBDSURVEY failed: $rc"
}
test_1a () {
	obdflter_survey_run disk
}
run_test 1a "Object Storage Targets survey"
test_1b () {
	local param_file=$TMP/$tfile-params
	do_nodesv $(comma_list $(osts_nodes)) \
		$LCTL get_param obdfilter.${FSNAME}-*.sync_journal
	save_lustre_params $(get_facets OST) \
		"obdfilter.${FSNAME}-*.sync_journal" > $param_file
	do_nodesv $(comma_list $(osts_nodes)) \
		$LCTL set_param obdfilter.${FSNAME}-*.sync_journal=0
	local stime=$(date +%s)
	thrlo=4 nobjhi=1 thrhi=4 obdflter_survey_run disk
	local etime=$(date +%s)
	local rtime=$((etime - stime))
	echo "obd survey finished in $rtime seconds"
	restore_lustre_params < $param_file
	rm -f $param_file
}
run_test 1b "Object Storage Targets survey, async journal"
test_1c () {
	nobjlo=1 nobjhi=1 thrlo=32 thrhi=32 rszlo=1024 rszhi=1024 size=8192\
	obdflter_survey_run disk
}
run_test 1c "Object Storage Targets survey, big batch"
test_2a () {
	skip "netdisk was removed"
}
run_test 2a "Stripe F/S over the Network"
test_2b () {
	skip "netdisk was removed"
}
run_test 2b "Stripe F/S over the Network, async journal"
test_3a () {
	[ "$CLIENTONLY" ] && skip "CLIENTONLY mode"
	remote_servers || skip "Local servers"
	cleanupall
	obdflter_survey_run network
	setupall
}
run_test 3a "Network survey"
complete_test $SECONDS
cleanup_echo_devs
check_and_cleanup_lustre
exit_status
