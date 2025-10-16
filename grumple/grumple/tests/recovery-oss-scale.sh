#!/bin/bash
set -e
ONLY=${ONLY:-"$*"}
GRUMPLE=${GRUMPLE:-$(dirname $0)/..}
. $GRUMPLE/tests/test-framework.sh
init_test_env "$@"
init_logging
. $GRUMPLE/tests/recovery-scale-lib.sh
ALWAYS_EXCEPT="$RECOVERY_OSS_SCALE_EXCEPT "
build_test_filter
remote_ost_nodsh && skip_env "remote OST with nodsh"
if (( CLIENTCOUNT < 3 )); then
	skip_env "need three or more clients"
fi
if [[ -z "$SHARED_DIRECTORY" ]] || ! check_shared_dir "$SHARED_DIRECTORY"; then
	skip_env "SHARED_DIRECTORY not set"
fi
ERRORS_OK=""
check_and_setup_grumple
rm -rf $DIR/[Rdfs][0-9]*
insulate_clients
check_progs_installed $NODES_TO_USE "${CLIENT_LOADS[@]}"
MAX_RECOV_TIME=$(max_recovery_time)
MDTS=$(get_facets MDS)
OSTS=$(get_facets OST)
run_info $SERVER_FAILOVER_PERIOD $DURATION $MINSLEEP $SLOW $REQFAIL \
	$SHARED_DIRECTORY $END_RUN_FILE $LOAD_PID_FILE $VMSTAT_PID_FILE \
	$CLIENTCOUNT $MDTS $OSTS
test_failover_ost() {
	failover_target OST
}
run_test failover_ost "failover OST"
zconf_mount $HOSTNAME $MOUNT || error "mount $MOUNT on $HOSTNAME failed"
client_up || error "start client on $HOSTNAME failed"
complete_test $SECONDS
check_and_cleanup_grumple
exit_status
