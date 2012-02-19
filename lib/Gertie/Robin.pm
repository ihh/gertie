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

sub reset_nl {
    my ($self) = @_;
    return $self->reset_color . "\n";
}

sub new_from_file {
    my ($class, $filename, %args) = @_;
    my $gertie = Gertie->new_from_file ($filename, defined($args{'gertie_args'}) ? @{$args{'gertie_args'}} : ());
    my $self = $class->new_robin ($gertie, 'text_filename' => "$filename.text", %args);
    $self->load_text_from_file ($self->text_filename) if -e $self->text_filename;
    # return
    return $self;
}

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

# play method
sub play {
    my ($self) = @_;

    $self->reset();

    if ($self->use_color) { $self->use_cool_color_scheme } else { $self->use_boring_color_scheme }
    my $log_color = $self->log_color;
    my $reset_nl = $self->reset_nl;
    my @begin_log = ($log_color, "--- BEGIN DEBUG LOG", $reset_nl);
    my @end_log = ($log_color, "--- END DEBUG LOG", $reset_nl);
    print @begin_log if $self->verbose;

    $self->rand_seed (time) unless defined $self->rand_seed;
    srand ($self->rand_seed);
    print $log_color, "Random seed: ", $self->rand_seed, $reset_nl if $self->verbose;

    my $trace_fh;
    if (defined $self->trace_filename) {
	$trace_fh = FileHandle->new (">".$self->trace_filename)
	    or confess "Couldn't open ", $self->trace_filename, ": $!";
	autoflush $trace_fh 1;
    }
    $self->{'trace_fh'} = $trace_fh;

    $self->load_game ($self->initial_restore_filename) if defined $self->initial_restore_filename;

    print $self->narrative_color, $self->story_excerpt, $self->reset_color;
    my $n_agents = @{$self->gertie->agents};
GAMELOOP:    
    for ($self->{'current_turn'} = 0;
	 !defined($self->max_rounds) || $self->current_round() < $self->max_rounds;
	 ++$self->{'current_turn'}) {

	my $turn = $self->current_turn;
	my $round = $self->current_round;
	my $agent = $self->current_agent;

	# status/log messages
	if ($self->verbose) {
	    print $log_color, "Turn: ", $turn, $reset_nl;
	    print $log_color, "Round: ", $round + 1, $reset_nl;
	    print $log_color, "Agent: $agent", $reset_nl;
	    print $log_color, "Player turns: ", $self->player_turns, $reset_nl;
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
	    next GAMELOOP;
	}

	# get next terminal from appropriate agent
	my $next_term;
	print @end_log if $self->verbose;
	if ($agent eq $self->gertie->player_agent) {
	    $next_term = $self->player_choice (@next_term);
	    # hack: if player_choice returns undef, then rebuild menu
	    if (!defined $next_term) {
		--$self->{'current_turn'};
		next GAMELOOP;
	    }
	} else {
	    $next_term = Gertie::sample (\@next_prob, \@next_term);
	}

	# record the turn
	$self->record_turn ($next_term);

	# print narrative text
	print $self->narrative_color, $self->story_excerpt, $self->reset_color;

	# log
	if ($self->verbose) {
	    print @begin_log;
	    print $log_color, "Terminal: $next_term", $reset_nl;
	}
    }

    print @end_log if $self->verbose;

    if (defined $trace_fh) {
	$trace_fh->close or confess "Couldn't close ", $self->trace_filename, ": $!";
	delete $self->{'trace_fh'};
    }
}

sub current_agent {
    my ($self) = @_;
    my $turn = $self->current_turn;
    my $n_agents = @{$self->gertie->agents};
    my $round = int ($turn / $n_agents);
    my $agent = $self->gertie->agents->[$turn % $n_agents];
    return $agent;
}

sub current_round {
    my ($self) = @_;
    my $turn = $self->current_turn;
    my $n_agents = @{$self->gertie->agents};
    my $round = int ($turn / $n_agents);
    return $round;
}

