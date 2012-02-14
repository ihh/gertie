package Gertie::Inside::CParser;
use Moose;
use AutoHash;
use Gertie;
use Gertie::Inside;
extends 'Gertie::Inside';

use lib "/Users/yam/gertie/lib/Gertie/Inside/CParser";
use parser;

# constructor
sub new_Inside {
    my ($class, $gertie, $tokseq, @args) = @_;
    my %arg_hash = @args;
    my $verbose = $arg_hash{'verbose'};

    my $symbols = @{$gertie->sym_name} + 0;
    my $rules = @{$gertie->rule} + 0;
    warn "Parser *p = parserNew ($symbols, $rules);\n" if $verbose;
    my $cpp_parser = parser::parserNew ($symbols, $rules);
    parser::parserDebug($cpp_parser) if $verbose;
    my $n_rule = 0;
    for (my $lhs = 0; $lhs < $symbols; ++$lhs) {
	while (my ($rhs1, $rule_list) = each %{$gertie->rule_by_lhs_rhs1->{$lhs}}) {
	    for my $rule (@$rule_list) {
		my ($rhs2, $rule_prob, $rule_index) = @$rule;
		confess "Too many rules" if $n_rule >= $rules;
		warn
		    "parserSetRule (p, $n_rule, $lhs, $rhs1, $rhs2, $rule_prob);  /* ",
		    $gertie->sym_name->[$lhs], " -> ",
		    $gertie->sym_name->[$rhs1], " ", $gertie->sym_name->[$rhs2],
		    " */\n" if $verbose;
		parser::parserSetRule ($cpp_parser, $n_rule++, $lhs, $rhs1, $rhs2, $rule_prob);
	    }
	}
    }
    confess "Wrong number of rules" if $n_rule != $rules;
    while (my ($sym, $p) = each %{$gertie->p_empty}) {
	warn "parserSetEmptyProb (p, $sym, $p);  /* ", $gertie->sym_name->[$sym], " */\n" if $verbose;
	parser::parserSetEmptyProb ($cpp_parser, $sym, $p);
    }

    my $self = $class->SUPER::new_Inside ( $gertie,
					   undef,  # don't pass tokseq to super

					   # subclass-specific members
					   'cpp_parser' => $cpp_parser,

					   @args );
    bless $self, $class;

    # push tokseq
    $self->push_tok (@$tokseq) if defined $tokseq;

    # fill and return
    return $self;

}

# destructor
sub DESTROY {
    my ($self) = @_;
    parser::parserDelete ($self->cpp_parser)
	if defined $self->{'cpp_parser'};
}

sub get_p {
    my ($self, $i, $j, $sym) = @_;
    confess "get_p out of bounds"
	if $i < 0 || $i > $j || $j > $self->len || $sym < 0 || $sym >= $self->gertie->n_symbols;
    warn "parserGetP (p, $i, $j, $sym);\n" if $self->verbose;
    return parser::parserGetP ($self->cpp_parser, $i, $j, $sym);
}

sub get_q {
    my ($self, $i, $sym) = @_;
    confess "get_q out of bounds"
	if $i < 0 || $i > $self->len || $sym < 0 || $sym >= $self->gertie->n_symbols;
    warn "parserGetQ (p, $i, $sym);\n" if $self->verbose;
    return parser::parserGetQ ($self->cpp_parser, $i, $sym);
}

sub push_tok {
    my ($self, @new_tok) = @_;
    for my $tok (@new_tok) {
	warn "parserPushTok (p, $tok);  /* ", $self->gertie->sym_name->[$tok], " */\n" if $self->verbose;
	push @{$self->tokseq}, $tok;
	parser::parserPushTok ($self->cpp_parser, $tok);
   }
}

sub pop_tok {
    my ($self) = @_;
    confess "Attempt to pop empty matrix" if $self->len == 0;
    warn "parserPopTok (p);\n" if $self->verbose;
    return parser::parserPopTok ($self->cpp_parser);
}

1;
 
