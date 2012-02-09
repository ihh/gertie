#!/usr/bin/perl -w

use Cwd qw(abs_path);
use FindBin;
use lib abs_path("$FindBin::Bin/../lib");

use Fasta;


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

my $s = ">a\nxxx\n>b\nyyy\n>c zzz\n>d www\n";
my $f0 = Fasta->new_fasta ("a"=>"xxx\n","b"=>"yyy\n","c"=>"zzz","d"=>"www");
test ($f0->to_string, $s, "Back and forth from a hash");

my $f1 = Fasta->new_from_string ($s);
test ($f1->to_string, $s, "Back and forth from a string");

my $f2 = Fasta->new_from_file ($FindBin::Bin."/fasta", "d"=>"www");
test ($f2->to_string, $s, "Back and forth from a file");

dump_log();
