#include <stdio.h>
#include "../parser.h"

#define ABS(x) ((x)>0?(x):-(x))
#define EQUAL(a,b) (ABS(a-b)<.00001)

int main() {
  Parser *p = parserNew (5, 3);
  parserSetRule (p, 0, 1, 0, 0, 1);
  parserSetRule (p, 1, 3, 2, 0, 1);
  parserSetRule (p, 2, 4, 3, 1, 1);
  parserSetEmptyProb (p, 1, 1);
  parserSetEmptyProb (p, 0, 1);
  parserFinalizeRules (p);
  parserPushTok (p, 2);
  /*
    parserPrintMatrix (p);
  */
  double pf = parserGetP (p, 0, 1, 4);
  double qf = parserGetQ (p, 0, 4);
  printf ("1..1\n");
  if (EQUAL(pf,1.) && EQUAL(qf,0.))
    printf ("ok 1 - C parser test\n");
  else
    printf ("not ok 1 - C parser test (final p=%g, final q=%g)\n", pf, qf);

  parserDelete (p);

  return 0;
}

