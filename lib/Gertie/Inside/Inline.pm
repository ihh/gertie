use Inline CPP => <<'END';

#include <vector>
using namespace std;

struct Rule {
  Rule (int lhs_sym, int rhs1_sym, int rhs2_sym, double rule_prob)
    : lhs_sym(lhs_sym), rhs1_sym(rhs1_sym), rhs2_sym(rhs2_sym), rule_prob(rule_prob) { }
  int lhs_sym, rhs1_sym, rhs2_sym;
  double rule_prob;
};

struct Grammar {
  Grammar (int symbols) : symbols(symbols), p_empty(symbols,0.), p_nonempty(symbols,0.) { }
  void add_rule (int lhs_sym, int rhs1_sym, int rhs2_sym, double rule_prob)
  { rule.push_back (Rule (lhs_sym, rhs1_sym, rhs2_sym, rule_prob)); }
  void set_p_empty (int sym, double p) { p_empty[sym] = p; }
  void set_p_nonempty (int sym, double p) { p_nonempty[sym] = p; }
  int symbols;
  vector<Rule> rule;
  vector<double> p_empty, p_nonempty;
};

struct Cell {
  Cell (const Grammar& g) : j(0), p(1,vector<double>(g.symbols,0.)), q(1,vector<double>(g.symbols,0.)) { }
  Cell (const Grammar& g, int tok, int j)
    : j(j), p(j+1,vector<double>(g.symbols,0.)), q(j+1,vector<double>(g.symbols,0.)) {
    p[j] = g.p_empty;
    p[j-1][tok] = 1.;
    q[j] = g.p_nonempty;
  }
  double get_p (int i, int sym) { return p[i][sym]; }
  double get_q (int i, int sym) { return q[i][sym]; }
  void inc_p (int i, int sym, double inc) { p[i][sym] += inc; }
  void inc_q (int i, int sym, double inc) { q[j][sym] += inc; }
  int j;
  vector<vector<double> > p, q;
};

struct Matrix {
  Matrix (const Grammar& g) : grammar(g) { cell.push_back (new Cell(g)); }
  ~Matrix() { for (vector<Cell*>::const_iterator c = cell.begin(); c != cell.end(); ++c) delete *c; }
  int len() { return tokseq.size(); }
  double get_p(int i,int j,int sym) { return cell[j]->get_p(i,sym); }
  double get_q(int i,int sym) { return cell.back()->get_q(i,sym); }
  void push_tok(int tok);
  int pop_tok();
  const Grammar& grammar;
  vector<Cell*> cell;
  vector<int> tokseq;
};

void Matrix::push_tok (int tok) {
  const int old_len = len();
  const int j = old_len + 1;
  tokseq.push_back(tok);
  Cell* j_cell = new Cell (grammar, tok, j);
  cell.push_back (j_cell);
  for (int i = old_len; i >= 0; --i)
    for (int k = i; k <= j; ++k)
      for (vector<Rule>::const_iterator r = grammar.rule.begin(); r != grammar.rule.end(); ++r)
	j_cell->inc_p (i, r->lhs_sym, get_p(i,k,r->rhs1_sym) * get_p(k,j,r->rhs2_sym) * r->rule_prob);
  for (int i = old_len; i >= 0; --i)
    for (vector<Rule>::const_iterator r = grammar.rule.begin(); r != grammar.rule.end(); ++r) {
      for (int k = i; k <= j; ++k)
	j_cell->inc_q (i, r->lhs_sym, get_p(i,k,r->rhs1_sym) * get_q(k,r->rhs2_sym) * r->rule_prob);
      j_cell->inc_q (i, r->lhs_sym, get_q(i,r->rhs2_sym) * r->rule_prob);
    }
}

int Matrix::pop_tok() {
  const int last_tok = tokseq.back();
  const Cell* last_cell = cell.back();
  tokseq.pop_back();
  cell.pop_back();
  delete last_cell;
  return last_tok;
}

END

package Gertie::Inside::Inline;
use Moose;
use AutoHash;
use Gertie;
use Gertie::Inside;
extends 'Gertie::Inside';

# constructor
sub new_Inside {
    my ($class, $gertie, $tokseq, @args) = @_;

    my $symbols = @{$gertie->sym_name} + 0;
    my $cpp_grammar = new Grammar ($symbols);
    for (my $lhs = 0; $lhs < $symbols; ++$lhs) {
	while (my ($rhs1, $rule_list) = each %{$gertie->rule_by_lhs_rhs1->{$lhs}}) {
	    for my $rule (@$rule_list) {
		my ($rhs2, $rule_prob, $rule_index) = @$rule;
		$cpp_grammar->add_rule ($lhs, $rhs1, $rhs2, $rule_prob);
	    }
	}
    }
    while (my ($sym, $p) = each %p_empty) { $cpp_grammar->set_p_empty ($sym, $p) }
    while (my ($sym, $p) = each %p_nonempty) { $cpp_grammar->set_p_nonempty ($sym, $p) }

    my $self = $class->SUPER::new_Inside ( $gertie,
					   undef,  # don't pass tokseq to super

					   # subclass-specific members
					   'cpp_grammar' => $cpp_grammar,
					   'cpp_matrix' => new Matrix ($cpp_grammar),

					   @args );
    bless $self, $class;

    # push tokseq
    $self->push_tok (@$tokseq) if defined $tokseq;

    # fill and return
    return $self;

}

sub get_p {
    my ($self, $i, $j, $sym) = @_;
    confess "get_p out of bounds"
	if $i < 0 || $i > $j || $j > $self->len || $sym < 0 || $sym >= $self->gertie->n_symbols;
    return $self->cpp_matrix->get_p ($i, $j, $sym);
}

sub get_q {
    my ($self, $i, $sym) = @_;
    confess "get_q out of bounds"
	if $i < 0 || $i >= $self->len || $sym < 0 || $sym >= $self->gertie->n_symbols;
    return $self->cpp_matrix->get_q ($i, $sym);
}

sub push_tok {
    my ($self, @new_tok) = @_;
    for my $tok (@new_tok) {
	$self->cpp_matrix->push_tok ($tok);
   }
}

sub pop_tok {
    my ($self) = @_;
    confess "Attempt to pop empty matrix" if $self->len == 0;
    return $self->cpp_matrix->pop_tok();
}

1;
 
