#!/usr/bin/env perl -w

use Cwd qw(abs_path);
use FindBin;
#use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../../../..");  # while resident in lib/Gertie/Inside/CParser/t/ instead of t/

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


my $g = Gertie->new_from_string ('a->b c;b->d;c->end;',verbose=>99);
$g->inside_class ('Gertie::Inside::CParser');

my $simparse = $g->simulate;
test ($g->print_parse_tree($simparse), "(a->(b->d),(c->end))", "Simulated parse");

my @seq = $g->tokenize ('d');
my $pq = $g->prefix_Inside (\@seq);
my $inside = <<END;
Prefix 1..: d=>1 b=>1 a=>1
Inside (1,1): end=>1 c=>1
Prefix 0..:
Inside (0,0): end=>1 c=>1
Inside (0,1): d=>1 b=>1 a=>1
END
test ($pq->to_string, $inside, "DP matrix");

my $tbparse = $pq->traceback;
test ($g->print_parse_tree($tbparse), "(a->(b->d),(c->end))", "Sampled parse");

dump_log();
