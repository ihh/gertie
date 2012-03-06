package Gertie::Percy;
use Moose;
use AutoHash;
use Gertie;
use Parse::RecDescent;
extends 'AutoHash';

use strict;

# generic imports
use Carp qw(carp croak cluck confess);
use Data::Dumper;
use File::Temp;
use Scalar::Util;
use IPC::Open3;
use Symbol qw(gensym);

# package data
our ($grammar_file, $grammar) = libdir_file_path_and_contents ("Gertie/Percy/grammar.txt");

# parser
sub new_parser {
    return Parse::RecDescent->new ($grammar);
}

# parse method
# returns object of type Gertie::Robin
sub parse {
    my ($self, @text) = @_;
    my $text = join ("", @text);
    my $parser = new_parser();
    return $parser->grammar ($text);
}

# load method
sub libdir_file_path_and_contents {
    my ($filename) = @_;
    my $full_path;
    for my $inc (@INC) {
	if (-e ($full_path = "$inc/$filename")) {
	    my @contents = `cat $full_path`;
	    return ($full_path, join("",@contents));
	}
    }
    return (undef, undef);
}

1;
