# Like FASTA format, but preserves the "cruft" on the name line,
# along with all newline and space formatting in the "sequence data"
package Fasta;
use Moose;
use Carp;

use strict;

# constructors
sub new_fasta {
    my ($class, @args) = @_;
    my $self = { @args };
    bless $self, $class;
    return $self;
}

sub new_from_file {
    my ($class, $filename, @args) = @_;
    my $self = $class->new_fasta (@args);
    local *FILE;
    local $_;
    open FILE, "<$filename" or confess "Couldn't open $filename: $!";
    my $current;
    while (<FILE>) { $self->parse_line ($_, \$current) }
    close FILE;
    return $self;
}

sub new_from_string {
    my ($class, @text) = @_;
    my $self = $class->new_fasta;
    @text = map (split(/\n/), @text);
    my $current;
    for my $line (@text) { $self->parse_line ("$line\n", \$current) }
    return $self;
}

sub parse_line {
    my ($self, $line, $name_ref) = @_;
    if ($line =~ /^\s*>\s*(\S+)\s*(.*)$/) {
	my ($name, $cruft) = ($1, $2);
	carp "Multiple definitions of $name -- overwriting" if defined $self->{$name};
	$self->{$name} = $cruft;
	$$name_ref = $name;
    } elsif (defined $$name_ref) {
	$self->{$$name_ref} .= $line;
    } else {
	carp "Discarding line $line" if $line =~ /\S/;
    }
}

sub to_string {
    my ($self) = @_;
    my @out;
    for my $sym (sort keys %$self) {
	my $text = $self->{$sym};
	if ($text =~ /\n/) {
	    push @out, ">$sym\n", $text;
	} else {
	    push @out, ">$sym $text\n";
	}
    }
    return join ("", @out);
}

1;
