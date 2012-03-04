#!/usr/bin/env perl -w

use Cwd qw(abs_path);
use FindBin;
use lib abs_path("$FindBin::Bin/../lib");

use Parse::RecDescent;

my @log;
my $failed = 0;

$::RD_HINT = 1;

my $grammar_file = abs_path("$FindBin::Bin/../lib/Gertie/Percy/grammar.txt");
my $text_file = abs_path("$FindBin::Bin/../t/turn-grammar");

my $grammar = `cat $grammar_file`;

my $parser = Parse::RecDescent->new ($grammar);
test_crucial (defined($parser)?1:0, 1, "Parse::RecDescent initialized from $grammar_file");

my $t0 = "a -> b c (1)";
my %sym_eval;
for my $sym (qw(rule statement statement_list grammar)) {
    my $expr = eval ("\$parser->$sym (\$t0)");
#    warn "sym='$sym' expr=",(defined($expr)?"'$expr'":"undef");
    test_crucial (defined($expr)?1:0, 1, "'$t0' parsed to '$sym' in $grammar_file");
    $sym_eval{$sym} = $expr;
}

my $r0 = $sym_eval{'grammar'};
test_crucial (ref($r0), "Gertie::Robin", "'grammar' returns a Gertie::Robin object");

test_crucial (!$failed && defined($r0->{"gertie"}), 1, "robin->gertie defined");
test_crucial (!$failed && ref($r0->gertie), "Gertie", "robin->gertie is a Gertie");

test (!$failed && $r0->gertie->has_symbol_index, 1, "Gertie is indexed");
test (!$failed && $r0->gertie->n_rules, 1, "Gertie has one rule");
test (!$failed && $r0->gertie->n_symbols, 4, "Gertie has four symbols");  # symbols are a,b,c,end

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
