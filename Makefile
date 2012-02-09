turn:
	bin/robin.pl t/turn-grammar

debug:
	bin/robin.pl -verbose 9 t/turn-grammar

test:
	prove
