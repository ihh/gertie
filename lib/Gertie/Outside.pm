package Gertie::Outside;
use Moose;
use AutoHash;
use Gertie;
extends 'AutoHash';

use strict;

# generic imports
use Carp qw(carp croak cluck confess);
use Data::Dumper;
use File::Temp;
use Scalar::Util;
use IPC::Open3;
use Symbol qw(gensym);

# specific imports
use Graph::Directed;
use Time::Progress;
use Term::ANSIColor;

# Let seq[0] be the first symbol in the sequence, seq[1] the second, etc., up to seq[length-1] the last symbol.
# For j>=i (with j=i corresponding to the empty subsequence):
# By "the subsequence from i..j-1" we mean inclusive of both i and j-1, or the empty sequence if i=j.

# Inside matrix
# p(i,j,sym) = P(seq[i]..seq[j-1] | sym)
#  = probability that parse tree rooted at sym will generate subseq i..j-1 (inclusive)
#  = sum_{symB,symC} P(sym->symB symC) sum_{k=i}^j p(i,k,symB) p(k,j,symC)

# p(i,i,sym) = p_end(sym)
# p_end(end) = 1
# p(i,j,term) = delta(j=i+1) delta(seq[i]=term)

# P(sequence) = p(0,length,start)

# Outside matrix
# r(i,j,sym) = P(seq[0]..seq[i] . sym . seq[j-1]..seq[length-1] | start) * deg(i,j,sym)
#  = expected number of times that derivation stopping at sym will generate everything except subseq i..j-1
#  = sum_{symA,symB} P(symA->symB sym) sum_{k=0}^i r(k,j,symA) p(k,i,symB)
#    + sum_{symA,symC} P(symA->sym symC) sum_{k=j}^{length} r(i,k,symA) p(j,k,symC)

# deg(i,j,sym) = expected number of times that a parse tree contains sym at (i,j)
# Since the grammar is cyclic, deg(i,j,sym)=1 unless i=j and sym can be generated multiple ways

# r(0,length,start) = 1

# Posterior probability that symbol X generated subseq i..j-1 is r(i,j,X)*p(i,j,X)/p(0,length,start)
# Post. prob. that rule A->BC generated i..j-1 and j..k-1 is r(i,j,A)*p(i,k,B)*p(k,j,C)*P(A->BC)/p(0,length,start)


# constructor
sub new_Outside {
    my ($class, $inside, @args) = @_;
    my $self = AutoHash->new ( 'inside' => $inside,
			       'gertie' => $inside->gertie,
			       'tokseq' => $inside->tokseq,
			       'r' => [map ([map ([map (0, 1..$inside->gertie->n_symbols)],
						  $_..$inside->len)],
					    0..$inside->len)],
			       'rule_count' => [map (0, 1..$inside->gertie->n_symbols)],
			       'verbose' => 0,
			       @args );
    bless $self, $class;
    $self->fill;
    return $self;
}

sub get_r {
    my ($self, $i, $j, $sym) = @_;
    confess "(i,j)=($i,$j) out of range" if $i < 0 || $j < $i || $j > $self->len;
    return $self->r->[$i]->[$j-$i]->[$sym];
}

sub set_r {
    my ($self, $i, $j, $sym, $rval) = @_;
    confess "(i,j)=($i,$j) out of range" if $i < 0 || $j < $i || $j > $self->len;
    $self->r->[$i]->[$j-$i]->[$sym] = $rval;
}

sub len {
    my ($self) = @_;
    return @{$self->tokseq} + 0;
}

sub to_string {
    my ($self) = @_;
    my $gertie = $self->gertie;
    my $len = $self->len;
    my @out;
    my @sym = @{$self->gertie->sym_name};
    for (my $i = 0; $i <= $len; ++$i) {

	for (my $j = $len; $j >= $i; --$j) {
	    push @out, "Outside ($i,$j):";
	    for my $sym_id (0..$#sym) {
		my $rval = $self->get_r ($i, $j, $sym_id);
		push @out, " ", $sym[$sym_id], "=>", $rval if $rval > 0;
	    }
	    push @out, "\n";
	}
    }
    return join ("", @out);
}

sub fill {
    my ($self) = @_;

    my $len = $self->len;
    my $rule_count = $self->rule_count;

    my $gertie = $self->gertie;
    my $n_symbols = $gertie->n_symbols;
    my $rule = $gertie->tokenized_rule;

    my $inside = $self->inside;
    my $final_p = $inside->final_p;

    my $r = $self->r;
    $self->set_r (0, $len, $gertie->start_id, 1);

    for (my $j = $len; $j > 0; --$j) {
	for (my $i = 0; $i <= $j; ++$i) {
	    for (my $sym = $n_symbols - 1; $sym >= 0; --$sym) {

		# r(i,j,sym) = sum_{symA,symB} P(symA->symB sym) sum_{k=0}^{i-1} r(k,j,symA) p(k,i,symB)
		#              + sum_{symA,symC} P(symA->sym symC) sum_{k=j+1}^{length} r(i,k,symA) p(j,k,symC)
		my $rval = $self->get_r ($i, $j, $sym);
		for my $rule_index (@{$gertie->rule_by_rhs2->{$sym}}) {
		    my ($lhs, $rhs1, $rhs2, $rule_prob) = @{$rule->[$rule_index]};
		    for (my $k = 0; $k <= $i; ++$k) {
			$rval += $rule_prob * $self->get_r($k,$j,$lhs) * $inside->get_p($k,$i,$rhs1);
		    }
		}
		for my $rule_index (@{$gertie->rule_by_rhs1->{$sym}}) {
		    my ($lhs, $rhs1, $rhs2, $rule_prob) = @{$rule->[$rule_index]};
		    for (my $k = $j; $k <= $len; ++$k) {
			$rval += $rule_prob * $self->get_r($i,$k,$lhs) * $inside->get_p($j,$k,$rhs2);
		    }
		}
		$self->set_r ($i, $j, $sym, $rval);

		# Accumulate counts
		for my $rule_index (@{$gertie->rule_by_lhs->{$sym}}) {
		    for (my $k = $i; $k <= $j; ++$k) {
			$rule_count->[$rule_index] += $self->post_rule_prob ($i, $j, $k, $rule_index);
		    }
		}
	    }
	}
    }
}

# Posterior probability that symbol X generated subseq i..j-1 is r(i,j,X)*p(i,j,X)/p(0,length,start)
sub post_nonterm_prob {
    my ($self, $i, $j, $sym) = @_;
    my $final_p = $self->inside->final_p;
    return undef if $final_p == 0;
    return $self->get_r($i,$j,$sym) * $self->inside->get_p($i,$j,$sym) / $final_p;
}

# Post. prob. that rule A->BC generated i..j-1 and j..k-1 is r(i,j,A)*p(i,k,B)*p(k,j,C)*P(A->BC)/p(0,length,start)
sub post_rule_prob {
    my ($self, $i, $j, $k, $rule_index) = @_;
    my ($lhs, $rhs1, $rhs2, $prob) = @{$self->gertie->tokenized_rule->[$rule_index]};
    my $final_p = $self->inside->final_p;
    return undef if $final_p == 0;
    return $self->get_r($i,$j,$lhs) * $self->inside->get_p($i,$k,$rhs1) * $self->inside->get_p($k,$j,$rhs2) * $prob
	/ $final_p;
}

1;
