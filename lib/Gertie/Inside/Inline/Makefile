
all: parser.bundle

%_wrap.c: %.i %.h
	swig -perl $*.i

%.o: %.c %_wrap.c
	gcc -c $*.c $*_wrap.c `perl -MExtUtils::Embed -e ccopts`

%.bundle: %.o
	gcc -bundle -o $*.bundle $*.o $*_wrap.o `perl -MExtUtils::Embed -e ldopts`

.SECONDARY:

.SUFFIXES:
