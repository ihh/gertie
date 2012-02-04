#!/usr/bin/perl -w

use Gertie;

my $g = Gertie->new_from_file ('GRAMMAR', 'verbose' => 99);

my $simparse = $g->simulate;
print Data::Dumper->new($simparse)->Dump;

my @seq = $g->tokenize (['D']);
my ($p, $q) = $g->prefix_Inside (\@seq);
$g->print_Inside ($p, $q);

my $tbparse = $g->traceback_Inside ($p, $q);
print Data::Dumper->new($tbparse)->Dump;
