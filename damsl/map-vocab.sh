cat vocab.txt | perl -e 'open F,"<".shift;while(<F>){($d,$g)=split;$gertie{$d}=$g}close F;while(<>){if(/^(\S+)\s+(.*)/){($d,$t)=($1,$2);unless(defined$gertie{$d}){for$k(sort{length($b)<=>length($a)}keys%gertie){if(substr($d,0,length($k))eq$k){$gertie{$d}=$gertie{$k};warn"Adding $d -> $k\n";last}}}if(defined$gertie{$d}){print"$gertie{$d} $t\n"}else{warn"Skipped: $d\n"unless$seen{$d}++}}}' damsl-mapping.txt