package Gertie;

use strict;
use vars ('@ISA', '@EXPORT', '@EXPORT_OK');

# generic imports
use Exporter;
use Carp qw(carp croak cluck confess);
use Data::Dumper;
use File::Temp;
use Scalar::Util;
use IPC::Open3;
use Symbol qw(gensym);

# specific imports
use Graph::Directed;
use Hash::PriorityQueue;

# imports from this repository
use AutoHash;

@ISA = qw (AutoHash);
@EXPORT = qw (new_from_file simulate tokenize prefix_Inside traceback_Inside print_Inside print_parse_tree AUTOLOAD);
@EXPORT_OK = @EXPORT;

# constructor
sub new_gertie {
    my ($class, @args) = @_;
    my $self = AutoHash->new ( 'graph' => Graph::Directed->new,
			       'end' => "end",
			       'rule' => [],
			       'outgoing_prob' => {},
			       'verbose' => 0,
			       @args );
    bless $self, $class;
    $self->graph->add_vertex ($self->end);
    return $self;
}

sub new_from_file {
    my ($class, $filename, @args) = @_;
    my $self = $class->new_gertie (@args);
    $self->parse_file ($filename);
    return $self;
}

# Read grammar file
sub parse_file {
    my ($self, $filename) = @_;
    local *FILE;
    local $_;
    open FILE, "<$filename";
    while (<FILE>) {
	$self->parse_line ($_);
    }
    close FILE;
    $self->index_symbols();
    warn "Symbols: (@{$self->sym_name})" if $self->verbose;
    warn "Terminals: (@{$self->term_name})" if $self->verbose;
    $self->index_rules();
}

sub parse_line {
    my ($self, $line) = @_;
    local $_;
    $_ = $line;
    return if /^\s*\/\//;  # // comments
    if (/^\s*(\w+)\s*\->\s*(\w+)\s*(\w*)\s*([\d\.]*)\s*;\s*$/) {
	my ($lhs, $rhs1, $rhs2, $prob) = ($1, $2, $3, $4);
	$self->add_rule ($lhs, $rhs1, $rhs2, $prob);
    }
}

sub add_rule {
    my ($self, $lhs, $rhs1, $rhs2, $prob) = @_;
    # Supply default values
    $rhs2 = $self->end unless length($rhs2);
    $prob = 1 unless length($prob);
    # Check the rule is valid
    die if $lhs eq $self->end;  # No rules starting with 'end'
    die if $rhs1 eq $self->end && $rhs2 ne $self->end;  # No rules A -> end C
    die if $prob < 0;  # Rule weights are nonnegative
    $self->{'start'} = $lhs unless defined $self->{'start'};  # First named nonterminal is start
    return if $prob == 0;  # Don't bother tracking zero-weight rules
    # Record the rule
    push @{$self->rule}, [$lhs, $rhs1, $rhs2, $prob, @{$self->rule} + 0];
    $self->outgoing_prob->{$lhs} += $prob;
    $self->graph->add_edge ($lhs, $rhs1);
}

