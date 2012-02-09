#!/usr/bin/perl -w

use Cwd qw(abs_path);
use FindBin;
use lib abs_path("$FindBin::Bin/../lib");

use Robin;

unless (@ARGV) {
    warn "Waiting for grammar on standard input\n";
    push @ARGV, '-';
}
my $robin = Robin->new_from_file (shift, 'verbose'=>9);
$robin->gertie->verbose(1);  # do this after reading the file
$robin->play;
