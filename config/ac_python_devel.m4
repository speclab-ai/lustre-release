AU_ALIAS([AC_PYTHON_DEVEL], [AX_PYTHON_DEVEL])
AC_DEFUN([AX_PYTHON_DEVEL],[
	if test -z "$2"; then
	   ax_python_devel_optional=false
	else
	   ax_python_devel_optional=$2
	fi
	ax_python_devel_found=yes
	AC_ARG_VAR([PYTHON_VERSION],[The installed Python
		version to use, for example '2.3'. This string
		will be appended to the Python interpreter
		canonical name.])
	AC_PATH_PROG([PYTHON],[python[$PYTHON_VERSION]])
	if test -z "$PYTHON"; then
	   AC_MSG_WARN([Cannot find python$PYTHON_VERSION in your system path])
	   if ! $ax_python_devel_optional; then
	      AC_MSG_ERROR([Giving up, python development not available])
	   fi
	   ax_python_devel_found=no
	   PYTHON_VERSION=""
	fi
	if test $ax_python_devel_found = yes; then
	   AC_MSG_CHECKING([for a version of Python >= '2.1.0'])
	   ac_supports_python_ver=`$PYTHON -c "import sys; \
		ver = sys.version.split ()[[0]]; \
		print (ver >= '2.1.0')"`
	   if test "$ac_supports_python_ver" != "True"; then
		if test -z "$PYTHON_NOVERSIONCHECK"; then
			AC_MSG_RESULT([no])
			AC_MSG_WARN([
This version of the AC@&t@_PYTHON_DEVEL macro
doesn't work properly with versions of Python before
2.1.0. You may need to re-run configure, setting the
variables PYTHON_CPPFLAGS, PYTHON_LIBS, PYTHON_SITE_PKG,
PYTHON_EXTRA_LIBS and PYTHON_EXTRA_LDFLAGS by hand.
Moreover, to disable this check, set PYTHON_NOVERSIONCHECK
to something else than an empty string.
])
			if ! $ax_python_devel_optional; then
			   AC_MSG_FAILURE([Giving up])
			fi
			ax_python_devel_found=no
			PYTHON_VERSION=""
		else
			AC_MSG_RESULT([skip at user request])
		fi
	   else
		AC_MSG_RESULT([yes])
	   fi
	fi
	if test $ax_python_devel_found = yes; then
	   if test -n "$1"; then
		AC_MSG_CHECKING([for a version of Python $1])
                cat << EOF > ax_python_devel_vpy.py
class VPy:
    def vtup(self, s):
        return tuple(map(int, s.strip().replace("rc", ".").split(".")))
    def __init__(self):
        import sys
        self.vpy = tuple(sys.version_info)[[:3]]
    def __eq__(self, s):
        return self.vpy == self.vtup(s)
    def __ne__(self, s):
        return self.vpy != self.vtup(s)
    def __lt__(self, s):
        return self.vpy < self.vtup(s)
    def __gt__(self, s):
        return self.vpy > self.vtup(s)
    def __le__(self, s):
        return self.vpy <= self.vtup(s)
    def __ge__(self, s):
        return self.vpy >= self.vtup(s)
EOF
		ac_supports_python_ver=`$PYTHON -c "import ax_python_devel_vpy; \
                        ver = ax_python_devel_vpy.VPy(); \
			print (ver $1)"`
                rm -rf ax_python_devel_vpy*.py* __pycache__/ax_python_devel_vpy*.py*
		if test "$ac_supports_python_ver" = "True"; then
			AC_MSG_RESULT([yes])
		else
			AC_MSG_RESULT([no])
			AC_MSG_WARN([this package requires Python $1.
If you have it installed, but it isn't the default Python
interpreter in your system path, please pass the PYTHON_VERSION
variable to configure. See ``configure --help'' for reference.
])
			if ! $ax_python_devel_optional; then
			   AC_MSG_ERROR([Giving up])
			fi
			ax_python_devel_found=no
			PYTHON_VERSION=""
		fi
	   fi
	fi
	if test $ax_python_devel_found = yes; then
	   AC_MSG_CHECKING([for the sysconfig Python package])
	   ac_sysconfig_result=`$PYTHON -c "import sysconfig" 2>&1`
	   if test $? -eq 0; then
		AC_MSG_RESULT([yes])
		IMPORT_SYSCONFIG="import sysconfig"
	   else
		AC_MSG_RESULT([no])
		AC_MSG_CHECKING([for the distutils Python package])
		ac_sysconfig_result=`$PYTHON -c "from distutils import sysconfig" 2>&1`
		if test $? -eq 0; then
			AC_MSG_RESULT([yes])
			IMPORT_SYSCONFIG="from distutils import sysconfig"
		else
			AC_MSG_WARN([cannot import Python module "distutils".
Please check your Python installation. The error was:
$ac_sysconfig_result])
			if ! $ax_python_devel_optional; then
			   AC_MSG_ERROR([Giving up])
			fi
			ax_python_devel_found=no
			PYTHON_VERSION=""
		fi
	   fi
	fi
	if test $ax_python_devel_found = yes; then
	   AC_MSG_CHECKING([for Python include path])
	   if test -z "$PYTHON_CPPFLAGS"; then
		if test "$IMPORT_SYSCONFIG" = "import sysconfig"; then
			python_path=`$PYTHON -c "$IMPORT_SYSCONFIG; \
				print (sysconfig.get_path ('include'));"`
			plat_python_path=`$PYTHON -c "$IMPORT_SYSCONFIG; \
				print (sysconfig.get_path ('platinclude'));"`
		else
			python_path=`$PYTHON -c "$IMPORT_SYSCONFIG; \
				print (sysconfig.get_python_inc ());"`
			plat_python_path=`$PYTHON -c "$IMPORT_SYSCONFIG; \
				print (sysconfig.get_python_inc (plat_specific=1));"`
		fi
		if test -n "${python_path}"; then
			if test "${plat_python_path}" != "${python_path}"; then
				python_path="-I$python_path -I$plat_python_path"
			else
				python_path="-I$python_path"
			fi
		fi
		PYTHON_CPPFLAGS=$python_path
	   fi
	   AC_MSG_RESULT([$PYTHON_CPPFLAGS])
	   AC_SUBST([PYTHON_CPPFLAGS])
	   AC_MSG_CHECKING([for Python library path])
	   if test -z "$PYTHON_LIBS"; then
		ac_python_version=`cat<<EOD | $PYTHON -
from sysconfig import *
e = get_config_var('VERSION')
if e is not None:
	print(e)
EOD`
		if test -z "$ac_python_version"; then
			if test -n "$PYTHON_VERSION"; then
				ac_python_version=$PYTHON_VERSION
			else
				ac_python_version=`$PYTHON -c "import sys; \
					print ("%d.%d" % sys.version_info[[:2]])"`
			fi
		fi
		AC_DEFINE_UNQUOTED([HAVE_PYTHON], ["$ac_python_version"],
                                   [If available, contains the Python version number currently in use.])
		ac_python_libdir=`cat<<EOD | $PYTHON -
$IMPORT_SYSCONFIG
e = sysconfig.get_config_var('LIBDIR')
if e is not None:
	print (e)
EOD`
		ac_python_library=`cat<<EOD | $PYTHON -
$IMPORT_SYSCONFIG
c = sysconfig.get_config_vars()
if 'LDVERSION' in c:
	print ('python'+c[['LDVERSION']])
else:
	print ('python'+c[['VERSION']])
EOD`
		if test -n "$ac_python_libdir" -a -n "$ac_python_library"
		then
			ac_python_library=`echo "$ac_python_library" | sed "s/^lib//"`
			PYTHON_LIBS="-L$ac_python_libdir -l$ac_python_library"
		else
			ac_python_libdir=`$PYTHON -c \
			  "from sysconfig import get_python_lib as f; \
			  import os; \
			  print (os.path.join(f(plat_specific=1, standard_lib=1), 'config'));"`
			PYTHON_LIBS="-L$ac_python_libdir -lpython$ac_python_version"
		fi
		if test -z "$PYTHON_LIBS"; then
			AC_MSG_WARN([
  Cannot determine location of your Python DSO. Please check it was installed with
  dynamic libraries enabled, or try setting PYTHON_LIBS by hand.
			])
			if ! $ax_python_devel_optional; then
			   AC_MSG_ERROR([Giving up])
			fi
			ax_python_devel_found=no
			PYTHON_VERSION=""
		fi
	   fi
	fi
	if test $ax_python_devel_found = yes; then
	   AC_MSG_RESULT([$PYTHON_LIBS])
	   AC_SUBST([PYTHON_LIBS])
	   AC_MSG_CHECKING([for Python site-packages path])
	   if test -z "$PYTHON_SITE_PKG"; then
		if test "$IMPORT_SYSCONFIG" = "import sysconfig"; then
			PYTHON_SITE_PKG=`$PYTHON -c "
$IMPORT_SYSCONFIG;
if hasattr(sysconfig, 'get_default_scheme'):
    scheme = sysconfig.get_default_scheme()
else:
    scheme = sysconfig._get_default_scheme()
if scheme == 'posix_local':
    scheme = 'posix_prefix'
prefix = '$prefix'
if prefix == 'NONE':
    prefix = '$ac_default_prefix'
sitedir = sysconfig.get_path('purelib', scheme, vars={'base': prefix})
print(sitedir)"`
		else
			PYTHON_SITE_PKG=`$PYTHON -c "$IMPORT_SYSCONFIG; \
				print (sysconfig.get_python_lib(0,0));"`
		fi
	   fi
	   AC_MSG_RESULT([$PYTHON_SITE_PKG])
	   AC_SUBST([PYTHON_SITE_PKG])
	   AC_MSG_CHECKING([for Python platform specific site-packages path])
	   if test -z "$PYTHON_PLATFORM_SITE_PKG"; then
		if test "$IMPORT_SYSCONFIG" = "import sysconfig"; then
			PYTHON_PLATFORM_SITE_PKG=`$PYTHON -c "
$IMPORT_SYSCONFIG;
if hasattr(sysconfig, 'get_default_scheme'):
    scheme = sysconfig.get_default_scheme()
else:
    scheme = sysconfig._get_default_scheme()
if scheme == 'posix_local':
    scheme = 'posix_prefix'
prefix = '$prefix'
if prefix == 'NONE':
    prefix = '$ac_default_prefix'
sitedir = sysconfig.get_path('platlib', scheme, vars={'platbase': prefix})
print(sitedir)"`
		else
			PYTHON_PLATFORM_SITE_PKG=`$PYTHON -c "$IMPORT_SYSCONFIG; \
				print (sysconfig.get_python_lib(1,0));"`
		fi
	   fi
	   AC_MSG_RESULT([$PYTHON_PLATFORM_SITE_PKG])
	   AC_SUBST([PYTHON_PLATFORM_SITE_PKG])
	   AC_MSG_CHECKING(python extra libraries)
	   if test -z "$PYTHON_EXTRA_LIBS"; then
	      PYTHON_EXTRA_LIBS=`$PYTHON -c "$IMPORT_SYSCONFIG; \
                conf = sysconfig.get_config_var; \
                print (conf('LIBS') + ' ' + conf('SYSLIBS'))"`
	   fi
	   AC_MSG_RESULT([$PYTHON_EXTRA_LIBS])
	   AC_SUBST(PYTHON_EXTRA_LIBS)
	   AC_MSG_CHECKING(python extra linking flags)
	   if test -z "$PYTHON_EXTRA_LDFLAGS"; then
		PYTHON_EXTRA_LDFLAGS=`$PYTHON -c "$IMPORT_SYSCONFIG; \
			conf = sysconfig.get_config_var; \
			print (conf('LINKFORSHARED'))"`
		PYTHON_EXTRA_LDFLAGS=`echo $PYTHON_EXTRA_LDFLAGS | sed 's/CoreFoundation.*$/CoreFoundation/'`
	   fi
	   AC_MSG_RESULT([$PYTHON_EXTRA_LDFLAGS])
	   AC_SUBST(PYTHON_EXTRA_LDFLAGS)
	   AC_MSG_CHECKING([consistency of all components of python development environment])
	   ac_save_LIBS="$LIBS"
	   ac_save_LDFLAGS="$LDFLAGS"
	   ac_save_CPPFLAGS="$CPPFLAGS"
	   LIBS="$ac_save_LIBS $PYTHON_LIBS $PYTHON_EXTRA_LIBS"
	   LDFLAGS="$ac_save_LDFLAGS $PYTHON_EXTRA_LDFLAGS"
	   CPPFLAGS="$ac_save_CPPFLAGS $PYTHON_CPPFLAGS"
	   AC_LANG_PUSH([C])
	   AC_LINK_IFELSE([
		AC_LANG_PROGRAM([[
				[[Py_Initialize();]])
		],[pythonexists=yes],[pythonexists=no])
	   AC_LANG_POP([C])
	   CPPFLAGS="$ac_save_CPPFLAGS"
	   LIBS="$ac_save_LIBS"
	   LDFLAGS="$ac_save_LDFLAGS"
	   AC_MSG_RESULT([$pythonexists])
	   if test ! "x$pythonexists" = "xyes"; then
	      AC_MSG_WARN([
  Could not link test program to Python. Maybe the main Python library has been
  installed in some non-standard library path. If so, pass it to configure,
  via the LIBS environment variable.
  Example: ./configure LIBS="-L/usr/non-standard-path/python/lib"
  ============================================================================
   ERROR!
   You probably have to install the development version of the Python package
   for your distribution.  The exact name of this package varies among them.
  ============================================================================
	      ])
	      if ! $ax_python_devel_optional; then
		 AC_MSG_ERROR([Giving up])
	      fi
	      ax_python_devel_found=no
	      PYTHON_VERSION=""
	   fi
	fi
])
