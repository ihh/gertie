perl -e 'for$_(@ARGV){open F,"<$_";while(<F>){last if/^===/}while(<F>){if(/^(\S+)\s+([AB]).*utt\d+: (.*)/){print"$1\@$2 $3\n"}}close F}' */*.utt
