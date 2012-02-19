package Gertie::Evaluator;
use Moose;
use strict;

# generic imports
use Carp qw(carp croak cluck confess);
use Data::Dumper;
use File::Temp;
use Scalar::Util;
use IPC::Open3;
use Symbol qw(gensym);

# methods
sub evaluate {
    local $_;
    for $_ (@_) {
	s/\%\[(.*?)\]\%//g;
	while (/\%\{(.*?)\}\%/) {
	    my $__expr__ = $1;
	    my $__val__ = eval($__expr__);
	    $__val__ = "" unless defined $__val__;
	    s/\%\{(.*?)\}\%/$__val__/;
#	    warn "dedication=",$v{'dedication'};
	}
	s/\\\n//g;
    }
    @_;
}

1;
