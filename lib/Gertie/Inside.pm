package Gertie::Inside;
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

# constructor
sub new_Inside {
    my ($class, $gertie, $tokseq, $prev_Inside) = @_;
    my $self = AutoHash->new ( 'gertie' => $gertie,
			       'tokseq' => $tokseq,
			       'prev' => $prev_Inside );
    bless $self, $class;
    $self->fill();
    return $self;
}

# subroutine to fill Inside matrix
sub fill {
    my ($self) = @_;

    my $gertie = $self->gertie;
    my $tokseq = $self->tokseq;
    my $prev_tokseq = defined($self->prev) ? $self->prev->tokseq : undef;
    my $prev_p = defined($self->prev) ? $self->prev->p : undef;

    my $len = @{$tokseq} + 0;
    my $max_inside_len = $gertie->max_inside_len;
    my $symbols = @{$gertie->sym_name} + 0;

    my $shared_len = 0;
    if (defined $prev_tokseq) {
	while ($shared_len < @$prev_tokseq && $shared_len < @$tokseq && $tokseq->[$shared_len] == $prev_tokseq->[$shared_len]) {
	    ++$shared_len;
	}
    }

    # Create Inside matrix
    # p(i,j,sym) = P(seq[i]..seq[j-1] | sym)
    #            = probability that parse tree rooted at sym will generate subseq i..j-1 (inclusive)
    # Note:
    # p(i,j,sym) is stored as $p->[$j]->[$i]->{$sym}
    # This facilitates re-using DP matrices for sequences with shared prefixes
    my $p = [ map ([map ({}, 0..$_)], 0..$len) ];
    my %empty = $gertie->empty_prob;
    for my $i (0..$len) { $p->[$i]->[$i] = \%empty }
    for my $i (0..$len-1) { $p->[$i+1]->[$i]->{$tokseq->[$i]} = 1 }

    # Inside recursion
    # p(i,j,sym) = \sum_{k=i}^j \sum_{lhs->rhs1 rhs1} P(lhs->rhs1 rhs2) p(i,k,rhs1) * p(k,j,rhs2)
    for (my $j = 1; $j <= $len; ++$j) {
	if ($j <= $shared_len) { $p->[$j] = $prev_p->[$j]; next }
	for (my $i = $j - 1; $i >= 0; --$i) {
	    next if defined($max_inside_len) && $j-$i > $max_inside_len && $i > 0;
	    for (my $lhs = 0; $lhs < $symbols; ++$lhs) {
		my $rule_by_rhs1 = $gertie->rule_by_lhs_rhs1->{$lhs};
		for (my $k = $i; $k <= $j; ++$k) {
		    next if defined($max_inside_len) && $j-$k > $max_inside_len && $k > 0;
		    for my $rhs1 (sort keys %{$p->[$k]->[$i]}) {
			if (defined $rule_by_rhs1->{$rhs1}) {
			    my $rhs1_prob = $p->[$k]->[$i]->{$rhs1};
			    for my $rule (@{$rule_by_rhs1->{$rhs1}}) {
				my ($rhs2, $rule_prob, $rule_index) = @$rule;
				if (defined (my $rhs2_prob = $p->[$j]->[$k]->{$rhs2})) {
				    $p->[$j]->[$i]->{$lhs} += $rhs1_prob * $rhs2_prob * $rule_prob;
				    warn "p($i,$j,",$gertie->sym_name->[$lhs],") += p($i,$k,",$gertie->sym_name->[$rhs1],")(=$rhs1_prob) * p($k,$j,",$gertie->sym_name->[$rhs2],")(=$rhs2_prob) * P(rule)(=$rule_prob)" if $gertie->verbose > 1;
				}
			    }
			}
		    }
		}
	    }
	}
    }

    # Create prefix Inside matrix
    # q(i,sym) = \sum_{j=N+1}^\infty p(i,j,sym)
    #          = probability that parse tree rooted at sym will generate prefix i..length-1 (inclusive) plus at least one extra terminal
    my $q = [ map ({}, 0..$len) ];
    for my $term_id (@{$gertie->term_id}) { $q->[$len]->{$term_id} = 1 }
    delete $q->[$len]->{$gertie->end_id};  # a parse tree rooted at 'end' cannot generate any more terminals, so we don't consider 'end' a terminal for this purpose

    # prefix Inside recursion
    # q(i,sym) = \sum_{lhs->rhs1 rhs1} P(lhs->rhs1 rhs2) (q(i,rhs1) + \sum_{k=i}^{length} p(i,k,rhs1) * q(k,rhs2))
    for (my $i = $len - 1; $i >= 0; --$i) {
	for (my $lhs = 0; $lhs < $symbols; ++$lhs) {
	    my $rule_by_rhs1 = $gertie->rule_by_lhs_rhs1->{$lhs};
	    while (my ($rhs1, $rule_list) = each %$rule_by_rhs1) {
		for my $rule (@$rule_list) {
		    my ($rhs2, $rule_prob, $rule_index) = @$rule;
		    for (my $k = $i; $k <= $len; ++$k) {
			if (defined (my $rhs1_prob = $p->[$k]->[$i]->{$rhs1})
			    && defined (my $rhs2_prob = $q->[$k]->{$rhs2})) {
			    $q->[$i]->{$lhs} += $rule_prob * $rhs1_prob * $rhs2_prob;
			    warn "q($i,",$gertie->sym_name->[$lhs],") += p($i,$k,",$gertie->sym_name->[$rhs1],")(=$rhs1_prob) * q($k,",$gertie->sym_name->[$rhs2],")(=$rhs2_prob) * P(rule)(=$rule_prob)" if $gertie->verbose > 1;
			}
		    }
		    if (defined $q->[$i]->{$rhs1}) {
			my $rhs1_prob = $q->[$i]->{$rhs1};
			$q->[$i]->{$lhs} += $rule_prob * $rhs1_prob;
			warn "q($i,",$gertie->sym_name->[$lhs],") += q($i,",$gertie->sym_name->[$rhs1],")(=$rhs1_prob) * P(rule)(=$rule_prob)" if $gertie->verbose > 1;
		    }
		}
	    }
	}
    }

    # store
    $self->{'p'} = $p;
    $self->{'q'} = $q;
}

