#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

plan skip_all => "These tests are for authors only!" unless $ENV{AUTHOR_TESTING} or $ENV{RELEASE_TESTING};

eval 'use Test::CPAN::Changes 0.27';
plan skip_all => 'Test::CPAN::Changes 0.27 required for this test' if $@;

changes_ok();
