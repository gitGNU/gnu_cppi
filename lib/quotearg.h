/* quotearg.h - quote arguments for output
   Copyright (C) 1998 Free Software Foundation, Inc.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2, or (at your option)
   any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software Foundation,
   Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.  */

/* Written by Paul Eggert <eggert@twinsun.com> */

/* Basic quoting styles.  */
enum quoting_style
  {
    literal_quoting_style,	/* --quoting-style=literal */
    shell_quoting_style,	/* --quoting-style=shell */
    shell_always_quoting_style,	/* --quoting-style=shell-always */
    c_quoting_style,		/* --quoting-style=c */
    escape_quoting_style	/* --quoting-style=escape */
  };

/* For now, --quoting-style=literal is the default, but
   this is planned to change to --quoting-style=shell in the future.  */
#ifndef DEFAULT_QUOTING_STYLE
# define DEFAULT_QUOTING_STYLE literal_quoting_style
#endif

/* Names of quoting styles.  */
extern char const *const quoting_style_args[];

struct quoting_options;

#ifndef PARAMS
# if defined PROTOTYPES || (defined __STDC__ && __STDC__)
#  define PARAMS(Args) Args
# else
#  define PARAMS(Args) ()
# endif
#endif

/* Allocate a new set of quoting options, with contents initially identical
   to O if O is not null, or to a default value if O is null.
   It is the caller's responsibility to free the result.  */
struct quoting_options *clone_quoting_options
   PARAMS ((struct quoting_options *o));

/* Get the value of O's quoting style.  */
enum quoting_style get_quoting_style PARAMS ((struct quoting_options *o));

/* In O, set the value of the quoting style to S.  */
void set_quoting_style PARAMS ((struct quoting_options *o,
				enum quoting_style s));

/* In O, set the value of the quoting options for character C to I.
   Return the old value.  Currently, the only values defined for I are
   0 (the default) and 1 (which means to quote the character even if
   it would not otherwise be quoted).  */
int set_char_quoting PARAMS ((struct quoting_options *o, char c, int i));

/* Place into buffer BUF (of size BUFSIZE) a quoted version of
   argument ARG (of size ARGSIZE), using O to control quoting.
   Terminate the output with a null character, and return the written
   size of the output, not counting the terminating null.
   If BUFSIZE is too small to store the output string, return the
   value that would have been returned had BUFSIZE been large enough.
   If ARGSIZE is -1, use the string length of the argument for ARGSIZE.  */
size_t quotearg_buffer PARAMS ((char *buf, size_t bufsize,
				char const *arg, size_t argsize,
				struct quoting_options const *o));

/* The quoting options used by the convenience functions listed below.  */

extern struct quoting_options quotearg_quoting_options;

/* Use storage slot N to return a quoted version of the string ARG.
   The variable quotearg_quoting_options specifies the quoting options.
   The returned value points to static storage that can be
   reused by the next call to this function with the same value of N.
   N must be nonnegative.  */
char *quotearg_n PARAMS ((int n, char const *arg));

/* Equivalent to quotearg_n (ARG, 0).  */
char *quotearg PARAMS ((char const *arg));

/* Like quotearg (ARG), except also quote any instances of CH.  */
char *quotearg_char PARAMS ((char const *arg, char ch));

/* Equivalent to quotearg_char (ARG, ':').  */
char *quotearg_colon PARAMS ((char const *arg));