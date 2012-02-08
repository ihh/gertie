package Robin;
use Moose;
use AutoHash;
use Gertie;
use Gertie::Inside;
extends 'AutoHash';

use strict;

# constructors
sub new_robin {
    my ($class, $gertie, @args) = @_;
    my $self = AutoHash->new ( 'gertie' => $gertie,
			       'seq' => [],
			       'tokseq' => [],
			       'inside' => $gertie->prefix_Inside([]),
			       'options_per_page' => 3,
			       'verbose' => 0,
			       @args );
    bless $self, $class;
    return $self;
}

sub new_from_file {
    my ($class, $filename, @args) = @_;
    my $gertie = Gertie->new_from_file ($filename);
    return $class->new_robin ($gertie, @args);
}

# play method
sub play {
    my ($self) = @_;
    while (1) {
	for my $agent (@{$self->gertie->agents}) {
	    warn "[Turn: $agent]" if $self->verbose;
	    warn "Sequence so far: (@{$self->seq})" if $self->verbose;
	    warn "Inside matrix:\n", $self->inside->to_string if $self->verbose > 9;
	    next unless $self->inside->continue_prob > 0;
	    my %term_prob = $self->inside->next_term_prob ($agent);
	    my @next_term = sort { $term_prob{$a} <=> $term_prob{$b} } keys %term_prob;
	    my @next_prob = map ($term_prob{$_}, @next_term);
	    next unless @next_term;
	    my $next_term;
	    if ($agent eq $self->gertie->player_agent) {
		$next_term = $self->player_choice (@next_term);
	    } else {
		$next_term = Gertie::sample (\@next_prob, \@next_term);
	    }
	    $self->print_term ($next_term);
	    push @{$self->seq}, $next_term;
	    push @{$self->tokseq}, $self->gertie->sym_id->{$next_term};
	    my $inside = $self->gertie->prefix_Inside ($self->tokseq, $self->inside);
	    $self->inside ($inside);
	}
    }
}

sub print_term {
    my ($self, $term) = @_;
    print $term, "\n";
}

sub player_choice {
    my ($self, @options) = @_;
    return $options[0] if @options == 1;
    my $page = 0;
    my $choice;
    while (!defined $choice) {
	my $min = $page * $self->options_per_page;
	my $max = $min + $self->options_per_page - 1;
	$max = $#options if $max > $#options;
	my @menu = (@options[$min..$max]);
	my ($next_page, $prev_page) = (-1, -1);
	if ($max < $#options) { push @menu, "More options"; $next_page = $#menu }
	if ($page > 0) { push @menu, "Previous options"; $prev_page = $#menu }
#	if (@options > $self->options_per_page) { print "[Page ", $page + 1, "]\n" }
	print
	    "Your choices:\n",
	    map (" ".($_+1).".  $menu[$_]\n", 0..$#menu),
	    "Enter your choice: ";
	my ($input, $n);
	do {
	    $input = <>;
	    chomp $input;
	    if ($input =~ /^\s*(\d+)\s*$/ && $input >= 1 && $input <= @menu) {
		$n = $input - 1;
	    } else {
		print "Invalid choice - try again\nEnter your choice: ";
	    }
	} while (!defined $n);
	if ($n == $next_page) { ++$page }
	elsif ($n == $prev_page) { --$page }
	else { $choice = $n }
    }
    return $options[$choice];
}
