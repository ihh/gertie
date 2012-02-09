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
my ($grammar_file, $text_file);
GetOptions ("grammar=s"   => \$grammar_file,
	    "text=s"   => \$text_file,
	    "verbose=i"  => \$verbose);

if (@ARGV && !defined $grammar_file) {
    $grammar_file = shift;
}

die "You must specify a filename" unless defined $grammar_file;

my $robin = Robin->new_from_file ($grammar_file,
				  'verbose' => $verbose,
				  defined($text_file) ? ('text_file' => $text_file) : ());

$robin->play;


END {
    print color('reset');
}
