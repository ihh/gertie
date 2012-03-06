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
our $use_percy = 1;

# parser
sub new_parser {
    return Parse::RecDescent->new ($grammar);
}

# parse method
# returns object of type Gertie::Robin
sub parse {
    my ($text, @args) = @_;
    my $parser = new_parser();
    return $parser->grammar ($text, 1, @args);
}

# parse wrappers
sub new_robin_from_file {
    my ($filename, @args) = @_;
    return parse (Gertie::file_contents ($filename), 'robin_args' => \@args);
}

sub new_gertie_from_string {
    my ($text, @args) = @_;
    my $robin = parse ($text, 'gertie_args' => \@args);
    unless (defined($robin) && ref($robin) eq 'Gertie::Robin') {
	$::RD_TRACE = 1;
	$robin = parse($text);
	confess "Parse failed: return value undefined" unless defined($robin);
	confess "Parse failed: returned $robin";
    }
    return $robin->gertie;
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
