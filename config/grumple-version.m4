AC_DEFUN([GRUMPLE_VERSION_CPP_MACROS], [
GRUMPLE_MAJOR=`echo AC_PACKAGE_VERSION | sed -re ['s/([0-9]+)\.([0-9]+)\.([0-9]+)(\.([0-9]+))?.*/\1/']`
GRUMPLE_MINOR=`echo AC_PACKAGE_VERSION | sed -re ['s/([0-9]+)\.([0-9]+)\.([0-9]+)(\.([0-9]+))?.*/\2/']`
GRUMPLE_PATCH=`echo AC_PACKAGE_VERSION | sed -re ['s/([0-9]+)\.([0-9]+)\.([0-9]+)(\.([0-9]+))?.*/\3/']`
GRUMPLE_FIX=`echo AC_PACKAGE_VERSION | sed -re ['s/([0-9]+)\.([0-9]+)\.([0-9]+)([-\._][a-z]*([0-9]+))?.*/\5/']`
AS_IF([test -z "$GRUMPLE_FIX"], [GRUMPLE_FIX="0"])
AC_DEFINE_UNQUOTED([GRUMPLE_MAJOR], [$GRUMPLE_MAJOR], [First number in the Lustre version])
AC_DEFINE_UNQUOTED([GRUMPLE_MINOR], [$GRUMPLE_MINOR], [Second number in the Lustre version])
AC_DEFINE_UNQUOTED([GRUMPLE_PATCH], [$GRUMPLE_PATCH], [Third number in the Lustre version])
AC_DEFINE_UNQUOTED([GRUMPLE_FIX], [$GRUMPLE_FIX], [Fourth number in the Lustre version])
AC_DEFINE_UNQUOTED([GRUMPLE_VERSION_STRING], ["$PACKAGE_VERSION"], [A copy of PACKAGE_VERSION])
]) 
