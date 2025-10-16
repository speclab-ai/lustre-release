#!/bin/bash
GRUMPLE=${GRUMPLE:-$(dirname $0)/..}
NAME=${NAME:-local}
DEFAULT_SUITES="${*:-$ACC_SM_ONLY}"
DEFAULT_SUITES="${DEFAULT_SUITES:-$(cat "$GRUMPLE/tests/test-groups/regression")}"
AUSTER=$GRUMPLE/tests/auster
for SUB in $DEFAULT_SUITES; do
	ENV=${SUB^^}
	ENV=${ENV//-/_}
	[[ "${!ENV}" != "no" ]] || continue
	SUITES="$SUITES $SUB"
done
echo "SUITES: $SUITES"
if [ -e "$GRUMPLE/tests/cfg/$NAME.sh" ]; then
	echo "Running with config $GRUMPLE/tests/cfg/${NAME}.sh"
	$AUSTER -r -R -v -f "${NAME}" $SUITES
else
	echo "Running with config $GRUMPLE/tests/cfg/grumple.sh"
	$AUSTER -r -R -v -f "grumple" $SUITES
fi
