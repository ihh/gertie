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

my $g1t = <<END;
\@p p0 p1 p2 p3 p4;
\@c c1 c2 c3 c4;
a -> end (0.25);
a -> p1 b (0.5);
a -> p3 c (0.25);
b -> c1 d (0.5);
b -> c3 d (0.25);
b -> end (0.25);
c -> c2 e (0.5);
c -> c4 e (0.25);
c -> end (0.25);
d -> end (0.25);
d -> p2 a (0.5);
d -> p4 a (0.25);
e -> end (0.25);
e -> p0 a (0.25);
e -> p2 a (0.5);
END
test_canonical ('@p p0 p1 p2 p3 p4;@c c1 c2 c3 c4;a->p1 b 2|p3 c|end;b->c1 d 2|c3 d|end;c->c2 e 2|c4 e|end;d->p2 a 2|p4 a|end;e->p2 a 2|p0 a|end',
		$g1t,
		"Ownership of terminals");

my $g2t = <<END;
\@c;
a\@c -> b\@p;
a\@p -> b\@c;
END
test_canonical ('@c;a@1->b@2;',
		$g2t,
		'Canonical form of grammar with @1- and @2-suffixed rule expansions');


my $g3t = <<END;
\@q;
\@r;
a\@p -> b\@q c\@r;
a\@q -> b\@r c\@p;
a\@r -> b\@p c\@q;
END
test_canonical ('@q c@q;@r b@r;a@1->b@2 c@3',
		$g3t,
		'Canonical form of grammar with @1-, @2- and @3-suffixed rule expansions');


dump_log();
