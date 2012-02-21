#!/usr/bin/env perl -w


use Cwd qw(abs_path);
use FindBin;
use Getopt::Long;
use Term::ANSIColor;
use lib abs_path("$FindBin::Bin/../lib");


use Gertie::Robin;

$SIG{'INT'} = sub {
    print color('reset'), "\n";
    print STDERR color('reset'), "\n";
    exit;
    kill 6, $$; # ABRT = 6
};

my $verbose = 0;
my $use_stdout = 0;
my $trim_text = 0;
my ($grammar_file, $text_file);
GetOptions ("grammar=s"   => \$grammar_file,
	    "text=s"   => \$text_file,
	    "verbose=i"  => \$verbose,
	    "stdout" => \$use_stdout,
	    "trim" => \$trim_text);

if (@ARGV && !defined $grammar_file) {
    $grammar_file = shift;
}

die "You must specify a filename" unless defined $grammar_file;


my $robin = Gertie::Robin->new_from_file
    ($grammar_file,
     'verbose' => $verbose,
     'gertie_args' => [ 'verbose' => $verbose ],
     defined($text_file) ? ('text_filename' => $text_file) : (),  # don't override default
    );
my $gertie = $robin->gertie;

my @term = grep ($_ ne $gertie->end, @{$gertie->term_name});
my %is_term = map (($_ => 1), @term);

my %choice = defined($robin->choice_text) ? %{$robin->choice_text} : ();
my %narrative = defined($robin->narrative_text) ? %{$robin->narrative_text} : ();

my @choice_term = sort (grep (length($choice{$_}) > 0, keys %choice));
my @narrative_term = sort (grep (length($narrative{$_}) > 0, keys %narrative));

my %has_text = map (($_ => 1), @term, @choice_term, @narrative_term);
my %sym_order = map (($_ => defined ($gertie->symbol_order->{$_}) ? $gertie->symbol_order->{$_} : 0),
		     keys %has_text);
my @sym = sort { $sym_order{$a} <=> $sym_order{$b} } keys %has_text;

my %owned_by_player = map (($_ => 1),
			   grep (defined($gertie->term_owner_by_name->{$_})
				 && $gertie->term_owner_by_name->{$_} eq $gertie->player_agent, @term));

my @text = ($robin->preamble_text);
for my $sym (@sym) {
    next if $trim_text && !$is_term{$sym};
    my $default = $sym;
    $default =~ s/\@.*$//;
    $default =~ s/_/ /g;
    $default =~ s/^([a-z])/@{[uc($1)]}/;
    my ($narrative, $choice);
    if (!defined ($narrative = $narrative{$sym})) {
	$narrative = "$default.\n\n";
    }
    if (!defined ($choice = $choice{$sym})) {
	$choice = $owned_by_player{$sym} ? " $default" : "";
    } elsif ($trim_text && !$owned_by_player{$sym}) {
	$choice = "";
    } else {
	$choice = " $choice";
    }
    push @text, ">$sym$choice\n$narrative";
}

my @unwanted_narrative = grep (!$is_term{$_}, @narrative_term);
my @unwanted_choice = grep (!($is_term{$_} && $owned_by_player{$_}), @choice_term);
warn "The following symbols have narrative text but are not terminals:\n@unwanted_narrative\n\n" if @unwanted_narrative;
warn "The following symbols have choice text but are not player terminals:\n@unwanted_choice\n\n" if @unwanted_choice;

if ($use_stdout) {
    print @text;
} else {
    my $outfile = $robin->text_filename;
    warn "Writing to $outfile\n";
    local *FILE;
    open FILE, ">$outfile" or die "Couldn't open $outfile: $!";
    print FILE @text;
    close FILE or die "Couldn't close $outfile: $!";
}
