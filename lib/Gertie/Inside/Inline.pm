
package Gertie::Inside::Inline;
use Moose;
use AutoHash;
use Gertie;
use Gertie::Inside;
extends 'Gertie::Inside';

use Gertie::Inside::Inline::Parser;

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

# destructor
sub DESTROY {
    my ($self) = @_;
    $self->{'cpp_parser'}->delete if defined $self->{'cpp_parser'};  # not sure if this is right
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
 
