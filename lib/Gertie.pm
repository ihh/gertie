package Gertie;

use strict;
use vars ('@ISA', '@EXPORT', '@EXPORT_OK');

# generic imports
use Exporter;
use Carp qw(carp croak cluck confess);
use Data::Dumper;
use File::Temp;
use Scalar::Util;
use IPC::Open3;
use Symbol qw(gensym);

# specific imports
use Graph::Directed;

# imports from this repository
use AutoHash;

@ISA = qw (AutoHash);
@EXPORT = qw (new_from_file new_from_string to_string simulate tokenize prefix_Inside traceback_Inside print_Inside print_parse_tree parse_tree_sequence AUTOLOAD);
@EXPORT_OK = @EXPORT;

# constructor
sub new_gertie {
    my ($class, @args) = @_;
    my $self = AutoHash->new ( 'end' => "end",
			       'rule' => [],
			       'symbol' => {},
			       'max_inside_len' => undef,
			       'rule_prob_by_name' => {},
			       'outgoing_prob_by_name' => {},
			       'verbose' => 0,
			       @args );
    bless $self, $class;
    $self->symbol->{$self->end} = 1;
    return $self;
}

sub new_from_file {
    my ($class, $filename, @args) = @_;
    my $self = $class->new_gertie (@args);
    $self->parse_files ($filename);
    $self->index();
    return $self;
}

sub new_from_string {
    my ($class, $text, @args) = @_;
    my $self = $class->new_gertie (@args);
    $self->parse ($text);
    $self->index();
    return $self;
}

# Read grammar file(s)
sub parse_files {
    my ($self, @filename) = @_;
    local *FILE;
    local $_;
    for my $filename (@filename) {
	open FILE, "<$filename" or confess "Can't open '$filename': $!";
	my @text = <FILE>;
	close FILE;
	$self->parse (@text);
    }
}

sub parse {
    my ($self, @text) = @_;
    my @lines = split (/;/, join ("", @text));
    for my $line (@lines) {
	$self->parse_line ($line);
    }
}

sub parse_line {
    my ($self, $line) = @_;
    local $_;
    $_ = $line;
    return unless /\S/;  # ignore blank lines
    return if /^\s*\/\//;  # ignore C++-style comments ("// ...")
    my $sym_regex = '[A-Za-z_]\w*\b([\?\*\+]?|\{\d+,\d*\}|\{\d*,\d+\}|\{\d+\})';
    if (/^\s*($sym_regex)\s*\->\s*($sym_regex)\s*(|$sym_regex)\s*([\d\.]*)\s*;?\s*$/) {  # Transition (A->B) or Chomsky-form rule (A->B C) with optional probability
	my ($lhs, $lhs_crap, $rhs1, $rhs1_crap, $rhs2, $rhs2_crap, $prob) = ($1, $2, $3, $4, $5, $6, $7);
	($rhs1, $rhs2) = $self->process_quantifiers ($rhs1, $rhs2);
	$self->add_rule ($lhs, $rhs1, $rhs2, $prob);
    } elsif (/^\s*($sym_regex)\s*\->((\s*$sym_regex)*)\s*([\d\.]*)\s*;?\s*$/) {  # Non-Chomsky rule (A->B C D ...) with optional probability
	my ($lhs, $lhs_crap, $rhs, $rhs1, $rhs_crap, $prob) = ($1, $2, $3, $4, $5, $6);
	# Convert "A->B C D E" into "A -> B.C.D E;  B.C.D -> B.C D;  B.C -> B C"
	$rhs =~ s/^\s*(.*?)\s*/$1/;
	my @rhs = split /\s+/, $rhs;
	confess "Parse error" unless @rhs >= 2;
	@rhs = $self->process_quantifiers (@rhs);
	$self->add_non_Chomsky_rule ($lhs, \@rhs, $prob);
    } elsif (/^\s*($sym_regex)\s*\->((\s*$sym_regex\b)*\s*([\d\.]*)(\s*\|(\s*$sym_regex\b)*\s*([\d\.]*))*)\s*;?\s*$/) {  # Multiple right-hand sides (A->B C|D E|F) with optional probabilities
	my ($lhs, $lhs_crap, $all_rhs) = ($1, $2, $3);
	my @rhs = split /\|/, $all_rhs;
	for my $rhs (@rhs) { $self->parse_line ("$lhs -> $rhs") }
    } else {
	warn "Unrecognized line: ", $_;
    }
}

