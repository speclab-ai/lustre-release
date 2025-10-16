AC_DEFUN([LPLUG_ENABLE], [
AC_ARG_ENABLE([compiler-plugins],
    AS_HELP_STRING([--enable-compiler-plugins], [Enable compiler plugins]))
AS_IF([test "x$enable_compiler_plugins" == "xyes"], [
CFLAGS="$CFLAGS -fplugin=$(pwd)/contrib/cc-plugins/.libs/libfindstatic.so"
], [])
AM_CONDITIONAL([CC_PLUGINS], [test x$enable_compiler_plugins = xyes])
]) 
AC_DEFUN([LPLUG_CONFIGURE], [
LPLUG_ENABLE
]) 
AC_DEFUN([LPLUG_CONFIG_FILES], [
	AC_CONFIG_FILES([
		contrib/cc-plugins/Makefile
	])
]) 
