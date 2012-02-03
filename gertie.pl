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

    # q(i,j,sym) = P(seq[i]..seq[j-1] | sym)
    #            = probability that parse tree rooted at sym will generate subseq i..j-1 (inclusive)
    my @q = map ([map ({}, $_..$len)], 0..$len);
    for my $i (0..$len) { $q[$i]->[$i]->{$end_id} = 1 }
    for my $i (0..$len-1) { $q[$i]->[$i+1]->{$seq->[$i]} = 1 }

    #   p(i,sym) = P(seq[i]..seq[length-1].. | sym)
    #            = probability that parse tree rooted at sym will generate prefix i..length-1 (inclusive)
    my @p = map ({}, 0..$len);
    $p[$len]->{$end_id} = 1;
# Commenting out this next line because I *think* it overcounts events, still not quite sure how
#    $p[$len-1]->{$seq->[$len-1]} = 1;

    # Inside recursion
    for (my $j = $len; $j >= 0; --$j) {
	for my $rhs1 (sort {$a<=>$b} keys %{$p[$j]}) {

	    # p(j,lhs) += p(j,rhs1) * \sum_rhs2 P(lhs->rhs1 rhs2)
	    while (my ($lhs, $partial_prob) = each %{$partial_prob{$rhs1}}) {
		$p[$j]->{$lhs} += $p[$j]->{$rhs1} * $partial_prob;
		warn "p($j,$sym_name[$lhs]) += p($j,$sym_name[$rhs1])[=",$p[$j]->{$rhs1},"] * sum_rhs2 P($sym_name[$lhs]->$sym_name[$rhs1] rhs2)[=", $partial_prob, "]";
	    }

	    # p(j,lhs) += q(j,j,rhs1) * p(j,rhs2) * P(lhs->rhs1 rhs2)
	    # ...skip this on the assumption that "lhs->rhs1 rhs2" always yields nonempty Inside sequence for rhs1
	}

	# k<j: p(k,lhs) += q(k,j,rhs1) * p(j,rhs2) * P(lhs->rhs1 rhs2)
	for (my $k = $j - 1; $k >= 0; --$k) {
	    while (my ($rhs2, $rhs2_prob) = each %{$p[$j]}) {
		for my $rule (@{$rule_by_rhs2{$rhs2}}) {
		    my ($lhs, $rhs1, $rule_prob) = @$rule;
		    if (exists $q[$k]->[$j]->{$rhs1}) {
			$p[$k]->{$lhs} += $q[$k]->[$j]->{$rhs1} * $rhs2_prob * $rule_prob;
			warn "p($k,$sym_name[$lhs]) += q($k,$j,$sym_name[$rhs1])[=",$q[$k]->[$j]->{$rhs1},"] * p($j,$sym_name[$rhs2])[=$rhs2_prob] * P($sym_name[$lhs]->$sym_name[$rhs1] $sym_name[$rhs2])[=$rule_prob]";
		    }
		}
	    }
	}

	for (my $i = $j; $i <= $len; ++$i) {

	    # q(i,j,lhs) += q(i,j,rhs1) * q(j,j,rhs2) * P(lhs->rhs1 rhs2)
	    for my $rhs1 (sort {$a<=>$b} keys %{$q[$i]->[$j]}) {
		for my $rule (@{$rule_by_rhs1{$rhs1}}) {
		    my ($lhs, $rhs2, $rule_prob) = @$rule;
		    if (exists $q[$j]->[$j]->{$rhs2}) {
			$q[$i]->[$j]->{$lhs} += $q[$i]->[$j]->{$rhs1} * $q[$j]->[$j]->{$rhs2} * $rule_prob;
		    }
		}
	    }

	    # k>j: q(i,k,lhs) += q(i,j,rhs1) * q(j,k,rhs2) * P(lhs->rhs1 rhs2)
	    for (my $k = $j + 1; $k <= $len; ++$k) {
		for my $rhs1 (keys %{$q[$i]->[$j]}) {
		    for my $rule (@{$rule_by_rhs1{$rhs1}}) {
			my ($lhs, $rhs2, $rule_prob) = @$rule;
			if (exists $q[$j]->[$k]->{$rhs2}) {
			    $q[$i][$k]->{$lhs} += $q[$i][$j]->{$rhs1} * $q[$j][$k]->{$rhs2} * $rule_prob;
			}
		    }
		}
	    }

	    # q(i,j,lhs) += q(i,i,rhs1) * q(i,j,rhs2) * P(lhs->rhs1 rhs2)
	    # ...skip this on the assumption that "lhs->rhs1 rhs2" always yields nonempty Inside sequence for rhs1

	    # k<i: q(k,j,lhs) += q(k,i,rhs1) * q(i,j,rhs2) * P(lhs->rhs1 rhs2)
	    for (my $k = $i - 1; $k >= 0; --$k) {
		for my $rhs2 (keys %{$q[$i]->[$j]}) {
		    for my $rule (@{$rule_by_rhs2{$rhs2}}) {
			my ($lhs, $rhs1, $rule_prob) = @$rule;
			if (exists $q[$k]->[$i]->{$rhs1}) {
			    $q[$k][$j]->{$lhs} += $q[$k][$i]->{$rhs1} * $q[$i][$j]->{$rhs2} * $rule_prob;
			}
		    }
		}
	    }
	}
    }

    return (\@p, \@q);
}

sub dump_Inside {
    my ($p, $q) = @_;
    my $len = $#$p;
    for (my $i = $len; $i >= 0; --$i) {

	print "Prefix $i..:";
	for my $sym (sort {$a<=>$b} keys %{$p->[$i]}) {
	    print " ", $sym_name[$sym], "=>", $p->[$i]->{$sym};
	}
	print "\n";

	for (my $j = $i; $j <= $len; ++$j) {
	    print "Inside ($i,$j):";
	    for my $sym (sort {$a<=>$b} keys %{$q->[$i]->[$j]}) {
		print " ", $sym_name[$sym], "=>", $q->[$i]->[$j]->{$sym};
	    }
	    print "\n";
	}
    }
}

my @seq = qw(D);
my @tok = tokenize (\@seq);
warn "tok: (@tok)";
my ($p, $q) = prefix_Inside (\@tok);
dump_Inside ($p, $q);
