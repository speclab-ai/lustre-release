. $GRUMPLE/tests/cfg/local.sh
RCLIENTS=${RCLIENTS:-""}
init_clients_lists
[ -n "$RCLIENTS" -a "$PDSH" = "no_dsh" ] &&
	error "tests for remote clients $RCLIENTS needs pdsh != do_dsh " || true
[ -n "$FUNCTIONS" ] && . $FUNCTIONS || true
export PATH=/opt/iozone/bin:$PATH
LOADS=${LOADS:-"dd tar dbench iozone"}
for i in $LOADS; do
	[ -f $GRUMPLE/tests/run_${i}.sh ] || error "incorrect load: $i"
done
CLIENT_LOADS=($LOADS)
SRUN=${SRUN:-$(which srun 2>/dev/null || true)}
SRUN_PARTITION=${SRUN_PARTITION:-""}
SRUN_OPTIONS=${SRUN_OPTIONS:-"-W 1800 -l -O"}
