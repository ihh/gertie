GRAMMAR = t/turn-grammar
CONVO = convo.grammar
GOLDIE = goldilocks.grammar

debug-turn: cparser
	bin/robin.pl -cparser -grammar $(GRAMMAR) -verbose 9 -color

turn: cparser
	bin/robin.pl -cparser $(GRAMMAR)

perl-turn:
	bin/robin.pl $(GRAMMAR)

debug-convo: cparser
	bin/robin.pl -cparser -grammar $(CONVO) -verbose 9 -color

convo: cparser
	bin/robin.pl -cparser $(CONVO)

goldie: cparser
	bin/robin.pl $(GOLDIE) -cparser

goldie-color: cparser
	bin/robin.pl $(GOLDIE) -cparser -color

test:
	prove

cparser:
	@cd lib/Gertie/Inside/CParser; make all >/dev/null

cparser-test: cparser
	cd lib/Gertie/Inside/CParser; make test
