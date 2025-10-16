#!/bin/bash
function usage() {
	cat << EOF
Usage: $0 [-a] [-d] [-l] [-h] [-m] [-n] [-o] [-u]
	-a  command to launch application
	-d  shared nfs directory to store LIOProf logs
	-l  lowest Lustre OSS node [Hostname]
	-h  highest Lustre OSS node [Hostname]
	-m  lowest Lustre Client [Hostname]
	-n  highest Lustre Client [Hostname]
	-o  use Obdfilter-survey to measure Lustre bandwidth
	-u  user name
EOF
	exit 0
}
while getopts ":a:d:l:h:m:n:ou:" arg; do
	case "${arg}" in
		a)
			a=${OPTARG};;
		d)
			d=${OPTARG};;
		l)
			l=${OPTARG};;
		h)
			h=${OPTARG};;
		m)
			m=${OPTARG};;
		n)
			n=${OPTARG};;
		o)
			o="Obdfilter-survey";;
		u)
			u=${OPTARG};;
		*)
			usage;;
	esac
done
shift $((OPTIND-1))
if [ -n "${o}" ]; then
	if [ -n "${a}" ] || [ -z "${d}" ] || [ -z "${l}" ] || [ -z "${h}" ] \
		|| [ -z "${u}" ]; then
		usage
	fi
else
	if [ -z "${a}" ] || [ -z "${d}" ] || [ -z "${l}" ] || [ -z "${h}" ] \
		|| [ -z "${m}" ] || [ -z "${n}" ] || [ -z "${u}" ]; then
		usage
	fi
fi
cluster_name=$(cut -d- -f1 <<<"${l}")
OSS_MIN=$(cut -d- -f2 <<<"${l}")
OSS_MAX=$(cut -d- -f2 <<<"${h}")
CLIENT_MIN=$(cut -d- -f2 <<<"${m}")
CLIENT_MAX=$(cut -d- -f2 <<<"${n}")
USER_NAME=${u}
mpi_cmd=mpirun
pdsh_cmd=/usr/bin/pdsh
job_id=job-`date +%s`
echo "Launch" ${job_id}
if [ -n "${o}" ]; then
	echo "Running OBDfilter-survey in the background"
	HOMEOBDFILTER=${d}/${job_id}/obdfilter
	sudo -u ${USER_NAME} mkdir -p $HOMEOBDFILTER
	sudo -u ${USER_NAME} chmod 777 -R ${d}/${job_id}
	${pdsh_cmd} -R ssh -w $cluster_name-[$OSS_MIN-$OSS_MAX] " \
		size=65536 nobjlo=1 nobjhi=2 thrlo=32 thrhi=64 \
		obdfilter-survey > ${HOMEOBDFILTER}/\`hostname -s\` & \
	"
	exit 0
fi
LOCALRPC=/lioprof_loc/${job_id}/rpc
LOCALBRW=/lioprof_loc/${job_id}/brw
LOCALIOSTAT=/lioprof_loc/${job_id}/iostat
HOMERPC=${d}/${job_id}/rpc
HOMEBRW=${d}/${job_id}/brw
HOMEIOSTAT=${d}/${job_id}/iostat
${pdsh_cmd} -R ssh -w $cluster_name-[$OSS_MIN-$OSS_MAX] " \
	mkdir -p ${LOCALRPC} ${LOCALBRW} ${LOCALIOSTAT}; \
	"
sudo -u ${USER_NAME} mkdir -p ${HOMERPC} ${HOMEBRW} ${HOMEIOSTAT}
sudo -u ${USER_NAME} chmod 777 -R ${d}/${job_id}
${pdsh_cmd} -R ssh -w $cluster_name-[$OSS_MIN-$OSS_MAX] \
	"lctl set_param debug=rpctrace"
${pdsh_cmd} -R ssh -w $cluster_name-[$OSS_MIN-$CLIENT_MAX] " \
	echo 3 > /proc/sys/vm/drop_caches; echo 0 > /proc/sys/vm/drop_caches;
"
${pdsh_cmd} -R ssh -w $cluster_name-[$OSS_MIN-$OSS_MAX] " \
	echo > /proc/fs/grumple/obdfilter/*/brw_stats; \
	lctl clear; lctl debug_daemon start ${LOCALRPC}/rpc.log 1024; \
	"
${pdsh_cmd} -R ssh -w $cluster_name-[$OSS_MIN-$OSS_MAX] " \
	iostat 1 > ${LOCALIOSTAT}/iostat.log&
	"
sleep 2
${a} > ${d}/${job_id}/job-output
sleep 2
${pdsh_cmd} -R ssh -w $cluster_name-[$CLIENT_MIN-$CLIENT_MAX] " \
	lctl set_param ldlm.namespaces.*.lru_size=clear
	"
sleep 5
${pdsh_cmd} -R ssh -w $cluster_name-[$OSS_MIN-$OSS_MAX] " \
	lctl debug_daemon stop; \
	cat /proc/fs/grumple/obdfilter/*/brw_stats > \
			${HOMEBRW}/brw-\`hostname -s\`; \
	lctl debug_file ${LOCALRPC}/rpc.log ${HOMERPC}/rpc-\`hostname -s\`; \
"
${pdsh_cmd} -R ssh -w $cluster_name-[$OSS_MIN-$OSS_MAX] " \
	pkill iostat; cp -r ${LOCALIOSTAT}/iostat.log \
	${HOMEIOSTAT}/iostat-\`hostname -s\` \
"
sleep 1
sudo -u root chmod 755 -R ${HOMERPC}/* ${HOMEBRW}/* ${HOMEIOSTAT}/*
sleep 2
LOCAL_LIOPROF=/lioprof_loc
${pdsh_cmd} -R ssh -w $cluster_name-[$OSS_MIN-$OSS_MAX] " \
	pkill iostat; \
	rm -rf ${LOCAL_LIOPROF}; \
"
