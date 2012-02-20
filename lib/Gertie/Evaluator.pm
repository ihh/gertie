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
    my ($expr, $val, @result, %a);
  SHIFT:
    goto NO_SHIFT unless @_;
    $_ = shift (@_);
    s/\%\[(.*?)\]\%//g;
  MATCH:
    goto NO_MATCH unless /\%\{(.*?)\}\%/;
    $expr = $1;
    $expr =~ s/\$(\w+)/\$a\{'$1'\}/g;
    $val = eval($expr);
    $val = "" unless defined $val;
#    warn "$expr evaluated to $val";
    s/\%\{(.*?)\}\%/$val/;
    goto MATCH;
  NO_MATCH:
    s/\\\n//g;
    push @result, $_;
    goto SHIFT;
  NO_SHIFT:
    return @result;
}

1;