sub add_rule {
    my ($self, $lhs, $rhs1, $rhs2, $prob) = @_;
    # Supply default values
    $rhs2 = $self->end unless length($rhs2);
    $prob = 1 unless length($prob);
    # Check the rule is valid
    confess unless defined($rhs1) && length($rhs1);
    confess if $lhs eq $self->end;  # No rules starting with 'end'
    confess if $prob < 0;  # Rule weights are nonnegative
    $self->{'start'} = $lhs unless defined $self->{'start'};  # First named nonterminal is start
    return if $prob == 0;  # Don't bother tracking zero-weight rules
    # Be idempotent
    if (exists $self->rule_prob_by_name->{$lhs}->{$rhs1}->{$rhs2}) {
	my $old_prob = $self->rule_prob_by_name->{$lhs}->{$rhs1}->{$rhs2};
	if ($old_prob != $prob) {
	    confess "Attempt to change probability of rule ($lhs->$rhs1 $rhs2) from $old_prob to $prob";
	}
	return;
    }
    # Record the rule
    push @{$self->rule}, [$lhs, $rhs1, $rhs2, $prob, @{$self->rule} + 0];
    $self->rule_prob_by_name->{$lhs}->{$rhs1}->{$rhs2} = $prob;
    $self->outgoing_prob_by_name->{$lhs} += $prob;
    grep (++$self->symbol->{$_}, $lhs, $rhs1, $rhs2);
}

sub add_non_Chomsky_rule {
    my ($self, $lhs, $rhs_listref, $prob) = @_;
    my @rhs = @$rhs_listref;
    if (@rhs == 0) {
	$self->add_rule ($lhs, $self->end, undef, $prob);
    } elsif (@rhs == 1) {
	$self->add_rule ($lhs, $rhs[0], undef, $prob);
    } else {
	while (@rhs >= 2) {
	    my $rhs2 = pop @rhs;
	    my $rhs1 = join (".", @rhs);
	    $self->add_rule ($lhs, $rhs1, $rhs2, $prob);
	    $lhs = $rhs1;
	    $prob = 1;
	}
    }
}

sub process_quantifiers {
    my ($self, @sym) = @_;
    my @sym_ret;
    for my $sym (@sym) {
	$sym =~ s/\{(\d+)\}$/\{$1,$1\}/;  # Convert X{N} into X{N,N}
	$sym =~ s/\{0,1\}$/?/;  # Convert X{0,1} into X?
	$sym =~ s/\{0,\}$/*/;   # Convert X{0,} into X*
	$sym =~ s/\{1,1\}$//;   # Convert X{1,1} into X
	$sym =~ s/\{1,\}$/+/;   # Convert X{1,} into X+
	push @sym_ret, $sym;
	if ($sym =~ /^(\w+)\?/) {
	    $self->add_rule ($sym, $1);
	    $self->add_rule ($sym, $self->end);
	} elsif ($sym =~ /^(\w+)\*/) {
	    $self->add_rule ($sym, $1, $sym);
	    $self->add_rule ($sym, $self->end);
	} elsif ($sym =~ /^(\w+)\+/) {
	    my $base = $1;
	    $self->add_rule ($sym, $base, $sym);
	    $self->add_rule ($sym, $base);
	} elsif ($sym =~ /^(\w+)\{(\d*),(\d*)\}/) {
	    my ($base, $min, $max) = ($1, $2, $3);
	    confess "Bad quantifiers in nonterminal $sym" if (length($max) && $max < $min) || (length($min) && $min <= 0) || ($min eq "" && $max eq "");
	    if (length $max) {
		for (my $n = $min; $n <= $max; ++$n) {
		    if ($n == 0) {
			$self->add_rule ($sym, $self->end);
		    } else {
			$self->add_non_Chomsky_rule ($sym, [map ($base, 1..$n)]);
		    }
		}
	    } else {  # $min > 1
		$self->add_non_Chomsky_rule ($sym, [map ($base, 1..$min-1), "$base+"]);
		$self->add_rule ("$base+", $base, "$base+");
		$self->add_rule ("$base+", $base);
	    }
	}
    }
    return @sym_ret;
}

