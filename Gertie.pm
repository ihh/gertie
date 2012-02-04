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
use AutoHash;

@ISA = qw (AutoHash);
@EXPORT = qw (new_from_file AUTOLOAD);
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
    $rhs2 = $self->end unless length($rhs2);
    $prob = 1 unless length($prob);
    die if $lhs eq $self->end;
    die if $rhs1 eq $self->end && $rhs2 ne $self->end;
    die if $prob < 0;
    return if $prob == 0;
    push @{$self->rule}, [$lhs, $rhs1, $rhs2, $prob];
    $self->outgoing_prob->{$lhs} += $prob;
    $self->graph->add_edge ($lhs, $rhs1);
}

# Treating each rule "A->B C" as an edge "A->B", compute toposort
sub index_symbols {
    my ($self) = @_;
    $self->{'sym_name'} = [reverse $self->graph->topological_sort];
    $self->{'sym_id'} = {map (($self->sym_name->[$_] => $_), 0..$#{$self->sym_name})};
    $self->{'end_id'} = $self->sym_id->{$self->end};
}

# Normalize & index
sub index_rules {
    my ($self) = @_;
    $self->{'rule_by_rhs1'} = {};
    $self->{'rule_by_rhs2'} = {};
    $self->{'partial_prob'} = {};
    for my $rule (@{$self->rule}) {
	my ($lhs, $rhs1, $rhs2, $prob) = @$rule;
	$prob /= $self->outgoing_prob->{$lhs};
	warn "$lhs -> $rhs1 $rhs2 $prob;" if $self->verbose;
	my ($lhs_id, $rhs1_id, $rhs2_id) = map ($self->sym_id->{$_}, $lhs, $rhs1, $rhs2);
	push @{$self->rule_by_rhs1->{$rhs1_id}}, [$lhs_id, $rhs2_id, $prob];
	push @{$self->rule_by_rhs2->{$rhs2_id}}, [$lhs_id, $rhs1_id, $prob];
	$self->partial_prob->{$rhs1_id}->{$lhs_id} += $prob;
    }
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
    my ($i, $j, $k, $rule, $lhs, $rhs1, $rhs2, $rule_prob, $rhs2_prob, $partial_prob);

    # Create Inside matrix
    # p(i,j,sym) = P(seq[i]..seq[j-1] | sym)
    #            = probability that parse tree rooted at sym will generate subseq i..j-1 (inclusive)
    my $p = [ map ([map ({}, $_..$len)], 0..$len) ];
    for $i (0..$len) { $p->[$i]->[$i]->{$self->end_id} = 1 }
    for $i (0..$len-1) { $p->[$i]->[$i+1]->{$tokseq->[$i]} = 1 }

    #   q(i,sym) = \sum_{j=N+1}^\infty p(i,j,sym)
    #            = probability that parse tree rooted at sym will generate prefix i..length-1 (inclusive)
    my $q = [ map ({}, 0..$len) ];
    $q->[$len]->{$self->end_id} = 1;

    # Inside recursion
    for ($j = $len; $j >= 0; --$j) {
	for $rhs1 (sort {$a<=>$b} keys %{$q->[$j]}) {

	    # q(j,lhs) += q(j,rhs1) * \sum_rhs2 P(lhs->rhs1 rhs2)
	    while (($lhs, $partial_prob) = each %{$self->partial_prob->{$rhs1}}) {
		$q->[$j]->{$lhs} += $q->[$j]->{$rhs1} * $partial_prob;
		warn "q($j,",$self->sym_name->[$lhs],") += q($j,",$self->sym_name->[$rhs1],")[=",$q->[$j]->{$rhs1},"] * sum_rhs2 P(",$self->sym_name->[$lhs],"->",$self->sym_name->[$rhs1]," *)[=", $partial_prob, "]" if $self->verbose;
	    }

	    # q(j,lhs) += p(j,j,rhs1) * q(j,rhs2) * P(lhs->rhs1 rhs2)
	    # ...skip this on the assumption that "lhs->rhs1 rhs2" always yields nonempty Inside sequence for rhs1
	}

	# k<j: q(k,lhs) += p(k,j,rhs1) * q(j,rhs2) * P(lhs->rhs1 rhs2)
	for ($k = $j - 1; $k >= 0; --$k) {
	    while (($rhs2, $rhs2_prob) = each %{$q->[$j]}) {
		for $rule (@{$self->rule_by_rhs2->{$rhs2}}) {
		    ($lhs, $rhs1, $rule_prob) = @$rule;
		    if (exists $p->[$k]->[$j]->{$rhs1}) {
			$q->[$k]->{$lhs} += $p->[$k]->[$j]->{$rhs1} * $rhs2_prob * $rule_prob;
			warn "q($k,",$self->sym_name->[$lhs],") += p($k,$j,",$self->sym_name->[$rhs1],")[=",$p->[$k]->[$j]->{$rhs1},"] * q($j,",$self->sym_name->[$rhs2],")[=$rhs2_prob] * P(",$self->sym_name->[$lhs],"->",$self->sym_name->[$rhs1]," ",$self->sym_name->[$rhs2],")[=$rule_prob]" if $self->verbose;
		    }
		}
	    }
	}

	for ($i = $j; $i <= $len; ++$i) {

	    # p(i,j,lhs) += p(i,j,rhs1) * p(j,j,rhs2) * P(lhs->rhs1 rhs2)
	    for $rhs1 (sort {$a<=>$b} keys %{$p->[$i]->[$j]}) {
		for $rule (@{$self->rule_by_rhs1->{$rhs1}}) {
		    ($lhs, $rhs2, $rule_prob) = @$rule;
		    if (exists $p->[$j]->[$j]->{$rhs2}) {
			$p->[$i]->[$j]->{$lhs} += $p->[$i]->[$j]->{$rhs1} * $p->[$j]->[$j]->{$rhs2} * $rule_prob;
		    }
		}
	    }

	    # k>j: p(i,k,lhs) += p(i,j,rhs1) * p(j,k,rhs2) * P(lhs->rhs1 rhs2)
	    for ($k = $j + 1; $k <= $len; ++$k) {
		for $rhs1 (keys %{$p->[$i]->[$j]}) {
		    for $rule (@{$self->rule_by_rhs1->{$rhs1}}) {
			($lhs, $rhs2, $rule_prob) = @$rule;
			if (exists $p->[$j]->[$k]->{$rhs2}) {
			    $p->[$i][$k]->{$lhs} += $p->[$i][$j]->{$rhs1} * $p->[$j][$k]->{$rhs2} * $rule_prob;
			}
		    }
		}
	    }

	    # p(i,j,lhs) += p(i,i,rhs1) * p(i,j,rhs2) * P(lhs->rhs1 rhs2)
	    # ...skip this on the assumption that "lhs->rhs1 rhs2" always yields nonempty Inside sequence for rhs1

	    # k<i: p(k,j,lhs) += p(k,i,rhs1) * p(i,j,rhs2) * P(lhs->rhs1 rhs2)
	    for ($k = $i - 1; $k >= 0; --$k) {
		for $rhs2 (keys %{$p->[$i]->[$j]}) {
		    for $rule (@{$self->rule_by_rhs2->{$rhs2}}) {
			($lhs, $rhs1, $rule_prob) = @$rule;
			if (exists $p->[$k]->[$i]->{$rhs1}) {
			    $p->[$k][$j]->{$lhs} += $p->[$k][$i]->{$rhs1} * $p->[$i][$j]->{$rhs2} * $rule_prob;
			}
		    }
		}
	    }
	}
    }

    # return
    return ($p, $q);
}

sub print_Inside {
    my ($self, $p, $q) = @_;
    my $len = $#$q;
    for (my $i = $len; $i >= 0; --$i) {

	print "Prefix $i..:";
	for my $sym (sort {$a<=>$b} keys %{$q->[$i]}) {
	    print " ", $self->sym_name->[$sym], "=>", $q->[$i]->{$sym};
	}
	print "\n";

	for (my $j = $i; $j <= $len; ++$j) {
	    print "Inside ($i,$j):";
	    for my $sym (sort {$a<=>$b} keys %{$p->[$i]->[$j]}) {
		print " ", $self->sym_name->[$sym], "=>", $p->[$i]->[$j]->{$sym};
	    }
	    print "\n";
	}
    }
}

1;
