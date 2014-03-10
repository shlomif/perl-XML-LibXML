#!/usr/bin/perl

# Test for:
# https://rt.cpan.org/Ticket/Display.html?id=93429
#
# Contributed by Nick Wellnhofer.

use strict;
use warnings;

use Test::More tests => 1;

use XML::LibXML;

{
    my $err_html = '<html><body><lkj/></body></html>';

    my $parser = XML::LibXML->new();

    my $buf = '';
    open(my $fh, '>', \$buf);

    {
        local *STDERR = $fh;
        $parser->load_html( string => $err_html, recover => 2, );
    }

    close($fh);

    is($buf, '', 'No warning emitted on load_html with recover => 2.');
}

