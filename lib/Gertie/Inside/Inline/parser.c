#include <stdlib.h>
#include <stdio.h>
#include "parser.h"

/* util functions */
void * SafeMalloc(size_t size) {
  void * result;

  if ( (result = malloc(size)) ) { /* assignment intentional */
    return(result);
  } else {
    printf("memory overflow: malloc failed in SafeMalloc.");
    printf("  Exiting Program.\n");
    exit(-1);
  }
  return(0);
}

void *SafeCalloc(size_t count, size_t size) {
  void * result;

  if ( (result = calloc(count,size)) ) { /* assignment intentional */
    return(result);
  } else {
    printf("memory overflow: calloc failed in SafeCalloc.");
    printf("  Exiting Program.\n");
    exit(-1);
  }
  return(0);
}

#define SafeFree(PTR) free(PTR)


/* parser */
#define cell_get_p(cell,i,j,sym) cell->p[sym * (j + 1) + i]
#define cell_get_q(cell,i,j,sym) cell->q[sym * (j + 1) + i]

#define cell_inc_p(cell,i,j,sym,inc) cell_get_p(cell,i,j,sym) += inc
#define cell_inc_q(cell,i,j,sym,inc) cell_get_q(cell,i,j,sym) += inc

#define parser_get_p(parser,i,j,sym) cell_get_p (parser->cell[j], i, j, sym)
#define parser_get_q(parser,i,sym) cell_get_q (parser->cell[parser->len], i, parser->len, sym)

Cell* cellNew (Parser *parser, int j) {
  Cell *cell;
  int sym;
  cell = SafeMalloc (sizeof (Cell));
  cell->p = SafeMalloc (sizeof (double) * parser->symbols * (j+1));
  cell->q = SafeMalloc (sizeof (double) * parser->symbols * (j+1));
  for (sym = 0; sym < parser->symbols; ++sym) {
    cell_get_p(cell,j,j,sym) = parser->p_empty[sym];
    cell_get_q(cell,j,j,sym) = 1. - parser->p_empty[sym];
  }
}

Cell* cellNewTok (Parser *parser, int j, int tok) {
  Cell *cell;
  cell = cellNew (parser, j);
  cell_get_p (cell, j-1, j, tok) = 1.;
}

void cellDelete (Cell* cell) {
  SafeFree (cell->p);
  SafeFree (cell->q);
  SafeFree (cell);
}

Parser* parserNew (int symbols, int rules) {
  Parser* parser;
  parser = SafeMalloc (sizeof (Parser));
  parser->symbols = symbols;
  parser->rules = rules;
  parser->len = 0;
  parser->alloc = 1;
  parser->rule = SafeMalloc (rules * sizeof (Rule));
  parser->p_empty = SafeMalloc (symbols * sizeof (double));
  parser->cell = SafeMalloc (sizeof (Cell*));
  parser->tokseq = NULL;
  parser->cell[0] = cellNew (parser, 0);
  return parser;
}

void parserDelete (Parser* parser) {
  int n;
  for (n = 0; n < parser->alloc; ++n)
    SafeFree (parser->cell[n]);
  if (parser->tokseq)
    SafeFree (parser->tokseq);
  SafeFree (parser->rule);
  SafeFree (parser->p_empty);
}

void parserSetRule (Parser *parser, int rule_index, int lhs_sym, int rhs1_sym, int rhs2_sym, double rule_prob) { 
  Rule *rule;
  rule = parser->rule + rule_index;
  rule->lhs_sym = lhs_sym;
  rule->rhs1_sym = rhs1_sym;
  rule->rhs2_sym = rhs2_sym;
  rule->rule_prob = rule_prob;
}

void parserSetEmptyProb (Parser *parser, int sym, double p) { parser->p_empty[sym] = p; }
int parserSeqLen (Parser *parser) { return parser->len; }

double parserGetP (Parser *parser, int i, int j, int sym) { return parser_get_p(parser,i,j,sym); }
double parserGetQ (Parser *parser, int i, int sym) { return parser_get_q(parser,i,sym); }

void parserPushTok (Parser *parser, int tok) {
  int old_len, j, i, k, r;
  Cell *j_cell, **new_cell;
  int *new_tokseq;
  Rule *rule, *rule_end;

  old_len = parser->len;
  j = old_len + 1;
  if (j >= parser->alloc) {
    parser->alloc *= 2;
    new_cell = SafeMalloc (parser->alloc * sizeof(Cell) + 1);
    new_tokseq = SafeMalloc (parser->alloc * sizeof(int));
    for (i = 0; i <= old_len; ++i)
      new_cell[i] = parser->cell[i];
    for (i = 0; i < old_len; ++i)
      new_tokseq[i] = parser->tokseq[i];
    SafeFree (parser->cell);
    SafeFree (parser->tokseq);
    parser->cell = new_cell;
    parser->tokseq = new_tokseq;
  }
  parser->tokseq[old_len] = tok;
  j_cell = cellNewTok (parser, j, tok);
  parser->cell[j] = j_cell;

  rule_end = parser->rule + parser->rules;
  for (i = old_len; i >= 0; --i)
    for (k = i; k <= j; ++k) {
      for (rule = parser->rule; rule != rule_end; ++rule)
	cell_inc_p
	  (j_cell, i, j, rule->lhs_sym,
	   parser_get_p(parser,i,k,rule->rhs1_sym) * parser_get_p(parser,k,j,rule->rhs2_sym) * rule->rule_prob);

      for (i = old_len; i >= 0; --i)
	for (rule = parser->rule; rule != rule_end; ++rule)
	  for (k = i; k <= j; ++k)
	    cell_inc_q
	      (j_cell, i, j, rule->lhs_sym,
	       parser_get_p(parser,i,k,rule->rhs1_sym) * parser_get_q(parser,k,rule->rhs2_sym) * rule->rule_prob);
      cell_inc_q
	(j_cell, i, j, rule->lhs_sym,
	 parser_get_q(parser,i,rule->rhs2_sym) * rule->rule_prob);
    }
}

int parserPopTok (Parser* parser) {
  int last_tok;
  Cell *last_cell;
  last_tok = parser->tokseq[parser->len-1];
  last_cell = parser->cell[parser->len];
  --parser->len;
  SafeFree (last_cell);
  return last_tok;
}
