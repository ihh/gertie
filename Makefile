GRAMMAR = turn-grammar

debug:
	bin/robin.pl -grammar t/$(GRAMMAR) -choice t/$(GRAMMAR).choice -narrative t/$(GRAMMAR).narrative -verbose 9

turn:
	bin/robin.pl t/$(GRAMMAR)

test:
	prove
