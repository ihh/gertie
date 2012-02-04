#!/usr/bin/perl -w

use Gertie;
my $g = Gertie->new_from_file ('GRAMMAR', 'verbose' => 1);
my @seq = $g->tokenize (['D']);
my ($p, $q) = $g->prefix_Inside (\@seq);
$g->print_Inside ($p, $q);
