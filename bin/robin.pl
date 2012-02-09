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
my $filename;
GetOptions ("filename=s"   => \$filename,
	    "verbose=i"  => \$verbose);

if (@ARGV && !defined $filename) {
    $filename = shift;
}

die "You must specify a filename" unless defined $filename;

my $robin = Robin->new_from_file ($filename, 'verbose' => $verbose);
$robin->play;


END {
    print color('reset');
}
