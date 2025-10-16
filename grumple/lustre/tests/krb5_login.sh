#!/bin/bash
[ $UID -eq 0 ] && exit 0
klist -5 -s && exit 0
GSS_USER=$(getent passwd $UID | cut -d: -f1)
GSS_PASS=${GSS_PASS:-"$GSS_USER"}
echo "***** refresh Kerberos V5 TGT for uid $UID *****"
if [ -z "$GSS_PASS" ]; then
    kinit
else
    echo $GSS_PASS | kinit
fi
ret=$?
exit $ret
