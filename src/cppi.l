/* flex-lexer for cppi
   Copyright (C) 1997-2017 Free Software Foundation, Inc.

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.  */

%option noyywrap
%top{
/* config.h must precede flex's inclusion of <stdio.h>
   in order for its _GNU_SOURCE definition to take effect.  */
#include "config.h"
#include "system.h"
}

%{

/* When output is inhibited, exit with status:
   0 if all's ok
   1 if indentation is wrong, or if text follows #else/#endif
   2 if #if/#endif mismatch
   3 if file error
   */

#ifndef FLEX_SCANNER
# error This scanner must be made using flex, not lex.
#endif

#include <assert.h>

#include <sys/types.h>
#include <getopt.h>

#define _(msgid) gettext (msgid)
#define N_(msgid) msgid

#include "cpp.h"
#include "error.h"
#include "obstack.h"
#include "xstrtol.h"

/* The official name of this program (e.g., no `g' prefix).  */
#define PROGRAM_NAME "cppi"

#define AUTHORS "Jim Meyering"

#define obstack_chunk_alloc malloc
#define obstack_chunk_free free

#ifdef MY_DEBUG
# define PUT2(x,y) do { putchar (x); putchar (y); } while (0)
#else
# define PUT2(x,y) /* empty */
#endif

#undef YY_DECL
#define YY_DECL static int cpp_i (const char *in_file)

#undef isblank
#define isblank(c) ((c) == ' ' || (c) == '\t')

#define MY_ECHO do { if (!inhibit_output) ECHO; } while (0)

#define OPENER_STACK_HEIGHT \
  (obstack_object_size (&opener_stack) / sizeof (struct KL_pair))

/* An entry on the stack of opener (keyword/line_number) specs.  */
struct KL_pair
{
  /* The type of cpp directive opening a block: one of
     EIC_IF, EIC_IFDEF, EIC_IFNDEF.  */
  enum Eic_type opener_type;

  /* The line number of the directive.  */
  unsigned int line_number;
};

enum
{
  EXIT_NOT_PROPERLY_INDENTED = 1,
  EXIT_STRING_TOO_LONG = 1,
  EXIT_LEX_ERROR = 2,
  EXIT_FILE_ERROR = 3
};

/* A stack of cpp-opener-directive-spec/line-number pairs.
   This lets us report the line numbers of any unmatched #if,
   #ifdef, or #ifndef directives.  */
static struct obstack opener_stack;

/* Current nesting level.  */
static int i_depth;

/* Initial indentation nesting depth.  May be negative.
   Use a value of -1 to cause code (usually header files) to be indented
   one level less than otherwise.  This is useful if you don't want file-
   enclosing ifdefs (e.g., #ifdef FOO_H/#define FOO_H/ ... #endif) to
   cause every enclosed cpp directive to have at least one space between
   the `#' and the cpp keyword.  */
static int initial_i_depth;

/* Nonzero means don't generate diagnostics about indentation, and print
   to stdout only the names of files that aren't properly indented.  */
static int list_files_only;

/* Set to non-zero to enable ANSI-conformance check
   (text after #else or #endif is non-ANSI).  */
static int ansi_check = 0;

/* Set to non-zero to inhibit non-error output.  */
static int inhibit_output = 0;

/* The maximum length of a double-quoted string.  Set to zero
   to indicate there is no limit.  */
static unsigned long int max_string_length = 0;

static char *default_file_list[] = {(char *) "-", NULL};

static struct option const long_options[] =
{
  {"ansi", no_argument, NULL, 'a'},
  {"check", no_argument, NULL, 'c'},
  {"list-files-only", no_argument, NULL, 'l'},
  {"max-string-length", required_argument, NULL, 'm'},
  {GETOPT_HELP_OPTION_DECL},
  {GETOPT_VERSION_OPTION_DECL},
  {NULL, 0, NULL, 0}
};

static void gobble_define (unsigned int *);
static void gobble_c_comment (const char *, unsigned int *);
static void gobble_line (unsigned int *);

/* Include gperf-generated hash function.  */
#include "cpp-cond.c"

#if __GNUC__ && ! __STRICT_ANSI__
/* this use of a statement-expression works only with gcc.  */
# define INPUT_AND_ECHO()			\
 ({						\
   int _c_ = input ();				\
   if (_c_ != EOF && !inhibit_output)		\
     fputc (_c_, yyout);			\
   _c_;						\
 })
#else
/* Although the above is a macro, this function definition must
   follow the declaration of inhibit_output, above.  */
static int input (void);
static int
INPUT_AND_ECHO (void)
{
  int _c_ = input ();
  if (_c_ != EOF && !inhibit_output)
    fputc (_c_, yyout);
  return _c_;
}
#endif

/* PREFIX is the cpp line from beginning of line to end of the keyword
   following the `#'.  */

static enum Eic_type
lookup_cpp_keyword (const char *prefix, size_t len, const char **kw)
{
  /* Find the beginning of the keyword.  */
  const char *p;
  for (p = prefix; ; ++p, --len)
    {
      switch (*p)
        {
        case '#':
        case ' ':
        case '\t':
          break;

        default:
          {
            struct KW const *ent = cpp_cond_lookup (p, len);
            *kw = p;
            return (ent ? ent->code : EIC_OTHER);
          }
        }
      assert (len > 0);
    }
}

static inline struct KL_pair
kth_entry (unsigned int k)
{
  struct KL_pair *s = (struct KL_pair *) obstack_base (&opener_stack);
  assert (k < OPENER_STACK_HEIGHT);
  return s[k];
}

static inline void
pop (void)
{
  int pair_size = sizeof (struct KL_pair);
  assert (OPENER_STACK_HEIGHT > 0);
  obstack_blank_fast (&opener_stack, -pair_size);
}

static inline void
push (enum Eic_type opener_type, unsigned int line_number)
{
  struct KL_pair pair;
  pair.opener_type = opener_type;
  pair.line_number = line_number;

  obstack_grow (&opener_stack, &pair, sizeof (struct KL_pair));
}

static int
emit_or_check (enum Eic_type type, const char *text, const char *other)
{
  int fail = 1;

  if (inhibit_output)
    {
      int n;
      int depth = (i_depth < 0 ? 0 : i_depth);
      if ((text[0] == '#'
           && (n = strspn (text + 1, " ")) == depth
           && !isblank (text[1 + n]))
          /* This allows pragmas to have exactly one space before the `#'.
             E.g., ` #pragma alloca' or ` #  pragma alloca' .  */
          || (text[0] == ' '
              && text[1] == '#'
              && type == EIC_PRAGMA
              && (n = strspn (text + 2, " ")) == depth - 1
              && text[n + 2] == 'p'))
        {
          fail = 0;
        }
    }
  else
    {
      int i;
      const char *dir = (type == EIC_OTHER ? other : directive[type]);
      int space_first = (type == EIC_PRAGMA && text[0] == ' ');

      if (space_first)
        {
          fputc (' ', yyout);
          fputc ('#', yyout);
          for (i = 0; i < i_depth - 1; i++)
            fputc (' ', yyout);
        }
      else
        {
          fputc ('#', yyout);
          for (i = 0; i < i_depth; i++)
            fputc (' ', yyout);
        }

      fputs (dir, yyout);

      fail = 0;
    }

  return fail;
}

static enum Eic_type
emit_indented_cpp (char const *in_file, unsigned int line_number,
                   char const *text, size_t len, int *fail)
{
  const char *keyword;
  enum Eic_type t = lookup_cpp_keyword (text, len, &keyword);

  *fail = 0;

  switch (t)
    {
    case EIC_IF:
    case EIC_IFDEF:
    case EIC_IFNDEF:
      /* Maintain a stack of (keyword, line number) pairs to better
         report any `unterminated #if...' errors.  Put a new pair
         on the stack.  */
      push (t, line_number);

      *fail = emit_or_check (t, yytext, keyword);
      ++i_depth;
      break;

    case EIC_ELSE:
    case EIC_ELIF:
      if (i_depth <= initial_i_depth)
        {
          if (!list_files_only)
            {
              error (0, 0, _("%s: line %d: found #%s without matching #if"),
                     in_file, line_number, directive[t]);
            }
          i_depth = 0;
          emit_or_check (t, yytext, keyword);
          *fail = 2;
        }
      else
        {
          --i_depth;
          *fail = emit_or_check (t, yytext, keyword);
          ++i_depth;
        }
      break;

    case EIC_ENDIF:
      if (i_depth <= initial_i_depth)
        {
          if (!list_files_only)
            {
              error (0, 0, _("%s: line %d: found #%s without matching #if"),
                     in_file, line_number, directive[t]);
            }
          i_depth = initial_i_depth + 1;
          *fail = 2;
        }
      else
        {
          /* We've just found an #endif.  Pop off and discard the
             keyword,line-number pair that's on the top of the stack.
             That pair identifies the matching #if, #ifdef, or #ifndef.  */
          pop ();
        }

      --i_depth;
      {
        int tf = emit_or_check (t, yytext, keyword);
        if (tf > *fail)
          *fail = tf;
      }
      break;

    case EIC_PRAGMA:
    case EIC_DEFINE:
    case EIC_OTHER:
      *fail = emit_or_check (t, yytext, keyword);
      break;

    case EIC_INVALID:
    default:
      abort ();
    }

  if (*fail == EXIT_NOT_PROPERLY_INDENTED)
    {
      if (!list_files_only)
        error (0, 0, _("%s: line %d: not properly indented"),
               in_file, line_number);
    }

  return t;
}

%}

