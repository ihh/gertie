#!/usr/bin/env perl -w

use Cwd qw(abs_path);
use FindBin;
use lib abs_path("$FindBin::Bin/../lib");

use Gertie::Percy;

my @log;
my $failed = 0;

$::RD_HINT = 1;
# $::RD_TRACE = 1;

# text file
my $text_file = abs_path("$FindBin::Bin/../t/turn-grammar");

# At some point, move contents of $grammar_file to $Gertie::Percy::grammar
my $grammar_file = $Gertie::Percy::grammar_file;
my $grammar = $Gertie::Percy::grammar;

my $parser = Gertie::Percy::new_parser;
test_crucial (!$failed && defined($parser)?1:0, 1, "Gertie::Percy initialized from $grammar_file");
my @basic = ("a" => "identifier",
	     "1" => "numeric_constant",
	     '"blurgh"' => "string_literal",
	     '"\"blurgh\", he said."' => "narrative_literal",
	     '{$blurgh=3}' => 'code_block');
while (@basic) {
    my $text = shift @basic;
    my $sym = shift @basic;
    my $expr = "\$parser->$sym(\$text)";
    my $expr_eval = eval ($expr);
    test_crucial ($failed ? undef : $expr_eval, $text, "'$text' parsed as $sym and recovered");
}

my $t0 = "a -> b c";
my $t1 = "a -> b c (1)";
my $ts = "a -> b c;";
my $t_rp = "a -> b c (3*2+1)";
test_parser ([$t0, $t1, $ts, $t_rp],
	     [qw(generic_rule rule statement statement_list)],
	     1, 4,  # rules, symbols
	     1);  # test serialization

my $t_nl = 'a -> "blurgh"';
my $t_anl = 'a -> "ug"=>"blurgh"';
my $t_anc = 'a -> "ug"=>{"blurgh"}';
my $t_ane = 'a -> "ug"=>start';
test_parser ([$t_nl, $t_anl, $t_anc, $t_ane],
	     [qw(narrative_rule rule statement statement_list)],
	     0, 2,  # rules, symbols
	     0);  # change this last 0 to 1 to test serialization

sub test_parser {
    my ($text_list, $sym_list, $rules, $symbols, $test_serialization) = @_;
    for my $t (@$text_list) {
	my %sym_eval;
	my $p = Gertie::Percy::new_parser;
	for my $sym (@$sym_list, 'grammar') {
	    my $expr = "\$p->$sym(\$t)";
	    my $expr_eval = eval ($expr);
	    test_crucial (!$failed && defined($expr_eval) ? 1 : 0, 1, "'$t' parsed to '$sym' in $grammar_file");
	    $sym_eval{$sym} = $expr_eval;
	}

	my $r0 = $sym_eval{'grammar'};
	test_crucial (ref($r0), "Gertie::Robin", "'$t' grammar returns a Gertie::Robin object");

	test_crucial (!$failed && defined($r0->{"gertie"}), 1, "'$t' robin->gertie defined");
	test_crucial (!$failed && ref($r0->gertie), "Gertie", "'$t' robin->gertie is a Gertie");

	test (!$failed && $r0->gertie->has_symbol_index, 1, "'$t' Gertie is indexed");
	test (!$failed && $r0->gertie->n_rules, $rules, "'$t' Gertie has $rules rule(s)");
	test (!$failed && $r0->gertie->n_symbols, $symbols, "'$t' Gertie has $symbols symbol(s)");

	if ($test_serialization) {
	    my $rs = $t . ($t =~ /;$/ ? "" : ";");
	    $rs =~ s/ \(1\)//;
	    test ($failed ? "" : $r0->gertie->to_string, "$rs\n", "'$t' Gertie serializes to '$rs'");
	}
    }
}


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
