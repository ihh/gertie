package Gertie::Robin;
use Moose;
use Term::ANSIColor;
use Carp;
use FileHandle;

use AutoHash;
extends 'AutoHash';

use Gertie;
use Gertie::Inside;
use Gertie::Evaluator;

use strict;

# constructors
sub new_robin {
    my ($class, $gertie, @args) = @_;
    my $self = AutoHash->new ( 'gertie' => $gertie,
			       'rand_seed' => undef,

			       'seq' => [],
			       'tokseq' => [],
			       'seq_turn' => [],

			       'inside' => undef,

			       'choice_text' => undef,
			       'narrative_text' => undef,
			       'preamble_text' => "",

			       'turns' => {},
			       'max_rounds' => undef,
			       'current_turn' => undef,

			       'options_per_page' => 3,

			       'trace_filename' => undef,
			       'text_filename' => undef,
			       'default_save_filename' => 'GAME',
			       'initial_restore_filename' => undef,

			       'use_color' => 0,
			       'verbose' => 0,
			       @args );
    bless $self, $class;
    return $self;
}

sub new_from_file {
    my ($class, $filename, %args) = @_;
    my $gertie = Gertie->new_from_file ($filename, defined($args{'gertie_args'}) ? @{$args{'gertie_args'}} : ());
    my $self = $class->new_robin ($gertie, 'text_filename' => "$filename.text", %args);
    $self->load_text_from_file ($self->text_filename) if -e $self->text_filename;
    # return
    return $self;
}

# Color scheme setters
sub use_cool_color_scheme {
    my ($self) = @_;
    my %color = ('log_color' => color('red on_black'),
		 'input_color' => color('white on_black'),
		 'choice_selector_color' => color('white on_black'),
		 'narrative_color' => color('cyan on_black'),
		 'choice_color' => color('white on_blue'),
		 'meta_color' => color('yellow on_black'),
		 'reset_color' => color('reset'));
    while (my ($col, $val) = each %color) {
	$self->{$col} = $val;
    }
}

sub use_boring_color_scheme {
    my ($self) = @_;
    my @color = ('log_color' ,
		 'input_color' ,
		 'choice_selector_color' ,
		 'narrative_color' ,
		 'choice_color' ,
		 'meta_color',
		 'reset_color');
    for my $col (@color) {
	$self->{$col} = color('reset');
    }
}

# Helper to prevent runaway background-colored lines
sub reset_color_newline {
    my ($self) = @_;
    return $self->reset_color . "\n";
}

# Initializers for narrative text database
sub load_text_from_file {
    my ($self, $filename) = @_;
    local *FILE;
    local $_;
    open FILE, "<$filename" or confess "Couldn't open $filename: $!";
    $self->init_text_parser;

    while (<FILE>) { $self->parse_text_line ($_) }
    $self->cleanup_text_parser;
    close FILE;
}

sub load_text_from_string {
    my ($self, @text) = @_;
    @text = map ("$_\n", map (split(/\n/), join ("", @text)));
    $self->init_text_parser;
    for my $line (@text) { $self->parse_text_line ($line) }
    $self->cleanup_text_parser;
}

# Parse/build methods for narrative text database
sub init_text_parser {
    my ($self) = @_;
    $self->{'choice_text'} = {};
    $self->{'narrative_text'} = {};
    $self->{'current_text_symbol'} = undef;
}

sub cleanup_text_parser {
    my ($self) = @_;
    delete $self->{'current_text_symbol'};
}

sub parse_text_line {
    my ($self, $line) = @_;
    if ($line =~ /^\s*>\s*(\S+)\s*(.*)$/) {
	my ($name, $choice) = ($1, $2);
	carp "Multiple definitions of $name -- overwriting" if defined $self->choice_text->{$name};
	$self->choice_text->{$name} = $choice;
	$self->narrative_text->{$name} = "";
	$self->current_text_symbol ($name);
    } elsif (defined $self->current_text_symbol) {
	$self->narrative_text->{$self->current_text_symbol} .= $line;
    } else {
	$self->{'preamble_text'} .= $line;
    }
}

