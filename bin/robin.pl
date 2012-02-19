#!/usr/bin/env perl -w

use Cwd qw(abs_path);
use FindBin;
use Getopt::Long;
use Term::ANSIColor;
use lib abs_path("$FindBin::Bin/../lib");


use Gertie::Robin;

$SIG{'INT'} = sub {
    print color('reset'), "\n";
    print STDERR color('reset'), "\n";
    exit;
    kill 6, $$; # ABRT = 6
};

my $verbose = 0;
my $color = 0;
my $c_parser = 0;
my ($grammar_file, $text_file, $game_file, $trace_file, $seed, $rounds);
GetOptions ("grammar=s"   => \$grammar_file,
	    "text=s"   => \$text_file,
	    "trace=s"  => \$trace_file,
	    "verbose=i"  => \$verbose,
	    "seed=i"  => \$seed,
	    "rounds=i"  => \$rounds,
	    "color" => \$color,
	    "cparser" => \$c_parser,
	    "restore=s" => \$game_file);  # not yet used

if (@ARGV && !defined $grammar_file) {
    $grammar_file = shift;
}

die "You must specify a filename" unless defined $grammar_file;

my $robin = Gertie::Robin->new_from_file
    ($grammar_file,
     'verbose' => $verbose,
     'inside_args' => [ 'verbose' => $verbose ],
     'gertie_args' => [ 'verbose' => $verbose, 'use_c_parser' => $c_parser ],
     defined($text_file) ? ('text_filename' => $text_file) : (),  # don't override default
     'trace_filename' => $trace_file,
     'initial_restore_filename' => $game_file,
     'rand_seed' => $seed,
     'max_rounds' => $rounds,
     'use_color' => $color);

$robin->play;


END {
    print color('reset');
}
