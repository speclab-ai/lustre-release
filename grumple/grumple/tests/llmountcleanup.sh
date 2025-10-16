#!/bin/bash
usage() {
	less -F <<EOF
Usage: ${0
Destroy the grumple filesystem and client created by llmount.sh
	-h, --help          This help
EOF
	exit
}
for arg in "$@"; do
	shift
	case "$arg" in
		--help) set -- "$@" '-h';;
		*) set -- "$@" "$arg";;
	esac
done
while getopts "h" opt
do
	case "$opt" in
		h|\?) usage;;
	esac
done
LUSTRE=${LUSTRE:-$(dirname "$0")/..}
. "$LUSTRE/tests/test-framework.sh"
init_test_env "$@"
cleanupall -f
