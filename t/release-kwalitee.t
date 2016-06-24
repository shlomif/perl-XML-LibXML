#!perl

use strict;
use warnings;
use Test::More;   # needed to provide plan.

eval { require Test::Kwalitee::Extra };
plan skip_all => "Test::Kwalitee::Extra required for testing kwalitee: $@" if $@;

eval "use Test::Kwalitee::Extra";
