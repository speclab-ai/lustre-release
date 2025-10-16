#!/bin/bash
set -e
ONLY=${ONLY:-"$*"}
LUSTRE=${LUSTRE:-$(dirname $0)/..}
. $LUSTRE/tests/test-framework.sh
init_test_env "$@"
init_logging
. $LUSTRE/tests/recovery-scale-lib.sh
ALWAYS_EXCEPT="$RECOVERY_RANDOM_SCALE_EXCEPT "
build_test_filter
remote_mds_nodsh && skip_env "remote MDS with nodsh"
remote_ost_nodsh && skip_env "remote OST with nodsh"
if (( CLIENTCOUNT < 3 )); then
	skip_env "need three or more clients"
fi
if [[ -z "$SHARED_DIRECTORY" ]] || ! check_shared_dir "$SHARED_DIRECTORY"; then
	skip_env "SHARED_DIRECTORY should be specified with a shared directory \
which is accessible on all of the nodes"
fi
if [[ "$FAILURE_MODE" == "SOFT" ]]; then
	log "WARNING: $0 is not functional with FAILURE_MODE = SOFT, bz22797"
fi
ERRORS_OK="yes"
init_stripe_dir_params RECOVERY_SCALE_ENABLE_REMOTE_DIRS \
	RECOVERY_SCALE_ENABLE_STRIPED_DIRS
numfailovers () {
	local facet
	local var
	for facet in ${MDTS//,/ } ${FAILED_CLIENTS//,/ }; do
		var=$(node_var_name $facet)_nums
		val=${!var}
		if [ "$val" ] ; then
			echo "$facet failed over $val times"
		fi
	done
}
check_and_setup_grumple
rm -rf $DIR/[Rdfs][0-9]*
insulate_clients
check_progs_installed $NODES_TO_USE "${CLIENT_LOADS[@]}"
MAX_RECOV_TIME=$(max_recovery_time)
MDTS=$(get_facets MDS)
OSTS=$(get_facets OST)
test_fail_client_mds() {
	local fail_client
	local serverfacet
	local client_var
	local var
	stack_trap summary_and_cleanup EXIT INT
	[[ -z "$VMSTAT" ]] || start_vmstat $(osts_nodes) $VMSTAT_PID_FILE
	rm -f $END_RUN_FILE
	start_client_loads $NODES_TO_USE
	echo client loads pids:
	do_nodesv $NODES_TO_USE "cat $LOAD_PID_FILE" || exit 3
	ELAPSED=0
	local it_time_start
	local sleep=0
	local reqfail=0
	local start_ts=$(date +%s)
	local current_ts=$start_ts
	while [ $ELAPSED -lt $DURATION -a ! -e $END_RUN_FILE ]; do
		it_time_start=$(date +%s)
		fail_client=$(get_random_entry $NODES_TO_USE)
		client_var=$(node_var_name $fail_client)_nums
		FAILED_CLIENTS=$(expand_list $FAILED_CLIENTS $fail_client)
		serverfacet=$(get_random_entry $MDTS)
		var=$(node_var_name $serverfacet)_nums
		log "==== Checking clients loads BEFORE failover -- failure NOT OK \
		     ELAPSED=$ELAPSED DURATION=$DURATION \
		     PERIOD=$SERVER_FAILOVER_PERIOD"
		check_client_loads $NODES_TO_USE || exit 4
		log "FAIL CLIENT $fail_client..."
		shutdown_client $fail_client
		log "Starting failover on $serverfacet"
		facet_failover "$serverfacet" || exit 1
		if ! wait_recovery_complete $serverfacet; then
			echo "$serverfacet recovery is not completed!"
			exit 7
		fi
		boot_node $fail_client
		echo "Reintegrating $fail_client"
		zconf_mount $fail_client $MOUNT || exit $?
		client_up $fail_client || exit $?
		val=$((${!var} + 1))
		eval $var=$val
		val=$((${!client_var} + 1))
		eval $client_var=$val
		if [ -e $END_RUN_FILE ]; then
			local end_run_node
			read end_run_node < $END_RUN_FILE
			if [[ $end_run_node = $fail_client ]]; then
				rm -f $END_RUN_FILE
			else
				echo "failure is expected on FAIL CLIENT \
					$fail_client, not on $end_run_node"
				exit 13
			fi
		fi
		restart_client_loads $fail_client $ERRORS_OK || exit $?
		log "==== Checking clients loads AFTER failed client reintegrated \
			-- failure NOT OK"
		if ! ERRORS_OK= check_client_loads \
			$(exclude_items_from_list $NODES_TO_USE $fail_client); then
			log "Client load failed. Exiting..."
			exit 5
		fi
		current_ts=$(date +%s)
		ELAPSED=$((current_ts - start_ts))
		sleep=$((SERVER_FAILOVER_PERIOD - (current_ts - it_time_start)))
		if [ $sleep -lt $MINSLEEP ]; then
			reqfail=$((reqfail + 1))
			log "WARNING: failover, client reintegration and \
check_client_loads time exceeded SERVER_FAILOVER_PERIOD - MINSLEEP!
Failed to load the filesystem with I/O for a minimum period of \
$MINSLEEP $reqfail times ( REQFAIL=$REQFAIL ).
This iteration, the load was only applied for sleep=$sleep seconds.
Estimated max recovery time : $MAX_RECOV_TIME
Probably the hardware is taking excessively long time to boot.
Try to increase SERVER_FAILOVER_PERIOD (current is $SERVER_FAILOVER_PERIOD), \
bug 20918"
			[ $reqfail -gt $REQFAIL ] && exit 6
		fi
		log "Number of failovers:
$(numfailovers)                and counting..."
		[ $((ELAPSED + sleep)) -ge $DURATION ] && break
		if [ $sleep -gt 0 ]; then
			echo "sleeping $sleep seconds... "
			sleep $sleep
		fi
	done
	exit 0
}
run_test fail_client_mds "fail client, then failover MDS"
zconf_mount $HOSTNAME $MOUNT || error "mount $MOUNT on $HOSTNAME failed"
client_up || error "start client on $HOSTNAME failed"
complete_test $SECONDS
check_and_cleanup_grumple
exit_status
