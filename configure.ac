dnl Process this file with autoconf to produce a configure script. -*-m4-*-
AC_INIT(cppi.l)
AM_CONFIG_HEADER(config.h)
AC_PREREQ(2.13)dnl               dnl Minimum Autoconf version required.
AC_CANONICAL_HOST

AM_INIT_AUTOMAKE([cppi], [1.11])

dnl Checks for programs.

AC_PROG_CC
AC_PROG_CPP
AC_AIX
AC_MINIX
AC_PROG_GCC_TRADITIONAL
AC_PROG_RANLIB
AM_PROG_LEX
AC_PROG_CC_STDC

dnl Checks for header files.
AC_CHECK_HEADERS(memory.h stdlib.h string.h unistd.h)
AC_HEADER_STDC

dnl This test must precede tests of compiler characteristics like
dnl that for the inline keyword, since it may change the degree to
dnl which the compiler supports such features.
AM_C_PROTOTYPES

dnl Checks for typedefs, structures, and compiler characteristics.
AC_C_CONST
AC_C_INLINE
AC_TYPE_SIZE_T

dnl This test replaces the obsolescent AC_ISC_POSIX kludge.
AC_CHECK_LIB(cposix, strerror, [LIBS="$LIBS -lcposix"])

dnl Checks for library functions.
AC_CHECK_FUNCS(strerror)

jm_AC_PREREQ_XSTRTOUMAX
jm_ASSERT

AC_CONFIG_FILES([Makefile m4/Makefile tests/Makefile])
AC_OUTPUT