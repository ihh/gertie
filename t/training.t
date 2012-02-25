#!/usr/bin/env perl -w

use Cwd qw(abs_path);
use FindBin;
use lib abs_path("$FindBin::Bin/../lib");

use Gertie;

my @log;
sub test {
    my ($val, $expected, $desc) = @_;
    my $n = @log + 1;
    $desc = defined($desc) ? " - $desc" : "";
    if ($val eq $expected) { push @log, "ok $n$desc\n" }
    else { push @log, "not ok $n$desc\nExpected:\n$expected\nGot:\n$val\n" }
}

sub test_array {
    my ($val, $expected, $desc) = @_;
    test (0+@$val, 0+@$expected, "$desc (array length)");
    for my $n (0..$#$val) {
	test ($val->[$n], $expected->[$n], "$desc (element $n)");
    }
}

sub dump_log {
    print "1..", @log+0, "\n", @log;
}

my $g = Gertie->new_from_string ('a->b c;b->d;c->end;');
my $inside = $g->prefix_Inside ([$g->tokenize ('d')]);
#warn $inside->to_string;
my $outside = Gertie::Outside->new_Outside ($inside);
#warn $outside->to_string;
my $outside_target = <<END;
Outside (1,1): c=>1
Outside (0,0):
Outside (0,1): d=>1 b=>1 a=>1
END
test ($outside->to_string, $outside_target, "DP matrix");

my ($prob, $counts) = $g->get_prob_and_rule_counts ([['d'],['d']]);
test_array ($counts, [2,2,2], "counts");

sub test_training {
    my ($g_init, $g_target, $training_seqs, $counts_target, $desc) = @_;
    my $g = Gertie->new_from_string ($g_init); # ,'verbose' => 1);
    my $counts = $g->get_prob_and_rule_counts ($training_seqs);
    test_array ($counts, $counts_target, "$desc (counts)");
    $g->train ($training_seqs);
    my $gs = $g->to_string;
    test ($gs, $g_target, "$desc (trained)");
}

my $g1t = <<END;
s -> x*;
x -> a (0.5);
x -> b (0.1);
x -> c (0.1);
x -> d (0.3);
x* -> end (0.2308);
x* -> x x* (0.7692);
END
test_training ('s->x*;x*->x x*(.5)|end(.5);x->a|b|c|d',
	       $g1t,
	       [[qw(a a a a)], [qw(a b c d)], [qw(d d)]],
	       [3, 10, 3, 5, 1, 1, 3],
	       "null model");



dump_log();
