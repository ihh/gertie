#!/usr/bin/perl -w

use Cwd qw(abs_path);
use FindBin;
use lib abs_path("$FindBin::Bin/../lib");

use Robin;

unless (@ARGV) {
    warn "Waiting for grammar on standard input\n";
    push @ARGV, '-';
}
my $robin = Robin->new_from_file (shift, 'verbose' => 5);
$robin->play;
