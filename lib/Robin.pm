package Robin;
use Moose;
use Term::ANSIColor;
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
			       'inside' => undef,

			       'choice_text' => undef,
			       'narrative_text' => undef,

			       'log_color' => color('red on_black'),
			       'input_color' => color('white on_black'),
			       'choice_selector_color' => color('yellow on_black'),
			       'narrative_color' => color('cyan on_black'),
			       'choice_color' => color('white on_blue'),
			       'meta_color' => color('yellow on_black'),

			       'options_per_page' => 3,
			       'turns' => {},
			       'verbose' => 0,
			       @args );
    bless $self, $class;
    return $self;
}

sub new_from_file {
    my ($class, $filename, @args) = @_;
    my $gertie = Gertie->new_from_file ($filename);
    my $self = $class->new_robin ($gertie, @args);
    # quick hack to load choice/narrative files if they have the same filename
    my ($choice_file, $narrative_file) = map ("$filename.$_", qw(choice narrative));
    $self->load_choice_text ($choice_file) if -e $choice_file;
    $self->load_narrative_text ($narrative_file) if -e $narrative_file;
    # return
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
    $self->inside ($self->gertie->prefix_Inside([]));  # initialize empty Inside matrix
    $self->inside->verbose ($self->verbose);  # make the Inside matrix as verbose as we are, for log tidiness
    $self->{'turns'} = { map (($_ => 0), @{$self->gertie->agents}) };
    my $log_color = $self->log_color;
    my $reset_nl = color('reset') . "\n";
    my @begin_log = ($log_color, "--- BEGIN DEBUG LOG", $reset_nl);
    my @end_log = ($log_color, "--- END DEBUG LOG", $reset_nl);
    print @begin_log if $self->verbose;
  GAMELOOP: while (1) {
    ROUNDROBIN: for my $agent (@{$self->gertie->agents}) {
	# status/log messages
	if ($self->verbose) {
	    print $log_color, "Turn: $agent", $reset_nl;
	    print $log_color, "Sequence: (@{$self->seq})", $reset_nl;
	    print $log_color, "Inside matrix:\n", $self->inside->to_string, $reset_nl if $self->verbose > 9;
	}

	# can we continue/play this agent?
	last GAMELOOP unless $self->inside->continue_prob > 0;
	my %term_prob = $self->inside->next_term_prob ($agent);
	my @next_term = sort { $term_prob{$b} <=> $term_prob{$a} } keys %term_prob;
	my @next_prob = map ($term_prob{$_}, @next_term);
	unless (@next_term) {
	    print $log_color, "No available move for $agent", $reset_nl if $self->verbose;
	    next ROUNDROBIN;
	}

	# get next terminal from appropriate agent
	my $next_term;
	if ($agent eq $self->gertie->player_agent) {
	    print @end_log if $self->verbose;
	    $next_term = $self->player_choice (@next_term);
	    print @begin_log if $self->verbose;
	} else {
	    $next_term = Gertie::sample (\@next_prob, \@next_term);
	}

	# record the turn
	++$self->turns->{$agent};
	push @{$self->seq}, $next_term;
	push @{$self->tokseq}, $self->gertie->sym_id->{$next_term};
	print $log_color, "Terminal: $next_term", $reset_nl if $self->verbose;
	push @{$self->updates}, $next_term;

	# update Inside matrix
	my $inside = $self->gertie->prefix_Inside ($self->tokseq, $self->inside);
	$self->inside ($inside);
    }
  }
}

sub player_choice {
    my ($self, @options) = @_;
#    return $options[0] if @options == 1;

    my $choice_text = $self->choice_text;
    my $narrative_text = $self->narrative_text;
    my $input_color = $self->input_color;
    my $choice_selector_color = $self->choice_selector_color;
    my $narrative_color = $self->narrative_color;
    my $choice_color = $self->choice_color;
    my $meta_color = $self->meta_color;

    my $page = 0;
    my $choice;
    while (!defined $choice) {
	# build menu
	my $min = $page * $self->options_per_page;
	my $max = $min + $self->options_per_page - 1;
	$max = $#options if $max > $#options;
	my @menu = @options[$min..$max];
	my @menu_color = map ($choice_color, @menu);
	if (defined $choice_text) { @menu = map (defined($choice_text->{$_}) ? $choice_text->{$_} : $_, @menu) }

	# add extra pseudo-options
	my ($next_page, $prev_page, $review) = (-1, -1, -1);
	if ($max < $#options) { $next_page = add_option (\@menu_color, $meta_color, \@menu, "(more options)") }
	if ($page > 0) { $prev_page = add_option (\@menu_color, $meta_color, \@menu, "(previous options)") }
	if ($self->player_turns > 0) { $review = add_option (\@menu_color, $meta_color, \@menu, "(review transcript)") }

	# print the menu
#	if (@options > $self->options_per_page) { print "[Page ", $page + 1, "]\n" }
	my @updates = map (defined($narrative_text) && defined($narrative_text->{$_})
			   ? $narrative_text->{$_}
			   : "$_\n",
			   @{$self->updates});
	print
	    "\n",
	    $narrative_color,
	    @updates,
	    $meta_color,
	    (@updates ? "\n" : ""),
	    "Your choices:\n",
	    map ((' ', $choice_selector_color, $_ + 1, '.', color('reset'), ' ',
		  $menu_color[$_], $menu[$_],
		  color('reset'), "\n"),
		 0..$#menu),
	    $meta_color,
	    "\nEnter your choice: ",
	    $input_color;
	@{$self->updates} = ();

	# get user input
	my ($input, $n);
	do {
	    $input = <>;
	    chomp $input;
	    $input =~ s/^\s*//;
	    $input =~ s/\s*$//;
	    my $quoted_input = quotemeta($input);
	    if ($input =~ /^\d+/ && $input >= 1 && $input <= @menu) {
		$n = $input - 1;
		print $menu_color[$n], $menu[$n], color('reset'), "\n";
	    } elsif (my @match = grep ($menu[$_] =~ /$quoted_input/i, 0..$#menu)) {
		$n = shift @match;
		print
		    $meta_color, "(Choice ", $n+1, ")", color('reset'), " ",
		    $menu_color[$n], $menu[$n], color('reset'), "\n";
	    } else {
		print $meta_color, "Invalid choice - try again\nEnter your choice: ", $input_color;
	    }
	} while (!defined $n);

	# decode user input
	if ($n == $next_page) { ++$page }
	elsif ($n == $prev_page) { --$page }
	elsif ($n == $review) {
	    print
		"\n",
		$narrative_color,
		$self->story_so_far;
	}
	else { $choice = $n + $min }
    }
    return $options[$choice];
}

sub add_option {
    my ($menu_color_ref, $color, $menu_ref, $option) = @_;
    push @$menu_color_ref, $color;
    push @$menu_ref, $option;
    return $#$menu_ref;
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

sub player_turns {
    my ($self) = @_;
    return $self->turns->{$self->gertie->player_agent};
}