w [a-zA-Z_]
b [^a-zA-Z_\n]

%%

%{
  /* This section contains dcls and code that is local to the
     scanning routine.  */

  /* Current line number -- for diagnostics and errors.  */
  unsigned int lineno = 1;

  int lex_fail = 0;

  obstack_init (&opener_stack);

  initial_i_depth = 0;
  i_depth = initial_i_depth;

%}

"/*"        {
  PUT2 ('[', '\0');
  MY_ECHO;
  gobble_c_comment (in_file, &lineno);
  PUT2 ('\0', ']');
}

"//"        {
  MY_ECHO;
  gobble_line (&lineno);
}

"'"\\?"\"'" {
  /* We need this rule so that the double quote in the character literal,
     '"' (also written as '\"'), is not interpreted as a string opener.  */
  MY_ECHO;
}

"'\\"/"\"" {
  /* This rule is included to make flex's scanner more efficient
     by avoiding backup states.  */
  MY_ECHO;
}
"'\\"    { /* Likewise.  */ MY_ECHO;}
"'"/"\"" { /* Likewise.  */ MY_ECHO; }

"\"" {
  register int c;
  int start_lineno = lineno;

  /* Count consecutive backslashes.  We'll need this number when
     a string of them immediately precedes a double quote.  */
  size_t n_backslashes = 0;
  size_t string_length = 0;
  int fail = 0;

  PUT2 ('[', '\0');
  MY_ECHO;

  while (1)
    {
      c = INPUT_AND_ECHO ();

      if (c == EOF)
        {
          error (0, 0, _("%s: line %d: EOF in string"),
                 in_file, start_lineno);
          fail = EXIT_LEX_ERROR;
          break;
        }

      /* If the number of preceding backslashes is even, then this is
         an unescaped double quote, and it marks the end of the string.  */
      if (c == '"' && n_backslashes % 2 == 0)
        break;

      n_backslashes = (c == '\\' ? n_backslashes + 1 : 0);

      /* Some compilers (irix4's cc) impose a limit on the length of a
         double quoted string.  It's probably a limit on the length of
         the actual value of the string, rather than on the number of
         bytes between `"'s in the source, but I'm not sure it's worth
         the trouble of computing the former.  */
      ++string_length;

      if (c == '\n')
        ++lineno;
    }

  PUT2 ('\0', ']');

  if (0 < max_string_length && max_string_length < string_length)
    {
      error (0, 0, _("%s: line %d: string (%lu) longer than maximum of %lu"),
             in_file, start_lineno, (unsigned long) string_length,
             (unsigned long) max_string_length);
      if (fail == 0)
        lex_fail = EXIT_STRING_TOO_LONG;
    }

  if (fail)
    lex_fail = 1;
}