# Index: convert symbols & rules to integers
sub index {
    my ($self) = @_;
    $self->index_symbols;
    $self->index_rules;
}

# Treating each rule "A->B C" as an edge "A->B", compute toposort
sub index_symbols {
    my ($self) = @_;

    # Check that we have some rules & symbols to index
    confess "No rules to index" unless @{$self->rule};

    # quick-index rules by rhs symbols
    my %by_rhs;
    for my $rule (@{$self->rule}) {
	my ($lhs, $rhs1, $rhs2, $prob, $rule_index) = @$rule;
	push @{$by_rhs{$rhs1}}, $rule;
	push @{$by_rhs{$rhs2}}, $rule unless $rhs1 eq $rhs2;
    }

    # find nonterms that have a null path to 'end'
    my @null_q = ($self->end);
    my %can_be_null = ($self->end => 1);
    while (@null_q) {
	my $sym = shift @null_q;
	for my $rule (@{$by_rhs{$sym}}) {
	    my ($lhs, $rhs1, $rhs2, $prob, $rule_index) = @$rule;
	    if ($can_be_null{$rhs1} && $can_be_null{$rhs2}) {
		push @null_q, $lhs unless $can_be_null{$lhs};
		$can_be_null{$lhs} = 1;
	    }
	}
    }
    warn "Nonterminals that can be null: ", join(" ",keys%can_be_null) if $self->verbose > 1;

    # build transition graph
    my $graph = Graph::Directed->new;
    for my $sym (keys %{$self->symbol}) {
	$graph->add_vertex ($sym);
    }
    for my $rule (@{$self->rule}) {
	my ($lhs, $rhs1, $rhs2, $prob, $rule_index) = @$rule;
	$graph->add_edge ($lhs, $rhs1) if $can_be_null{$rhs2};
	$graph->add_edge ($lhs, $rhs2) if $can_be_null{$rhs1};
    }

    # do toposort
    if ($graph->is_cyclic) {
	my @cycle = $graph->find_a_cycle;
	confess "Transition graph is cyclic! e.g. ", join ("->", @cycle, $cycle[0]);
    }
    $self->{'sym_name'} = [reverse $graph->topological_sort];
    $self->{'sym_id'} = {map (($self->sym_name->[$_] => $_), 0..$#{$self->sym_name})};
    $self->{'start_id'} = $self->sym_id->{$self->start};
    $self->{'end_id'} = $self->sym_id->{$self->end};

    # We define "terminals" to include 'end'
    my @term = grep (!exists($self->rule_prob_by_name->{$_}), keys %{$self->symbol});
    $self->{'term_name'} = \@term;
    $self->{'term_id'} = [map ($self->sym_id->{$_}, @term)];
    $self->{'is_term'} = {map (($_ => 1), @{$self->term_id})};

    warn "Symbols: (@{$self->sym_name})" if $self->verbose;
    warn "Terminals: (@{$self->term_name})" if $self->verbose;

    # delete indices we have no further use for
    delete $self->{'symbols'};  # use $self->sym_name instead
    delete $self->{'rule_prob_by_name'};
}

# Normalize & index
sub index_rules {
    my ($self) = @_;
    $self->{'rule_by_lhs_rhs1'} = {};
    $self->{'rule_by_rhs2'} = {};
    for my $rule (@{$self->rule}) {
	my ($lhs, $rhs1, $rhs2, $prob, $rule_index) = @$rule;
	$prob /= $self->outgoing_prob_by_name->{$lhs};
	warn "Indexed rule: $lhs -> $rhs1 $rhs2 $prob;" if $self->verbose;
	my ($lhs_id, $rhs1_id, $rhs2_id) = map ($self->sym_id->{$_}, $lhs, $rhs1, $rhs2);
	push @{$self->rule_by_lhs_rhs1->{$lhs_id}->{$rhs1_id}}, [$rhs2_id, $prob, $rule_index];
	push @{$self->rule_by_rhs2->{$rhs2_id}}, [$lhs_id, $rhs1_id, $prob, $rule_index];
    }

    # delete indices we have no further use for
    delete $self->{'outgoing_prob_by_name'};
}

# empty probs
sub empty_prob {
    my ($self) = @_;
    my %empty = ($self->end_id => 1);
    my @rhs2_queue = keys %empty;
    while (@rhs2_queue) {
	my $rhs2 = shift @rhs2_queue;
	for my $rule (@{$self->rule_by_rhs2->{$rhs2}}) {
	    my ($lhs, $rhs1, $rule_prob, $rule_index) = @$rule;
	    if (exists $empty{$rhs1}) {
		push @rhs2_queue, $lhs unless exists $empty{$lhs};
		$empty{$lhs} += $empty{$rhs1} * $empty{$rhs2};
	    }
	}
    }
    return %empty;
}

# subroutine to print grammar
sub to_string {
    my ($self) = @_;
    my @text;
    for my $lhs (sort @{$self->sym_name}) {
	next if $lhs =~ /\./;  # don't print rules added by Chomsky-fication
	my $lhs_id = $self->sym_id->{$lhs};
	my @rhs1 = map ($self->sym_name->[$_], keys %{$self->rule_by_lhs_rhs1->{$lhs_id}});
	for my $rhs1 (sort @rhs1) {
	    my $rhs1_id = $self->sym_id->{$rhs1};
	    $rhs1 =~ s/\./ /g;  # de-Chomskyfy
	    my @rule = sort {$self->sym_name->[$a->[0]] cmp $self->sym_name->[$b->[0]]} @{$self->rule_by_lhs_rhs1->{$lhs_id}->{$rhs1_id}};
	    for my $rule (@rule) {
		my ($rhs2_id, $rule_prob, $rule_index) = @$rule;
		my $rhs2 = $self->sym_name->[$rhs2_id];
		my $rhs = " $rhs1 $rhs2";
		$rhs =~ s/ @{[$self->end]}//g;
		$rhs =~ s/\s+/ /;
		$rhs =~ s/^\s*//;
		$rhs = $self->end unless length $rhs;
		$rule_prob = ($rule_prob == 1 ? "" : "  $rule_prob");
		push @text, "$lhs -> $rhs$rule_prob;\n";
	    }
	}
    }
    return join ("", @text);
}

# subroutine to tokenize a sequence
sub tokenize {
    my ($self, $seq) = @_;
    my @undefs = grep (!exists($self->sym_id->{$_}), @$seq);
    confess "Undefined symbols (@undefs)" if @undefs;
    return map ($self->sym_id->{$_}, @$seq);
}

# subroutine to compute Inside matrix for given tokenized prefix sequence
sub prefix_Inside {
    my ($self, $tokseq, $prev_tokseq, $prev_p) = @_;

    my $len = @{$tokseq} + 0;
    my $max_inside_len = $self->max_inside_len;
    my $symbols = @{$self->sym_name} + 0;

    my $shared_len = 0;
    if (defined $prev_tokseq) {
	while ($shared_len < @$prev_tokseq && $shared_len < @$tokseq && $tokseq->[$shared_len] == $prev_tokseq->[$shared_len]) {
	    ++$shared_len;
	}
    }

    # Create Inside matrix
    # p(i,j,sym) = P(seq[i]..seq[j-1] | sym)
    #            = probability that parse tree rooted at sym will generate subseq i..j-1 (inclusive)
    # Note:
    # p(i,j,sym) is stored as $p->[$j]->[$i]->{$sym}
    # This facilitates re-using DP matrices for sequences with shared prefixes
    my $p = [ map ([map ({}, 0..$_)], 0..$len) ];
    my %empty = $self->empty_prob;
    for my $i (0..$len) { $p->[$i]->[$i] = \%empty }
    for my $i (0..$len-1) { $p->[$i+1]->[$i]->{$tokseq->[$i]} = 1 }

    # Inside recursion
    # p(i,j,sym) = \sum_{k=i}^j \sum_{lhs->rhs1 rhs1} P(lhs->rhs1 rhs2) p(i,k,rhs1) * p(k,j,rhs2)
    for (my $j = 1; $j <= $len; ++$j) {
	if ($j <= $shared_len) { $p->[$j] = $prev_p->[$j]; next }
	for (my $i = $j - 1; $i >= 0; --$i) {
	    next if defined($max_inside_len) && $j-$i > $max_inside_len && $i > 0;
	    for (my $lhs = 0; $lhs < $symbols; ++$lhs) {
		my $rule_by_rhs1 = $self->rule_by_lhs_rhs1->{$lhs};
		for (my $k = $i; $k <= $j; ++$k) {
		    next if defined($max_inside_len) && $j-$k > $max_inside_len && $k > 0;
		    for my $rhs1 (sort keys %{$p->[$k]->[$i]}) {
			if (defined $rule_by_rhs1->{$rhs1}) {
			    my $rhs1_prob = $p->[$k]->[$i]->{$rhs1};
			    for my $rule (@{$rule_by_rhs1->{$rhs1}}) {
				my ($rhs2, $rule_prob, $rule_index) = @$rule;
				if (defined (my $rhs2_prob = $p->[$j]->[$k]->{$rhs2})) {
				    $p->[$j]->[$i]->{$lhs} += $rhs1_prob * $rhs2_prob * $rule_prob;
				    warn "p($i,$j,",$self->sym_name->[$lhs],") += p($i,$k,",$self->sym_name->[$rhs1],")(=$rhs1_prob) * p($k,$j,",$self->sym_name->[$rhs2],")(=$rhs2_prob) * P(rule)(=$rule_prob)" if $self->verbose > 1;
				}
			    }
			}
		    }
		}
	    }
	}
    }

    # Create prefix Inside matrix
    # q(i,sym) = \sum_{j=N+1}^\infty p(i,j,sym)
    #          = probability that parse tree rooted at sym will generate prefix i..length-1 (inclusive) plus at least one extra terminal
    my $q = [ map ({}, 0..$len) ];
    for my $term_id (@{$self->term_id}) { $q->[$len]->{$term_id} = 1 }
    delete $q->[$len]->{$self->end_id};  # a parse tree rooted at 'end' cannot generate any more terminals, so we don't consider 'end' a terminal for this purpose

    # prefix Inside recursion
    # q(i,sym) = \sum_{lhs->rhs1 rhs1} P(lhs->rhs1 rhs2) (q(i,rhs1) + \sum_{k=i}^{length} p(i,k,rhs1) * q(k,rhs2))
    for (my $i = $len - 1; $i >= 0; --$i) {
	for (my $lhs = 0; $lhs < $symbols; ++$lhs) {
	    my $rule_by_rhs1 = $self->rule_by_lhs_rhs1->{$lhs};
	    while (my ($rhs1, $rule_list) = each %$rule_by_rhs1) {
		for my $rule (@$rule_list) {
		    my ($rhs2, $rule_prob, $rule_index) = @$rule;
		    for (my $k = $i; $k <= $len; ++$k) {
			if (defined (my $rhs1_prob = $p->[$k]->[$i]->{$rhs1})
			    && defined (my $rhs2_prob = $q->[$k]->{$rhs2})) {
			    $q->[$i]->{$lhs} += $rule_prob * $rhs1_prob * $rhs2_prob;
			    warn "q($i,",$self->sym_name->[$lhs],") += p($i,$k,",$self->sym_name->[$rhs1],")(=$rhs1_prob) * q($k,",$self->sym_name->[$rhs2],")(=$rhs2_prob) * P(rule)(=$rule_prob)" if $self->verbose > 1;
			}
		    }
		    if (defined $q->[$i]->{$rhs1}) {
			my $rhs1_prob = $q->[$i]->{$rhs1};
			$q->[$i]->{$lhs} += $rule_prob * $rhs1_prob;
			warn "q($i,",$self->sym_name->[$lhs],") += q($i,",$self->sym_name->[$rhs1],")(=$rhs1_prob) * P(rule)(=$rule_prob)" if $self->verbose > 1;
		    }
		}
	    }
	}
    }

    # return
    return ($p, $q);
}

sub print_Inside {
    my ($self, $p, $q) = @_;
    my $len = $#$p;
    my @out;
    for (my $i = $len; $i >= 0; --$i) {

	push @out, "Prefix $i..:";
	for my $sym (sort {$a<=>$b} keys %{$q->[$i]}) {
	    push @out, " ", $self->sym_name->[$sym], "=>", $q->[$i]->{$sym};
	}
	push @out, "\n";

	for (my $j = $i; $j <= $len; ++$j) {
	    push @out, "Inside ($i,$j):";
	    for my $sym (sort {$a<=>$b} keys %{$p->[$j]->[$i]}) {
		push @out, " ", $self->sym_name->[$sym], "=>", $p->[$j]->[$i]->{$sym};
	    }
	    push @out, "\n";
	}
    }
    return join ("", @out);
}

sub traceback_Inside {
    my ($self, $p, $q) = @_;
    my $len = $#$p;
    my $q_prob = $q->[0]->{$self->start_id};
    my $p_prob = $p->[$len]->[0]->{$self->start_id};
    my $is_complete = sample ([defined($q_prob) ? $q_prob : 0,
			       defined($p_prob) ? $p_prob : 0]);
    my $parse_tree =
	$is_complete
	? $self->traceback_Inside_p ($p, 0, $len, $self->start_id)
	: $self->traceback_Inside_q ($p, $q, 0, $self->start_id);

    return $self->flatten_parse_tree ($parse_tree);
}

sub traceback_Inside_p {
    my ($self, $p, $i, $j, $lhs) = @_;
    return [$self->sym_name->[$lhs]] if $self->is_term->{$lhs};
    my (@rhs_k, @prob);
    my $rule_by_rhs1 = $self->rule_by_lhs_rhs1->{$lhs};
    confess "Traceback error: i=$i, j=$j, lhs=", $self->sym_name->[$lhs] unless defined $rule_by_rhs1;
    for (my $k = $i; $k <= $j; ++$k) {
	for my $rhs1 (keys %$rule_by_rhs1) {
	    if (defined $p->[$k]->[$i]->{$rhs1}) {
		for my $rule (@{$rule_by_rhs1->{$rhs1}}) {
		    my ($rhs2, $rule_prob, $rule_index) = @$rule;
		    if (defined $p->[$j]->[$k]->{$rhs2}) {
			push @rhs_k, [$rhs1, $rhs2, $k];
			push @prob, $p->[$k]->[$i]->{$rhs1} * $p->[$j]->[$k]->{$rhs2} * $rule_prob;
		    }
		}
	    }
	}
    }
    confess "Traceback error: i=$i, j=$j, lhs=", $self->sym_name->[$lhs] unless @prob;
    my ($rhs1, $rhs2, $k) = @{sample (\@prob, \@rhs_k)};
    return [$self->sym_name->[$lhs],
	    $self->traceback_Inside_p ($p, $i, $k, $rhs1),
	    $self->traceback_Inside_p ($p, $k, $j, $rhs2)];
}

sub traceback_Inside_q {
    my ($self, $p, $q, $i, $lhs) = @_;
    my $len = $#$p;
    return [$self->sym_name->[$lhs]] if $self->is_term->{$lhs} && $i == $len;
    my (@rhs_k, @prob);
    my $rule_by_rhs1 = $self->rule_by_lhs_rhs1->{$lhs};
    confess "Traceback error: i=$i, lhs=", $self->sym_name->[$lhs] unless defined $rule_by_rhs1;
    while (my ($rhs1, $rule_list) = each %$rule_by_rhs1) {
	for (my $k = $i; $k <= $len; ++$k) {
	    if (defined $p->[$k]->[$i]->{$rhs1}) {
		for my $rule (@$rule_list) {
		    my ($rhs2, $rule_prob, $rule_index) = @$rule;
		    if (defined $q->[$k]->{$rhs2}) {
			push @rhs_k, [$rhs1, $rhs2, $k];
			push @prob, $p->[$k]->[$i]->{$rhs1} * $q->[$k]->{$rhs2} * $rule_prob;
		    }
		}
	    }
	}
	if (defined $q->[$i]->{$rhs1}) {
	    for my $rule (@$rule_list) {
		my ($rhs2, $rule_prob, $rule_index) = @$rule;
		push @rhs_k, [$rhs1, $rhs2, $len + 1];
		push @prob, $q->[$i]->{$rhs1} * $rule_prob;
	    }
	}
    }
    confess "Traceback error: i=$i, lhs=", $self->sym_name->[$lhs] unless @prob;
    my ($rhs1, $rhs2, $k) = @{sample (\@prob, \@rhs_k)};
    return [$self->sym_name->[$lhs],
	    $k > $len
	    ? ($self->traceback_Inside_q ($p, $q, $i, $rhs1),
	       $self->simulate_Chomsky ($rhs2))
	    : ($self->traceback_Inside_p ($p, $i, $k, $rhs1),
	       $self->traceback_Inside_q ($p, $q, $k, $rhs2))];
}

sub simulate_Chomsky {
    my ($self, $lhs) = @_;
    $lhs = $self->start_id unless defined $lhs;
    return [$self->sym_name->[$lhs]] if $self->is_term->{$lhs};
    my $rule_by_rhs1 = $self->rule_by_lhs_rhs1->{$lhs};
    confess "Simulation error: lhs=", $self->sym_name->[$lhs] unless defined $rule_by_rhs1;
    my (@rhs, @prob);
    while (my ($rhs1, $rule_list) = each %$rule_by_rhs1) {
	for my $rule (@$rule_list) {
	    my ($rhs2, $rule_prob, $rule_index) = @$rule;
	    push @rhs, [$rhs1, $rhs2];
	    push @prob, $rule_prob;
	}
    }
    my ($rhs1, $rhs2) = @{sample (\@prob, \@rhs)};
    return [$self->sym_name->[$lhs],
	    $self->simulate_Chomsky($rhs1),
	    $self->simulate_Chomsky($rhs2)];
}

sub simulate {
    my ($self, $lhs) = @_;
    my $parse_tree = $self->simulate_Chomsky ($lhs);
    return $self->flatten_parse_tree ($parse_tree);
}

sub sample {
    my ($p_array, $opt_array) = @_;
    my $total = 0;
    for my $p (@$p_array) {
	confess "Undefined probability" unless defined $p;
	$total += $p;
    }
    my $r = rand() * $total;
    for my $i (0..$#$p_array) {
	$r -= $p_array->[$i];
	return defined($opt_array) ? $opt_array->[$i] : $i if $r <= 0;
    }
    return defined($opt_array) ? $opt_array->[$#$opt_array] : $#$p_array;
}

sub print_parse_tree {
    my ($self, $tree) = @_;
    my $lhs = $tree->[0];
    my @rhs = (@$tree)[1..$#$tree];
    while (@rhs > 1 && $rhs[$#rhs]->[0] eq $self->end) { pop @rhs }
    return @rhs > 0
	? ("(" . $lhs . "->" . join (",", map ($self->print_parse_tree($_), @rhs)) . ")")
	: $lhs;
}

# flatten Chomsky-fied nodes
sub flatten_parse_tree {
    my ($self, $tree) = @_;
    my $lhs = $tree->[0];
    my @rhs = (@$tree)[1..$#$tree];
    my $retry;
    do {
	$retry = 0;
	my @new_rhs;
	for my $rhs (@rhs) {
	    if ($rhs->[0] =~ /\./) {
		push @new_rhs, @{$rhs}[1..$#$rhs];
		$retry = 1;
	    } else {
		push @new_rhs, $rhs;
	    }
	}
	@rhs = @new_rhs;
    } while ($retry);
    return [$lhs, map ($self->flatten_parse_tree($_), @rhs)];
}

# convert a parse tree into a sequence
sub parse_tree_sequence {
    my ($self, $tree) = @_;
    my $lhs = $tree->[0];
    my @rhs = (@$tree)[1..$#$tree];
    return @rhs > 0
	? map ($self->parse_tree_sequence($_), @rhs)
	: ($lhs eq $self->end ? () : $lhs);
}

1;
