#!/usr/bin/env perl -w

use Cwd qw(abs_path);
use FindBin;
use Getopt::Long;
use Term::ANSIColor;
use lib abs_path("$FindBin::Bin/../lib");


use Gertie::Robin;

my $need_color_reset = 0;

$SIG{'INT'} = sub {
    if ($need_color_reset) {
	print color('reset'), "\n";
	print STDERR color('reset'), "\n";
    }
    exit;
    kill 6, $$; # ABRT = 6
};

my $verbose = 0;
my $color = 0;
my $c_parser = 0;
my $render_html = 0;
my ($grammar_file, $game_file, $trace_file, $seed, $rounds);
GetOptions ("grammar=s"   => \$grammar_file,
	    "trace=s"  => \$trace_file,
	    "verbose=i"  => \$verbose,
	    "seed=i"  => \$seed,
	    "rounds=i"  => \$rounds,
	    "color" => \$color,
	    "cparser" => \$c_parser,
	    "restore=s" => \$game_file,
	    "html" => \$render_html);

if (@ARGV && !defined $grammar_file) {
    $grammar_file = shift;
}

die "You must specify a filename" unless defined $grammar_file;

my $robin = Gertie::Robin->new_from_file
    ($grammar_file,
     'verbose' => $verbose,
     'inside_args' => [ 'verbose' => $verbose ],
     'gertie_args' => [ 'verbose' => $verbose, 'use_c_parser' => $c_parser ],
     'trace_filename' => $trace_file,
     'initial_restore_filename' => $game_file,
     'rand_seed' => $seed,
     'max_rounds' => $rounds,
     'use_color' => $color);

# The -html option just tests the HTML rendering
# Commented-out code shows how this would be used for CGI play
# You would also need to pass appropriate JavaScript functions into render_dynamic_html, to visit the "move" URL
# e.g. window.location.href = '...'
if ($render_html) {
    $robin->initialize_game_for_player;
#    if ($CGI_TURN_PARAMETER == $robin->current_turn) {
#	if ($CGI_COMMAND_PARAMETER eq "move") {
#	    $robin->record_player_turn ($CGI_MOVE_PARAMETER);
#	    $robin->save_game ($robin->initial_restore_filename);
#	} elsif ($CGI_COMMAND_PARAMETER eq "undo") {
#	    $robin->undo_turn;
#	    $robin->save_game ($robin->initial_restore_filename);
#	}
#    }
    print $robin->render_dynamic_html;
    exit;
}

$need_color_reset = 1;
$robin->play;


END {
    if ($need_color_reset) {
	print color('reset');
    }
}
