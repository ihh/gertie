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
use Time::Progress;
use Term::ANSIColor;

# constructor
sub new_Inside {
    my ($class, $gertie, $tokseq, @args) = @_;
    my $self = AutoHash->new ( 'gertie' => $gertie,
			       'tokseq' => [],
			       'verbose' => 0,
			       @args );
    bless $self, $class;

    # this is an abstract superclass constructor, called only by subclasses; $tokseq should always be undef
    confess "Attempt to parse sequences via abstract superclass constructor" if defined($tokseq) && @$tokseq > 0;

    return $self;
}

# abstract methods
sub get_p {
    my ($self, $i, $j, $sym) = @_;
    confess "Attempt to use abstract superclass get_p accessor";
}

sub get_q {
    my ($self, $i, $sym) = @_;
    confess "Attempt to use abstract superclass get_q accessor";
}

# subroutine to extend Inside matrix
sub push_tok {
    my ($self, @new_tok) = @_;
    push @{$self->tokseq}, @new_tok;  # subclass method should always do this, even if it maintains a separate representation of tokseq
    confess "Attempt to use abstract superclass push_tok method";
}

sub pop_tok {
    my ($self) = @_;
    confess "Attempt to use abstract superclass pop_tok method";
}

# common base class methods
sub len {
    my ($self) = @_;
    return @{$self->tokseq} + 0;
}

sub push_sym {
    my ($self, @sym) = @_;
    return $self->push_tok ($self->gertie->tokenize (@sym));
}

sub pop_sym {
    my ($self) = @_;
    return $self->gertie->sym_name->[$self->pop_tok];
}

sub final_p {
    my ($self) = @_;
    return $self->get_p (0, $self->len, $self->gertie->start_id);
}

sub final_q {
    my ($self) = @_;
    return $self->get_q (0, $self->gertie->start_id);
}

sub final_total {
    my ($self) = @_;
    return $self->final_p + $self->final_q;
}

sub continue_prob {
    my ($self) = @_;
    return $self->final_q / $self->final_total;
}

sub to_string {
    my ($self) = @_;
    my $gertie = $self->gertie;
    my $len = $self->len;
    my @out;
    my @sym = @{$self->gertie->sym_name};
    for (my $i = $len; $i >= 0; --$i) {

	push @out, "Prefix $i..:";
	for my $sym_id (0..$#sym) {
	    my $qval = $self->get_q ($i, $sym_id);
	    push @out, " ", $sym[$sym_id], "=>", $qval if $qval > 0;
	}
	push @out, "\n";

	for (my $j = $i; $j <= $len; ++$j) {
	    push @out, "Inside ($i,$j):";
	    for my $sym_id (0..$#sym) {
		my $pval = $self->get_p ($i, $j, $sym_id);
		push @out, " ", $sym[$sym_id], "=>", $pval if $pval > 0;
	    }
	    push @out, "\n";
	}
    }
    return join ("", @out);
}

sub traceback {
    my ($self) = @_;
    my $gertie = $self->gertie;
    my $len = $self->len;
    my $q_prob = $self->final_q;
    my $p_prob = $self->final_p;
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
    my (@rhs_k, @prob);
    my $rule_by_rhs1 = $gertie->rule_by_lhs_rhs1->{$lhs};
    confess "Traceback error: i=$i, j=$j, lhs=", $gertie->sym_name->[$lhs] unless defined $rule_by_rhs1;
    for (my $k = $i; $k <= $j; ++$k) {
	for my $rhs1 (keys %$rule_by_rhs1) {
	    if (my $rhs1_prob = $self->get_p($i,$k,$rhs1)) {
		for my $rule (@{$rule_by_rhs1->{$rhs1}}) {
		    my ($rhs2, $rule_prob, $rule_index) = @$rule;
		    if (my $rhs2_prob = $self->get_p($j,$k,$rhs2)) {
			push @rhs_k, [$rhs1, $rhs2, $k];
			push @prob, $rhs1_prob * $rhs2_prob * $rule_prob;
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
    my $len = $self->len;
    return [$gertie->sym_name->[$lhs]] if $gertie->is_term->{$lhs} && $i == $len;
    my (@rhs_k, @prob);
    my $rule_by_rhs1 = $gertie->rule_by_lhs_rhs1->{$lhs};
    confess "Traceback error: i=$i, lhs=", $gertie->sym_name->[$lhs] unless defined $rule_by_rhs1;
    while (my ($rhs1, $rule_list) = each %$rule_by_rhs1) {
	for (my $k = $i; $k <= $len; ++$k) {
	    if (my $rhs1_prob = $self->get_p($i,$k,$rhs1)) {
		for my $rule (@$rule_list) {
		    my ($rhs2, $rule_prob, $rule_index) = @$rule;
		    if (my $rhs2_prob = $self->get_q($k,$rhs2)) {
			push @rhs_k, [$rhs1, $rhs2, $k];
			push @prob, $rhs1_prob * $rhs2_prob * $rule_prob;
		    }
		}
	    }
	}
	if (my $rhs1_prob = $self->get_q($i,$rhs1)) {
	    for my $rule (@$rule_list) {
		my ($rhs2, $rule_prob, $rule_index) = @$rule;
		push @rhs_k, [$rhs1, $rhs2, $len + 1];
		push @prob, $rhs1_prob * $rule_prob;
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

# Return probability distribution over next terminal, by exhaustive enumeration
# Caller can optionally select terminals owned by just one agent
sub next_term_prob {
    my ($self, @agents) = @_;
    @agents = @{$self->gertie->agents} unless @agents;
    my %agent_ok = map (($_ => 1), @agents);
    my $continue_evidence = $self->final_q;
    my %term_prob;
    if ($continue_evidence > 0) {
	my @term_id;
	for my $term_id (@{$self->gertie->term_id}) {
	    next if $term_id == $self->gertie->end_id;
	    next unless $agent_ok{$self->gertie->term_owner->{$term_id}};
	    push @term_id, $term_id;
	}
	my $progress = Time::Progress->new;
	$progress->restart ('max' => $#term_id);
	for my $n (0..$#term_id) {
	    my $term_id = $term_id[$n];
	    my $term_name = $self->gertie->sym_name->[$term_id];
	    $self->push_tok ($term_id);
	    my $prob = $self->final_total / $continue_evidence;
	    if ($prob > 0) { $term_prob{$self->gertie->sym_name->[$term_id]} = $prob }
	    $self->pop_tok;
	    # Progress bar
	    print
		color('red'),
		$progress->report ("\%B (".sprintf("% 10f",$prob).") \%L $term_name\n", $n),
		color('reset')
		if $self->verbose;
	}
    }
    return %term_prob;
}

1;
