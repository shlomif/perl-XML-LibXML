#!/bin/bash
set -x
export HARNESS_OPTIONS="j4:c" TEST_JOBS=4
mak='make -j8'
perl Makefile.PL && \
    ($mak docs || true) && \
    perl Makefile.PL && \
    $mak test && \
    $mak disttest
