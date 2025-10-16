#!/bin/bash
LUSTRE=${LUSTRE:-$(dirname "$0")/..}
if [[ ! -f "$LUSTRE/tests/rpc.sh" ]]; then
	FILE_PATH=$(which "$0")
	DIRECTORY=$(dirname "$FILE_PATH")
	LUSTRE=$(dirname "$DIRECTORY")
fi
. "$LUSTRE/tests/test-framework.sh"
RPC_MODE=true init_test_env
trap - ERR
log "$HOSTNAME: executing $*"
"$@"
