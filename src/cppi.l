%{ /* -*- C -*- */

/* When output is inhibited, exit with status:
   0 if all's ok
   1 if indentation is wrong
   2 if #if/#endif mismatch
   3 if file error
   */

#ifndef FLEX_SCANNER
# error This scanner must be made using flex, not lex.
#endif

#ifndef __GNUC__
# error This scanner must be compiled with gcc.
#endif

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>
#include <ctype.h>

#include <errno.h>
#ifndef errno
extern int errno;
#endif

#include "fatal.h"

#ifndef EXIT_FAILURE
# define EXIT_FAILURE 1
#endif

#ifndef EXIT_SUCCESS
# define EXIT_SUCCESS 0
#endif

#ifdef MY_DEBUG
# define PUT2(x,y) do { putchar (x); putchar (y); } while (0)
#else
# define PUT2(x,y) /* empty */
#endif

#define STREQ(A,B) (strcmp ((A), (B)) == 0)

#undef YY_DECL
#define YY_DECL static int cpp_i (const char *in_file)

#define INPUT_AND_ECHO()			\
 ({						\
   int _c_ = input ();				\
   if (_c_ != EOF && !inhibit_output)		\
     fputc (_c_, yyout);			\
   _c_;						\
 })

#define MY_ECHO do { if (!inhibit_output) ECHO; } while (0)

#define EMIT_DIR(Tok) emit_indented_cpp (yyout, (Tok), yytext, in_file)

enum eic_type
{
  EIC_IF,
  EIC_IFDEF,
  EIC_IFNDEF,
  EIC_ELSE,
  EIC_ELIF,
  EIC_ENDIF,
  EIC_OTHER
};

static char const *const directive[] =
{
  [EIC_IF]	"if",
  [EIC_IFDEF]	"ifdef",
  [EIC_IFNDEF]	"ifndef",
  [EIC_ELSE]	"else",
  [EIC_ELIF]	"elif",
  [EIC_ENDIF]	"endif",
  [EIC_OTHER]	""
};

static unsigned int lineno = 1;
static unsigned int i_depth = 0;
static int inhibit_output = 0;
static int g_fail = 0;

char *program_name;

int
yywrap (void)
{
  return 1;
  {
  }
}

#define EMIT(T)								\
  do									\
    {									\
      if (inhibit_output)						\
	{								\
	  size_t n;							\
	  if (text[0] == '#'						\
	      && (n = strspn (text + 1, " ")) == i_depth		\
	      && text[1 + n] != ' ')					\
	    {								\
	      ok = 1;							\
	    }								\
	}								\
      else								\
	{								\
	  ok = 1;							\
	  fputc ('#', out);						\
	  assert (i_depth <= MAX_DEPTH);				\
	  blanks[i_depth] = '\0';					\
	  fputs (blanks, out);						\
	  blanks[i_depth] = ' ';					\
	  fputs (directive[T], out);					\
	}								\
    }									\
  while (0)

static void
emit_indented_cpp (FILE *out, enum eic_type t, char const *text,
		   char const *in_file)
{
#define MAX_DEPTH 40
  static char blanks[] = { [0 ... MAX_DEPTH] = ' ' };
  int ok = 0;

  switch (t)
    {
    case EIC_IF:
    case EIC_IFDEF:
    case EIC_IFNDEF:
      EMIT (t);
      ++i_depth;
      break;

    case EIC_ELSE:
    case EIC_ELIF:
      --i_depth;
      EMIT (t);
      ++i_depth;
      break;

    case EIC_ENDIF:
      --i_depth;
      EMIT (t);
      break;

    case EIC_OTHER:
      EMIT (t);
      break;

    default:
      abort ();
    }

  if (!ok)
    {
      g_fail = 1;
      warn (0, "%s: %s: line %d: not properly indented",
	    program_name, in_file, lineno);
    }
}

%}

w [^/ \t\n]
b [^a-zA-Z_\n]

%%

