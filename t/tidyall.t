#!/usr/bin/perl

use strict;
use warnings;

my $KEY = 'XML_LIBXML_ENABLE_TIDYALL';
if ( !$ENV{$KEY} )
{
    require Test::More;
    Test::More::plan(
        'skip_all' => "Skipping perltidy test because $KEY was not set" );
}
require Test::Code::TidyAll;

Test::Code::TidyAll::tidyall_ok( conf_file => ".tidyallrc", );
