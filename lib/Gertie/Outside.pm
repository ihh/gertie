package Gertie::Outside;
use Moose;
use AutoHash;
use Gertie;
extends 'AutoHash';

use strict;

# generic imports
use Carp qw(carp croak cluck confess);
use Data::Dumper;
use File::Temp;
use Scalar::Util;
use IPC::Open3;
use Symbol qw(gensym);

# specific imports
use Graph::Directed;
use Time::Progress;
use Term::ANSIColor;

# Let seq[0] be the first symbol in the sequence, seq[1] the second, etc., up to seq[length-1] the last symbol.
# For j>=i (with j=i corresponding to the empty subsequence):
# By "the subsequence from i..j-1" we mean inclusive of both i and j-1, or the empty sequence if i=j.

# Inside matrix
# p(i,j,sym) = P(seq[i]..seq[j-1] | sym)
#  = probability that parse tree rooted at sym will generate subseq i..j-1 (inclusive)
#  = sum_{symB,symC} P(sym->symB symC) sum_{k=i}^j p(i,k,symB) p(k,j,symC)

# p(i,i,sym) = p_end(sym)
# p_end(end) = 1
# p(i,j,term) = delta(j=i+1) delta(seq[i]=term)

# P(sequence) = p(0,length,start)

# Outside matrix
# r(i,j,sym) = P(seq[0]..seq[i] . sym . seq[j-1]..seq[length-1] | start)
#  = probability that derivation stopping at sym will generate everything except subseq i..j-1
#  = sum_{symA,symB} P(symA->symB sym) sum_{k=0}^i r(k,j,symA) p(k,i,symB)
#    + sum_{symA,symC} P(symA->sym symC) sum_{k=j}^{length} r(i,k,symA) p(j,k,symC)

# Posterior probability that symbol X generated subseq i..j-1 is r(i,j,X)*p(i,j,X)/p(0,length,start)
# Post. prob. that rule A->BC generated i..j-1 and j..k-1 is r(i,j,A)*p(i,k,B)*p(k,j,C)*P(A->BC)/p(0,length,start)


# constructor
sub new_Outside {
    my ($class, $inside) = @_;
    my $self = AutoHash->new ( 'inside' => $inside,
			       'gertie' => $inside->gertie,
			       'tokseq' => $inside->tokseq,
			       'verbose' => 0,
			       @args );
    bless $self, $class;
    return $self;
}

sub len {
    my ($self) = @_;
    return @{$self->tokseq} + 0;
}

sub to_string {
    my ($self) = @_;
    my $gertie = $self->gertie;
    my $len = $self->len;
    my @out;
    my @sym = @{$self->gertie->sym_name};
    for (my $i = $len; $i >= 0; --$i) {

	for (my $j = $i; $j <= $len; ++$j) {
	    push @out, "Outside ($i,$j):";
	    for my $sym_id (0..$#sym) {
#		my $pval = $self->get_p ($i, $j, $sym_id);
#		push @out, " ", $sym[$sym_id], "=>", $pval if $pval > 0;
	    }
	    push @out, "\n";
	}
    }
    return join ("", @out);
}

sub post_prob {
    my ($self, $i, $j, $sym) = @_;
    # more to go here
}

1;
