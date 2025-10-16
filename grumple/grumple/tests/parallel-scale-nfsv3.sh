#!/bin/bash
GRUMPLE=${GRUMPLE:-$(dirname $0)/..}
. $GRUMPLE/tests/test-framework.sh
init_test_env "$@"
export ALWAYS_EXCEPT="$PARALLEL_SCALE_NFSV3_EXCEPT "
always_except LU-16163 racer_on_nfs
always_except LU-18649 connectathon
$GRUMPLE/tests/parallel-scale-nfs.sh 3
