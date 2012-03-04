#!/usr/bin/env perl -w

use Cwd qw(abs_path);
use FindBin;
use lib abs_path("$FindBin::Bin/../lib");

use Parse::RecDescent;

my @log;
my $failed = 0;

$::RD_HINT = 1;

# text file
my $text_file = abs_path("$FindBin::Bin/../t/turn-grammar");

# At some point, move contents of $grammar_file to $Gertie::Percy::grammar
my $grammar_file = abs_path("$FindBin::Bin/../lib/Gertie/Percy/grammar.txt");
my $grammar = `cat $grammar_file`;

my $parser = Parse::RecDescent->new ($grammar);
test_crucial (!$failed && defined($parser)?1:0, 1, "Parse::RecDescent initialized from $grammar_file");

my $t0 = "a -> b c (1)";
my $t_rp = "a -> b c (3 * 2 + 1)";
my %sym_eval;
for my $t ($t_rp, $t0) {
    for my $sym (qw(rule statement statement_list grammar)) {
	my $p = Parse::RecDescent->new ($grammar);
	my $expr = "\$p->$sym(\$t)";
	my $expr_eval = eval ($expr);
#    warn "\$sym='$sym' \$t='$t' $expr=",Data::Dumper->new([$expr_eval])->Dump;
	test_crucial (!$failed && defined($expr_eval) ? 1 : 0, 1, "'$t' parsed to '$sym' in $grammar_file");
	$sym_eval{$t}->{$sym} = $expr_eval;
    }
}

my $r0 = $sym_eval{$t0}->{'grammar'};
test_crucial (ref($r0), "Gertie::Robin", "'grammar' returns a Gertie::Robin object");

test_crucial (!$failed && defined($r0->{"gertie"}), 1, "robin->gertie defined");
test_crucial (!$failed && ref($r0->gertie), "Gertie", "robin->gertie is a Gertie");

test (!$failed && $r0->gertie->has_symbol_index, 1, "Gertie is indexed");
test (!$failed && $r0->gertie->n_rules, 1, "Gertie has one rule");
test (!$failed && $r0->gertie->n_symbols, 4, "Gertie has four symbols");  # symbols are a,b,c,end
test ($failed ? "" : $r0->gertie->to_string, "a -> b c;\n", "Gertie serializes to '$t0'");


my $text = `cat $text_file`;
#my $robin = $parser->grammar ($text);


dump_log();

sub test {
    my ($expr, $expected, $desc) = @_;
    my $n = @log + 1;
    $desc = defined($desc) ? " - $desc" : "";
    my $result;
    $result = !$failed && $expr eq $expected;
    if ($failed) { push @log, "not ok $n (did not attempt$desc)\n" }
    elsif ($result) { push @log, "ok $n$desc\n" }
    else { push @log, "not ok $n$desc\nExpected '$expected'\nActual '$expr'\n" }
    return $result;
}

sub test_crucial {
    my ($expr, $expected, $desc) = @_;
    my $ok = test ($expr, $expected, $desc);
    $failed = 1 unless $ok;
    return $ok;
}

sub dump_log {
    print "1..", @log+0, "\n", @log;
}
