use Inline CPP => <<'END';

#include <vector>
using namespace std;

struct Rule {
  Rule (int lhs_sym, int rhs1_sym, int rhs2_sym, double rule_prob)
    : lhs_sym(lhs_sym), rhs1_sym(rhs1_sym), rhs2_sym(rhs2_sym), rule_prob(rule_prob) { }
  int lhs_sym, rhs1_sym, rhs2_sym;
  double rule_prob;
};

struct Cell {
public:
  Cell (const vector<double>& p_empty, const vector<double>& p_nonempty)
    : j(0), p(1,vector<double>(p_empty.size(),0.)), q(1,vector<double>(p_empty.size(),0.)) {
    init (p_empty, p_nonempty);
  }
  Cell (const vector<double>& p_empty, const vector<double>& p_nonempty, int tok, int j)
    : j(j), p(j+1,vector<double>(p_empty.size(),0.)), q(j+1,vector<double>(p_empty.size(),0.)) {
    init (p_empty, p_nonempty);
    p[j-1][tok] = 1.;
  }
  double get_p (int i, int sym) { return p[i][sym]; }
  double get_q (int i, int sym) { return q[i][sym]; }
  void inc_p (int i, int sym, double inc) { p[i][sym] += inc; }
  void inc_q (int i, int sym, double inc) { q[j][sym] += inc; }
private:
  void init (const vector<double>& p_empty, const vector<double>& p_nonempty) {
    p[j] = p_empty;
    q[j] = p_nonempty;
  }
  int j;
  vector<vector<double> > p, q;
};
typedef Cell* CellPtr;

class Parser {
public:
  // constructor, destructor
  Parser (int symbols) : symbols(symbols), p_empty(symbols,0.), p_nonempty(symbols,0.) { }
  ~Parser() { for (vector<CellPtr>::const_iterator c = cell.begin(); c != cell.end(); ++c) delete *c; }
  // builder methods
  void add_rule (int lhs_sym, int rhs1_sym, int rhs2_sym, double rule_prob)
  { rule.push_back (Rule (lhs_sym, rhs1_sym, rhs2_sym, rule_prob)); }
  void set_p_empty (int sym, double p) { p_empty[sym] = p; }
  void set_p_nonempty (int sym, double p) { p_nonempty[sym] = p; }
  void init_matrix() { cell.push_back (new Cell(p_empty,p_nonempty)); }
  // accessors
  int len() { return tokseq.size(); }
  double get_p(int i,int j,int sym) { return cell[j]->get_p(i,sym); }
  double get_q(int i,int sym) { return cell.back()->get_q(i,sym); }
  // push/pop
  void push_tok(int tok);
  int pop_tok();
private:
  int symbols;
  vector<Rule> rule;
  vector<double> p_empty, p_nonempty;
  vector<CellPtr> cell;
  vector<int> tokseq;
};

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
    my $cpp_parser = new Parser ($symbols);
    for (my $lhs = 0; $lhs < $symbols; ++$lhs) {
	while (my ($rhs1, $rule_list) = each %{$gertie->rule_by_lhs_rhs1->{$lhs}}) {
	    for my $rule (@$rule_list) {
		my ($rhs2, $rule_prob, $rule_index) = @$rule;
		$cpp_parser->add_rule ($lhs, $rhs1, $rhs2, $rule_prob);
	    }
	}
    }
    while (my ($sym, $p) = each %{$gertie->p_empty}) { $cpp_parser->set_p_empty ($sym, $p) }
    while (my ($sym, $p) = each %{$gertie->p_nonempty}) { $cpp_parser->set_p_nonempty ($sym, $p) }
    $cpp_parser->init_matrix();

    my $self = $class->SUPER::new_Inside ( $gertie,
					   undef,  # don't pass tokseq to super

					   # subclass-specific members
					   'cpp_parser' => $cpp_parser,

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
    return $self->cpp_parser->get_p ($i, $j, $sym);
}

sub get_q {
    my ($self, $i, $sym) = @_;
    confess "get_q out of bounds"
	if $i < 0 || $i >= $self->len || $sym < 0 || $sym >= $self->gertie->n_symbols;
    return $self->cpp_parser->get_q ($i, $sym);
}

sub push_tok {
    my ($self, @new_tok) = @_;
    for my $tok (@new_tok) {
	$self->cpp_parser->push_tok ($tok);
   }
}

sub pop_tok {
    my ($self) = @_;
    confess "Attempt to pop empty matrix" if $self->len == 0;
    return $self->cpp_parser->pop_tok();
}

1;
 