# Play a game interactively over an ANSI terminal
sub play {
    my ($self) = @_;

    # initialize ANSI terminal color
    if ($self->use_color) { $self->use_cool_color_scheme } else { $self->use_boring_color_scheme }

    # initialize debugging log
    my $log_color = $self->log_color;
    my $reset_color_newline = $self->reset_color_newline;
    my @begin_log = ($log_color, "--- BEGIN DEBUG LOG", $reset_color_newline);
    my @end_log = ($log_color, "--- END DEBUG LOG", $reset_color_newline);
    print @begin_log if $self->verbose;

    # open trace file
    my $trace_fh;
    if (defined $self->trace_filename) {
	$trace_fh = FileHandle->new (">".$self->trace_filename)
	    or confess "Couldn't open ", $self->trace_filename, ": $!";
	autoflush $trace_fh 1;
    }
    $self->{'trace_fh'} = $trace_fh;

    # initialize random seed
    $self->rand_seed (time) unless defined $self->rand_seed;
    srand ($self->rand_seed);
    print $log_color, "Random seed: ", $self->rand_seed, $reset_color_newline if $self->verbose;

    # load state of game (i.e. terminal sequence), if applicable
    if (defined $self->initial_restore_filename) {
	$self->load_and_print_game ($self->initial_restore_filename);
    } else {
	# reset state of game (i.e. terminal sequence)
	$self->reset();
	# print preamble
	$self->print_latest_episode;
    }

    # Main loop
GAMELOOP:    
    while (1) {

	# Round Robin: each turn (terminal) is offered to one agent, visiting all agents cyclically.
	# Note that these rules distort the probabilistic structure of the grammar, encouraging cyclic sequences.
	# The structure would not be distorted if we sampled the next agent randomly.
	# TODO: add option to sample next agent randomly, then advance the turn counter until it's that agent's turn.

	# One "round" = a visit to each of N agents, in order = N "turns"
	my $turn = $self->current_turn;
	my $round = $self->current_round;
	my $agent = $self->current_agent;

	# status/log messages, for debugging
	if ($self->verbose) {
	    print $log_color, "Turn: ", $turn, $reset_color_newline;
	    print $log_color, "Round: ", $round + 1, $reset_color_newline;
	    print $log_color, "Agent: $agent", $reset_color_newline;
	    print $log_color, "Player turns: ", $self->player_turns, $reset_color_newline;
	    print $log_color, "Sequence: (@{$self->seq})", $reset_color_newline;
	    print $log_color, "Inside matrix:\n", $self->inside->to_string, $reset_color_newline if $self->verbose > 9;
	}

	# can we continue?
	last GAMELOOP unless $self->play_continues;

	# log
	print @end_log if $self->verbose;

	# get next terminal
	my $next_term;
	if ($self->is_players_turn) {
	    $next_term = $self->player_choice;
	} else {
	    $next_term = $self->agent_choice;
	}

	# record the turn
	$self->record_turn ($next_term);

	# print narrative text
	$self->print_latest_episode if defined $next_term;

	# log
	if ($self->verbose) {
	    print @begin_log;
	    print $log_color, "Terminal: $next_term", $reset_color_newline;
	}
    }

    # end log
    print @end_log if $self->verbose;

    # close trace
    if (defined $trace_fh) {
	$trace_fh->close or confess "Couldn't close ", $self->trace_filename, ": $!";
	delete $self->{'trace_fh'};
    }
}

# Test to see if more moves are possible
sub play_continues {
    my ($self) = @_;
    my $more_rounds = !defined($self->max_rounds) || $self->current_round() < $self->max_rounds;
    my $more_probability = $self->inside->continue_prob > 0;
    return $more_rounds && $more_probability;
}

# Test to see if it's the player's move
sub is_players_turn {
    my ($self) = @_;
    return $self->current_agent eq $self->gertie->player_agent;
}

# Wrapper to record the player's move then advance to the next player move
sub record_player_turn {
    my ($self, $next_term) = @_;
    if (defined $next_term) {
	confess "Not player's turn" unless $self->is_players_turn;
	$self->record_turn ($next_term);
    } else {
	confess "Can't skip player's turn" if $self->is_players_turn;
    }
    while (!$self->is_players_turn) {
	$self->record_turn ($self->agent_choice);
    }
}

