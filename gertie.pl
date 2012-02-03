#!/usr/bin/perl -w

use Graph::Directed;

# Read grammar file
my $end = "end";
my (@rule, %outgoing_prob);
my $graph = Graph::Directed->new;
$graph->add_vertex ($end);
while (<>) {
    next if /^\s*\/\//;  # // comments
    if (/^\s*(\w+)\s*\->\s*(\w+)\s*(\w*)\s*([\d\.]*)\s*;\s*$/) {
	my ($lhs, $rhs1, $rhs2, $prob) = ($1, $2, $3, $4);
	$rhs2 = $end unless length($rhs2);
	$prob = 1 unless length($prob);
	die if $lhs eq $end;
	die if $rhs1 eq $end && $rhs2 ne $end;
	die if $prob < 0;
	next if $prob == 0;
	push @rule, [$lhs, $rhs1, $rhs2, $prob];
	$outgoing_prob{$lhs} += $prob;
	$graph->add_edge ($lhs, $rhs1);
    }
}

# Treating each rule "A->B C" as an edge "A->B", compute toposort
my @sym_name = reverse $graph->topological_sort;
my %sym_id = map (($sym_name[$_] => $_), 0..$#sym_name);
my $end_id = $sym_id{$end};

warn "Symbols: (@sym_name)";

# Normalize & index
my (%rule_by_rhs1, %rule_by_rhs2, %partial_prob);
for my $rule (@rule) {
    my ($lhs, $rhs1, $rhs2, $prob) = @$rule;
    $prob /= $outgoing_prob{$lhs};
    warn "$lhs -> $rhs1 $rhs2 $prob;";
    my ($lhs_id, $rhs1_id, $rhs2_id) = map ($sym_id{$_}, $lhs, $rhs1, $rhs2);
    push @{$rule_by_rhs1{$rhs1_id}}, [$lhs_id, $rhs2_id, $prob];
    push @{$rule_by_rhs2{$rhs2_id}}, [$lhs_id, $rhs1_id, $prob];
    $partial_prob{$rhs1_id}->{$lhs_id} += $prob;
}

# subroutine to tokenize a sequence
sub tokenize {
    my ($seq) = @_;
    # TODO: more error checking here
    return map ($sym_id{$_}, @$seq);
}

# subroutine to compute Inside matrix for given prefix sequence
sub prefix_Inside {
    my ($seq) = @_;
    my $len = @{$seq} + 0;

    # Create Inside matrix

    # p(i,j,sym) = P(seq[i]..seq[j-1] | sym)
    #            = probability that parse tree rooted at sym will generate subseq i..j-1 (inclusive)
    my @p = map ([map ({}, $_..$len)], 0..$len);
    for my $i (0..$len) { $p[$i]->[$i]->{$end_id} = 1 }
    for my $i (0..$len-1) { $p[$i]->[$i+1]->{$seq->[$i]} = 1 }

    #   q(i,sym) = \sum_{j=N+1}^\infty p(i,j,sym)
    #            = probability that parse tree rooted at sym will generate prefix i..length-1 (inclusive)
    my @q = map ({}, 0..$len);
    $q[$len]->{$end_id} = 1;

    # Inside recursion
    for (my $j = $len; $j >= 0; --$j) {
	for my $rhs1 (sort {$a<=>$b} keys %{$q[$j]}) {

	    # q(j,lhs) += q(j,rhs1) * \sum_rhs2 P(lhs->rhs1 rhs2)
	    while (my ($lhs, $partial_prob) = each %{$partial_prob{$rhs1}}) {
		$q[$j]->{$lhs} += $q[$j]->{$rhs1} * $partial_prob;
		warn "q($j,$sym_name[$lhs]) += q($j,$sym_name[$rhs1])[=",$q[$j]->{$rhs1},"] * sum_rhs2 P($sym_name[$lhs]->$sym_name[$rhs1] rhs2)[=", $partial_prob, "]";
	    }

	    # q(j,lhs) += p(j,j,rhs1) * q(j,rhs2) * P(lhs->rhs1 rhs2)
	    # ...skip this on the assumption that "lhs->rhs1 rhs2" always yields nonempty Inside sequence for rhs1
	}

	# k<j: q(k,lhs) += p(k,j,rhs1) * q(j,rhs2) * P(lhs->rhs1 rhs2)
	for (my $k = $j - 1; $k >= 0; --$k) {
	    while (my ($rhs2, $rhs2_prob) = each %{$q[$j]}) {
		for my $rule (@{$rule_by_rhs2{$rhs2}}) {
		    my ($lhs, $rhs1, $rule_prob) = @$rule;
		    if (exists $p[$k]->[$j]->{$rhs1}) {
			$q[$k]->{$lhs} += $p[$k]->[$j]->{$rhs1} * $rhs2_prob * $rule_prob;
			warn "q($k,$sym_name[$lhs]) += p($k,$j,$sym_name[$rhs1])[=",$p[$k]->[$j]->{$rhs1},"] * q($j,$sym_name[$rhs2])[=$rhs2_prob] * P($sym_name[$lhs]->$sym_name[$rhs1] $sym_name[$rhs2])[=$rule_prob]";
		    }
		}
	    }
	}

	for (my $i = $j; $i <= $len; ++$i) {

	    # p(i,j,lhs) += p(i,j,rhs1) * p(j,j,rhs2) * P(lhs->rhs1 rhs2)
	    for my $rhs1 (sort {$a<=>$b} keys %{$p[$i]->[$j]}) {
		for my $rule (@{$rule_by_rhs1{$rhs1}}) {
		    my ($lhs, $rhs2, $rule_prob) = @$rule;
		    if (exists $p[$j]->[$j]->{$rhs2}) {
			$p[$i]->[$j]->{$lhs} += $p[$i]->[$j]->{$rhs1} * $p[$j]->[$j]->{$rhs2} * $rule_prob;
		    }
		}
	    }

	    # k>j: p(i,k,lhs) += p(i,j,rhs1) * p(j,k,rhs2) * P(lhs->rhs1 rhs2)
	    for (my $k = $j + 1; $k <= $len; ++$k) {
		for my $rhs1 (keys %{$p[$i]->[$j]}) {
		    for my $rule (@{$rule_by_rhs1{$rhs1}}) {
			my ($lhs, $rhs2, $rule_prob) = @$rule;
			if (exists $p[$j]->[$k]->{$rhs2}) {
			    $p[$i][$k]->{$lhs} += $p[$i][$j]->{$rhs1} * $p[$j][$k]->{$rhs2} * $rule_prob;
			}
		    }
		}
	    }

	    # p(i,j,lhs) += p(i,i,rhs1) * p(i,j,rhs2) * P(lhs->rhs1 rhs2)
	    # ...skip this on the assumption that "lhs->rhs1 rhs2" always yields nonempty Inside sequence for rhs1

	    # k<i: p(k,j,lhs) += p(k,i,rhs1) * p(i,j,rhs2) * P(lhs->rhs1 rhs2)
	    for (my $k = $i - 1; $k >= 0; --$k) {
		for my $rhs2 (keys %{$p[$i]->[$j]}) {
		    for my $rule (@{$rule_by_rhs2{$rhs2}}) {
			my ($lhs, $rhs1, $rule_prob) = @$rule;
			if (exists $p[$k]->[$i]->{$rhs1}) {
			    $p[$k][$j]->{$lhs} += $p[$k][$i]->{$rhs1} * $p[$i][$j]->{$rhs2} * $rule_prob;
			}
		    }
		}
	    }
	}
    }

    return (\@q, \@p);
}

sub dump_Inside {
    my ($q, $p) = @_;
    my $len = $#$q;
    for (my $i = $len; $i >= 0; --$i) {

	print "Prefix $i..:";
	for my $sym (sort {$a<=>$b} keys %{$q->[$i]}) {
	    print " ", $sym_name[$sym], "=>", $q->[$i]->{$sym};
	}
	print "\n";

	for (my $j = $i; $j <= $len; ++$j) {
	    print "Inside ($i,$j):";
	    for my $sym (sort {$a<=>$b} keys %{$p->[$i]->[$j]}) {
		print " ", $sym_name[$sym], "=>", $p->[$i]->[$j]->{$sym};
	    }
	    print "\n";
	}
    }
}

my @seq = qw(D);  # test sequence for GRAMMAR file
my @tok = tokenize (\@seq);
warn "tok: (@tok)";
my ($q, $p) = prefix_Inside (\@tok);
dump_Inside ($q, $p);
