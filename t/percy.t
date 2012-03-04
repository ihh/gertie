#!/usr/bin/env perl -w

use Cwd qw(abs_path);
use FindBin;
use lib abs_path("$FindBin::Bin/../lib");

use Parse::RecDescent;

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

$::RD_HINT = 1;

my $grammar_file = abs_path("$FindBin::Bin/../lib/Gertie/Percy/grammar.txt");
my $text_file = abs_path("$FindBin::Bin/../t/turn-grammar");

my $grammar = `cat $grammar_file`;

my $parser = Parse::RecDescent->new ($grammar);
test (1, 1, "Parse::RecDescent initialized from grammar.txt");

my $t0 = "a -> b c (1)";
my $rule = $parser->rule ($t0);
die unless defined $rule;

my $r0 = $parser->grammar ($t0);

test (defined($r0), 1, "turn-grammar parsed to grammar.txt");
test (ref($r0), "Gertie::Robin", "parser creates a Gertie::Robin");

test ($r0->gertie->has_symbol_index, 1, "Gertie is indexed");
test ($r0->gertie->n_rules, 1, "Gertie has one rule");
test ($r0->gertie->n_symbols, 3, "Gertie has three symbols");

my $text = `cat $text_file`;
#my $robin = $parser->grammar ($text);


dump_log();
