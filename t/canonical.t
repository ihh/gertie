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


my $g = Gertie->new_from_string ('A->C 2|D E F G 5|B 1');
my $gs = $g->to_string;
my $gt = <<END;
A -> B  0.125;
A -> C  0.25;
A -> D E F G  0.625;
END
test ($gs, $gt, "Canonical form of grammar with multiple RHS separated by '|'");


my $g2 = Gertie->new_from_string ('A->B+ C{,3} D{,4} E{1,4} F* G?');
my $g2s = $g2->to_string;
my $g2t = <<END;
A -> B+ C{,3} D{,4} E{1,4} F* G?;
B+ -> B B+  0.5;
B+ -> B  0.5;
C{,3} -> C C  0.25;
C{,3} -> C  0.25;
C{,3} -> C C C  0.25;
C{,3} -> end  0.25;
D{,4} -> D D  0.2;
D{,4} -> D  0.2;
D{,4} -> D D D  0.2;
D{,4} -> D D D D  0.2;
D{,4} -> end  0.2;
E{1,4} -> E E  0.25;
E{1,4} -> E  0.25;
E{1,4} -> E E E  0.25;
E{1,4} -> E E E E  0.25;
F* -> F F*  0.5;
F* -> end  0.5;
G? -> G  0.5;
G? -> end  0.5;
END
test ($g2s, $g2t, "Canonical form of grammar with quantifiers");


dump_log();
