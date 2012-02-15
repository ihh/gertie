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

sub test_canonical {
    my ($g_init, $g_canon, $desc) = @_;
    my $g = Gertie->new_from_string ($g_init);
    my $gs = $g->to_string;
    my $g2 = Gertie->new_from_string ($gs);
    my $g2s = $g2->to_string;
    test ($gs, $g_canon, "$desc (string representation is canonical)");
    test ($gs, $g2s, "$desc (reproduced from canonical form)");
}


my $gt = <<END;
a -> b (0.125);
a -> c (0.25);
a -> d e f g (0.625);
END
test_canonical ('a->c 2|d e f g 5|b 1',
		$gt,
		"Canonical form of grammar with multiple RHS separated by '|'");


my $g2t = <<END;
a -> b+ c{,3} d{,4} e{1,4} f* g?;
// b+ -> b b+ (0.5);
// b+ -> b (0.5);
// c{,3} -> c c (0.25);
// c{,3} -> c (0.25);
// c{,3} -> c c c (0.25);
// c{,3} -> end (0.25);
// d{,4} -> d d (0.2);
// d{,4} -> d (0.2);
// d{,4} -> d d d (0.2);
// d{,4} -> d d d d (0.2);
// d{,4} -> end (0.2);
// e{1,4} -> e e (0.25);
// e{1,4} -> e (0.25);
// e{1,4} -> e e e (0.25);
// e{1,4} -> e e e e (0.25);
// f* -> end (0.5);
// f* -> f f* (0.5);
// g? -> end (0.5);
// g? -> g (0.5);
END
test_canonical ('a->b+ c{,3} d{,4} e{1,4} f* g?',
		$g2t,
		"Canonical form of grammar with quantifiers");


dump_log();
