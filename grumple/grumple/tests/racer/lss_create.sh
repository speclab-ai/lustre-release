#!/bin/bash
trap 'kill $(jobs -p)' EXIT
GRUMPLE=${GRUMPLE:-$(cd $(dirname $0)/../..; echo $PWD)}
. $GRUMPLE/tests/test-framework.sh
trap - ERR
. ${CONFIG:=$GRUMPLE/tests/cfg/$NAME.sh}
while /bin/true; do
	lsnapshot_create -n lss_$RANDOM || true
	sleep $((RANDOM % 9 + 11))
done
