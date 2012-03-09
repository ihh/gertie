#!/usr/bin/env perl -w
my (%seen,%gertie);
open F,"<damsl-mapping.txt";while(<F>){my ($d,$g)=split;$gertie{$d}=$g}close F;
my $started;
for my $file (@ARGV) {
    open F, "<$file";
while(<F>){if(/^===/){++$started;next}next unless $started;if(/^(\S+)\s+([A-Z])\.\d+ utt\d+: (.*?)\s*\/\s*$/){my($d,$s,$t)=($1,$2,$3);unless(defined$gertie{$d}){for$k(sort{length($b)<=>length($a)}keys%gertie){if(substr($d,0,length($k))eq$k){$gertie{$d}=$gertie{$k};warn"Adding $d -> $k\n";last}}}if(defined$gertie{$d}){print"$gertie{$d}\@$s $t\n"}else{warn"Skipped: $d\n"unless$seen{$d}++}}}
    close F;
}

