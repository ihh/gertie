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


my $g = Gertie->new_from_string ('a->b1 b2 b3 c;b1->d;b2->end;b3->end;c->end;');

my $simparse = $g->simulate;
test ($g->print_parse_tree($simparse), "(a->(b1->d),(b2->end),(b3->end),(c->end))", "Simulated parse");

dump_log();