# The dumbest AI for playing a move. Selects at random from the posterior for the current agent's move
# Returns undef if no move is possible move for this agent
sub random_choice {
    my ($self) = @_;
    my $next_term;
    my $agent = $self->current_agent;

    my ($term_prob_hashref, $next_term_listref) = $self->next_term_prob;
    if (@$next_term_listref) {
	my @next_prob = map ($term_prob_hashref->{$_}, @$next_term_listref);
	$next_term = Gertie::sample (\@next_prob, $next_term_listref);
    }
    return $next_term;
}

# Wrapper for the dumbest AI ever
# A place to hang future, even dumber AI
sub agent_choice {
    my ($self) = @_;
    return $self->random_choice;
}

# Accessor for current agent
sub current_agent {
    my ($self) = @_;
    my $turn = $self->current_turn;
    my $n_agents = @{$self->gertie->agents};
    my $round = int ($turn / $n_agents);
    my $agent = $self->gertie->agents->[$turn % $n_agents];
    return $agent;
}

# Accessor for current round number
sub current_round {
    my ($self) = @_;
    my $turn = $self->current_turn;
    my $n_agents = @{$self->gertie->agents};
    my $round = int ($turn / $n_agents);
    return $round;
}

# Accessor to count the number of turns the player has had
sub player_turns {
    my ($self) = @_;
    return $self->turns->{$self->gertie->player_agent};
}

# Method to advance the turn counter and (optionally) record a turn
sub record_turn {
    my ($self, $next_term) = @_;
    if (defined $next_term) {
	my $agent = $self->gertie->term_owner_by_name->{$next_term};
	my $trace_fh = $self->trace_fh;
	++$self->turns->{$agent};
	push @{$self->seq}, $next_term;
	push @{$self->tokseq}, $self->gertie->sym_id->{$next_term};
	push @{$self->seq_turn}, $self->current_turn;
	if (defined $trace_fh) { print $trace_fh "PUSH $next_term\n" }

	# update Inside matrix
	$self->inside->push_sym ($next_term);
    }

    # count
    ++$self->{'current_turn'};
}

# Method to undo a turn, winding back the turn counter
sub undo_turn {
    my ($self, $agent) = @_;
    my $trace_fh = $self->trace_fh;
    while (@{$self->seq}) {
	my $undone_term = pop @{$self->seq};
	my $undone_term_id = pop @{$self->tokseq};
	$self->inside->pop_tok();
	$self->current_turn (pop @{$self->seq_turn});
	--$self->turns->{$self->current_agent};
	if (defined $trace_fh) { print $trace_fh "POP $undone_term\n" }
	last if !defined($agent) || $agent eq $self->current_agent;
    }
}

# Reset
sub reset {
    my ($self) = @_;
    $self->seq ([]);
    $self->tokseq ([]);
    $self->seq_turn ([]);
    $self->inside ($self->gertie->prefix_Inside ([], @{$self->inside_args}));  # initialize empty Inside matrix
    $self->{'turns'} = { map (($_ => 0), @{$self->gertie->agents}) };
    $self->current_turn(0);
}

# Default 'error' handler for save/restore dialogs
sub terminal_error_handler {
    my ($self) = @_;
    return sub { print $self->meta_color, @_, $self->reset_color_newline };
}

# Load game
sub load_game {
    my ($self, $filename, $err_handler) = @_;
    $filename = $self->default_save_filename unless defined $filename;
    $err_handler = $self->terminal_error_handler unless defined $err_handler;
    unless (-e $filename)
    { &$err_handler ("Oops - I can't find a game called '$filename'. Are you sure you spelled it right?"); return 0 }
    local *FILE;
    local $_;
    unless (open FILE, "<$filename")
    { &$err_handler ("Oops - I wasn't able to load game '$filename': $!"); return 0 }
    $self->reset;
    while (<FILE>) {
	my ($turn, $term) = split;
	$self->current_turn ($turn);
	$self->record_turn ($term);
    }
    close FILE;
    ++$self->{'current_turn'};
    return 1;
}

# Terminal wrapper for load_game
sub load_and_print_game {
    my ($self, $filename) = @_;
    my $ok = $self->load_game ($filename);
    if ($ok) {
	print $self->meta_color, "Game restored from file '$filename'.", $self->reset_color_newline;
	$self->print_latest_episode;
    }
    return $ok;
}

