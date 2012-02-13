package Gertie::Inside::PerlParser;
use Moose;
use AutoHash;
use Gertie;
use Gertie::Inside;
extends 'Gertie::Inside';

# constructor
sub new_Inside {
    my ($class, $gertie, $tokseq, @args) = @_;
    my $self = $class->SUPER::new_Inside ( $gertie,
					   undef,  # don't pass tokseq to super

					   # subclass-specific members
					   'p' => [[ $gertie->p_empty ]],
					   'q' => [ $gertie->p_nonempty ],
					   'old_q_by_len' => [],

					   @args );
    bless $self, $class;

    # fill and return
    $self->push_tok (@$tokseq) if defined $tokseq;
    return $self;
}

# accessors
sub get_p {
    my ($self, $i, $j, $sym) = @_;
    my $val = $self->p->[$j]->[$i]->{$sym};
    return defined($val) ? $val : 0;
}

sub get_q {
    my ($self, $i, $sym) = @_;
    my $val = $self->q->[$i]->{$sym};
    return defined($val) ? $val : 0;
}

# subroutine to extend Inside matrix
sub push_tok {
    my ($self, @new_tok) = @_;

    my $gertie = $self->gertie;
    my $tokseq = $self->tokseq;

    my $shared_len = @{$tokseq} + 0;
    my $len = $shared_len + @new_tok;
    my $max_inside_len = $gertie->max_inside_len;
    my $symbols = @{$gertie->sym_name} + 0;

    push @$tokseq, @new_tok;

    # Create Inside matrix
    # p(i,j,sym) = P(seq[i]..seq[j-1] | sym)
    #            = probability that parse tree rooted at sym will generate subseq i..j-1 (inclusive)
    # Note:
    # p(i,j,sym) is stored as $p->[$j]->[$i]->{$sym}
    # This facilitates re-using DP matrices for sequences with shared prefixes
    confess "fuckup: pre-push matrix is wrong size (",@{$self->p}+0,"!=",$shared_len+1,")" unless @{$self->p} == $shared_len + 1;
    my $p = [ @{$self->p}, map ([map ({}, 0..$_)], $shared_len+1..$len) ];
    for my $i ($shared_len+1..$len) { $p->[$i]->[$i] = $gertie->p_empty }
    for my $i ($shared_len..$len-1) { $p->[$i+1]->[$i]->{$tokseq->[$i]} = 1 }
    confess "fuckup: post-push matrix is wrong size (",@$p+0,"!=",$len+1,")" unless @$p == $len + 1;

    # Inside recursion
    # p(i,j,sym) = \sum_{k=i}^j \sum_{lhs->rhs1 rhs1} P(lhs->rhs1 rhs2) p(i,k,rhs1) * p(k,j,rhs2)
    for (my $j = $shared_len + 1; $j <= $len; ++$j) {
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
				    warn "p($i,$j,",$gertie->sym_name->[$lhs],") += p($i,$k,",$gertie->sym_name->[$rhs1],")(=$rhs1_prob) * p($k,$j,",$gertie->sym_name->[$rhs2],")(=$rhs2_prob) * P(rule)(=$rule_prob)" if $self->verbose > 10;
				}
			    }
			}
		    }
		}
	    }
	}
    }

    # store
    $self->{'p'} = $p;

    # recompute prefix probs
    $self->old_q_by_len->[$shared_len] = $self->q;
    $self->recompute_q;

    return $self;
}

sub recompute_q {
    my ($self) = @_;

    my $gertie = $self->gertie;
    my $len = @{$self->tokseq};
    my $symbols = @{$gertie->sym_name} + 0;
    my $p = $self->p;

    if (defined $self->old_q_by_len->[$len]) {
	$self->q ($self->old_q_by_len->[$len]);  # re-use cached probs
	return;
    }

    # Create prefix Inside matrix
    # q(i,sym) = \sum_{j=N+1}^\infty p(i,j,sym)
    #          = probability that parse tree rooted at sym will generate prefix i..length-1 (inclusive) plus at least one extra terminal
    my $q = [ map ({}, 0..$len) ];
    $q->[$len] = $gertie->p_nonempty;

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
			    warn "q($i,",$gertie->sym_name->[$lhs],") += p($i,$k,",$gertie->sym_name->[$rhs1],")(=$rhs1_prob) * q($k,",$gertie->sym_name->[$rhs2],")(=$rhs2_prob) * P(rule)(=$rule_prob)" if $self->verbose > 10;
			}
		    }
		    if (defined $q->[$i]->{$rhs1}) {
			my $rhs1_prob = $q->[$i]->{$rhs1};
			$q->[$i]->{$lhs} += $rule_prob * $rhs1_prob;
			warn "q($i,",$gertie->sym_name->[$lhs],") += q($i,",$gertie->sym_name->[$rhs1],")(=$rhs1_prob) * P(rule)(=$rule_prob)" if $self->verbose > 10;
		    }
		}
	    }
	}
    }

    # store
    $self->{'q'} = $q;
}

sub pop_tok {
    my ($self) = @_;
    my $len = @{$self->tokseq};
    confess "Nothing to pop" if $len == 0;
    delete $self->old_q_by_len->[$len];
    my $tok = pop @{$self->tokseq};
    pop @{$self->p};
    $self->recompute_q;
    return $tok;
}

1;
