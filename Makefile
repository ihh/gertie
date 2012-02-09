debug:
	bin/robin.pl -verbose 9 t/turn-grammar

turn:
	bin/robin.pl t/turn-grammar

test:
	prove
