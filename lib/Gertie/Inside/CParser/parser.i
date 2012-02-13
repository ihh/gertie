// File : parser.i
%module Swig
%{
#include "parser.h"
%}

Parser* parserNew (int symbols, int rules);
void parserDelete (Parser *parser);
void parserSetRule (Parser *parser, int rule_index, int lhs_sym, int rhs1_sym, int rhs2_sym, double rule_prob);
void parserSetEmptyProb (Parser *parser, int sym, double prob);
int parserSeqLen (Parser *parser);
double parserGetP (Parser *parser, int i, int j, int sym);
double parserGetQ (Parser *parser, int i, int sym);
void parserPushTok (Parser *parser, int sym);
int parserPopTok (Parser *parser);
