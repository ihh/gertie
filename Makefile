GRAMMAR = turn-grammar

debug:
	bin/robin.pl -grammar t/$(GRAMMAR) -text t/$(GRAMMAR).text -verbose 9 -color

turn:
	bin/robin.pl t/$(GRAMMAR)

test:
	prove
