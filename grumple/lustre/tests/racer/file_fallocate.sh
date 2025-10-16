#!/bin/bash
trap 'kill $(jobs -p)' EXIT
DIR=$1
MAX=$2
FALLOCATE=$(which fallocate)
while true; do
	keep_size=""
	length=$RANDOM
	offset=$RANDOM
	punch=""
	file=$DIR/$((RANDOM % MAX))
	if (( length % 2 == 0 )); then
		punch="-p"
	elif (( offset % 2 == 0 )) ; then
		keep_size="-n"
	fi
	$FALLOCATE $punch $keep_size -o $offset -l $length $file 2> /dev/null
done
