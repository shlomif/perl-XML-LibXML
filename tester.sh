#! /bin/sh
make

MEMORY_TEST=1 \
THREAD_TEST=1 \
PERL_DL_NONLAZY=1 \
/usr/bin/perl \
                 -Iblib/arch \
                 -Iblib/lib \
                 -e 'use Test::Harness qw(&runtests $verbose); $verbose=1; runtests @ARGV;' \
                  t/$1*.t