# Treating each rule "A->B C" as an edge "A->B", compute toposort
sub index_symbols {
    my ($self) = @_;
    croak "Transition graph is cyclic!" if $self->graph->is_cyclic;
    $self->{'sym_name'} = [reverse $self->graph->topological_sort];
    $self->{'sym_id'} = {map (($self->sym_name->[$_] => $_), 0..$#{$self->sym_name})};
    $self->{'start_id'} = $self->sym_id->{$self->start};
    $self->{'end_id'} = $self->sym_id->{$self->end};
    $self->{'term_name'} = [$self->graph->sink_vertices];  # We define "terminals" to include 'end'
    $self->{'term_id'} = [map ($self->sym_id->{$_}, @{$self->term_name})];
    $self->{'is_term'} = {map (($_ => 1), @{$self->term_id})};
}

# Normalize & index
sub index_rules {
    my ($self) = @_;
    $self->{'rule_by_lhs_rhs1'} = {};
    $self->{'rule_by_rhs1'} = {};
    $self->{'rule_by_rhs2'} = {};
    $self->{'partial_prob'} = {};
    for my $rule (@{$self->rule}) {
	my ($lhs, $rhs1, $rhs2, $prob, $rule_index) = @$rule;
	$prob /= $self->outgoing_prob->{$lhs};
	warn "Indexed rule: $lhs -> $rhs1 $rhs2 $prob;" if $self->verbose;
	my ($lhs_id, $rhs1_id, $rhs2_id) = map ($self->sym_id->{$_}, $lhs, $rhs1, $rhs2);
	push @{$self->rule_by_lhs_rhs1->{$lhs_id}->{$rhs1_id}}, [$rhs2_id, $prob, $rule_index];
	push @{$self->rule_by_rhs1->{$rhs1_id}}, [$lhs_id, $rhs2_id, $prob, $rule_index];
	push @{$self->rule_by_rhs2->{$rhs2_id}}, [$lhs_id, $rhs1_id, $prob, $rule_index];
	$self->partial_prob->{$rhs1_id}->{$lhs_id} += $prob;
    }
}

# empty probs
sub empty_prob {
    my ($self) = @_;
    my %empty = ($self->end_id => 1);
    my @rhs2_queue = keys %empty;
    while (@rhs2_queue) {
	my $rhs2 = shift @rhs2_queue;
	for my $rule (@{$self->rule_by_rhs2->{$rhs2}}) {
	    my ($lhs, $rhs1, $rule_prob, $rule_index) = @$rule;
	    if (exists $empty{$rhs1}) {
		push @rhs2_queue, $lhs unless exists $empty{$lhs};
		$empty{$lhs} += $empty{$rhs1} * $empty{$rhs2};
	    }
	}
    }
    return %empty;
}

# subroutine to tokenize a sequence
sub tokenize {
    my ($self, $seq) = @_;
    # TODO: more error checking here
    return map ($self->sym_id->{$_}, @$seq);
}

# subroutine to compute Inside matrix for given tokenized prefix sequence
sub prefix_Inside {
    my ($self, $tokseq) = @_;
    my $len = @{$tokseq} + 0;

    # Create Inside matrix
    # p(i,j,sym) = P(seq[i]..seq[j-1] | sym)
    #            = probability that parse tree rooted at sym will generate subseq i..j-1 (inclusive)
    my $p = [ map ([map ({}, $_..$len)], 0..$len) ];
    my %empty = $self->empty_prob;
    for my $i (0..$len) { $p->[$i]->[$i] = \%empty }
    for my $i (0..$len-1) { $p->[$i]->[$i+1]->{$tokseq->[$i]} = 1 }

    # Inside recursion
    for (my $j = 1; $j <= $len; ++$j) {
	for (my $i = $j - 1; $i >= 0; --$i) {
	    for (my $k = $i; $k <= $j; ++$k) {
		for my $rhs1 (sort keys %{$p->[$i]->[$k]}) {
		    my $rhs1_prob = $p->[$i]->[$k]->{$rhs1};
		    for my $rule (@{$self->rule_by_rhs1->{$rhs1}}) {
			my ($lhs, $rhs2, $rule_prob, $rule_index) = @$rule;
			if (defined (my $rhs2_prob = $p->[$k]->[$j]->{$rhs2})) {
			    $p->[$i]->[$j]->{$lhs} += $rhs1_prob * $rhs2_prob * $rule_prob;
			}
		    }
		}
	    }
	}
    }

    #   q(i,sym) = \sum_{j=N+1}^\infty p(i,j,sym)
    #            = probability that parse tree rooted at sym will generate prefix i..length-1 (inclusive)
    my $q = [ map ({}, 0..$len) ];
    for my $term_id (@{$self->term_id}) { $q->[$len]->{$term_id} = 1 }

    # prefix Inside recursion
    my $symbols = @{$self->sym_name} + 0;
    for (my $i = $len - 1; $i >= 0; --$i) {
	for my $rhs1 (0..$symbols-1) {
	    for my $rule (@{$self->rule_by_rhs1->{$rhs1}}) {
		my ($lhs, $rhs2, $rule_prob, $rule_index) = @$rule;
		for (my $k = $i; $k <= $len; ++$k) {
		    if (defined (my $rhs1_prob = $p->[$i]->[$k]->{$rhs1})
			&& defined (my $rhs2_prob = $q->[$k]->{$rhs2})) {
			$q->[$i]->{$lhs} += $rule_prob * $rhs1_prob * $rhs2_prob;
		    }
		}
		if (defined $q->[$i]->{$rhs1}) {
		    $q->[$i]->{$lhs} += $rule_prob * $q->[$i]->{$rhs1};
		}
	    }
	}
    }

    # return
    return ($p, $q);
}

sub print_Inside {
    my ($self, $p, $q) = @_;
    my $len = $#$p;
    my @out;
    for (my $i = $len; $i >= 0; --$i) {

	push @out, "Prefix $i..:";
	for my $sym (sort {$a<=>$b} keys %{$q->[$i]}) {
	    push @out, " ", $self->sym_name->[$sym], "=>", $q->[$i]->{$sym};
	}
	push @out, "\n";

	for (my $j = $i; $j <= $len; ++$j) {
	    push @out, "Inside ($i,$j):";
	    for my $sym (sort {$a<=>$b} keys %{$p->[$i]->[$j]}) {
		push @out, " ", $self->sym_name->[$sym], "=>", $p->[$i]->[$j]->{$sym};
	    }
	    push @out, "\n";
	}
    }
    return join ("", @out);
}

sub traceback_Inside {
    my ($self, $p, $q) = @_;
    my $len = $#$p;
    my $q_prob = $q->[0]->{$self->start_id};
    my $p_prob = $p->[0]->[$len]->{$self->start_id};
    my $is_complete = sample ([defined($q_prob) ? $q_prob : 0,
			       defined($p_prob) ? $p_prob : 0]);
    if ($is_complete) {
	return $self->traceback_Inside_p ($p, 0, $len, $self->start_id);
    } else {
	return $self->traceback_Inside_q ($p, $q, 0, $self->start_id);
    }
}

sub traceback_Inside_p {
    my ($self, $p, $i, $j, $lhs) = @_;
    return [$self->sym_name->[$lhs]] if $self->is_term->{$lhs};
    my (@rhs_k, @prob);
    my $rule_by_lhs_rhs1 = $self->rule_by_lhs_rhs1->{$lhs};
    confess "Traceback error" unless defined $rule_by_lhs_rhs1;
    for (my $k = $i; $k <= $j; ++$k) {
	for my $rhs1 (keys %$rule_by_lhs_rhs1) {
	    if (defined $p->[$i]->[$k]->{$rhs1}) {
		for my $rule (@{$rule_by_lhs_rhs1->{$rhs1}}) {
		    my ($rhs2, $rule_prob, $rule_index) = @$rule;
		    if (defined $p->[$k]->[$j]->{$rhs2}) {
			push @rhs_k, [$rhs1, $rhs2, $k];
			push @prob, $p->[$i]->[$k]->{$rhs1} * $p->[$k]->[$j]->{$rhs2} * $rule_prob;
		    }
		}
	    }
	}
    }
    confess "Traceback error" unless @prob;
    my ($rhs1, $rhs2, $k) = @{sample (\@prob, \@rhs_k)};
    return [$self->sym_name->[$lhs],
	    $self->traceback_Inside_p ($p, $i, $k, $rhs1),
	    $self->traceback_Inside_p ($p, $k, $j, $rhs2)];
}

sub traceback_Inside_q {
    my ($self, $p, $q, $i, $lhs) = @_;
    my $len = $#$p;
    return [$self->sym_name->[$lhs]] if $self->is_term->{$lhs} && $i == $len;
    my (@rhs_k, @prob);
    my $rule_by_lhs_rhs1 = $self->rule_by_lhs_rhs1->{$lhs};
    confess "Traceback error" unless defined $rule_by_lhs_rhs1;
    while (my ($rhs1, $rule_list) = each %$rule_by_lhs_rhs1) {
	for (my $k = $i; $k <= $len; ++$k) {
	    if (defined $p->[$i]->[$k]->{$rhs1}) {
		for my $rule (@$rule_list) {
		    my ($rhs2, $rule_prob, $rule_index) = @$rule;
		    if (defined $q->[$k]->{$rhs2}) {
			push @rhs_k, [$rhs1, $rhs2, $k];
			push @prob, $p->[$i]->[$k]->{$rhs1} * $q->[$k]->{$rhs2} * $rule_prob;
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
    confess "Traceback error" unless @prob;
    my ($rhs1, $rhs2, $k) = @{sample (\@prob, \@rhs_k)};
    return [$self->sym_name->[$lhs],
	    $k > $len
	    ? ($self->traceback_Inside_q ($p, $q, $i, $rhs1),
	       $self->simulate ($rhs2))
	    : ($self->traceback_Inside_p ($p, $i, $k, $rhs1),
	       $self->traceback_Inside_q ($p, $q, $k, $rhs2))];
}

sub simulate {
    my ($self, $lhs) = @_;
    $lhs = $self->start_id unless defined $lhs;
    return [$self->sym_name->[$lhs]] if $self->is_term->{$lhs};
    my $rule_by_lhs_rhs1 = $self->rule_by_lhs_rhs1->{$lhs};
    confess "Simulation error: lhs=", $self->sym_name->[$lhs] unless defined $rule_by_lhs_rhs1;
    my (@rhs, @prob);
    while (my ($rhs1, $rule_list) = each %$rule_by_lhs_rhs1) {
	for my $rule (@$rule_list) {
	    my ($rhs2, $rule_prob, $rule_index) = @$rule;
	    push @rhs, [$rhs1, $rhs2];
	    push @prob, $rule_prob;
	}
    }
    my ($rhs1, $rhs2) = @{sample (\@prob, \@rhs)};
    return [$self->sym_name->[$lhs],
	    $self->simulate($rhs1),
	    $self->simulate($rhs2)];
}

sub sample {
    my ($p_array, $opt_array) = @_;
    my $total = 0;
    for my $p (@$p_array) {
	confess "Undefined probability" unless defined $p;
	$total += $p;
    }
    my $r = rand() * $total;
    for my $i (0..$#$p_array) {
	$r -= $p_array->[$i];
	return defined($opt_array) ? $opt_array->[$i] : $i if $r <= 0;
    }
    return defined($opt_array) ? $opt_array->[$#$opt_array] : $#$p_array;
}

sub print_parse_tree {
    my ($self, $tree) = @_;
    my $lhs = $tree->[0];
    my @rhs = (@$tree)[1..$#$tree];
    return @rhs > 0
	? ("(" . $lhs . "->" . join (",", map ($self->print_parse_tree($_), @rhs)) . ")")
	: $lhs;
}

1;
