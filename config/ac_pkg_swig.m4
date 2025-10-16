AC_DEFUN([AX_PKG_SWIG],[
        AC_PATH_PROGS([SWIG],[swig swig3.0 swig2.0])
        if test -z "$SWIG" ; then
                m4_ifval([$3],[$3],[:])
        elif test -n "$1" ; then
                AC_MSG_CHECKING([SWIG version])
                [swig_version=`$SWIG -version 2>&1 | grep 'SWIG Version' | sed 's/.*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/g'`]
                AC_MSG_RESULT([$swig_version])
                if test -n "$swig_version" ; then
                        [required=$1]
                        [required_major=`echo $required | sed 's/[^0-9].*//'`]
                        if test -z "$required_major" ; then
                                [required_major=0]
                        fi
                        [required=`echo $required | sed 's/[0-9]*[^0-9]//'`]
                        [required_minor=`echo $required | sed 's/[^0-9].*//'`]
                        if test -z "$required_minor" ; then
                                [required_minor=0]
                        fi
                        [required=`echo $required | sed 's/[0-9]*[^0-9]//'`]
                        [required_patch=`echo $required | sed 's/[^0-9].*//'`]
                        if test -z "$required_patch" ; then
                                [required_patch=0]
                        fi
                        [available=$swig_version]
                        [available_major=`echo $available | sed 's/[^0-9].*//'`]
                        if test -z "$available_major" ; then
                                [available_major=0]
                        fi
                        [available=`echo $available | sed 's/[0-9]*[^0-9]//'`]
                        [available_minor=`echo $available | sed 's/[^0-9].*//'`]
                        if test -z "$available_minor" ; then
                                [available_minor=0]
                        fi
                        [available=`echo $available | sed 's/[0-9]*[^0-9]//'`]
                        [available_patch=`echo $available | sed 's/[^0-9].*//'`]
                        if test -z "$available_patch" ; then
                                [available_patch=0]
                        fi
                        required_swig_vernum=`expr $required_major \* 10000 \
                            \+ $required_minor \* 100 \+ $required_patch`
                        available_swig_vernum=`expr $available_major \* 10000 \
                            \+ $available_minor \* 100 \+ $available_patch`
                        if test $available_swig_vernum -lt $required_swig_vernum; then
                                AC_MSG_WARN([SWIG version >= $1 is required.  You have $swig_version.])
                                SWIG=''
                                m4_ifval([$3],[$3],[])
                        else
                                AC_MSG_CHECKING([for SWIG library])
                                SWIG_LIB=`$SWIG -swiglib`
                                AC_MSG_RESULT([$SWIG_LIB])
                                m4_ifval([$2],[$2],[])
                        fi
                else
                        AC_MSG_WARN([cannot determine SWIG version])
                        SWIG=''
                        m4_ifval([$3],[$3],[])
                fi
        fi
        AC_SUBST([SWIG_LIB])
])