^[ \t]*#[ \t]*[a-zA-Z0-9_]+   {
  enum Eic_type t;
  int fail;

  t = emit_indented_cpp (in_file, lineno, yytext, yyleng, &fail);

  if (t == EIC_IF || t == EIC_IFNDEF || t == EIC_ELIF || t == EIC_DEFINE)
    {
      int c;
      if (inhibit_output)
        {
          /* Make sure there's exactly one space after this directive.  */
          c = input ();
          if (c != ' ' || ((c = input ()) == ' ' || c == '\t' || c == EOF))
            {
              if (!list_files_only)
                {
                  error (0, 0, _("%s: line %d: not properly formatted;\n\
there must be exactly one SPACE character after each\n\
#if, #elif, and #define directive"),
                         in_file, lineno);
                }
              if (fail < 1)
                fail = 1;
            }
        }
      else
        {
          /* Squeeze multiple spaces and tabs after an #if or #elif
             directive to a single space.  */
          fputc (' ', yyout);
          while ((c = input ()) == ' ' || c == '\t')
            {
              /* empty */
            }
        }
      unput (c);
      if (t == EIC_DEFINE)
        {
          gobble_define (&lineno);
        }
    }
  else if (ansi_check && (t == EIC_ELSE || t == EIC_ENDIF))
    {
      /* If requested, make sure there's nothing after an #else or #endif.  */
      int found_non_ansi = 0;
      int cpp_directive_lineno = lineno;
      int c;
      while ((c = INPUT_AND_ECHO ()) != EOF)
        {
          if (isblank (c))
            continue;
          if (c == '/')
            {
              c = INPUT_AND_ECHO ();
              if (c == EOF)
                break;
              if (c == '*')
                {
                  gobble_c_comment (in_file, &lineno);
                  continue;
                }
              if (c == '/')
                {
                  gobble_line (&lineno);
                  break;
                }

              /* else, fall through to next if-stmt */
            }

          if (c == '\n')
            {
              ++lineno;
              break;
            }

          /* We've found a token after an #else or #endif.
             Continue reading to end of line.  */
          found_non_ansi = 1;
        }

      if (found_non_ansi)
        {
          if (!list_files_only)
            error (0, 0,
              _("%s: line %d: text following `#%s' violates ANSI standard"),
                   in_file, cpp_directive_lineno,
                   (t == EIC_ELSE ? "else" : "endif"));
          if (fail < 1)
            fail = 1;
        }
    }

  if (fail > lex_fail)
    lex_fail = fail;
}
^[ \t]*#[ \t]*            { MY_ECHO; }
^[ \t]*                   { MY_ECHO; }