sub record_turn {
    my ($self, $next_term) = @_;
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

sub reset {
    my ($self) = @_;
    $self->seq ([]);
    $self->tokseq ([]);
    $self->seq_turn ([]);
    $self->inside ($self->gertie->prefix_Inside ([], @{$self->inside_args}));  # initialize empty Inside matrix
    $self->inside->verbose ($self->verbose);  # make the Inside matrix as verbose as we are, for log tidiness
    $self->{'turns'} = { map (($_ => 0), @{$self->gertie->agents}) };
}

sub load_game {
    my ($self, $filename) = @_;
    unless (-e $filename) { print $self->meta_color, "Oops - I can't find a saved game file called '$filename'. Are you sure you spelled it right?", $self->reset_nl; return }
    local *FILE;
    local $_;
    unless (open FILE, "<$filename") { print $self->meta_color, "Oops - I wasn't able to load the game from file '$filename': $!", $self->reset_nl; return }
    $self->reset;
    while (<FILE>) {
	my ($turn, $term) = split;
	$self->current_turn ($turn);
	$self->record_turn ($term);
    }
    close FILE;
    ++$self->{'current_turn'};
    print $self->meta_color, "Game restored from file '$filename'.", $self->reset_nl;
    $self->print_story_so_far;
}

sub save_game {
    my ($self, $filename) = @_;
    if (-e $filename) {
	print $self->meta_color, "There's already a file called '$filename'. Are you sure you want to overwrite it? Please type 'yes' or 'no':", $self->reset_nl;
	my $yes_no;
	while (1) {
	    $yes_no = <>;
	    last if $yes_no =~ /\S/;
	    print $self->meta_color, "Please type 'yes' or 'no'.", $self->reset_nl;
	}
	unless ($yes_no =~ /^\s*y/i) {
	    if ($yes_no =~ /^\s*n/i) {
		print $self->meta_color, "OK. If you still want to save you'll need to choose the 'save game' option again, and use a different filename.", $self->reset_nl;
	    } else {
		print $self->meta_color, "I didn't really understand your answer, so I'm not going to over-write the existing file.\nIf you still want to save you'll need to pick that option again, and use a different filename.", $self->reset_nl;
	    }
	    return;
	}
    }
    local *FILE;
    unless (open FILE, ">$filename") { print $self->meta_color, "Oops - I wasn't able to save the game to the file '$filename': $!", $self->reset_nl; return }
    for (my $n = 0; $n < @{$self->seq}; ++$n) {
	print FILE $self->seq_turn->[$n], " ", $self->seq->[$n], "\n";
    }
    unless (close FILE) { print $self->meta_color, "Oops - I couldn't save the game to file '$filename': $!", $self->reset_nl }
    print $self->meta_color, "OK, game saved to file '$filename'.", $self->reset_nl;
}

sub get_save_filename {
    my ($self) = @_;
    print
	$self->meta_color,
	"Please enter a filename (or just hit RETURN to use the default filename, '", $self->default_save_filename, "')",
	$self->reset_nl;
    my $filename = <>;
    chomp $filename;
    $filename =~ s/^\s*(.*?)\s*$/$1/;
    $filename = $self->default_save_filename unless length($filename);
    return $filename;
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

	if ($self->player_turns > 0) {
	    push @item_callback,
	    [$meta_color . "(review the story so far)", sub { $self->print_story_so_far } ],
	    [$meta_color . "(undo my last choice)", sub { $self->undo_turn ($self->gertie->player_agent);
							  $self->print_story_so_far;
							  $choice = -1 } ];
	}

	if ($max < $#options) {
	    push @item_callback,
	    [$meta_color . "(more choices)", sub { ++$page }];
	}

	if ($page > 0) {
	    push @item_callback,
	    [$meta_color . "(previous choices)", sub { --$page }];
	}

	push @item_callback,
	[$meta_color . "(save the game)", sub { $self->save_game ($self->get_save_filename);
						print "\n", $narrative_color, $self->story_excerpt, $self->reset_color }],
	[$meta_color . "(restore the game)", sub { $self->load_game ($self->get_save_filename); $choice = -1 }];

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
    return $choice < 0 ? undef : $options[$choice];
}

sub print_story_so_far {
    my ($self) = @_;
    print "\n", $self->narrative_color, $self->story_excerpt (0, $self->story_episodes - 1), $self->reset_color;
}

sub story_episodes {
    my ($self) = @_;
    return @{$self->seq} + 1;  # the extra 1 is the preamble
}

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

sub player_turns {
    my ($self) = @_;
    return $self->turns->{$self->gertie->player_agent};
}
