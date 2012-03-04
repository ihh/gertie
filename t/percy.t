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


my $grammar_file = abs_path("$FindBin::Bin/../lib/Gertie/Percy/grammar.txt");
my $text_file = abs_path("$FindBin::Bin/../t/turn-grammar");

my $grammar = `cat $grammar_file`;
my $text = `cat $text_file`;

my $parser = Parse::RecDescent->new ($grammar);
test (1, 1, "Parse::RecDescent initialized from grammar.txt");

my $gertie = $parser->grammar ($text);
test (defined($gertie), 1, "turn-grammar parsed to grammar.txt");
test (ref($gertie), "Gertie", "parser creates a Gertie");

test ($gertie->has_symbol_index, 1, "Gertie is indexed");
if ($gertie->has_symbol_index) {
#    warn $gertie->to_string;
}

dump_log();
