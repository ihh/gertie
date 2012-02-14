GRAMMAR = t/turn-grammar
CONVO = convo.grammar

debug-turn: cparser
	bin/robin.pl -cparser -grammar $(GRAMMAR) -text $(GRAMMAR).text -verbose 9 -color

turn: cparser
	bin/robin.pl -cparser $(GRAMMAR)

perl-turn:
	bin/robin.pl $(GRAMMAR)

debug-convo: cparser
	bin/robin.pl -cparser -grammar $(CONVO) -verbose 9 -color

convo: cparser
	bin/robin.pl -cparser $(CONVO)

test:
	prove

cparser:
	cd lib/Gertie/Inside/CParser; make all test