"/*"        {
  register int c;
  int start_lineno = lineno;

  PUT2 ('[', '\0');
  MY_ECHO;
  for ( ; ; )
    {
      while ((c = INPUT_AND_ECHO ()) != '*' && c != EOF)
	{
	  if (c == '\n')
	    ++lineno;
	}

      if (c == '*')
	{
	  while ((c = INPUT_AND_ECHO ()) == '*')
	    ;
	  if (c == '/')
	    break;    /* found the end */
	}

      if (c == EOF)
	{
	  fatal (2, 0, "%s: %s: line %d: EOF in comment",
		 program_name, in_file, start_lineno);
	  break;
	}
    }
  PUT2 ('\0', ']');
}

"'\"'" {
  /* We need this rule so that the double quote in the character literal,
     '"', is not interpreted as the string opener.  */
  MY_ECHO;
}

"\"" {
  register int c;
  int start_lineno = lineno;

  /* Count consecutive backslashes.  We'll need this number when
     a string of them immediately precedes a double quote.  */
  int n_backslashes = 0;

  PUT2 ('[', '\0');
  MY_ECHO;

  while (1)
    {
      c = INPUT_AND_ECHO ();

      if (c == EOF)
	{
	  fatal (2, 0, "%s: %s: line %d: EOF in string",
		 program_name, in_file, start_lineno);
	}

      /* If the number of preceding backslashes is even, then this is
	 an unescaped double quote, and it marks the end of the string.  */
      if (c == '"' && n_backslashes % 2 == 0)
	break;

      n_backslashes = (c == '\\' ? n_backslashes + 1 : 0);
      if (c == '\n')
	++lineno;
    }
  PUT2 ('\0', ']');
}

^[ \t]*#[ \t]*if/[ \t]    { EMIT_DIR (EIC_IF); }
^[ \t]*#[ \t]*ifdef/[ \t] { EMIT_DIR (EIC_IFDEF); }
^[ \t]*#[ \t]*ifndef/[ \t] {EMIT_DIR (EIC_IFNDEF); }

^[ \t]*#[ \t]*elif/[ \t]  { EMIT_DIR (EIC_ELIF); }
^[ \t]*#[ \t]*else{w}     { MY_ECHO; }
^[ \t]*#[ \t]*else/{b}    { EMIT_DIR (EIC_ELSE); }
^[ \t]*#[ \t]*else$       { EMIT_DIR (EIC_ELSE); }

^[ \t]*#[ \t]*endif{w}    { MY_ECHO; }
^[ \t]*#[ \t]*endif/{b}   { EMIT_DIR (EIC_ENDIF); }
^[ \t]*#[ \t]*endif$      { EMIT_DIR (EIC_ENDIF); }
^[ \t]*#[ \t]*endif       { EMIT_DIR (EIC_ENDIF); }

^[ \t]*#                  { EMIT_DIR (EIC_OTHER); }

\n                        { MY_ECHO; ++lineno; }
.                         { MY_ECHO; }

<<EOF>> {
  /* FIXME */

  if (i_depth != 0)
    {
      warn (0, "%s: %s: unterminated #if, #ifdef, or #ifndef",
	    program_name, in_file);
    }

  return g_fail;
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
	fatal (3, errno, "%s: %s", program_name, in_file);
      yyin = in;
    }

  fail = cpp_i (in_file);

  if (in && fclose (in) == EOF)
    fatal (3, errno, "%s: %s", program_name, in_file);

  return fail;
}

int
main (int argc, char** argv)
{
  int i;
  int fail;

  program_name = argv[0];

  if (argc >= 2 && STREQ (argv[1], "-c"))
    {
      inhibit_output = 1;
      ++argv;
      --argc;
    }

  if (!inhibit_output && argc > 2)
    {
      fprintf (stderr, "\
Usage: %s [FILE]\n\
  or:  %s [-c] [FILE]...", program_name, program_name);
      exit (1);
    }

  fail = 0;
  for (i = 1; i < argc; i++)
    {
      char *in = (argc == 1 ? "-" : argv[i]);
      int err = cpp_indent (in);
      if (err > fail)
	fail = err;
    }

  if (fclose (stdout) == EOF)
    fatal (3, errno, "%s: write error", program_name);

  exit (fail);
}