\n                        { MY_ECHO; ++lineno; }
.                         { MY_ECHO; }

<<EOF>> {
  if (i_depth != initial_i_depth)
    {
      if (!list_files_only)
        {
          /* Iterate the opener stack from bottom to top, giving a
             diagnostic per unterminated #if* directive.
             Torture this code with a command like this:
             $ yes '#if FOO' |head -600 |cppi -c */
          unsigned int i;
          for (i = 0; i < OPENER_STACK_HEIGHT; i++)
            {
              struct KL_pair x = kth_entry (i);
              error (0, 0, _("%s: line %d: unterminated #%s"),
                     in_file, x.line_number, directive[x.opener_type]);
            }
        }

      lex_fail = EXIT_LEX_ERROR;
    }

  return lex_fail;
}

%%

static int
cpp_indent (const char *in_file)
{
  FILE *in = NULL;
  int fail;

  if (STREQ (in_file, "-"))
    {
      yyin = stdin;
      in_file = "standard input";
    }
  else
    {
      if ((in = fopen (in_file, "r")) == NULL)
        {
          error (EXIT_FILE_ERROR, errno, "%s", in_file);
        }
      yyin = in;
    }

  fail = cpp_i (in_file);

  obstack_free (&opener_stack, NULL);

  if (in && fclose (in) == EOF)
    error (EXIT_FILE_ERROR, errno, "%s", in_file);

  return fail;
}

static void usage (int status) ATTRIBUTE_NORETURN;
static void
usage (int status)
{
  if (status != 0)
    {
      fprintf (stderr, "Try `%s --help' for more information.\n",
               program_name);
    }
  else
    {
      printf (_("\
Usage: %s [FILE]\n\
  or:  %s -c [OPTION] [FILE]...\n\
"), program_name, program_name);
      fputs (_("\
\n\
Indent the C preprocessor directives in FILE to reflect their nesting\n\
and ensure that there is exactly one space character between each #if,\n\
#elif, #define directive and the following token, and write the result\n\
"), stdout);
      fputs (_("\
to standard output.  The number of spaces between the `#' and the following\n\
directive must correspond to the level of nesting of that directive.\n\
With no FILE, or when FILE is -, read standard input.\n\
"), stdout);
      fputs (_("\
\n\
  -a, --ansi             when checking, fail if text follows #else or #endif\n\
  -c, --check            set exit code, but don't produce any output\n\
  -l, --list-files-only  don't generate diagnostics about indentation;\n\
                         print to stdout only the names of files that\n\
                         are not properly indented\n\
"), stdout);
      fputs (_("\
  -m, --max-string-length=LENGTH\n\
                         fail if there is a double-quoted string longer\n\
                         than LENGTH;  if LENGTH is 0 (the default),\n\
                         then there is no limit\n\
"), stdout);
      fputs (HELP_OPTION_DESCRIPTION, stdout);
      fputs (VERSION_OPTION_DESCRIPTION, stdout);
      fputs (_("\n\
With the -c option, don't write to stdout.  Instead, check the\n\
indentation of the specified files giving diagnostics for preprocessor\n\
lines that aren't properly indented or are otherwise invalid.\n\
"), stdout);
      fputs (_("\
\n\
Note that --ansi without --check does not correct the problem of\n\
non-ANSI text following #else and #endif directives.\n\
"), stdout);
      fputs (_("\
\n\
The exit code will be one of these:\n\
  0  all directives properly indented\n\
  1  some cpp directive(s) improperly indented, or\n\
     text follows #else/#endif (enabled with --check --ansi), or\n\
     a double-quoted string is longer than the specified maximum\n\
  2  #if/#endif mismatch, EOF in comment or string\n\
  3  file (e.g. open/read/write) error\n\
"), stdout);
      fputs (_("\
\n\
A pragma directive may have its `#' indented.\n\
"), stdout);
      printf (_("\nReport bugs to <%s>.\n"), PACKAGE_BUGREPORT);
    }
  exit (status == 0 ? EXIT_SUCCESS : EXIT_FAILURE);
}

