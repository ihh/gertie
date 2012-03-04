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

# constructor
sub new_parser {
    my ($class, @args) = @_;

    my $self = AutoHash->new ( # ...
			       @args );
    bless $self, $class;
    return $self;
}

# parse method
sub parse {
    my ($self, @text) = @_;
    # ...
}

# grammar
$grammar = <<END;
END

1;
