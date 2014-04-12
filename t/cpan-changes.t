#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

eval 'use Test::CPAN::Changes 0.27';
plan skip_all => 'Test::CPAN::Changes 0.27 required for this test' if $@;

changes_ok();

