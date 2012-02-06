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

sub test_expr {
    my ($expr, $desc) = @_;
    my $n = @log + 1;
    if (eval($expr)) { push @log, "ok $n - $desc\n" }
    else { push @log, "not ok $n - $desc\n" }
}

sub dump_log {
    print "1..", @log+0, "\n", @log;
}


my $g = Gertie->new_from_string ('A->D D;A->D;');

my @seq = $g->tokenize (['D']);
my ($p, $q) = $g->prefix_Inside (\@seq);

my $inside = <<END;
Prefix 1..: D=>1
Inside (1,1): end=>1
Prefix 0..: A=>0.5
Inside (0,0): end=>1
Inside (0,1): D=>1 A=>0.5
END
test ($g->print_Inside ($p, $q), $inside, "DP matrix");

srand(1);
my (%sim, %tb);
my $samples = 10_000;
for (my $k = 0; $k < $samples; ++$k) {
    my $simparse = $g->simulate;
    ++$sim{$g->print_parse_tree($simparse)};
    my $tbparse = $g->traceback_Inside ($p, $q);
    ++$tb{$g->print_parse_tree($tbparse)};
}

my $parse1 = "(A->D)";
my $parse2 = "(A->D,D)";
my $min = $samples * .48;  # leave some margin for error

sub balance_test {
    my ($type, %hash) = @_;
    return test_expr ($hash{$parse1} > $min && $hash{$parse2} > $min,
		      "$type parses roughly balanced (" . (100*$hash{$parse1} / $samples) . '% / ' . (100*$hash{$parse2} / $samples) . '%)');
}

balance_test ("simulation", %sim);
balance_test ("stochastic traceback", %tb);

dump_log();

