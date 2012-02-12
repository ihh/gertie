#include "parser.h"

Rule::Rule (int lhs_sym, int rhs1_sym, int rhs2_sym, double rule_prob)
  : lhs_sym(lhs_sym), rhs1_sym(rhs1_sym), rhs2_sym(rhs2_sym), rule_prob(rule_prob) { }

Cell::Cell (const vector<double>& p_empty, const vector<double>& p_nonempty)
  : j(0), p(1,vector<double>(p_empty.size(),0.)), q(1,vector<double>(p_empty.size(),0.)) {
  init (p_empty, p_nonempty);
}
Cell::Cell (const vector<double>& p_empty, const vector<double>& p_nonempty, int tok, int j)
  : j(j), p(j+1,vector<double>(p_empty.size(),0.)), q(j+1,vector<double>(p_empty.size(),0.)) {
  init (p_empty, p_nonempty);
  p[j-1][tok] = 1.;
}
double Cell::get_p (int i, int sym) { return p[i][sym]; }
double Cell::get_q (int i, int sym) { return q[i][sym]; }
void Cell::inc_p (int i, int sym, double inc) { p[i][sym] += inc; }
void Cell::inc_q (int i, int sym, double inc) { q[j][sym] += inc; }
void Cell::init (const vector<double>& p_empty, const vector<double>& p_nonempty) {
  p[j] = p_empty;
  q[j] = p_nonempty;
}

// constructor, destructor
Parser::Parser (int symbols) : symbols(symbols), p_empty(symbols,0.), p_nonempty(symbols,0.) { }
Parser::~Parser() { for (vector<CellPtr>::const_iterator c = cell.begin(); c != cell.end(); ++c) delete *c; }
// builder methods
void Parser::add_rule (int lhs_sym, int rhs1_sym, int rhs2_sym, double rule_prob)
{ rule.push_back (Rule (lhs_sym, rhs1_sym, rhs2_sym, rule_prob)); }
void Parser::set_p_empty (int sym, double p) { p_empty[sym] = p; p_nonempty[sym] = 1 - p; }
void Parser::init_matrix() { cell.push_back (new Cell(p_empty,p_nonempty)); }
// accessors
int Parser::len() { return tokseq.size(); }
double Parser::get_p(int i,int j,int sym) { return cell[j]->get_p(i,sym); }
double Parser::get_q(int i,int sym) { return cell.back()->get_q(i,sym); }
// push/pop

void Parser::push_tok (int tok) {
  const int old_len = len();
  const int j = old_len + 1;
  tokseq.push_back(tok);
  CellPtr j_cell = new Cell (p_empty, p_nonempty, tok, j);
  cell.push_back (j_cell);
  for (int i = old_len; i >= 0; --i)
    for (int k = i; k <= j; ++k)
      for (vector<Rule>::const_iterator r = rule.begin(); r != rule.end(); ++r)
	j_cell->inc_p (i, r->lhs_sym, get_p(i,k,r->rhs1_sym) * get_p(k,j,r->rhs2_sym) * r->rule_prob);
  for (int i = old_len; i >= 0; --i)
    for (vector<Rule>::const_iterator r = rule.begin(); r != rule.end(); ++r) {
      for (int k = i; k <= j; ++k)
	j_cell->inc_q (i, r->lhs_sym, get_p(i,k,r->rhs1_sym) * get_q(k,r->rhs2_sym) * r->rule_prob);
      j_cell->inc_q (i, r->lhs_sym, get_q(i,r->rhs2_sym) * r->rule_prob);
    }
}

int Parser::pop_tok() {
  const int last_tok = tokseq.back();
  const CellPtr last_cell = cell.back();
  tokseq.pop_back();
  cell.pop_back();
  delete last_cell;
  return last_tok;
}
