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
    my (@result, %attr);
    while (@_) {
	local $_;
	$_ = shift (@_);
	while (/\%\{(.*?)\}\%/) {
	    my ($prefix, $expr, $suffix) = ($`, $1, $');
	    $prefix =~ s/\$\$(\w+)/$attr{$1}/g;
	    $expr =~ s/\$\$(\w+)/\$attr\{'$1'\}/g;
	    my $val = eval($expr);
	    $val = "" unless defined $val;
	    $_ = $prefix . $val . $suffix;
	}
#        while (/\$\$(\w+)/g) {warn$1}
        s/\$\$(\w+)/$attr{$1}/g;
	s/\\\n//g;
	push @result, $_;
    }
    return @result;
}

1;
