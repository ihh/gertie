#!/usr/bin/perl -w

use Cwd qw(abs_path);
use FindBin;
use File::Temp qw/tempfile/;

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


my $robin = abs_path("$FindBin::Bin/../bin") . "/robin.pl";
my $grammar = abs_path("$FindBin::Bin") . "/turn-grammar";
my $desired_log_file = abs_path("$FindBin::Bin") . "/turn-grammar-log";
my $rounds = 10;
my $seed = 12345;

my ($fh_in, $fn_in) = tempfile();
print $fh_in map ("1\n", 1..$rounds);

my ($fh_log, $fn_log) = tempfile();
my $command = "cat $fn_in | $robin $grammar -seed $seed -trace $fn_log -rounds $rounds >/dev/null";
# warn $command;
system $command;
my $expected = <<END;
intro
p1
c3
p2
c0
p1
c1
p2
c0
p1
c3
p2
c0
p1
c3
p2
c0
p1
c1
END
my $actual = `cat $fn_log`;
test ($actual, $expected, "Reproducible Robin trace");

dump_log();
