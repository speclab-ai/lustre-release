#!/bin/bash
LUSTRE=${LUSTRE:-$(dirname $0)/..}
NAME=${NAME:-local}
DEFAULT_SUITES="${*:-$ACC_SM_ONLY}"
DEFAULT_SUITES="${DEFAULT_SUITES:-$(cat "$LUSTRE/tests/test-groups/regression")}"
AUSTER=$LUSTRE/tests/auster
for SUB in $DEFAULT_SUITES; do
	ENV=${SUB^^}
	ENV=${ENV//-/_}
	[[ "${!ENV}" != "no" ]] || continue
	SUITES="$SUITES $SUB"
done
echo "SUITES: $SUITES"
if [ -e "$LUSTRE/tests/cfg/$NAME.sh" ]; then
	echo "Running with config $LUSTRE/tests/cfg/${NAME}.sh"
	$AUSTER -r -R -v -f "${NAME}" $SUITES
else
	echo "Running with config $LUSTRE/tests/cfg/lustre.sh"
	$AUSTER -r -R -v -f "lustre" $SUITES
fi
