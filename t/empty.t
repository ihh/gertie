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


my $g = Gertie->new_from_string ('a->b c;b->d;c->end;');
test ($g->has_empty_nonterms() ? 1 : 0, 1, "Grammar with empty nonterms");

my $g2 = Gertie->new_from_string ('a->b c;b->d;c->d d;');
test ($g2->has_empty_nonterms() ? 1 : 0, 0, "Grammar without empty nonterms");

dump_log();
