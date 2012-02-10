#!/usr/bin/perl -w

use Cwd qw(abs_path);
use FindBin;
use Getopt::Long;
use Term::ANSIColor;
use lib abs_path("$FindBin::Bin/../lib");


use Robin;

$SIG{'INT'} = sub {
    print color('reset'), "\n";
    print STDERR color('reset'), "\n";
    exit;
    kill 6, $$; # ABRT = 6
};

my $verbose = 0;
my ($grammar_file, $text_file, $trace_file, $seed, $rounds);
GetOptions ("grammar=s"   => \$grammar_file,
	    "text=s"   => \$text_file,
	    "trace=s"  => \$trace_file,
	    "verbose=i"  => \$verbose,
	    "seed=i"  => \$seed,
	    "rounds=i"  => \$rounds);

if (@ARGV && !defined $grammar_file) {
    $grammar_file = shift;
}

die "You must specify a filename" unless defined $grammar_file;

my $robin = Robin->new_from_file ($grammar_file,
				  'verbose' => $verbose,
				  defined($text_file) ? ('text_filename' => $text_file) : (),  # don't override default
				  'trace_filename' => $trace_file,
				  'rand_seed' => $seed,
				  'max_rounds' => $rounds);

$robin->play;


END {
    print color('reset');
}
