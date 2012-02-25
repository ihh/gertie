#!/usr/bin/env perl -w

use Cwd qw(abs_path);
use FindBin;
use lib abs_path("$FindBin::Bin/../lib");
use Carp qw(carp croak cluck confess);

use Gertie;

my @log;
sub test {
    my ($val, $expected, $desc) = @_;
    my $n = @log + 1;
    $desc = defined($desc) ? " - $desc" : "";
    confess unless defined $expected;
    if ($val eq $expected) { push @log, "ok $n$desc\n" }
    else { push @log, "not ok $n$desc\nExpected:\n$expected\nGot:\n$val\n" }
}

sub test_array {
    my ($val, $expected, $desc) = @_;
    test (0+@$val, 0+@$expected, "$desc (array length)");
    if (@$val == @$expected) {
	for my $n (0..$#$val) {
	    test ($val->[$n], $expected->[$n], "$desc (element $n)");
	}
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
Outside (0,1): d=>1 b=>1 a=>1
Outside (0,0):
Outside (1,1): end=>3 c=>1
END
test ($outside->to_string, $outside_target, "DP matrix");

my ($prob, $counts) = $g->get_prob_and_rule_counts ([['d'],['d']]);
test_array ($counts, [2,2,2], "counts");

sub test_training {
    my ($g_init, $g_target, $training_seqs, $counts_target, $desc) = @_;
    my $g = Gertie->new_from_string ($g_init);# ,'verbose' => 1);
    my $counts = $g->get_prob_and_rule_counts ($training_seqs);
    test_array ($counts, $counts_target, "$desc (counts)");
    $g->train ($training_seqs);
    $g->output_precision (4);  # only want 4 significant digits on this test - see below
    my $gs = $g->to_string;
    test ($gs, $g_target, "$desc (trained)");
}

# In the trained grammar below:
# 0.2308 = 3/13 (to 4 significant digits)
# 0.7692 = 10/13 (to 4 significant digits)
my $g1t = <<END;
s -> x*;
x -> a (0.5);
x -> b (0.1);
x -> c (0.1);
x -> d (0.3);
x* -> end (0.2308);
x* -> x x* (0.7692);
END
# note how we write out all the implicit quantifier rules explicitly in the grammar initializer (first argument)
# this is not strictly required, but it makes the test more readable:
# the first three counts 3,10,3... (fourth argument) are counts for the rules "s->x*", "x*->x x*" and "x*->end"
test_training ('s->x*;x*->x x*(.5)|end(.5);x->a|b|c|d',  # the "x->x x*|end" rule is shown explicitly, to make sense of the counts in the fourth argument to test_training
	       $g1t,
	       [[qw(a a a a)], [qw(a b c d)], [qw(d d)]],
	       [3, 10, 3, 5, 1, 1, 3],  # order of these counts follows rules in first subroutine arg to test_training
	       "null model");


my $g2t = <<END;
(f, g) = (0.7692, 0.2308);
s -> x*;
x -> a (0.5);
x -> b (0.1);
x -> c (0.1);
x -> d (0.3);
x* -> end (g);
x* -> x x* (f);
END
test_training ('(f,g)=(.5,.5);s->x*;x*->x x*(f)|end(g);x->a|b|c|d',
	       $g2t,
	       [[qw(a a a a)], [qw(a b c d)], [qw(d d)]],
	       [3, 10, 3, 5, 1, 1, 3],
	       "parametric null model");

my $g3t = <<END;
(f, g) = (0.7692, 0.2308);
(pa, pb, pc, pd) = (0.5, 0.1, 0.1, 0.3);
s -> x*;
x -> x1 (0.5);
x -> x2 (0.5);
x* -> end (g);
x* -> x x* (f);
x1 -> a (pa);
x1 -> b (pb);
x1 -> c (pc);
x1 -> d (pd);
x2 -> a (pa);
x2 -> b (pb);
x2 -> c (pc);
x2 -> d (pd);
END
test_training ('(f,g)=(.5,.5);(pa,pb,pc,pd)=(.25,.25,.25,.25);s->x*;x*->x x*(f)|end(g);x->x1|x2;x1->a(pa)|b(pb)|c(pc)|d(pd);x2->a(pa)|b(pb)|c(pc)|d(pd)',
	       $g3t,
	       [[qw(a a a a)], [qw(a b c d)], [qw(d d)]],
	       [3, 10, 3, 5, 5, 2.5, .5, .5, 1.5, 2.5, .5, .5, 1.5],
	       "parametric null model");



dump_log();