sub to_string {
    my ($self) = @_;
    my $gertie = $self->gertie;
    my $p = $self->p;
    my $q = $self->q;
    my $len = $#$p;
    my @out;
    for (my $i = $len; $i >= 0; --$i) {

	push @out, "Prefix $i..:";
	for my $sym (sort {$a<=>$b} keys %{$q->[$i]}) {
	    push @out, " ", $gertie->sym_name->[$sym], "=>", $q->[$i]->{$sym};
	}
	push @out, "\n";

	for (my $j = $i; $j <= $len; ++$j) {
	    push @out, "Inside ($i,$j):";
	    for my $sym (sort {$a<=>$b} keys %{$p->[$j]->[$i]}) {
		push @out, " ", $gertie->sym_name->[$sym], "=>", $p->[$j]->[$i]->{$sym};
	    }
	    push @out, "\n";
	}
    }
    return join ("", @out);
}

sub traceback {
    my ($self) = @_;
    my $gertie = $self->gertie;
    my $p = $self->p;
    my $q = $self->q;
    my $len = $#$p;
    my $q_prob = $q->[0]->{$gertie->start_id};
    my $p_prob = $p->[$len]->[0]->{$gertie->start_id};
    my $is_complete = Gertie::sample ([defined($q_prob) ? $q_prob : 0,
				       defined($p_prob) ? $p_prob : 0]);
    my $parse_tree =
	$is_complete
	? $self->traceback_p (0, $len, $gertie->start_id)
	: $self->traceback_q (0, $gertie->start_id);

    return $gertie->flatten_parse_tree ($parse_tree);
}

sub traceback_p {
    my ($self, $i, $j, $lhs) = @_;
    my $gertie = $self->gertie;
    return [$gertie->sym_name->[$lhs]] if $gertie->is_term->{$lhs};
    my $p = $self->p;
    my $q = $self->q;
    my (@rhs_k, @prob);
    my $rule_by_rhs1 = $gertie->rule_by_lhs_rhs1->{$lhs};
    confess "Traceback error: i=$i, j=$j, lhs=", $gertie->sym_name->[$lhs] unless defined $rule_by_rhs1;
    for (my $k = $i; $k <= $j; ++$k) {
	for my $rhs1 (keys %$rule_by_rhs1) {
	    if (defined $p->[$k]->[$i]->{$rhs1}) {
		for my $rule (@{$rule_by_rhs1->{$rhs1}}) {
		    my ($rhs2, $rule_prob, $rule_index) = @$rule;
		    if (defined $p->[$j]->[$k]->{$rhs2}) {
			push @rhs_k, [$rhs1, $rhs2, $k];
			push @prob, $p->[$k]->[$i]->{$rhs1} * $p->[$j]->[$k]->{$rhs2} * $rule_prob;
		    }
		}
	    }
	}
    }
    confess "Traceback error: i=$i, j=$j, lhs=", $gertie->sym_name->[$lhs] unless @prob;
    my ($rhs1, $rhs2, $k) = @{Gertie::sample (\@prob, \@rhs_k)};
    return [$gertie->sym_name->[$lhs],
	    $self->traceback_p ($i, $k, $rhs1),
	    $self->traceback_p ($k, $j, $rhs2)];
}

sub traceback_q {
    my ($self, $i, $lhs) = @_;
    my $gertie = $self->gertie;
    my $p = $self->p;
    my $q = $self->q;
    my $len = $#$p;
    return [$gertie->sym_name->[$lhs]] if $gertie->is_term->{$lhs} && $i == $len;
    my (@rhs_k, @prob);
    my $rule_by_rhs1 = $gertie->rule_by_lhs_rhs1->{$lhs};
    confess "Traceback error: i=$i, lhs=", $gertie->sym_name->[$lhs] unless defined $rule_by_rhs1;
    while (my ($rhs1, $rule_list) = each %$rule_by_rhs1) {
	for (my $k = $i; $k <= $len; ++$k) {
	    if (defined $p->[$k]->[$i]->{$rhs1}) {
		for my $rule (@$rule_list) {
		    my ($rhs2, $rule_prob, $rule_index) = @$rule;
		    if (defined $q->[$k]->{$rhs2}) {
			push @rhs_k, [$rhs1, $rhs2, $k];
			push @prob, $p->[$k]->[$i]->{$rhs1} * $q->[$k]->{$rhs2} * $rule_prob;
		    }
		}
	    }
	}
	if (defined $q->[$i]->{$rhs1}) {
	    for my $rule (@$rule_list) {
		my ($rhs2, $rule_prob, $rule_index) = @$rule;
		push @rhs_k, [$rhs1, $rhs2, $len + 1];
		push @prob, $q->[$i]->{$rhs1} * $rule_prob;
	    }
	}
    }
    confess "Traceback error: i=$i, lhs=", $gertie->sym_name->[$lhs] unless @prob;
    my ($rhs1, $rhs2, $k) = @{Gertie::sample (\@prob, \@rhs_k)};
    return [$gertie->sym_name->[$lhs],
	    $k > $len
	    ? ($self->traceback_q ($i, $rhs1),
	       $gertie->simulate_Chomsky ($rhs2))
	    : ($self->traceback_p ($i, $k, $rhs1),
	       $self->traceback_q ($k, $rhs2))];
}

1;