/* Read the body of a #define directive (echoing or not, as appropriate).
   That is, read up to and including the first unescaped newline (or EOF).
   This is necessary because otherwise, we could mistakenly interpret the
   stringification of a macro argument as a cpp directive.  */

static void
gobble_define (unsigned int *line_number)
{
  int c;
  int backslash_count = 0;
  while ((c = INPUT_AND_ECHO ()) != EOF)
    {
      if (c == '\n')
        {
          ++(*line_number);
          if (backslash_count % 2 == 0)
            break;
        }

      if (c == '\\')
        ++backslash_count;
      else
        backslash_count = 0;
    }
}

/* We've read the C comment opener.  Read up to and including
   the closing delimiter.  */

static void
gobble_c_comment (const char *in_file, unsigned int *line_number)
{
  int start_lineno = *line_number;
  for ( ; ; )
    {
      int c;
      while ((c = INPUT_AND_ECHO ()) != '*' && c != EOF)
        {
          if (c == '\n')
            ++(*line_number);
        }

      if (c == '*')
        {
          while ((c = INPUT_AND_ECHO ()) == '*')
            ;
          if (c == '/')
            break;    /* found the end */
          if (c == '\n')
            ++(*line_number);
        }

      if (c == EOF)
        {
          error (EXIT_LEX_ERROR, 0, _("%s: line %d: EOF in comment"),
                 in_file, start_lineno);
          break;
        }
    }
}

/* Read up to and including any newline.  */

static void
gobble_line (unsigned int *line_number)
{
  int c;
  while ((c = INPUT_AND_ECHO ()) != EOF)
    {
      if (c == '\n')
        {
          ++(*line_number);
          break;
        }
    }
}

int
main (int argc, char **argv)
{
  int i;
  int max_err;
  char **file_list;
  int c;
  int fail = 0;

  set_program_name (argv[0]);
  setlocale (LC_ALL, "");
  bindtextdomain (PACKAGE, LOCALEDIR);
  textdomain (PACKAGE);

  atexit (close_stdout);

  while ((c = getopt_long (argc, argv, "aclm:", long_options, NULL)) != -1)
    {
      switch (c)
        {
        case 0:
          break;

        case 'a':
          ansi_check = 1;
          break;

        case 'c':
          inhibit_output = 1;
          break;

        case 'l':
          inhibit_output = 1;
          list_files_only = 1;
          break;

        case 'm':
          if (xstrtoul (optarg, NULL, 0, &max_string_length, NULL)
              != LONGINT_OK)
            {
              error (0, 0, _("invalid maximum string length %s"), optarg);
              fail = 1;
            }
          break;

        case_GETOPT_HELP_CHAR;

        case_GETOPT_VERSION_CHAR (PROGRAM_NAME, AUTHORS);

        default:
          usage (EXIT_LEX_ERROR);
          break;
        }
    }

  if (fail)
    exit (EXIT_FAILURE);

  if (!inhibit_output && argc - optind > 2)
    {
      error (0, 0, _("too many arguments"));
      usage (EXIT_FAILURE);
    }

  file_list = (optind == argc ? default_file_list : argv + optind);

  max_err = 0;
  for (i = 0; file_list[i]; i++)
    {
      int err;

      err = cpp_indent (file_list[i]);
      if (err > max_err)
        max_err = err;

      if (err && list_files_only)
        puts (file_list[i]);
    }

  exit (max_err);
}

/*
  Local Variables:
  mode: c
  End:
*/
