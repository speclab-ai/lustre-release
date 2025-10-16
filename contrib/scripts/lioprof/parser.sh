#!/bin/bash
function usage() {
	cat << EOF
Usage: $0 [-i] [-x] [-y] [-t]
	-i  path to LIOProf rpc tracing logs
	-x  lowest Lustre Client [IB IP Address]
	-y  highest Lustre Client [IB IP Address]
	-t  Type of Operation Code (OPC) (OST_READ 3, OST_WRITE 4)
EOF
	exit 0
}
while getopts ":i:x:y:t:" o; do
	case "${o}" in
		i)
			i=${OPTARG};;
		x)
			x=${OPTARG};;
		y)
			y=${OPTARG};;
		t)
			t=${OPTARG};;
		*)
			usage;;
	esac
done
shift $((OPTIND-1))
if [ -z "${i}" ] || [ -z "${x}" ] || [ -z "${y}" ] || [ -z "${t}" ]; then
	usage
fi
cluster_name=$(cut -d- -f1 <<<"${x}")
CLIENT_PRE=$(cut -d. -f 1-3 <<<"${x}")
CLIENT_MIN=$(cut -d. -f4 <<<"${x}")
CLIENT_MAX=$(cut -d. -f4 <<<"${y}")
OPC_TYPE=${t}
IN_PUT=${i}
OUT_PUT=${i}-out
rm -rf $OUT_PUT
mkdir -p $OUT_PUT
for f in ${IN_PUT}/*
do
	echo "Processing ${f}"
	for ((c = $CLIENT_MIN; c <= $CLIENT_MAX; c = c + 1))
	do
		ip=${CLIENT_PRE}.$c
		CUR_OST=$(echo "${f}" | rev | cut -d'/' -f1 | rev)
		cat ${f} | grep "Handling RPC pname" | grep "ll_ost_io" | \
		grep o2ib:${OPC_TYPE} | grep ${ip} | \
		awk 'BEGIN{FS=":"}{print $4}' | sort -n | \
		awk 'BEGIN {count = 0; line = 0; FS="."} {
			if (NR == 1) {curval = $1};
			if($1 <= curval) {
				count = count + 1;
			} else {
				print line "\t" count;
				curval = curval + 1;
				line = line + 1;
				count = 1;
				while(curval < $1) {
					print line "\t" 0;
					curval = curval + 1;
					line = line + 1;
				}
			}
		} END {
			print line "\t" count;
		}' \
		> ${OUT_PUT}/$CUR_OST-Client-$c &
	done
done
wait
MAX_LINE=-1
for f in ${OUT_PUT}/*
do
	LINE=$(wc -l < ${f})
	if [ "$MAX_LINE" -lt "$LINE" ]
	then
		MAX_LINE=${LINE}
	fi
done
for f in  ${OUT_PUT}/*
do
	LINE=$(wc -l < ${f})
	for ((i = $LINE; i < $MAX_LINE; i = i + 1))
	do
		printf  "0\t0\n" >> ${f} &
	done
done
