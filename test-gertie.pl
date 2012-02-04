#!/usr/bin/perl -w

use Gertie;

my $g = Gertie->new_from_file ('GRAMMAR', 'verbose' => 99);

my $simparse = $g->simulate;
print $g->print_parse_tree($simparse), "\n";

my @seq = $g->tokenize (['D']);
my ($p, $q) = $g->prefix_Inside (\@seq);
print $g->print_Inside ($p, $q);

my $tbparse = $g->traceback_Inside ($p, $q);
print $g->print_parse_tree($tbparse), "\n";