# Simple yes/no dialog
sub yes_or_no {
    my ($self, $err_handler) = @_;
    $err_handler = $self->terminal_error_handler unless defined $err_handler;
    &$err_handler ("Please type 'yes' or 'no':");
    my $yes_no;
    while (1) {
	$yes_no = <>;
	last if $yes_no =~ /\S/;
	&$err_handler ("Please type 'yes' or 'no'.");
    }
    if ($yes_no =~ /^\s*y/i) {
	return 1;
    }
    unless ($yes_no =~ /^\s*n/i) {
	&$err_handler ("I didn't really understand your answer, so I'm taking that as a 'no'.");
    }
    return 0;
}

# Save game
sub save_game {
    my ($self, $filename, $err_handler) = @_;
    $filename = $self->default_save_filename unless defined $filename;
    $err_handler = $self->terminal_error_handler unless defined $err_handler;
    if (-e $filename) {
	&$err_handler ("There's already a file called '$filename'. Are you sure you want to overwrite it?");
	return 0 unless $self->yes_or_no ($err_handler);
    }
    local *FILE;
    unless (open FILE, ">$filename")
    { &$err_handler ("Oops - I wasn't able to save the game to the file '$filename': $!");
      return 0 }
    for (my $n = 0; $n < @{$self->seq}; ++$n) {
	print FILE $self->seq_turn->[$n], " ", $self->seq->[$n], "\n";
    }
    unless (close FILE)
    { &$err_handler ("Oops - I couldn't save the game to file '$filename': $!") }
    &$err_handler ("OK, game saved to file '$filename'.");
    return 1;
}

# Simple terminal-based dialog handler for savefiles
sub get_save_filename {
    my ($self) = @_;
    print
	$self->meta_color,
	"Please enter a filename (or just hit RETURN to use the default filename, '",
	$self->default_save_filename, "')",
	$self->reset_color_newline;
    my $filename = <>;
    chomp $filename;
    $filename =~ s/^\s*(.*?)\s*$/$1/;
    $filename = $self->default_save_filename unless length($filename);
    return $filename;
}

# Probability distribution over next terminal
# Returns a list of two references: the distribution (as a hashref), and the sorted key list (as an arrayref)
sub next_term_prob {
    my ($self) = @_;
    my %term_prob_hash = $self->inside->next_term_prob ($self->current_agent);
    my @term_list = sort { $term_prob_hash{$b} <=> $term_prob_hash{$a}
			   || $a cmp $b } keys %term_prob_hash;
    return (\%term_prob_hash, \@term_list);
}

