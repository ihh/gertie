#!/usr/bin/perl -w

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


my $g = Gertie->new_from_string ('A->B1 B2 B3 C;B1->D;B2->E|F;B3->F|G;C->G;');

my @seq1 = $g->tokenize([qw(D E F G)]);
my ($p1, $q1) = $g->prefix_Inside (\@seq1);

my @seq2 = $g->tokenize([qw(D E G G)]);
my ($p2, $q2) = $g->prefix_Inside (\@seq2);
my ($p2s, $q2s) = $g->prefix_Inside (\@seq2, \@seq1, $p1);

my $dp2 = $g->print_Inside ($p2, $q2);
my $dp2s = $g->print_Inside ($p2s, $q2s);

test ($dp2, $dp2s, "Re-using part of DP matrix for two sequences that share a prefix");

dump_log();