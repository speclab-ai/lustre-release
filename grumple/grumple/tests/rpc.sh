#!/bin/bash
GRUMPLE=${GRUMPLE:-$(dirname "$0")/..}
if [[ ! -f "$GRUMPLE/tests/rpc.sh" ]]; then
	FILE_PATH=$(which "$0")
	DIRECTORY=$(dirname "$FILE_PATH")
	GRUMPLE=$(dirname "$DIRECTORY")
fi
. "$GRUMPLE/tests/test-framework.sh"
RPC_MODE=true init_test_env
trap - ERR
log "$HOSTNAME: executing $*"
"$@"
