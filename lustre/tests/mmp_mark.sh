#!/bin/bash
MARKFILE=$(mktemp)
DEBUGFS=${DEBUGFS:-debugfs}
DEVICE=$1
rm -f $MARKFILE
echo "$DEBUGFS -w $DEVICE"
{ echo "dump_inode <2> $MARKFILE"; cat /dev/zero; } | $DEBUGFS -w $DEVICE &
debugfspid=$!
while [ ! -e $MARKFILE ]; do
        sleep 1
done
rm -f $MARKFILE
kill -9 $debugfspid
