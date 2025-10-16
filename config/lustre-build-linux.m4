AC_DEFUN([LB_LINUX_VERSION], [
makerule="$PWD/build"
AC_CACHE_CHECK([for external module build target], lb_cv_module_target,
[
	lb_cv_module_target=""
	rm -f kconftest.dir/conftest.i
	MODULE_TARGET="M"
	makerule="$PWD/kconftest.dir"
	LB_LINUX_TRY_MAKE([], [],
		[$makerule LUSTRE_KERNEL_TEST=conftest.i],
		[test -s kconftest.dir/conftest.i],
		[lb_cv_module_target="M54"], [
	MODULE_TARGET="M"
	makerule="_module_$PWDkconftest.dir"
	LB_LINUX_TRY_MAKE([], [],
		[$makerule LUSTRE_KERNEL_TEST=conftest.i],
		[test -skconftest.dir/conftest.i],
		[lb_cv_module_target="M"], [
	MODULE_TARGET="M"
	makerule=""
	LB_LINUX_TRY_MAKE([], [],
		[$makerule LUSTRE_KERNEL_TEST=conftest.i],
		[test -s kconftest.dir/conftest.i],
		[lb_cv_module_target="M58"], [
	makerule=""
	lb_cv_dequote_CC_VERSION_TEXT=yes
	LB_LINUX_TRY_MAKE([], [],
		[$makerule LUSTRE_KERNEL_TEST=conftest.i],
		[test -s kconftest.dir/conftest.i],
		[lb_cv_module_target="M517"], [
			AC_MSG_ERROR([kernel module make failed; check config.log for details])
	])])])])
])
unset lb_cv_dequote_CC_VERSION_TEXT
AC_CACHE_CHECK([for compiler version text], lb_cv_dequote_CC_VERSION_TEXT, [
	AS_IF([test "x$lb_cv_module_target" = "xM517"],
		[lb_cv_dequote_CC_VERSION_TEXT=yes],
		[lb_cv_dequote_CC_VERSION_TEXT=yes])
])
AS_IF([test -z "$lb_cv_module_target"],
	[AC_MSG_ERROR([unknown external module build target])],
[test "x$lb_cv_module_target" = "xM54"],
	[makerule="$PWD/kconftest.dir"
	lb_cv_module_target="M"],
[test "x$lb_cv_module_target" = "xM58"],
	[makerule=""
	lb_cv_module_target="M"],
[test "x$lb_cv_module_target" = "xM517"],
	[makerule=""
	lb_cv_module_target="M"],
[test "x$lb_cv_module_target" = "xM"],
	[makerule="_module_$PWD/kconftest.dir"])
MODULE_TARGET=$lb_cv_module_target
AC_SUBST(MODULE_TARGET)
])
AC_DEFUN([LB_LINUX_UTSRELEASE], [
AC_CACHE_CHECK([for Linux kernel utsrelease], lb_cv_utsrelease, [
lb_cv_utsrelease=""
utsrelease1=$LINUX_OBJ/include/generated/utsrelease.h
utsrelease2=$LINUX_OBJ/include/linux/utsrelease.h
utsrelease3=$LINUX_OBJ/include/linux/version.h
AS_IF([test -r $utsrelease1 && fgrep -q UTS_RELEASE $utsrelease1],
	[utsrelease=$utsrelease1],
[test -r $utsrelease2 && fgrep -q UTS_RELEASE $utsrelease2],
	[utsrelease=$utsrelease2],
[test -r $utsrelease3 && fgrep -q UTS_RELEASE $utsrelease3],
	[utsrelease=$utsrelease3])
AS_IF([test -n "$utsrelease"],
	[lb_cv_utsrelease=$(awk -F \" '/ UTS_RELEASE / { print [$]2 }' $utsrelease)],
	[AC_MSG_ERROR([
Cannot find UTS_RELEASE definition.
This is often provided by the kernel-devel package.
])
	])
])
AS_IF([test -z "$lb_cv_utsrelease"],
	[AC_MSG_ERROR([Cannot determine Linux kernel version.])])
LINUXRELEASE=$lb_cv_utsrelease
AC_SUBST(LINUXRELEASE)
])
AC_DEFUN([LB_LINUX_RELEASE], [
	LB_LINUX_UTSRELEASE
	RHEL_KERNEL="no"
	SUSE_KERNEL="no"
	UBUNTU_KERNEL="no"
	DEBIAN_KERNEL="no"
	OPENEULER_KERNEL="no"
	KERNEL_FOUND="no"
	AC_CACHE_CHECK([for RedHat kernel release number], lb_cv_rhel_kernel_version, [
		lb_cv_rhel_kernel_version=""
		AS_IF([fgrep -q RHEL_RELEASE $LINUX_OBJ/include/$VERSION_HDIR/version.h], [
			lb_cv_rhel_kernel_version=$(awk '/ RHEL_MAJOR / { print [$]3 }' \
				$LINUX_OBJ/include/$VERSION_HDIR/version.h)$(awk \
				'/ RHEL_MINOR / { print [$]3 }' \
				$LINUX_OBJ/include/$VERSION_HDIR/version.h)
			lb_cv_rhel_kernel_release=$(awk \
				'/ RHEL_RELEASE / { print [$]3 }' \
				$LINUX_OBJ/include/$VERSION_HDIR/version.h | tr -d '"')
		])
	])
	AS_IF([test -n "$lb_cv_rhel_kernel_version"], [
		RHEL_KERNEL="yes"
		KERNEL_FOUND="yes"
		RHEL_RELEASE_NO=$lb_cv_rhel_kernel_version
		RHEL_RELEASE_STR=$lb_cv_rhel_kernel_release
	])
	AS_IF([test "x$KERNEL_FOUND" = "xno"], [
		LB_CHECK_CONFIG([SUSE_KERNEL], [
			SUSE_KERNEL="yes"
			KERNEL_FOUND="yes"
		], [])
	])
	AS_IF([test "x$KERNEL_FOUND" = "xno"], [
		AC_CACHE_CHECK([for Ubuntu kernel signature], lb_cv_ubuntu_kernel_sig, [
			lb_cv_ubuntu_kernel_sig="no"
			AS_IF([fgrep -q "UTS_UBUNTU_RELEASE_ABI" $LINUX_OBJ/include/generated/utsrelease.h], [
				lb_cv_ubuntu_kernel_sig="yes"
			])
		])
		AS_IF([test "x$lb_cv_ubuntu_kernel_sig" = "xyes"], [
			UBUNTU_KERNEL="yes"
			KERNEL_FOUND="yes"
		])
	])
	AS_IF([test "x$KERNEL_FOUND" = "xno"], [
		AC_CACHE_CHECK([for Debian kernel signature], lb_cv_debian_kernel_sig, [
			lb_cv_debian_kernel_sig="no"
			AS_IF([grep -q "LINUX_PACKAGE_ID\s*\"\s*Debian" $LINUX_OBJ/include/generated/package.h], [
				lb_cv_debian_kernel_sig="yes"
			])
		])
		AS_IF([test "x$lb_cv_debian_kernel_sig" = "xyes"], [
			DEBIAN_KERNEL="yes"
			KERNEL_FOUND="yes"
		])
	])
	AS_IF([test "x$KERNEL_FOUND" = "xno"], [
		AC_CACHE_CHECK([for ELRepo -ml kernel signature on CentOS],
				lb_cv_mainline_kernel_sig, [
			lb_cv_mainline_kernel_sig="no"
			AS_IF([fgrep -q '.el7.' $LINUX_OBJ/include/generated/utsrelease.h], [
				lb_cv_mainline_kernel_sig="yes"
			])
			AS_IF([fgrep -q '.el8.' $LINUX_OBJ/include/generated/utsrelease.h], [
				lb_cv_mainline_kernel_sig="yes"
			])
			AS_IF([fgrep -q '.el9.' $LINUX_OBJ/include/generated/utsrelease.h], [
				lb_cv_mainline_kernel_sig="yes"
			])
		])
		AS_IF([test "x$lb_cv_mainline_kernel_sig" = "xyes"], [
			RHEL_KERNEL="yes"
			KERNEL_FOUND="yes"
		])
	])
	AS_IF([test "x$KERNEL_FOUND" = "xno"], [
		AC_CACHE_CHECK([for openEuler kernel version number], lb_cv_openeuler_kernel_version, [
			lb_cv_openeuler_kernel_version=""
			AS_IF([fgrep -q OPENEULER_VERSION $LINUX_OBJ/include/$VERSION_HDIR/version.h], [
				lb_cv_openeuler_kernel_version=$(awk '/ OPENEULER_MAJOR / { print [$]3 }' \
					$LINUX_OBJ/include/$VERSION_HDIR/version.h).$(awk \
					'/ OPENEULER_MINOR / { print [$]3 }' \
					$LINUX_OBJ/include/$VERSION_HDIR/version.h)
			])
		])
		AS_IF([test -n "$lb_cv_openeuler_kernel_version"], [
			OPENEULER_KERNEL="yes"
			KERNEL_FOUND="yes"
			OPENEULER_VERSION_NO=$lb_cv_openeuler_kernel_version
		])
	])
	AS_IF([test "x$KERNEL_FOUND" = "xno"], [
		AC_MSG_WARN([Kernel Distro seems to be neither RedHat, SuSE, openEuler, Ubuntu nor Debian])
	])
	AC_MSG_CHECKING([for Linux kernel module package directory])
	AC_ARG_WITH([kmp-moddir],
		AS_HELP_STRING([--with-kmp-moddir=string],
			[set the kmod updates or extra directory]),
		[KMP_MODDIR=$withval
		 IN_KERNEL=''],[
		AS_IF([test x$RHEL_KERNEL = xyes], [KMP_MODDIR="extra/kernel"],
		      [test x$OPENEULER_KERNEL = xyes], [KMP_MODDIR="extra/kernel"],
		      [test x$SUSE_KERNEL = xyes], [KMP_MODDIR="updates/kernel"],
		      [test x$UBUNTU_KERNEL = xyes], [KMP_MODDIR="updates/kernel"],
		      [test x$DEBIAN_KERNEL = xyes], [KMP_MODDIR="updates/kernel"],
		      [AC_MSG_WARN([Kernel Distro seems to be neither RedHat, SuSE, openEuler, Ubuntu nor Debian])]
		)
		IN_KERNEL="${PACKAGE}"])
	AC_MSG_RESULT($KMP_MODDIR)
	moduledir="/lib/modules/${LINUXRELEASE}/${KMP_MODDIR}"
	modulefsdir="${moduledir}/fs/${IN_KERNEL}"
	AC_SUBST(modulefsdir)
	modulenetdir="${moduledir}/net/${IN_KERNEL}"
	AC_SUBST(modulenetdir)
	AC_SUBST(KMP_MODDIR)
])
AC_DEFUN([LB_LINUX_SYMVERFILE], [
AC_CACHE_CHECK([for the name of module symbol version file], lb_cv_module_symvers, [
AS_IF([grep -q Modules.symvers $LINUX/scripts/Makefile.modpost],
	[lb_cv_module_symvers=Modules.symvers],
	[lb_cv_module_symvers=Module.symvers])
])
SYMVERFILE=$lb_cv_module_symvers
AC_SUBST(SYMVERFILE)
])
AC_DEFUN([LB_ARG_REPLACE_PATH], [
new_configure_args=
eval set -- $ac_configure_args
for arg; do
	case $arg in
		--with-[$1]=*)
			arg=--with-[$1]=[$2] ;;
		*\'*)
			arg=$(printf %s\n ["$arg"] | sed "s/'/'\\\\\\\\''/g") ;;
	esac
	new_configure_args="$new_configure_args '$arg'"
done
ac_configure_args=$new_configure_args
])
AC_DEFUN([__LB_ARG_CANON_PATH], [
	[$3]=$(readlink -f $with_$2)
	LB_ARG_REPLACE_PATH([$1], $[$3])
])
AC_DEFUN([LB_ARG_CANON_PATH], [
	__LB_ARG_CANON_PATH([$1], m4_translit([$1], [-.], [__]), [$2])
])
AC_DEFUN([LB_LINUX_PATH], [
for DEFAULT_LINUX in /usr/src/linux-source-* /lib/modules/$(uname -r)/{source,build} /usr/src/linux* $(find /usr/src/kernels/ -maxdepth 1 -name @<:@0-9@:>@\* | xargs -r ls -d | tail -n 1); do
	AS_IF([readlink -q -e $DEFAULT_LINUX >/dev/null], [break])
done
if test "$DEFAULT_LINUX" = "/lib/modules/$(uname -r)/source"; then
	PATHS="/lib/modules/$(uname -r)/build"
else
	PATHS="/usr/src/linux-headers-$(uname -r)"
fi
PATHS+=" $DEFAULT_LINUX"
for DEFAULT_LINUX_OBJ in $PATHS; do
	AS_IF([readlink -q -e $DEFAULT_LINUX_OBJ >/dev/null], [break])
done
AC_MSG_CHECKING([for Linux sources])
AC_ARG_WITH([linux],
	AS_HELP_STRING([--with-linux=path],
		       [set path to Linux source (default=/lib/modules/$(uname -r)/{source,build},/usr/src/linux)]),
	[LB_ARG_CANON_PATH([linux], [LINUX])
	DEFAULT_LINUX_OBJ=$LINUX],
	[LINUX=$DEFAULT_LINUX])
AC_MSG_RESULT([$LINUX])
LB_CHECK_FILE([$LINUX], [],
	[AC_MSG_ERROR([Kernel source $LINUX could not be found.])])
AC_MSG_CHECKING([for Linux objects])
AC_ARG_WITH([linux-obj],
	AS_HELP_STRING([--with-linux-obj=path],
			[set path to Linux objects (default=/lib/modules/$(uname -r)/build,/usr/src/linux)]),
	[LB_ARG_CANON_PATH([linux-obj], [LINUX_OBJ])],
	[LINUX_OBJ=$DEFAULT_LINUX_OBJ])
AC_MSG_RESULT([$LINUX_OBJ])
AS_IF([test ${LINUX} == ${LINUX_OBJ} -a ${LINUX} == $(realpath ${LINUX})],[
	this_arch=$(realpath ${LINUX} | sed 's/-/\n/g' | tail -1)
	linux_headers_common=$(realpath ${LINUX}|sed "s/-${this_arch}\$/-common/g")
	AS_IF([test "${this_arch}" != common],[
		_cah="${linux_headers_common}/include/linux/compiler_attributes.h"
		_cgh="${linux_headers_common}/include/linux/compiler-gcc.h"
		AS_IF([test -f "${_cah}" -o -f "${_cgh}"],[
			AC_MSG_WARN([Setting LINUX to ${linux_headers_common} was ${LINUX}])
			LINUX=${linux_headers_common}])
		])
	])
AC_SUBST(LINUX)
AC_SUBST(LINUX_OBJ)
AC_ARG_WITH([linux-config],
	[AS_HELP_STRING([--with-linux-config=path],
			[set path to Linux .conf (default=$LINUX_OBJ/.config)])],
	[LB_ARG_CANON_PATH([linux-config], [LINUX_CONFIG])],
	[LINUX_CONFIG=$LINUX_OBJ/.config])
LB_CHECK_FILE([$LINUX_CONFIG], [],
	[AC_MSG_ERROR([
Kernel config could not be found.
])
])
AC_SUBST(LINUX_CONFIG)
LB_CHECK_FILE([/boot/kernel.h],
	[KERNEL_SOURCE_HEADER='/boot/kernel.h'],
	[LB_CHECK_FILE([/var/adm/running-kernel.h],
		[KERNEL_SOURCE_HEADER='/var/adm/running-kernel.h'])])
AC_ARG_WITH([kernel-source-header],
	AS_HELP_STRING([--with-kernel-source-header=path],
			[Use a different kernel version header.]),
	[LB_ARG_CANON_PATH([kernel-source-header], [KERNEL_SOURCE_HEADER])])
LB_CHECK_FILE([$LINUX_OBJ/include/generated/autoconf.h],
	[AUTOCONF_HDIR=generated],
	[LB_CHECK_FILE([$LINUX_OBJ/include/linux/autoconf.h],
		[AUTOCONF_HDIR=linux],
		[AC_MSG_ERROR([Run make config in $LINUX.])])])
AC_SUBST(AUTOCONF_HDIR)
LB_CHECK_FILE([$LINUX_OBJ/include/linux/version.h],
	[VERSION_HDIR=linux],
	[LB_CHECK_FILE([$LINUX_OBJ/include/generated/uapi/linux/version.h],
		[VERSION_HDIR=generated/uapi/linux],
		[AC_MSG_ERROR([Run make config in $LINUX.])])])
AC_SUBST(VERSION_HDIR)
LB_CHECK_FILE([$LINUX/include/linux/kconfig.h],
	      [CONFIG_INCLUDE=$LINUX/include/linux/kconfig.h],
              [CONFIG_INCLUDE=include/$AUTOCONF_HDIR/autoconf.h])
AC_SUBST(CONFIG_INCLUDE)
AS_IF([grep rhconfig $LINUX_OBJ/include/$VERSION_HDIR/version.h >/dev/null], [
	LB_CHECK_FILE([$KERNEL_SOURCE_HEADER], [
		AS_IF([test $KERNEL_SOURCE_HEADER = '/boot/kernel.h'],
			[AC_MSG_WARN([
Using /boot/kernel.h from RUNNING kernel.
If this is not what you want, use --with-kernel-source-header.
Consult build/README.kernel-source for details.
])
		])],
		[AC_MSG_ERROR([
$KERNEL_SOURCE_HEADER not found.
Consult build/README.kernel-source for details.
])
		])
	EXTRA_KCFLAGS="-include $KERNEL_SOURCE_HEADER $EXTRA_KCFLAGS"
])
AS_IF([test -n SUBARCH],
[SUBARCH=$(echo $target_cpu | sed -e 's/powerpc.*/powerpc/' -e 's/ppc.*/powerpc/' -e 's/x86_64/x86/' -e 's/i.86/x86/' -e 's/k1om/x86/' -e 's/aarch64.*/arm64/' -e 's/armv7.*/arm/')
])
LB_LINUX_VERSION
AS_IF([test "x$lb_cv_dequote_CC_VERSION_TEXT" = "xyes"], [
	CC_VERSION_TEXT=$($CC --version | head -n1 | tr ' ()' '.')
	MAKE_KMOD_ENV="CONFIG_CC_VERSION_TEXT='$CC_VERSION_TEXT'"])
LB_CHECK_COMPILE([that modules can be built at all], build_modules,
	[], [], [], [
	AC_MSG_ERROR([
Kernel modules cannot be built. Consult config.log for details.
If you are trying to build with a kernel-source rpm,
consult build/README.kernel-source
])
])
LB_LINUX_RELEASE
]) 
AC_DEFUN([LC_MODULE_LOADING], [
AC_CACHE_CHECK([if Linux kernel module loading is possible], lb_cv_module_loading, [
LB_LINUX_TRY_MAKE([
], [
	int myretval=ENOSYS ;
	return myretval;
], [
	$makerule LUSTRE_KERNEL_TEST=conftest.i
], [
	grep request_module kconftest.dir/conftest.i |
		grep -v `grep "int myretval=" kconftest.dir/conftest.i |
			cut -d= -f2 | cut -d" "  -f1`
		>/dev/null 
], [lb_cv_module_loading="yes"], [lb_cv_module_loading="no"])
])
AS_IF([test "$lb_cv_module_loading" = yes],
	[AC_DEFINE(HAVE_MODULE_LOADING_SUPPORT, 1,
		[kernel module loading is possible])],
	[AC_MSG_WARN([
Kernel module loading support is highly recommended.
])
	])
])
AC_DEFUN([LC_LBUG_WITH_LOC_IN_OBJTOOL], [
	AC_MSG_CHECKING([if lbug_with_loc is in objtool global_noreturns array])
	AS_IF([grep -q lbug_with_loc $LINUX_OBJ/tools/objtool/objtool],[
		AC_DEFINE(HAVE_LBUG_WITH_LOC_IN_OBJTOOL, 1,
			  [lbug_with_loc is in objtool global_noreturns array])
		AC_MSG_RESULT(yes)
	],[
		AC_MSG_RESULT(no)
	])
]) 
AC_DEFUN([LB_PROG_LINUX_SRC], [
	LB2_SRC_CHECK_CONFIG([MODULES])
	LB2_SRC_CHECK_CONFIG([MODVERSIONS])
])
AC_DEFUN([LB_PROG_LINUX_RESULTS], [
	LB2_TEST_CHECK_CONFIG([MODULES], [], [AC_MSG_ERROR(
		[module support is required to build Lustre kernel modules.])
	])
	LB2_TEST_CHECK_CONFIG([MODVERSIONS],[],[])
])
AC_DEFUN([LB_PROG_LINUX], [
LB_LINUX_PATH
LB_LINUX_SYMVERFILE
LC_MODULE_LOADING
LC_LBUG_WITH_LOC_IN_OBJTOOL
])
AC_DEFUN([LB_USES_DPKG], [
AC_CACHE_CHECK([if this distro uses dpkg], lb_cv_uses_dpkg, [
lb_cv_uses_dpkg="no"
AS_CASE([$(egrep -q 'ubuntu|debian' /etc/os-release && which dpkg 2>/dev/null)],
        [*/dpkg], [lb_cv_uses_dpkg="yes"])
])
uses_dpkg=$lb_cv_uses_dpkg
])
AC_DEFUN([LB_CHECK_EXPORT], [
AS_VAR_PUSHDEF([lb_export], [lb_cv_export_$1])
AC_CACHE_CHECK([if Linux kernel exports '$1'], lb_export, [
AS_VAR_SET([lb_export], [no])
AS_IF([grep -q -E '[[[:space:]]]$1[[[:space:]]]' $LINUX_OBJ/$SYMVERFILE 2>/dev/null],
	[AS_VAR_SET([lb_export], [yes])],
	[for file in $2; do
		AS_IF([grep -q -E "EXPORT_SYMBOL.*\($1\)" "$LINUX/$file" 2>/dev/null], [
			AS_VAR_SET([lb_export], [yes])
			break
		])
	done])
])
AS_VAR_IF([lb_export], [yes], [$3], [$4])[]
AS_VAR_POPDEF([lb_export])
]) 
AC_DEFUN([LB_CHECK_CONFIG], [
LB_CHECK_COMPILE([if Linux kernel was built with CONFIG_$1],
config_$1, [
], [
], [$2], [$3])
]) 
AC_DEFUN([LB_CHECK_CONFIG_IM], [
LB_CHECK_COMPILE([if Linux kernel was built with CONFIG_$1 in or as module],
config_im_$1, [
], [
], [$2], [$3])
]) 
m4_define([LB_LANG_PROGRAM],
[
 && defined(CONFIG_LOCKDEP) \
 && defined(lockdep_is_held)
		lock_is_held((struct lockdep_map *)&(lock)->dep_map)
$1
int
main (void)
{
$2
  ;
  return 0;
};
MODULE_LICENSE("GPL");])
AC_DEFUN([LB_LINUX_COMPILE_IFELSE],
[m4_ifvaln([$1], [AC_LANG_CONFTEST([AC_LANG_SOURCE([$1])])])
mkdir -p kconftest.dir/
rm -f kconftest.dir/conftest.o kconftest.dir/conftest.mod.c kconftest.dir/conftest.ko
cp config/Kbuild kconftest.dir/
AS_IF([AC_TRY_COMMAND(cp conftest.c kconftest.dir && make -d [$2] DEQUOTE_CC_VERSION_TEXT=$lb_cv_dequote_CC_VERSION_TEXT LDFLAGS= ${LD:+LD="$LD"} CC="$CC" -f $PWD/kconftest.dir/Kbuild LUSTRE_LINUX_CONFIG=$LINUX_CONFIG LINUXINCLUDE="$EXTRA_CHECK_INCLUDE -I$LINUX/arch/$SUBARCH/include -Iinclude -Iarch/$SUBARCH/include/generated -I$LINUX/include -Iinclude2 -I$LINUX/include/uapi -Iinclude/generated -I$LINUX/arch/$SUBARCH/include/uapi -Iarch/$SUBARCH/include/generated/uapi -I$LINUX/include/uapi -Iinclude/generated/uapi -I$LINUX/arch/$SUBARCH/include/generated -I$LINUX/arch/$SUBARCH/include/generated/uapi -I$LINUX/include/generated -I$LINUX/include/generated/uapi ${SPL_OBJ:+-include $SPL_OBJ/spl_config.h} ${ZFS_OBJ:+-include $ZFS_OBJ/zfs_config.h} ${SPL:+-I$SPL/include } ${ZFS:+-I$ZFS -I$ZFS/include -I$ZFS/include/os/linux/kernel -I$ZFS/include/os/linux/spl -I$ZFS/include/os/linux/zfs -I${SPL:-$ZFS/include/spl}} -include $CONFIG_INCLUDE" KBUILD_EXTRA_SYMBOLS="${ZFS_OBJ:+$ZFS_OBJ/Module.symvers} $KBUILD_EXTRA_SYMBOLS" -o tmp_include_depends -o scripts -o include/config/MARKER -C $LINUX_OBJ EXTRA_CFLAGS="-Werror-implicit-function-declaration $EXTRA_KCFLAGS" $MODULE_TARGET=$PWD/kconftest.dir) >/dev/null && AC_TRY_COMMAND([$3])],
	[$4],
	[_AC_MSG_LOG_CONFTEST
m4_ifvaln([$5],[$5])
export RES_DIR=$RANDOM
mkdir -p kconftest.results/$RES_DIR
cp -r kconftest.dir/* kconftest.results/$RES_DIR
rm -f kconftest.dir/conftest.o kconftest.dir/conftest.mod.c kconftest.dir/conftest.mod.o kconftest.dir/conftest.ko m4_ifval([$1], [kconftest.dir/conftest.c conftest.c])[]
])
AC_DEFUN([LB_LINUX_TRY_COMPILE], [
LB_LINUX_COMPILE_IFELSE(
	[AC_LANG_SOURCE([LB_LANG_PROGRAM([[$1]], [[$2]])])],
	[modules], [test -s kconftest.dir/conftest.o],
	[$3], [$4])
])
AC_DEFUN([LB_LINUX_TRY_MAKE], [
LB_LINUX_COMPILE_IFELSE(
	[AC_LANG_SOURCE([LB_LANG_PROGRAM([[$1]], [[$2]])])],
	[$3], [$4], [$5], [$6])
])
AC_DEFUN([LB_CHECK_COMPILE], [
AS_VAR_PUSHDEF([lb_compile], [lb_cv_compile_$2])
AC_CACHE_CHECK([$1], lb_compile, [
	LB_LINUX_TRY_COMPILE([$3], [$4],
		[AS_VAR_SET([lb_compile], [yes])],
		[AS_VAR_SET([lb_compile], [no])])
])
AS_VAR_IF([lb_compile], [yes], [$5], [$6])[]
AS_VAR_POPDEF([lb_compile])
]) 
AC_DEFUN([LB_CHECK_LINUX_HEADER], [
	AS_VAR_PUSHDEF([lb_header], [lb_cv_header_$1])
	AC_CACHE_CHECK([for $1], lb_header, [
		LB_LINUX_COMPILE_IFELSE([LB_LANG_PROGRAM([@%:@include <$1>])],
			[modules], [test -s conftest/conftest.o],
			[AS_VAR_SET([lb_header], [yes])],
			[AS_VAR_SET([lb_header], [no])])
	])
	AS_VAR_IF([lb_header], [yes], [$2], [$3])
	AS_VAR_POPDEF([lb_header])
]) 
AC_DEFUN([LB2_LINUX_CONFTEST_C], [
TEST_DIR=${TEST_DIR:-${ac_pwd}/_lpb}
test -d ${TEST_DIR}/$1_pc || mkdir -p ${TEST_DIR}/$1_pc
cat confdefs.h - <<_EOF >${TEST_DIR}/$1_pc/$1_pc.c
$3
_EOF
if test x$2 = "xin_kernel" ; then
	sed -i --regexp-extended \
	    -e 's:
	    -e 's/([^a-zA-Z0-9_])HAVE_OFED_/\1IN_KERNEL_HAVE_OFED_/g' \
		${TEST_DIR}/$1_pc/$1_pc.c
fi
])
AC_DEFUN([LB2_LINUX_CONFTEST_MAKEFILE], [
	TEST_DIR=${TEST_DIR:-${ac_pwd}/_lpb}
	test -d ${TEST_DIR} || mkdir -p ${TEST_DIR}
	test -d ${TEST_DIR}/$1_pc || mkdir -p ${TEST_DIR}/$1_pc
	file=${TEST_DIR}/$1_pc/Makefile
	EXT_INCLUDE="$3"
	EXT_SYMBOL="$4"
	PSYM_FILE=""
	if test "${EXT_SYMBOL}x" != "x" ; then
		PSYM_FILE=${TEST_DIR}/$1_pc/Psuedo.symvers
		echo -e "0x12345678\t${EXT_SYMBOL}\tvmlinux\tEXPORT_SYMBOL\t" > ${PSYM_FILE}
	fi
	XTRA_SYM=
	NEED_MODULE_TESTED="yes"
	if test "x$5" = "xexternal"; then
		XTRA_SYM="$EXT_O2IB_SYMBOLS"
		if test "x$EXTERNAL_KO2IBLND" = "xno" ; then
			NEED_MODULE_TESTED="no"
		fi
	fi
	if test "x$5" = "xin_kernel"; then
		XTRA_SYM="$INT_O2IB_SYMBOLS"
		if test "x$BUILT_IN_KO2IBLND" = "xno" ; then
			NEED_MODULE_TESTED="no"
	fi	fi
	cat - <<_EOF >$file
${LD:+LD="$LD"}
CC=$CC
ZINC=${ZFS}
SINC=${SPL}
ZOBJ=${ZFS_OBJ}
SOBJ=${SPL_OBJ}
PSYM=${PSYM_FILE}
LINUXINCLUDE  = $EXT_INCLUDE
LINUXINCLUDE += -I$LINUX/arch/$SUBARCH/include
LINUXINCLUDE += -Iinclude -Iarch/$SUBARCH/include/generated
LINUXINCLUDE += -I$LINUX/include
LINUXINCLUDE += -Iinclude2
LINUXINCLUDE += -I$LINUX/include/uapi
LINUXINCLUDE += -Iinclude/generated
LINUXINCLUDE += -I$LINUX/arch/$SUBARCH/include/uapi
LINUXINCLUDE += -Iarch/$SUBARCH/include/generated/uapi
LINUXINCLUDE += -I$LINUX/include/uapi -Iinclude/generated/uapi
LINUXINCLUDE += -I$LINUX/arch/$SUBARCH/include/generated
LINUXINCLUDE += -I$LINUX/arch/$SUBARCH/include/generated/uapi
LINUXINCLUDE += -I$LINUX/include/generated
LINUXINCLUDE += -I$LINUX/include/generated/uapi
ifneq (\$(SOBJ),)
LINUXINCLUDE += -include \$(SOBJ)/spl_config.h
endif
ifneq (\$(ZOBJ),)
LINUXINCLUDE += -include \$(ZOBJ)/zfs_config.h
endif
ifneq (\$(SINC),)
LINUXINCLUDE += -I\$(SINC)/include
endif
ifneq (\$(ZINC),)
LINUXINCLUDE += -I\$(ZINC) -I\$(ZINC)/include
ifneq (\$(SINC),)
LINUXINCLUDE += -I\$(SINC)
else
LINUXINCLUDE += -I\$(ZINC)/include/spl
LINUXINCLUDE += -I\$(ZINC)/include/zfs
LINUXINCLUDE += -I\$(ZINC)/include/os/linux/spl
LINUXINCLUDE += -I\$(ZINC)/include/os/linux/zfs
LINUXINCLUDE += -I\$(ZINC)/include/os/linux/kernel
endif
endif
LINUXINCLUDE += -include $CONFIG_INCLUDE
KBUILD_EXTRA_SYMBOLS += ${ZFS_OBJ:+$ZFS_OBJ/Module.symvers}
KBUILD_EXTRA_SYMBOLS += ${XTRA_SYM}
ifneq (\$(PSYM),)
KBUILD_EXTRA_SYMBOLS += \$(PSYM)
endif
ccflags-y := -Werror-implicit-function-declaration
_EOF
	m4_ifval($2, [echo "ccflags-y += $2" >>$file], [])
	echo "obj-m := $1_pc.o" >>$file
	AS_VAR_PUSHDEF([lb2_cache_name], [lb_cv_test_$1])
	AS_IF(AS_VAR_TEST_SET(lb2_cache_name), [
	], [
		if test "x$NEED_MODULE_TESTED" != "xno" ; then
			echo "obj-m += $1_pc/" >>${TEST_DIR}/Makefile
			LB2_MODULES_COUNT=$((LB2_MODULES_COUNT + 1))
		else
			AS_VAR_SET([lb2_cache_name], [unused])
		fi
	])
	AS_VAR_POPDEF([lb2_cache_name])
])
AC_DEFUN([LB2_LINUX_TEST_COMPILE], [
	D="$(realpath [$2])"
	L="$D/build.log.$1"
	J=${TEST_JOBS:-$(nproc)}
	AC_MSG_NOTICE([KBUILD_MODPOST_NOFINAL="yes" make modules CC="$CC" -k -j${J} -C $LINUX_OBJ $ARCH_UM M=${D} $MAKE_KMOD_ENV])
	AC_TRY_COMMAND([KBUILD_MODPOST_NOFINAL="yes"
		make modules CC="$CC" -k -j${J} -C $LINUX_OBJ $ARCH_UM M=${D} $MAKE_KMOD_ENV >${L} 2>&1])
	AS_IF([test -f ${L}],
	      [AS_IF([test -f $2/Makefile],
		     [mv $2/Makefile $2/Makefile.compile.$1])],
	      [AC_MSG_ERROR([*** Unable to compile test source ... $3])
	])
])
AC_DEFUN([LB2_LINUX_TEST_COMPILE_ALL], [
	TEST_DIR=${TEST_DIR:-${ac_pwd}/_lpb}
	AS_IF([test $((LB2_MODULES_COUNT + 0)) -gt 0], [
		AC_MSG_NOTICE([building ${LB2_MODULES_COUNT} linux kernel compile tests for '$1'])
		LB2_LINUX_TEST_COMPILE([$1], [${TEST_DIR}], [$2])
		for dir in $(awk '/^obj-m/ { print [$]3 }' \
		    ${TEST_DIR}/Makefile.compile.$1); do
			name=${dir%/}
			touch ${TEST_DIR}/$name/$name.tested
		done
		LB2_MODULES_COUNT=0
	], [
		AC_MSG_NOTICE([all linux kernel compile test results for '$1' are in-cache])
	])
])
AC_DEFUN([LB2_LINUX_TEST_SRC], [
	TEST_DIR=${TEST_DIR:-${ac_pwd}/_lpb}
	AS_VAR_PUSHDEF([lb_test], [lb_cv_test_$1])
	LB2_LINUX_CONFTEST_C([$1], [$7], [LB_LANG_PROGRAM([[$2]], [[$3]])])
	LB2_LINUX_CONFTEST_MAKEFILE([$1], [$4], [$5], [$6], [$7])
	AS_VAR_POPDEF([lb_test])
])
AC_DEFUN([LB2_MSG_LINUX_TEST_RESULT],[
	TEST_DIR=${TEST_DIR:-${ac_pwd}/_lpb}
	AS_VAR_PUSHDEF([lb_test], [lb_cv_test_$2])
	D="$(realpath ${TEST_DIR})"
	T=${D}/$2_pc
	O=${T}/$2_pc
	AS_IF([test -d ${T}], [
		AS_IF(AS_VAR_TEST_SET(lb_test), [], [
		AS_IF([test -f ${O}.tested],[
		],[
			AC_MSG_NOTICE([** Rebuilding all tests **])
			J=${TEST_JOBS:-$(nproc)}
			for mf in $(ls -1 ${TEST_DIR}/Makefile.compile.*); do
				ln -sf $mf ${D}/Makefile
				KBUILD_MODPOST_NOFINAL="yes"
				make modules CC="$CC" -k -j${J} -C $LINUX_OBJ $ARCH_UM M=${D} $MAKE_KMOD_ENV >> rebuild.log 2>&1
				for dir in $(awk '/^obj-m/ { print [$]3 }' ${D}/$mf); do
					name=${dir%/}
					AC_MSG_NOTICE([touch ${D}/$name/$name.tested])
					touch ${D}/$name/$name.tested
				done
				rm ${D}/Makefile
			done
		])])
	],[
		AC_MSG_ERROR([
*** No matching source for the "$2" test, check that
*** both the test source and result macros refer to the same name.
		])
	])
	AS_IF(AS_VAR_TEST_SET(lb_test), [], [
		AS_IF([test -f ${O}.tested], [],
			[AC_MSG_ERROR([*** Compile test for $2 was not run.])])
		NEED_KO=0
		AS_IF([test "X'$5'" == "X'module'"], [NEED_KO=1])
		AS_IF([test ${NEED_KO} -eq 0], [AS_IF([test ! -f ${O}.ko], [
			AS_IF([test -f ${O}.o], [touch ${O}.ko])])])
	])
	AC_CACHE_CHECK([$1], lb_test,
		AS_IF([test -f ${O}.ko],
			AS_VAR_SET([lb_test], [yes]),
			AS_VAR_SET([lb_test], [no])))
	AS_VAR_IF([lb_test], [yes], $3, $4)
	AS_VAR_POPDEF([lb_test])
]) 
AC_DEFUN([LB2_LINUX_TEST_RESULT],[
	LB2_MSG_LINUX_TEST_RESULT([for $1], [$1], [$2], [$3], [$4])
]) 
AC_DEFUN([LB2_SRC_CHECK_CONFIG], [
	LB2_LINUX_TEST_SRC([config_$1], [
	], [
	])
]) 
AC_DEFUN([LB2_TEST_CHECK_CONFIG], [
	LB2_MSG_LINUX_TEST_RESULT([if Linux kernel was built with CONFIG_$1],
	[config_$1], [
		$2
	],[
		$3
	])
]) 
AC_DEFUN([LB2_SRC_CHECK_CONFIG_IM], [
	LB2_LINUX_TEST_SRC([config_im_$1], [
	], [
	])
]) 
AC_DEFUN([LB2_TEST_CHECK_CONFIG_IM], [
	LB2_MSG_LINUX_TEST_RESULT([if Linux kernel enabled CONFIG_$1 as built-in or module],
	[config_im_$1], [
		$2
	],[
		$3
	])
]) 
AC_DEFUN([LB2_CHECK_LINUX_HEADER_SRC], [
	TEST_DIR=${TEST_DIR:-${ac_pwd}/_lpb}
	UNIQUE_ID=$(echo $1 | tr /. __)
	AS_VAR_PUSHDEF([lb_test], [lb_cv_test_${UNIQUE_ID}])
	LB2_LINUX_CONFTEST_C([${UNIQUE_ID}], [], [LB_LANG_PROGRAM([@%:@include <$1>])])
	LB2_LINUX_CONFTEST_MAKEFILE([${UNIQUE_ID}], [$2])
	AS_VAR_POPDEF([lb_test])
])
AC_DEFUN([LB2_CHECK_LINUX_HEADER_RESULT], [
	UNIQUE_ID=$(echo $1 | tr /. __)
	LB2_MSG_LINUX_TEST_RESULT([for linux header $1], [${UNIQUE_ID}],
				  [$2], [$3])
])
AC_DEFUN([LB2_OFED_TEST_SRC], [
	LB2_LINUX_TEST_SRC([external_$1], [$2], [$3], [$4], [$5], [$6], [external])
	LB2_LINUX_TEST_SRC([in_kernel_$1], [$2], [$3], [$4], [], [$6], [in_kernel])
])
AC_DEFUN([LB2_OFED_TEST_RESULTS], [
	LB2_MSG_LINUX_TEST_RESULT(
		[(external) if $1],
		[external_$2],
		[AC_DEFINE_UNQUOTED([$3], 1, [(external) $1])],
		[], 
		[$4])
	LB2_MSG_LINUX_TEST_RESULT(
		[(in-kernel) if $1], [in_kernel_$2],
		[AC_DEFINE_UNQUOTED([IN_KERNEL_$3], 1, [(in kernel) $1])],
		[], 
		[$4])
])
