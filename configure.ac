AC_INIT([checkwiki], [2013-02-15], [tim@tim-landscheidt.de])
AC_CONFIG_AUX_DIR([build-aux])
AC_CONFIG_MACRO_DIR([m4])

AM_INIT_AUTOMAKE([foreign no-dist color-tests parallel-tests silent-rules -Wall])
AC_PROG_INSTALL

AX_PROG_PERL_MODULES([CGI DBI Encode Getopt::Long LWP::UserAgent URI::Escape],
                     [],
                     [AC_MSG_ERROR(Perl module requirements unfulfilled)])

# Directories.
AC_ARG_WITH([cgibindir],
            AS_HELP_STRING([--with-cgibindir=DIR],
                           [Install CGI executables in DIR]),
            [CGIBINDIR=${withval}],
            [CGIBINDIR=${HOME}/cgi-bin])
AC_SUBST([cgibindir], [$CGIBINDIR])

AC_CONFIG_FILES([Makefile
                 cgi-bin/Makefile])

AC_OUTPUT
