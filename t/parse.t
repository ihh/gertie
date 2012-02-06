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


my $g = Gertie->new_from_string ('A->B C;B->D;C->end;');

my $simparse = $g->simulate;
test ($g->print_parse_tree($simparse), "(A->(B->D,end),(C->end,end))", "Simulated parse");

my @seq = $g->tokenize (['D']);
my ($p, $q) = $g->prefix_Inside (\@seq);
my $inside = <<END;
Prefix 1..: end=>1 D=>1
Inside (1,1): end=>1 C=>1
Prefix 0..: B=>1 A=>1
Inside (0,0): end=>1 C=>1
Inside (0,1): D=>1 B=>1 A=>1
END
test ($g->print_Inside ($p, $q), $inside, "DP matrix");

my $tbparse = $g->traceback_Inside ($p, $q);
test ($g->print_parse_tree($tbparse), "(A->(B->D,end),(C->end,end))", "Sampled parse");

dump_log();