# Present a menu on a ANSI terminal; read choice from stdin
sub player_choice {
    my ($self) = @_;

REDISPLAY:
    my ($tp_hash, $t_list) = $self->next_term_prob;
    my @options = @$t_list;

    return undef unless @options;

# Commented-out line chooses automatically if there is only one choice
#    return $options[0] if @options == 1;

    my $choice_text = $self->choice_text;
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

	# Create menu text
	my @menu = @options[$min..$max];
	my $tidy = sub { local $_ = shift; s/\@\w+$//; return $_ };
	if (defined $choice_text) { @menu = map (defined($choice_text->{$_}) && length($choice_text->{$_})
						 ? $choice_text->{$_}
						 : &$tidy($_),
						 @menu) }

	# Create menu callbacks
	my @item_callback = map ([$choice_color . $_, sub { $choice = shift() + $min; print "\n" }],
				 @menu);

	if ($max < $#options) {
	    push @item_callback,
	    [$meta_color . "(more choices)", sub { ++$page }];
	}

	if ($page > 0) {
	    push @item_callback,
	    [$meta_color . "(previous choices)", sub { --$page }];
	}

	if ($self->player_turns > 0) {
	    push @item_callback,
	    [$meta_color . "(review the story so far)", sub { $self->print_story_so_far } ],
	    [$meta_color . "(undo my last choice)", sub { $self->undo_turn ($self->gertie->player_agent);
							  $self->print_latest_episode;
							  goto REDISPLAY } ];
	}

	push @item_callback,
	[$meta_color . "(save the game)",
	 sub { if ($self->save_game ($self->get_save_filename)) { $self->print_latest_episode } }],
	[$meta_color . "(restore the game)", sub { $self->load_and_print_game ($self->get_save_filename);
						   goto REDISPLAY }];

	# variables determining whether to print the menu
	my $display_choices = 1;
	my $display_prompt = 1;
	my $frustrated_tries = 0;
	my $max_frustrated_tries = 3;

	# get user input
	my ($input, $n);
	do {
	    # Redisplay the choices periodically
	    if ($frustrated_tries) {
		$display_prompt = 1;
		if ($frustrated_tries >= $max_frustrated_tries) {
		    $display_choices = 1;
		    $frustrated_tries = 0;
		    print "\n";
		}
	    }

	    # Commented-out line displays page number in longer choices list
	    # if (@options > $self->options_per_page) { print "[Page ", $page + 1, "]\n" if $display_choices }
	    print
		"\n",
		$meta_color,
		"Your choices:\n",
		map ((' ', $choice_selector_color, $_ + 1, '.', $self->reset_color, ' ',
		      $item_callback[$_]->[0],
		      $self->reset_color, "\n"),
		     0..$#item_callback)
		if $display_choices;
	    print
		$meta_color, "\nEnter your choice: ", $input_color if $display_prompt;
	    $display_prompt = $display_choices = 0;

	    $input = <>;
	    chomp $input;
	    $input =~ s/^\s*//;
	    $input =~ s/\s*$//;
	    my $quoted_input = quotemeta($input);

	    if ($input =~ /^\-?(\d+)/) {
		my $number = $1;
		if ($number >= 1 && $number <= @item_callback) {
		    $n = $number - 1;
		    print $item_callback[$n]->[0], $self->reset_color, "\n";
		} else {
		    print $meta_color, "Wow, that's weird - did you mean ",
		    join (", ", map ($choice_selector_color . $_ . $meta_color, 1..$#item_callback)),
		    (@item_callback > 1 ? " or " : ""),
		    $choice_selector_color, @item_callback+0, $meta_color, ", maybe?";
		    ++$frustrated_tries;
		}
	    } elsif (my @match = length($input)
		     ? grep ($item_callback[$_]->[0] =~ /$quoted_input/i,
			     0..$#item_callback)
		     : ()) {
		if (@match == 1) {
		    ($n) = @match;
		    print
			$meta_color, "(Choice ", $n+1, ")", $self->reset_color, " ",
			$item_callback[$n]->[0], $self->reset_color, "\n\n";
		} else {
		    my $last = pop(@match);
		    print
			$meta_color, "Ambiguous choice (",
			join (", ", map ($choice_selector_color . ($_ + 1) . $meta_color, @match)),
			" or ", $choice_selector_color, $last + 1, $meta_color,
			"?) - try selecting by number";
		    ++$frustrated_tries;
		}
	    } else {
		print $meta_color, "Not sure which choice you meant there - please try again?";
		++$frustrated_tries;
	    }
	} while (!defined $n);

	# act on user choice
	&{$item_callback[$n]->[1]} ($n);
    }
    return $options[$choice];
}

# Renderers/output adapters
sub print_story_so_far {
    my ($self) = @_;
    print "\n", $self->narrative_color, $self->story_excerpt (0, $self->story_episodes - 1), $self->reset_color;
}

sub print_latest_episode {
    my ($self) = @_;
    print $self->narrative_color, $self->story_excerpt, $self->reset_color;
}

# An episode is the preamble text, or some terminal narrative text.
# This method counts the number of episodes.
sub story_episodes {
    my ($self) = @_;
    return @{$self->seq} + 1;  # the extra 1 is the preamble
}

# This method renders a slice of the episode list
sub story_excerpt {
    my ($self, $first_turn, $last_turn) = @_;
    $first_turn = $self->story_episodes - 1 unless defined $first_turn;
    $last_turn = $first_turn unless defined $last_turn;
    my @out = ($self->preamble_text);
    my $narrative_text = $self->narrative_text;
    for my $turn (1..$last_turn) {
	my $sym = $self->seq->[$turn - 1];
	if (defined($narrative_text) && defined($narrative_text->{$sym})) {
	    push @out, $narrative_text->{$sym};
	} else {
	    push @out, "$sym\n";
	}
    }
    @out = Gertie::Evaluator::evaluate (@out);
    return @out[$first_turn..$last_turn];
}
