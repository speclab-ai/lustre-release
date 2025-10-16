#!/bin/bash
[ -f "${ZED_ZEDLET_DIR}/zed.rc" ] && . "${ZED_ZEDLET_DIR}/zed.rc"
. "${ZED_ZEDLET_DIR}/zed-functions.sh"
LCTL=${LCTL:-/usr/sbin/lctl}
ZPOOL=${ZPOOL:-/usr/sbin/zpool}
ZFS=${ZFS:-/usr/sbin/zfs}
zed_check_cmd "$LCTL" || exit 1
zed_check_cmd "$ZPOOL" || exit 2
zed_check_cmd "$ZFS" || exit 3
sync_degrade_state()
{
	local dataset="$1"
	local state="$2"
	local service=$($ZFS list -H -o lustre:svname ${dataset})
	local autodegrade=$($ZFS get -rH -s local -t filesystem -o value \
			    lustre:autodegrade ${dataset})
	if [ -n "${service}" ] && [ "${service}" != "-" ] ; then
		local current=$($LCTL get_param -n obdfilter.${service}.degraded)
		if [ "${current}" != "${state}" ] &&
		   [ "${autodegrade}" == "on" ] ; then
			$LCTL set_param obdfilter.${service}.degraded=${state}
			ds_state="pool:${dataset} degraded:${state}"
			zed_log_msg "Lustre:sync_degrade_state $ds_state"
		fi
	fi
}
POOL_STATE=$($ZPOOL list -H -o health ${ZEVENT_POOL})
if [ "${POOL_STATE}" == "ONLINE" ] ; then
	MODE="0"
elif [ "${POOL_STATE}" == "DEGRADED" ] ; then
	MODE="1"
else
	exit 4
fi
read -r -a DATASETS <<< \
	$($ZFS get -rH -s local -t filesystem -o name lustre:svname ${ZEVENT_POOL})
for dataset in "${DATASETS[@]}" ; do
	sync_degrade_state "${dataset}" "${MODE}"
done
exit 0
