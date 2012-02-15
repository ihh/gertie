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

sub dump_log {
    print "1..", @log+0, "\n", @log;
}


my $g = Gertie->new_from_string ('a->b1 b2 b3 c;b1->d;b2->e|f;b3->f|g;c->g;');

my @seq0 = $g->tokenize(qw(d e));
my $pq0 = $g->prefix_Inside (\@seq0);

my @seq1 = $g->tokenize(qw(d e f g));
my $pq1 = $g->prefix_Inside (\@seq1);
my $pq1b = $pq0->push_sym(qw(f g));

my $dp1 = $pq1->to_string;
my $dp1b = $pq1b->to_string;
test ($dp1, $dp1b, "Building DP matrix by extension from a prefix");

test ($pq0->pop_sym, 'g', "Popping tokens back off the DP matrix (g)");
test ($pq0->pop_sym, 'f', "Popping tokens back off the DP matrix (f)");

my @seq2 = $g->tokenize(qw(d e g g));
my $pq2 = $g->prefix_Inside (\@seq2);
my $pq2b = $pq0->push_sym ('g', 'g');

my $dp2 = $pq2->to_string;
my $dp2b = $pq2b->to_string;
test ($dp2, $dp2b, "Building DP matrix by extension from a prefix (after retracting a different extension)");


dump_log();
