package Gertie;
use Moose;
use AutoHash;
use Gertie::Inside;
use Gertie::Outside;
extends 'AutoHash';

use strict;

# generic imports
use Carp qw(carp croak cluck confess);
use Data::Dumper;
use File::Temp;
use Scalar::Util;
use IPC::Open3;
use Symbol qw(gensym);

# specific imports
use Graph::Directed;
use Math::Symbolic;
use Parse::RecDescent;

# constructor
sub new_gertie {
    my ($class, @args) = @_;
    my $sym_regex = '[a-z][\w@]*\b';
    my $quant_regex = '[\?\*\+]|\{\d+,\d*\}|\{\d*,\d+\}|\{\d+\}';
    my $quantified_sym_regex = "$sym_regex(|$quant_regex)";
    my $self = AutoHash->new ( 'end' => "end",
			       'rule' => [],  # fields are (lhs,rhs1,rhs2,prob,rule_index,prob_func)
			       'deferred_rule' => [],
			       'rule_index_by_name' => {},
			       'pgroups' => [],
			       'param' => {},

			       'symbol_order' => {},
			       'symbol_list' => [],

			       'max_inside_len' => undef,
			       'term_owner_by_name' => {},
			       'agents' => [qw(p)],  # first agent is the human player

			       'agent_regex' => '[a-z]\w*\b',
			       'sym_regex' => $sym_regex,
			       'sym_with_quant_regex' => $quantified_sym_regex,
			       'lhs_regex' => $quantified_sym_regex,
			       'rhs_regex' => $quantified_sym_regex,
			       'prob_regex' => '[\d\.]*|\([^\|;]*\)',
			       'param_regex' => '[a-z]\w*',
			       'num_regex' => '[\d\.]*',
			       'quantifier_regex' => $quant_regex,

			       'inside_class' => 'Gertie::Inside::PerlParser',
			       'use_c_parser' => 0,

			       'verbose' => 0,
			       'output_precision' => 10,
			       @args );
    bless $self, $class;
    $self->add_symbols ($self->end);
    $self->inside_class ('Gertie::Inside::CParser') if $self->use_c_parser;
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
    my @text = split /\n/, $text;
    $self->parse (@text);
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
    grep (s/\/\/.*$//, @text);  # strip out C++ style // comments
    my @lines = split (/;/, join ("", @text));
    for my $line (@lines) {
	$self->parse_line ($line);
    }
    $self->add_deferred_rules;
}

sub parse_line {
    my ($self, $line) = @_;
    local $_;
    $_ = $line;
    s/\n/ /g;
    return unless /\S/;  # ignore blank lines
    warn "Parsing $line" if $self->verbose > 10;

    my $agent_regex = $self->agent_regex;
    my $lhs_regex = $self->lhs_regex;
    my $rhs_regex = $self->rhs_regex;
    my $prob_regex = $self->prob_regex;
    my $param_regex = $self->param_regex;
    my $num_regex = $self->num_regex;

    if (/^\s*($lhs_regex)\s*\->\s*($rhs_regex)\s*(|$rhs_regex)\s*($prob_regex)\s*;?\s*$/) {  # Transition (A->B) or Chomsky-form rule (A->B C) with optional probability
	my ($lhs, $lhs_crap, $rhs1, $rhs1_crap, $rhs2, $rhs2_crap, $prob) = ($1, $2, $3, $4, $5, $6, $7);
	$self->foreach_agent ([$lhs, $rhs1, $rhs2],
			      sub { my ($lhs, $rhs1, $rhs2) = @_;
				    my ($deferred_rule, $newrhs1, $newrhs2) = $self->process_quantifiers ($rhs1, $rhs2);
				    $self->add_rule ($lhs, $newrhs1, $newrhs2, $prob);
				    push @{$self->deferred_rule}, @$deferred_rule });
    } elsif (/^\s*($lhs_regex)\s*\->((\s*$rhs_regex)*)\s*($prob_regex)\s*;?\s*$/) {  # Non-Chomsky rule (A->B C D ...) with optional probability
	my ($lhs, $lhs_crap, $rhs, $rhs1, $rhs_crap, $prob) = ($1, $2, $3, $4, $5, $6);
	# Convert "A->B C D E" into "A -> B.C.D E;  B.C.D -> B.C D;  B.C -> B C"
	$rhs =~ s/^\s*(.*?)\s*$/$1/;
	my @rhs = split /\s+/, $rhs;
	confess "Parse error" unless @rhs >= 2;
	$self->expand_rule ($lhs, \@rhs, $prob);
    } elsif (/^\s*($lhs_regex)\s*\->((\s*$rhs_regex)*\s*($prob_regex)(\s*\|(\s*$rhs_regex)*\s*($prob_regex))*)\s*;?\s*$/) {  # Multiple right-hand sides (A->B C|D E|F) with optional probabilities
	my ($lhs, $lhs_crap, $all_rhs) = ($1, $2, $3);
	my @rhs = split /\|/, $all_rhs;
	for my $rhs (@rhs) { $self->parse_line ("$lhs -> $rhs") }
    } elsif (/^\s*\@($agent_regex)((\s+$lhs_regex)*)\s*;?$/) {  # @agent_name symbol1 symbol2 symbol3...
	my ($owner, $symbols, $symbols_crap) = ($1, $2, $3);
	$symbols =~ s/^\s*(.*?)\s*$/$1/;
	my @symbols = split /\s+/, $symbols;
	$self->declare_agent_ownership ($owner, @symbols);
    } elsif (/^\s*\(\s*($param_regex(\s*,\s*$param_regex)*)\s*\)\s*=\s*\(\s*($num_regex(\s*,\s*$num_regex)*)\s*\)\s*$/) {   # (param1, param2, param3...) = (value1, value2, value3...)
	my ($params, $params_crap, $nums, $nums_crap) = ($1, $2, $3, $4);
	my @params = split /,/, $params;
	my @nums = split /,/, $nums;
	$self->declare_params (\@params, \@nums);
    } else {
	warn "Unrecognized line: ", $_;
    }
}

sub declare_params {
    my ($self, $params, $nums) = @_;
    confess "params (@$params) and values (@$nums) do not match in length" unless @$params == @$nums;
    push @{$self->pgroups}, $params;
    for my $n (0..$#$params) { $self->param->{$params->[$n]} = $nums->[$n] }
}

sub declare_agent_ownership {
    my ($self, $owner, @symbols) = @_;
    push @{$self->agents}, $owner unless grep ($_ eq $owner, @{$self->agents});
    for my $sym (@symbols) { $self->term_owner_by_name->{$sym} = $owner }
}

sub expand_rule {
    my ($self, $lhs, $rhs, $prob) = @_;
    confess "rhs must be an arrayref" unless ref($rhs) eq 'ARRAY';
    warn "expanding rule $lhs -> @$rhs ($prob)" if $self->verbose > 5;
    $self->foreach_agent ([$lhs, @$rhs],
			  sub { my ($lhs, @rhs) = @_;
				my ($deferred_rule, @newrhs) = $self->process_quantifiers (@rhs);
				$self->add_non_Chomsky_rule ($lhs, \@newrhs, $prob);
				push @{$self->deferred_rule}, @$deferred_rule });
}

sub foreach_agent {
    my ($self, $sym_list, $agent_sub) = @_;
    my $quant_re = '(|' . $self->quantifier_regex . ')$';
    if (grep (/\@\d+$quant_re/, @$sym_list)) {
	warn "Found agent macro in (@$sym_list)" if $self->verbose > 10;
	for (my $a1 = 0; $a1 < @{$self->agents}; ++$a1) {
	    my @sym = @$sym_list;
	    for (my $a_delta = 0; $a_delta < @{$self->agents}; ++$a_delta) {
		my $agent_index = ($a1 + $a_delta) % (@{$self->agents} + 0);
		my $agent = $self->agents->[$agent_index];
		my $num = $a_delta + 1;
		grep (s/\@$num$quant_re/\@$agent$1/g, @sym);
		warn "Expanded to (@sym)" if $self->verbose > 10;
	    }
	    &$agent_sub (@sym);
	}
    } else {
	&$agent_sub (@$sym_list);
    }
}

# add_rule is the core grammar-building method that adds a new Chomsky-normal form rule,
# defining new symbols if necessary
sub add_rule {
    my ($self, $lhs, $rhs1, $rhs2, $prob) = @_;
    # Supply default values
    $rhs2 = $self->end unless defined($rhs2) && length($rhs2);
    $prob = 1 unless defined($prob) && length($prob);
    $prob =~ s/^\(\s*(.*?)\s*\)$/$1/;  # remove brackets
    my $prob_is_func = ($prob =~ /^[a-z]/);
    if ($prob_is_func) {
	my $f = Math::Symbolic::parse_from_string ($prob);
	my @undef_param = grep (!defined($self->param->{$_}), $f->signature);
	confess "Expression ($prob_is_func) has undefined parameters (@undef_param)" if @undef_param;
    }
    warn "Adding Chomsky rule: $lhs -> $rhs1 $rhs2 ($prob)" if $self->verbose > 10;
    # Check the rule is valid
    confess "Empty rule" unless defined($rhs1) && length($rhs1);
    confess "Transformation of 'end'" if $lhs eq $self->end;  # No rules starting with 'end'
    $self->{'start'} = $lhs unless defined $self->{'start'};  # First named nonterminal is start
    return if !$prob_is_func && $prob == 0;  # Don't bother tracking zero-weight rules
    confess "Negative probability" if !$prob_is_func && $prob < 0;  # Rule weights are nonnegative
    # Be idempotent
    my $rule_index;
    if (exists $self->rule_index_by_name->{$lhs}->{$rhs1}->{$rhs2}) {
	$rule_index = $self->rule_index_by_name->{$lhs}->{$rhs1}->{$rhs2};
	my $old_prob = $self->get_rule_prob ($rule_index);
	my $old_prob_is_func = ($old_prob =~ /^[a-z]/);
	unless (($prob_is_func || $old_prob_is_func) ? ($old_prob eq $prob) : ($old_prob == $prob)) {
	    warn "Ignoring attempt to change probability of rule ($lhs->$rhs1 $rhs2) from $old_prob to $prob\n" if $self->verbose;
	}
	return;
    } else {
	$rule_index = @{$self->rule};
    }
    # Record the rule
    $self->rule_index_by_name->{$lhs}->{$rhs1}->{$rhs2} = $rule_index;
    $self->rule->[$rule_index] = [$lhs, $rhs1, $rhs2, $prob, $rule_index, $prob_is_func ? $prob : undef];
    $self->add_symbols ($lhs, $rhs1, $rhs2);
}

sub add_symbols {
    my ($self, @sym) = @_;
    for my $sym (@sym) {
	if (!defined $self->symbol_order->{$sym}) {
	    push @{$self->symbol_list}, $sym;
	    $self->symbol_order->{$sym} = @{$self->symbol_list};
	}
    }
}

# general, non-Chomsky context-free rules are broken down into Chomsky rules via intermediate nonterminals
# e.g.
#   A -> B C D E;
# becomes
#      A -> B.C.D  E;
#  B.C.D -> B.C  D;
#    B.C -> B  C;
sub add_non_Chomsky_rule {
    my ($self, $lhs, $rhs_listref, $prob) = @_;
    $prob = 1 unless defined $prob;
    warn "Adding non-Chomsky rule: $lhs -> @$rhs_listref ($prob)" if $self->verbose > 10;
    $self->add_symbols ($lhs, @$rhs_listref);
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

# Perl regexp-style quantifiers get broken down into non-Chomsky rules
sub process_quantifiers {
    my ($self, @sym) = @_;
    my $sym_regex = $self->sym_regex;
    # all the nonsense with @deferred_rule is so that we don't introduce a spurious start nonterminal
    # ...also so we give the input file a chance to define its own probabilities, parameterizations etc.
    my (@sym_ret, @deferred_rule);
    for my $sym (@sym) {
	$sym =~ s/\{(\d+)\}$/\{$1,$1\}/;  # Convert X{N} into X{N,N}
	$sym =~ s/\{0?,1\}$/?/;  # Convert X{0,1} into X?
	$sym =~ s/\{0?,\}$/*/;   # Convert X{0,} into X*
	$sym =~ s/\{1,1\}$//;   # Convert X{1,1} into X
	$sym =~ s/\{1,\}$/+/;   # Convert X{1,} into X+
	$sym =~ s/\{0,(\d+)\}$/{,$1}/;  # Convert X{0,N} into X{,N}
	push @sym_ret, $sym;
	if ($sym =~ /^($sym_regex)\?$/) {
	    push @deferred_rule, [.5, $sym, $1];
	    push @deferred_rule, [.5, $sym, $self->end];
	} elsif ($sym =~ /^($sym_regex)\*$/) {
	    push @deferred_rule, [.5, $sym, $1, $sym];
	    push @deferred_rule, [.5, $sym, $self->end];
	} elsif ($sym =~ /^($sym_regex)\+$/) {
	    my $base = $1;
	    push @deferred_rule, [.5, $sym, $base, $sym];
	    push @deferred_rule, [.5, $sym, $base];
	} elsif ($sym =~ /^($sym_regex)\{(\d*),(\d*)\}$/) {
	    my ($base, $min, $max) = ($1, $2, $3);
	    confess "Bad quantifiers in nonterminal $sym" if (length($max) && $max < 0) || (length($min) && $min <= 0) || (length($max) && length($min) && $max < $min) || ($min eq "" && $max eq "");
	    if (length $max) {
		my $start = length($min) ? $min : 0;
		my $count = $max + 1 - $start;
		for (my $n = $start; $n <= $max; ++$n) {
		    if ($n == 0) {
			push @deferred_rule, [1/$count, $sym, $self->end];
		    } else {
			push @deferred_rule, [1/$count, $sym, map ($base, 1..$n)];
		    }
		}
	    } else {  # $min > 1, no $max
		push @deferred_rule, [$sym, map ($base, 1..$min-1), "$base+"];
		push @deferred_rule, ["$base+", $base, "$base+"];
		push @deferred_rule, ["$base+", $base];
	    }
	}
    }
    return (\@deferred_rule, @sym_ret);
}

sub add_deferred_rules {
    my ($self) = @_;
    for my $rule (@{$self->deferred_rule}) {
	my ($prob, $deflhs, @defrhs) = @$rule;
	if (@defrhs <= 2) {
	    $self->add_rule ($deflhs, @defrhs[0,1], $prob);
	} else {
	    $self->add_non_Chomsky_rule ($deflhs, \@defrhs, $prob);
	}
    }
    delete $self->{'deferred_rule'};
}

# get_rule_prob: get a rule probability
sub get_rule_prob {
    my ($self, $rule_index) = @_;
    return $self->rule->[$rule_index]->[3];  # fields of rule are (lhs,rhs1,rhs2,prob,rule_index,prob_func)
}

# set_rule_prob: change a rule probability
# Used internally by the EM algorithm. Do not use!
# Call index() after this method, to update all caches
sub set_rule_prob {
    my ($self, $rule_index, $new_prob) = @_;
    confess "Probability undefined" unless defined $new_prob;
    $self->rule->[$rule_index]->[3] = $new_prob;  # fields of rule are (lhs,rhs1,rhs2,prob,rule_index,prob_func)
}

# Index: convert symbols & rules to integers
sub index {
    my ($self) = @_;
    $self->index_symbols;
    $self->index_rules;
}

sub normalize_rule_probs {
    my ($self) = @_;

    # Normalize pgroups
    for my $pgroup (@{$self->pgroups}) {
	my $norm = 0;
	for my $param (@$pgroup) {
	    $norm += $self->param->{$param};
	}
	if ($norm != 0) {
	    for my $param (@$pgroup) {
		$self->param->{$param} /= $norm;
	    }
	}
    }

    # Evaluate rule probabilities & normalize rules
    my %outgoing_prob_by_name;
    for my $rule (@{$self->rule}) {
	my ($lhs, $rhs1, $rhs2, $prob, $rule_index, $prob_func) = @$rule;
	if (defined $prob_func) {
	    $prob = Math::Symbolic::parse_from_string($prob_func)->value(%{$self->param});
	    @$rule = ($lhs, $rhs1, $rhs2, $prob, $rule_index, $prob_func);
	}
	$outgoing_prob_by_name{$lhs} += $prob;
    }

    for my $rule (@{$self->rule}) {
	my ($lhs, $rhs1, $rhs2, $prob, $rule_index, $prob_func) = @$rule;
	$prob /= $outgoing_prob_by_name{$lhs} if $outgoing_prob_by_name{$lhs} != 0;
	@$rule = ($lhs, $rhs1, $rhs2, $prob, $rule_index, $prob_func);
    }

    # quick-index rules by rhs symbols
    my %by_rhs;
    for my $rule (@{$self->rule}) {
	my ($lhs, $rhs1, $rhs2, $prob, $rule_index) = @$rule;
	push @{$by_rhs{$rhs1}}, $rule;
	push @{$by_rhs{$rhs2}}, $rule unless $rhs1 eq $rhs2;
    }

    # find probability that each symbol has a null path to 'end'
    # this hash should be sparse: every key must have a nonzero (positive) value
    my @null_q = ($self->end);
    my %p_empty = ($self->end => 1);
    while (@null_q) {
	my $sym = shift @null_q;
	for my $rule (@{$by_rhs{$sym}}) {
	    my ($lhs, $rhs1, $rhs2, $rule_prob, $rule_index) = @$rule;
	    if (defined($p_empty{$rhs1}) && defined($p_empty{$rhs2})) {
		push @null_q, $lhs unless defined ($p_empty{$lhs});
		$p_empty{$lhs} += $p_empty{$rhs1} * $p_empty{$rhs2} * $rule_prob;
	    }
	}
    }
    warn "Nonterminals that can be null: ", join(" ",keys%p_empty) if $self->verbose > 1;

    $self->{'p_empty_by_name'} = \%p_empty;
}

sub update_p_empty {
    my ($self) = @_;
    my $p_empty = $self->p_empty_by_name;
    $self->{'p_empty'} = { map (($self->sym_id->{$_} => $p_empty->{$_}), keys %$p_empty) };
    $self->{'p_nonempty'} = { map (defined($p_empty->{$_})
				   ? ($p_empty->{$_} == 1
				      ? ()
				      : ($self->sym_id->{$_} => (1 - $p_empty->{$_})))
				   : ($self->sym_id->{$_} => 1),
				   @{$self->sym_name}) };
    delete $self->{'p_empty_by_name'};
}

# helper called by EM
sub update_indexed_rule_probs {
    my ($self) = @_;
    $self->normalize_rule_probs;
    $self->update_p_empty;
    $self->index_rules;
}

# Treating each rule "A->B C" as an edge "A->B", compute toposort
sub index_symbols {
    my ($self) = @_;

    # Check that we have some rules & symbols to index
    unless (@{$self->rule}) {
	warn "No rules to index; adding default start nonterminal\n";
	$self->{'start'} = "start";
	$self->add_symbols ($self->start);
    }

    # normalize
    $self->normalize_rule_probs;

    # build transition graph
    my $graph = Graph::Directed->new;
    $self->{'graph'} = $graph;
    for my $sym (@{$self->symbol_list}) {
	$graph->add_vertex ($sym);
    }

    my $p_empty = $self->p_empty_by_name;
    for my $rule (@{$self->rule}) {
	my ($lhs, $rhs1, $rhs2, $prob, $rule_index) = @$rule;
	$graph->add_edge ($lhs, $rhs1);
	$graph->add_edge ($lhs, $rhs2) if defined $p_empty->{$rhs1};
	if ($self->verbose > 2) {
	    warn "Added edge $lhs->$rhs1";
	    warn "Added edge $lhs->$rhs2" if defined $p_empty->{$rhs1};
	}
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

    $self->update_p_empty;

    # We define "terminals" to include 'end'
    my @term = grep (!exists($self->rule_index_by_name->{$_}), sort @{$self->symbol_list});
    $self->{'term_name'} = \@term;
    $self->{'term_id'} = [map ($self->sym_id->{$_}, @term)];
    $self->{'is_term'} = {map (($_ => 1), @{$self->term_id})};
    $self->{'nonterm_id'} = grep (!$self->is_term->{$_}, 0..$#{$self->sym_name});

    # Terminal ownership
    $self->{'term_owner'} = {};
    while (my ($term_name, $owner) = each %{$self->term_owner_by_name}) {
	my $term_id = $self->sym_id->{$term_name};
	confess "Terminal $term_name not in grammar" unless defined $term_id;
	$self->{'term_owner'}->{$term_id} = $owner;
    }
    my $agent_regex = $self->agent_regex;
    my %is_agent = map (($_ => 1), @{$self->agents});
    for my $term_num (0..$#{$self->term_id}) {
	my $term_id = $self->term_id->[$term_num];
	if ($term_id != $self->end_id) {
	    my $term_name = $self->term_name->[$term_num];
	    if ($term_name =~ /\@($agent_regex)/ && $is_agent{$1}) {
		my $agent = $1;
		if (defined $self->term_owner->{$term_id}) {
		    if ($self->term_owner->{$term_id} ne $agent) {
			confess "Tried to override automatic $agent-ownership of $term_name" if $self->verbose;
		    }
		} else {
		    $self->term_owner->{$term_id} = $agent;
		}
	    } elsif (!defined $self->term_owner->{$term_id}) {
		$self->term_owner->{$term_id} = $self->player_agent;
	    }
	}
    }
    %{$self->term_owner_by_name} = map (($self->sym_name->[$_] => $self->term_owner->{$_}), @{$self->term_id});

    # Log
    if ($self->verbose) {
	warn "Symbols: (@{$self->sym_name})";
	warn "Terminals: (@{$self->term_name})";
    }

    # delete transient indices/lookups/variables we have no further use for
    delete $self->{'symbols'};  # use $self->sym_name instead
}

sub has_symbol_index {
    my ($self) = @_;
    return defined ($self->{'sym_id'});
}

sub dense_graph {
    my ($self) = @_;
    my $graph = $self->graph->copy_graph;
    for my $rule (@{$self->rule}) {
	my ($lhs, $rhs1, $rhs2, $prob, $rule_index) = @$rule;
	$graph->add_edge ($lhs, $rhs2) unless $graph->has_edge ($lhs, $rhs2);
    }
    return $graph;
}


sub player_agent {
    my ($self) = @_;
    return $self->agents->[0];
}

sub n_rules {
    my ($self) = @_;
    return @{$self->rule} + 0;
}

sub n_symbols {
    my ($self) = @_;
    return @{$self->sym_name} + 0;
}

# Index rules
sub index_rules {
    my ($self) = @_;
    $self->{'tokenized_rule'} = [];
    $self->{'rule_by_lhs_rhs1'} = {};
    $self->{'rule_by_lhs'} = {};
    $self->{'rule_by_rhs1'} = {};
    $self->{'rule_by_rhs2'} = {};
    for my $rule (@{$self->rule}) {
	my ($lhs, $rhs1, $rhs2, $prob, $rule_index, $prob_func) = @$rule;
	my ($lhs_id, $rhs1_id, $rhs2_id) = map ($self->sym_id->{$_}, $lhs, $rhs1, $rhs2);
	push @{$self->rule_by_lhs_rhs1->{$lhs_id}->{$rhs1_id}}, [$rhs2_id, $prob, $rule_index, $prob_func];
	push @{$self->rule_by_lhs->{$lhs_id}}, $rule_index;
	push @{$self->rule_by_rhs1->{$rhs1_id}}, $rule_index;
	push @{$self->rule_by_rhs2->{$rhs2_id}}, $rule_index;
	push @{$self->tokenized_rule}, [$lhs_id, $rhs1_id, $rhs2_id, $prob, $prob_func];
	warn "Indexed rule: $lhs -> $rhs1 $rhs2 $prob;" if $self->verbose;
    }
}

# subroutine to print grammar
sub to_string {
    my ($self) = @_;
    my @text;
    my $fmt = '%.' . $self->output_precision . 'g';
    if (@{$self->agents} > 1) {
	for my $agent (@{$self->agents}) {
	    my @term = grep (!/\@$agent$/,
			     map ($self->term_name->[$_],
				  grep ($self->term_id->[$_] != $self->end_id
					&& $self->term_owner->{$self->term_id->[$_]} eq $agent,
					0..$#{$self->term_id})));
	    if (@term) {
		push @text, "\@$agent @term;\n";
	    } elsif ($agent ne $self->player_agent) {
		push @text, "\@$agent;\n";
	    }
	}
    }

    for my $pgroup (@{$self->pgroups}) {
	push @text, "(" . join (", ", @$pgroup) . ") = (" . join (", ", map (sprintf ($fmt, $self->param->{$_}),
									     @$pgroup)) . ");\n";
    }

    my $quant_regex = $self->quantifier_regex . '$';
    for my $lhs (sort @{$self->sym_name}) {
	next if $lhs =~ /\./;  # don't print rules added by Chomsky-fication
	next if $lhs eq $self->end;  # don't mess around with 'end' nonterminal
	my $lhs_id = $self->sym_id->{$lhs};
	my @rhs1 = map ($self->sym_name->[$_], keys %{$self->rule_by_lhs_rhs1->{$lhs_id}});
	for my $rhs1 (sort @rhs1) {
	    my $rhs1_id = $self->sym_id->{$rhs1};
	    $rhs1 =~ s/\./ /g;  # de-Chomskyfy
	    my @rule = sort {$self->sym_name->[$a->[0]] cmp $self->sym_name->[$b->[0]]}
	    @{$self->rule_by_lhs_rhs1->{$lhs_id}->{$rhs1_id}};
	    for my $rule (@rule) {
		my ($rhs2_id, $rule_prob, $rule_index, $prob_func) = @$rule;
		my $rhs2 = $self->sym_name->[$rhs2_id];
		my $rhs = " $rhs1 $rhs2";
		$rhs =~ s/ @{[$self->end]}//g;
		$rhs =~ s/\s+/ /;
		$rhs =~ s/^\s*//;
		$rhs = $self->end unless length $rhs;
		$rule_prob = defined($prob_func)
		    ? " ($prob_func)"
		    : ($rule_prob == 1 ? "" : sprintf(" ($fmt)", $rule_prob));
		push @text, "$lhs -> $rhs$rule_prob;\n";
	    }
	}
    }
    return join ("", @text);
}

# subroutine to tokenize a sequence
sub tokenize {
    my ($self, @seq) = @_;
    my @undefs = grep (!exists($self->sym_id->{$_}), @seq);
    confess "Undefined symbols (@undefs)" if @undefs;
    return map ($self->sym_id->{$_}, @seq);
}

# subroutine to compute Inside matrix for given tokenized prefix sequence
sub prefix_Inside {
    my ($self, $tokseq, @args) = @_;
    confess "tokseq must be a listref" unless defined($tokseq) && ref($tokseq) eq 'ARRAY';
    my $inside_class = $self->inside_class;
    eval ("require $inside_class");
    return $inside_class->new_Inside ($self, $tokseq, 'verbose' => 0, @args);
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

# do Inside-Outside training
sub train {
    my ($self, $training_seq_list) = @_;
    my $last_prob;
    for (my $iter = 1; 1; ++$iter) {
	my $prob = $self->single_EM_iteration_likelihood ($training_seq_list);
	warn "EM iteration \#$iter: Probability $prob", defined($last_prob) ? (" (previous $last_prob") : ()
	    if $self->verbose;
	last if defined($last_prob) && $prob <= $last_prob;
	$last_prob = $prob;
    }
}

sub single_EM_iteration_likelihood {
    my ($self, $training_seq_list) = @_;
    my ($all_prob, $rule_count) = $self->get_prob_and_rule_counts ($training_seq_list);
    $self->update_rule_probs ($rule_count);
    return $all_prob;
}

sub get_prob_and_rule_counts {
    my ($self, $training_seq_list) = @_;
    my @rule_count = map (0, @{$self->rule});
    my $all_prob = 1;
    for my $seq (@$training_seq_list) {
	my $inside = $self->prefix_Inside ([$self->tokenize (@$seq)]);
	my $outside = Gertie::Outside->new_Outside ($inside, 'rule_count' => \@rule_count);
	$all_prob *= $inside->final_p;
	warn "Sequence=(@$seq) rule_count=(@rule_count)" if $self->verbose;
    }
    return ($all_prob, \@rule_count);
}

# subroutine to print "raw" counts
sub counts_to_string {
    my ($self) = @_;
    my @text;
    for my $pgroup (@{$self->pgroups}) {
	push @text, "(" . join (", ", @$pgroup) . ") = (" . join (", ", map ($self->param->{$_}, @$pgroup)) . ");\n";
    }
    for my $rule (@{$self->rule}) {
	my ($lhs, $rhs1, $rhs2, $count, $rule_index, $prob_func) = @$rule;
	push @text, "$lhs -> $rhs1 $rhs2 ($count);  // Rule $rule_index\n" unless defined $prob_func;
    }
    return join ("", @text);
}

# update rule probabilities from a set of Inside-Outside counts
sub update_rule_probs {
    my ($self, $rule_count) = @_;
    confess "|rule_count|=", @$rule_count+0, " |rule|=", @{$self->rule}+0 unless @$rule_count == @{$self->rule};
    my %param_count = map (($_ => 0), keys %{$self->param});
    for my $rule_index (0..$#{$self->rule}) {
	my ($lhs, $rhs1, $rhs2, $prob, $prob_func) = @{$self->tokenized_rule->[$rule_index]};
	my $rc = $rule_count->[$rule_index];
	if (defined $prob_func) {
	    my $f = Math::Symbolic::parse_from_string ($prob_func);
	    my $fval = $f->value (%{$self->param});
	    if ($fval != 0) {
		for my $param ($f->signature) {
		    my $pval = $self->param->{$param};
		    next if $pval == 0;
		    my $df_dp = Math::Symbolic::Derivative::partial_derivative ($f, $param);
		    my $df_dp_val = $df_dp->value (%{$self->param});
		    my $dlogf_dlogp_val = $df_dp_val * $pval / $fval;
		    $param_count{$param} += $rc * $dlogf_dlogp_val;
		}
	    }
	} else {
	    $self->set_rule_prob ($rule_index, $rc);
	}
    }
    $self->param (\%param_count);
    warn $self->counts_to_string if $self->verbose;
    $self->update_indexed_rule_probs;  # update any caches that contain probabilities
}

1;
