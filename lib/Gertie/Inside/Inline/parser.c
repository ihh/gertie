#include "parser.h"

#define cell_p(cell,i,sym) cell->p[sym * (cell->j + 1) + i]
#define cell_q(cell,i,sym) cell->q[sym * (cell->j + 1) + i]

#define cell_inc_p(cell,i,sym,inc) cell_p(cell,i,sym) += inc
#define cell_inc_q(cell,i,sym,inc) cell_q(cell,i,sym) += inc

Cell* cellNew (Parser *parser, int j) {
  Cell *cell;
  int sym;
  cell = SafeMalloc (sizeof (Cell));
  cell->j = j;
  cell->p = SafeMalloc (sizeof (double) * parser->symbols * (j+1));
  cell->q = SafeMalloc (sizeof (double) * parser->symbols * (j+1));
  for (int sym = 0; sym < parser->symbols; ++sym) {
    cell_p(cell,j,sym) = parser->p_empty[sym];
    cell_q(cell,j,sym) = 1. - parser->p_empty[sym];
  }
}

Cell* cellNewTok (Parser *parser, int j, int tok) {
  Cell *cell;
  cell = cellNew (parser, j);
  cell_p (cell, j-1, tok) = 1.;
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
  if (cell->tokseq)
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
double parserGetP (Parser *parser, int i, int j, int sym) { return cell_get_p (parser->cell[j], i, sym); }
double parserGetQ (Parser *parser, int i, int sym) { return cell_get_p (parser->cell[parser->len], i, sym); }

void parserPushTok (Parser *parser, int tok) {
  int old_len, j, j_cell, i, k, r;
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
  cell[j] = j_cell;

  rule_end = parser->rule + parser->rules;
  for (i = old_len; i >= 0; --i)
    for (k = i; k <= j; ++k) {
      for (rule = parser->rule; rule != rule_end; ++rule)
	j_cell->inc_p (i, rule->lhs_sym, get_p(i,k,rule->rhs1_sym) * get_p(k,j,rule->rhs2_sym) * rule->rule_prob);

  for (int i = old_len; i >= 0; --i)
    for (rule = parser->rule; rule != rule_end; ++rule)
      for (int k = i; k <= j; ++k)
	j_cell->inc_q (i, rule->lhs_sym, get_p(i,k,rule->rhs1_sym) * get_q(k,rule->rhs2_sym) * rule->rule_prob);
      j_cell->inc_q (i, rule->lhs_sym, get_q(i,rule->rhs2_sym) * rule->rule_prob);
    }
}

int parserPopTok (Parser* parser) {
  int last_tok;
  CellPtr last_cell;
  last_tok = parser->tokseq[parser->len-1];
  last_cell = parser->cell[parser->len];
  --parser->len;
  SafeFree (last_cell);
  return last_tok;
}
