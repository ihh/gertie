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
my ($grammar_file, $text_file);
GetOptions ("grammar=s"   => \$grammar_file,
	    "text=s"   => \$text_file,
	    "verbose=i"  => \$verbose,
    );

if (@ARGV && !defined $grammar_file) {
    $grammar_file = shift;
}

die "You must specify a filename" unless defined $grammar_file;


my $robin = Gertie::Robin->new_from_file
    ($grammar_file,
     'verbose' => $verbose,
     defined($text_file) ? ('text_filename' => $text_file) : (),  # don't override default
    );

my %is_term = map (($_ => 1), @{$robin->gertie->term_name});
my %has_text = map (($_ => 1), @{$robin->gertie->term_name},
		    keys %{$robin->choice_text},
		    keys %{$robin->narrative_text});
my @term = sort keys %has_text;

my @text;
for my $term (@term) {
    my $default = $term;
    $default =~ s/\@.*$//;
    $default =~ s/_/ /g;
    $default =~ s/^([a-z])/@{[uc($1)]}/;
    my ($narrative, $choice);
    if (!defined ($narrative = $robin->narrative_text->{$term})) {
	$narrative = "$default\n";
    }
    if (!defined ($choice = $robin->choice_text->{$term})) {
	$choice = "$default.";
    }
    push @text, ">$term $choice\n$narrative";
}

for my $term (@term) {
    if (!$is_term{$term}) {
	my @unwanted;
	push @unwanted, "narrative" if defined $robin->narrative_text->{$term};
	push @unwanted, "choice" if defined $robin->choice_text->{$term};
	warn "Terminal '$term' has ", join(" and ",@unwanted), " text but is not a grammar terminal\n";
    }
}

print @text;
