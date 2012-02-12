swig -c++ -perl5 parser.i
gcc -c `perl -MConfig -e 'print join(" ", @Config{qw(ccflags optimize cccdlflags)}, "-I$Config{archlib}/CORE")'` parser.cxx parser_wrap.cxx
gcc `perl -MConfig -e 'print $Config{lddlflags}'` parser.o parser_wrap.o -o parser.so
perl -e 'use Parser'
