#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use File::Spec;

if ( ! $ENV{AUTHOR_TESTING} ) {
    plan skip_all => "only for AUTHORS";
} else {
    plan tests => 3;
}

sub _is_present
{
    my $path = shift;

    my $fn = File::Spec->catfile( File::Spec->curdir(), @$path );

    return ( ( -e $fn ) and ( ( -s $fn ) > 0 ) );
}

{
    # TEST*3
    foreach my $path (
        [qw#lib XML LibXML DOM.pod#],
        [qw#lib XML LibXML Document.pod#],
        [qw#lib XML LibXML Parser.pod#],
        )
    {
        if ( !ok( scalar( _is_present($path) ), "Path [@$path] exists." ) )
        {
            diag('Perhaps you should run "make docs"');
        }
    }
}
