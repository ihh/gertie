# Linux
swig -c++ -perl5 parser.i
g++ -c `perl -MConfig -e 'print join(" ", @Config{qw(ccflags optimize cccdlflags)}, "-I$Config{archlib}/CORE")'` parser.cxx parser_wrap.cxx
g++ `perl -MConfig -e 'print $Config{lddlflags}'` parser.o parser_wrap.o -o parser.so
perl -e 'use parser'

# OS X
swig -c++ -perl parser.i
g++ -c parser.cxx parser_wrap.cxx `perl -MExtUtils::Embed -e ccopts`
g++ -bundle -o parser.bundle parser.o parser_wrap.o `perl -MExtUtils::Embed -e ldopts`
perl -e 'use parser'
