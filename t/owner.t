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


my $g = Gertie->new_from_string ('@p p0 p1 p2 p3 p4;@c c1 c2 c3 c4;A->p1 B 2|p3 C|end;B->c1 D 2|c3 D|end;C->c2 E 2|c4 E|end;D->p2 A 2|p4 A|end;E->p2 A 2|p0 A|end');
my $gs = <<END;
\@p p0 p1 p2 p3 p4;
\@c c1 c2 c3 c4;
A -> end  0.25;
A -> p1 B  0.5;
A -> p3 C  0.25;
B -> c1 D  0.5;
B -> c3 D  0.25;
B -> end  0.25;
C -> c2 E  0.5;
C -> c4 E  0.25;
C -> end  0.25;
D -> end  0.25;
D -> p2 A  0.5;
D -> p4 A  0.25;
E -> end  0.25;
E -> p0 A  0.25;
E -> p2 A  0.5;
END

test ($g->to_string, $gs, "Ownership of terminals");

my $g2 = Gertie->new_from_string ('@c;a@1->b@2;');
my $g2s = $g2->to_string;
my $g2t = <<END;
a\@c -> b\@p;
a\@p -> b\@c;
END
test ($g2s, $g2t, 'Canonical form of grammar with @1- and @2-suffixed rule expansions');


my $g3 = Gertie->new_from_string ('@q c@q;@r b@r;a@1->b@2 c@3');
my $g3s = $g3->to_string;
my $g3t = <<END;
a\@p -> b\@q c\@r;
a\@q -> b\@r c\@p;
a\@r -> b\@p c\@q;
END
test ($g3s, $g3t, 'Canonical form of grammar with @1-, @2- and @3-suffixed rule expansions');


dump_log();
