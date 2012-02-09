GRAMMAR = turn-grammar

debug:
	bin/robin.pl -grammar t/$(GRAMMAR) -text t/$(GRAMMAR).text -verbose 9

turn:
	bin/robin.pl t/$(GRAMMAR)

test:
	prove
