package Robin;
use Moose;
use AutoHash;
use Gertie;
use Gertie::Inside;
use Fasta;
extends 'AutoHash';

use strict;

# constructors
sub new_robin {
    my ($class, $gertie, @args) = @_;
    my $self = AutoHash->new ( 'gertie' => $gertie,
			       'seq' => [],
			       'tokseq' => [],
			       'inside' => $gertie->prefix_Inside([]),
			       'choice_text' => undef,
			       'narrative_text' => undef,
			       'options_per_page' => 3,
			       'updates' => [],
			       'verbose' => 0,
			       @args );
    bless $self, $class;
    return $self;
}

sub new_from_file {
    my ($class, $filename, @args) = @_;
    my $gertie = Gertie->new_from_file ($filename);
    my $self = $class->new_robin ($gertie, @args);
    my ($choice_file, $narrative_file) = map ("$filename.$_", qw(choice narrative));
    $self->load_choice_text ($choice_file) if -e $choice_file;
    $self->load_narrative_text ($narrative_file) if -e $narrative_file;
    return $self;
}

sub load_choice_text {
    my ($self, $filename) = @_;
    $self->{'choice_text'} = Fasta->new_from_file ($filename);
}

sub load_narrative_text {
    my ($self, $filename) = @_;
    $self->{'narrative_text'} = Fasta->new_from_file ($filename);
}

# play method
sub play {
    my ($self) = @_;
  GAMELOOP: while (1) {
    ROUNDROBIN: for my $agent (@{$self->gertie->agents}) {
	    # log/debug
	    warn "[Turn: $agent]" if $self->verbose;
	    warn "Sequence so far: (@{$self->seq})" if $self->verbose;
	    warn "Inside matrix:\n", $self->inside->to_string if $self->verbose > 9;

	    # can we continue/play this agent?
	    last GAMELOOP unless $self->inside->continue_prob > 0;
	    my %term_prob = $self->inside->next_term_prob ($agent);
	    my @next_term = sort { $term_prob{$b} <=> $term_prob{$a} } keys %term_prob;
	    my @next_prob = map ($term_prob{$_}, @next_term);
	    unless (@next_term) {
		warn "[No available move for $agent]" if $self->verbose;
		next ROUNDROBIN;
	    }

	    # get next terminal from appropriate agent
	    my $next_term;
	    if ($agent eq $self->gertie->player_agent) {
		$next_term = $self->player_choice (@next_term);
	    } else {
		$next_term = Gertie::sample (\@next_prob, \@next_term);
	    }

	    # store terminal
	    push @{$self->seq}, $next_term;
	    push @{$self->tokseq}, $self->gertie->sym_id->{$next_term};
	    push @{$self->updates}, $next_term;
	    warn "Terminal: $next_term" if $self->verbose > 20;

	    # update inside matrix
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
#    return $options[0] if @options == 1;
    my $page = 0;
    my $choice;
    my $choice_text = $self->choice_text;
    my $narrative_text = $self->narrative_text;
    while (!defined $choice) {
	# build menu
	my $min = $page * $self->options_per_page;
	my $max = $min + $self->options_per_page - 1;
	$max = $#options if $max > $#options;
	my @menu = @options[$min..$max];
	if (defined $choice_text) { @menu = map (defined($choice_text->{$_}) ? $choice_text->{$_} : $_, @menu) }

	# add extra pseudo-options
	my ($next_page, $prev_page, $review) = (-1, -1, -1);
	if ($max < $#options) { push @menu, "More options"; $next_page = $#menu }
	if ($page > 0) { push @menu, "Previous options"; $prev_page = $#menu }
	if (@{$self->seq} > 0) { push @menu, "Review the story so far"; $review = $#menu }

	# print the menu
#	if (@options > $self->options_per_page) { print "[Page ", $page + 1, "]\n" }
	my @updates = map (defined($narrative_text) && defined($narrative_text->{$_})
			   ? $narrative_text->{$_}
			   : "$_\n",
			   @{$self->updates});
	print
	    @updates,
	    "Your choices:\n",
	    map (" ".($_+1).".  $menu[$_]\n", 0..$#menu),
	    "Enter your choice: ";
	@{$self->updates} = ();

	# get user input
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

	# decode user input
	if ($n == $next_page) { ++$page }
	elsif ($n == $prev_page) { --$page }
	elsif ($n == $review) { print "\n--- From the Beginning:\n", $self->story_so_far, "--- That's it, so far.\n\n" }
	else { $choice = $n + $min }
    }
    return $options[$choice];
}

sub story_so_far {
    my ($self) = @_;
    my @out;
    my $narrative_text = $self->narrative_text;
    for my $sym (@{$self->seq}) {
	if (defined($narrative_text) && defined($narrative_text->{$sym})) {
	    push @out, $narrative_text->{$sym};
	} else {
	    push @out, "$sym\n";
	}
    }
    return join ("", @out);
}
