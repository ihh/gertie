
all: parser.bundle

clean:
	rm *_wrap.* *.o *.bundle *~

%_wrap.c: %.i %.h
	swig -perl $*.i

%.o: %.c %_wrap.c
	gcc -Wall -c $*.c $*_wrap.c `perl -MExtUtils::Embed -e ccopts`

%.bundle: %.o
	gcc -Wall -bundle -o $*.bundle $*.o $*_wrap.o `perl -MExtUtils::Embed -e ldopts`

test: parser.c parser.h test.c
	gcc -Wall -g -o test parser.c parser.h test.c

.SECONDARY:

.SUFFIXES:
