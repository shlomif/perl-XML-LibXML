#! /bin/sh
make

MEMORY_TEST=1 \
PERL_DL_NONLAZY=1 \
/usr/bin/perl \
                 -Iblib/arch \
                 -Iblib/lib \
                 -I/usr/local/lib/perl5/5.6.1/i686-linux \
                 -I/usr/local/lib/perl5/5.6.1 \
                 -e 'use Test::Harness qw(&runtests $verbose); $verbose=1; runtests @ARGV;' \
                  t/$1*.t
