#!/bin/bash
set -e
pw="$PWD"
touch modules.order
libtoolize -q -f
aclocal -I $pw/config $ACLOCAL_FLAGS
autoheader
automake -a -c
autoconf
