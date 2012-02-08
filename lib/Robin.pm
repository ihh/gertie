package Robin;
use Moose;
use AutoHash;
use Gertie;
use Gertie::Inside;
extends 'AutoHash';

use strict;

# constructor
sub new_robin {
    my ($class, $gertie, @args) = @_;
    my $self = AutoHash->new ( 'gertie' => $gertie,
			       'tokseq' => [],
			       'verbose' => 0,
			       @args );
    bless $self, $class;
    return $self;
}
