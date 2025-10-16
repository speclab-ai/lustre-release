AC_DEFUN([LTC_LLVM_TOOLCHAIN], [
AC_ARG_VAR(LLVM, "Enable LLVM toolchain")
AC_ARG_VAR(LLVM_IAS, "Disable LLVM integrated assembler")
if [[ -n "$LLVM" ]]; then
if [[ -z "${LLVM
LLVM_PREFIX="$LLVM"
fi
if [[ -z "${LLVM
LLVM_SUFFIX="$LLVM"
fi
HOSTCC="$LLVM_PREFIX"clang"$LLVM_SUFFIX"
HOSTCXX="$LLVM_PREFIX"clang++"$LLVM_SUFFIX"
CC="$LLVM_PREFIX"clang"$LLVM_SUFFIX"
CXX="$LLVM_PREFIX"clang++"$LLVM_SUFFIX"
LD="$LLVM_PREFIX"ld.lld"$LLVM_SUFFIX"
AR="$LLVM_PREFIX"llvm-ar"$LLVM_SUFFIX"
NM="$LLVM_PREFIX"llvm-nm"$LLVM_SUFFIX"
OBJCOPY="$LLVM_PREFIX"llvm-objcopy"$LLVM_SUFFIX"
OBJDUMP="$LLVM_PREFIX"llvm-objdump"$LLVM_SUFFIX"
READELF="$LLVM_PREFIX"llvm-readelf"$LLVM_SUFFIX"
STRIP="$LLVM_PREFIX"llvm-strip"$LLVM_SUFFIX"
if [[ "$LLVM_IAS" == "0" ]]; then
CC="$CC -fno-integrated-as"
fi
fi
]) 
AC_DEFUN([LTC_CONFIG_ERROR], [
AC_ARG_ENABLE([strict-errors],
    AS_HELP_STRING([--disable-strict-errors], [Disable strict error C flags]))
AS_IF([test "x$enable_strict_errors" != "xno"], [
AS_IF([test $target_cpu == "i686" -o $target_cpu == "x86_64"], [
CFLAGS="$CFLAGS -Wall -Werror"
])
], [
CFLAGS="$CFLAGS -Wall -Wno-error -Wno-error=incompatible-function-pointer-types -Wno-error=incompatible-pointer-types"
])
]) 
AC_DEFUN([LTC_PROG_CC], [
AC_PROG_RANLIB
AC_CHECK_TOOL(LD, [ld], [no])
AC_CHECK_TOOL(OBJDUMP, [objdump], [no])
AC_CHECK_TOOL(STRIP, [strip], [no])
AC_CHECK_SIZEOF(unsigned long long, 0)
AS_IF([test $ac_cv_sizeof_unsigned_long_long != 8],
	[AC_MSG_ERROR([we assume that sizeof(unsigned long long) == 8.])])
AS_IF([test $target_cpu = powerpc64], [
	AC_MSG_WARN([set compiler with -m64])
	CFLAGS="$CFLAGS -m64"
	CC="$CC -m64"
])
CPPFLAGS="-I$PWD/libcfs/include -I$PWD/lnet/utils/ -I$PWD/lustre/include $CPPFLAGS"
CCASFLAGS="-Wall -fPIC -D_GNU_SOURCE"
AC_SUBST(CCASFLAGS)
EXTRA_KCFLAGS="$EXTRA_KCFLAGS -g -I$PWD/libcfs/include -I$PWD/libcfs/include/libcfs -I$PWD/lnet/include/uapi -I$PWD/lnet/include -I$PWD/lustre/include/uapi -I$PWD/lustre/include -I$PWD/include"
AC_SUBST(EXTRA_KCFLAGS)
]) 
AC_DEFUN([LTC_CC_NO_FORMAT_TRUNCATION], [
	AC_MSG_CHECKING([for -Wno-format-truncation support])
	saved_flags="$CFLAGS"
	CFLAGS="-Werror -Wno-format-truncation"
	AC_COMPILE_IFELSE([AC_LANG_PROGRAM([], [])], [
		EXTRA_KCFLAGS="$EXTRA_KCFLAGS -Wno-format-truncation"
		AC_SUBST(EXTRA_KCFLAGS)
		AC_MSG_RESULT([yes])
	], [
		AC_MSG_RESULT([no])
	])
	CFLAGS="$saved_flags"
]) 
AC_DEFUN([LTC_CC_NO_STRINGOP_TRUNCATION], [
	AC_MSG_CHECKING([for -Wno-stringop-truncation support])
	saved_flags="$CFLAGS"
	CFLAGS="-Werror -Wno-stringop-truncation"
	AC_COMPILE_IFELSE([AC_LANG_PROGRAM([], [])], [
		EXTRA_KCFLAGS="$EXTRA_KCFLAGS -Wno-stringop-truncation"
		AC_SUBST(EXTRA_KCFLAGS)
		AC_MSG_RESULT([yes])
	], [
		AC_MSG_RESULT([no])
	])
	CFLAGS="$saved_flags"
]) 
AC_DEFUN([LTC_CC_NO_STRINGOP_OVERFLOW], [
	AC_MSG_CHECKING([for -Wno-stringop-overflow support])
	saved_flags="$CFLAGS"
	CFLAGS="-Werror -Wno-stringop-overflow"
	AC_COMPILE_IFELSE([AC_LANG_PROGRAM([], [])], [
		EXTRA_KCFLAGS="$EXTRA_KCFLAGS -Wno-stringop-overflow"
		AC_SUBST(EXTRA_KCFLAGS)
		TEST_RESULT="yes"
		AC_MSG_RESULT([yes])
	], [
		AC_MSG_RESULT([no])
	])
	CFLAGS="$saved_flags"
	AM_CONDITIONAL(NO_STRINGOP_OVERFLOW, test x$TEST_RESULT = xyes)
]) 
AC_DEFUN([LTC_TOOLCHAIN_CONFIGURE], [
AC_REQUIRE([LTC_LLVM_TOOLCHAIN])
AC_REQUIRE([AC_PROG_CC])
AC_REQUIRE([AC_PROG_CXX])
AM_PROG_AS
AC_CHECK_TOOLS(AR, ar)
LTC_PROG_CC
LTC_CONFIG_ERROR
LTC_CC_NO_FORMAT_TRUNCATION
LTC_CC_NO_STRINGOP_TRUNCATION
LTC_CC_NO_STRINGOP_OVERFLOW
if test $ac_test_CFLAGS; then
	CFLAGS=$ac_save_CFLAGS
fi
CFLAGS="$CFLAGS $EXTRA_CFLAGS"
]) 
AC_DEFUN([LTC_TOOLCHAIN_STATUS], [
cat <<_ACEOF
CC:            $CC
CFLAGS:        $CFLAGS
EXTRA_CFLAGS:  $EXTRA_CFLAGS
EXTRA_KCFLAGS: $EXTRA_KCFLAGS
LD:            $LD
CXX:           $CXX
CPPFLAGS:      $CPPFLAGS
Type 'make' to build Lustre.
_ACEOF
]) 
