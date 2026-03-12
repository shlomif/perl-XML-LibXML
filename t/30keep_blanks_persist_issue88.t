#!/usr/bin/perl

# Regression test for https://github.com/shlomif/perl-XML-LibXML/issues/88
#
# Creating a parser with no_blanks and then creating another with keep_blanks
# should honor the keep_blanks setting. The bug was that xmlKeepBlanksDefault()
# was called after context creation, so the context inherited the stale global
# default from the previous parse.

use strict;
use warnings;

use Test::More tests => 6;

use XML::LibXML;

my $xmlstring = <<'EOM';
<?xml version="1.0"?>
<hello><bold>Line1</bold>
<bold>This should be on a new line</bold></hello>
EOM

my $with_blanks    = qq{<?xml version="1.0"?>\n<hello><bold>Line1</bold>\n<bold>This should be on a new line</bold></hello>\n};
my $without_blanks = qq{<?xml version="1.0"?>\n<hello><bold>Line1</bold><bold>This should be on a new line</bold></hello>\n};

# TEST
{
    my $parser = XML::LibXML->new( keep_blanks => 1 );
    my $dom = $parser->load_xml( string => $xmlstring );
    is( $dom->serialize, $with_blanks, 'first parser: keep_blanks=1 keeps whitespace' );
}

# TEST
{
    my $parser = XML::LibXML->new( no_blanks => 1 );
    my $dom = $parser->load_xml( string => $xmlstring );
    is( $dom->serialize, $without_blanks, 'second parser: no_blanks=1 strips whitespace' );
}

# TEST - this is the core regression from issue #88
{
    my $parser = XML::LibXML->new( keep_blanks => 1 );
    my $dom = $parser->load_xml( string => $xmlstring );
    is( $dom->serialize, $with_blanks, 'third parser: keep_blanks=1 after no_blanks still keeps whitespace' );
}

# Reverse order: keep_blanks first, then no_blanks, then no_blanks again

# TEST
{
    my $parser = XML::LibXML->new( keep_blanks => 1 );
    my $dom = $parser->load_xml( string => $xmlstring );
    is( $dom->serialize, $with_blanks, 'fourth parser: keep_blanks=1 baseline' );
}

# TEST
{
    my $parser = XML::LibXML->new( no_blanks => 1 );
    my $dom = $parser->load_xml( string => $xmlstring );
    is( $dom->serialize, $without_blanks, 'fifth parser: no_blanks=1 strips whitespace' );
}

# TEST
{
    my $parser = XML::LibXML->new( no_blanks => 1 );
    my $dom = $parser->load_xml( string => $xmlstring );
    is( $dom->serialize, $without_blanks, 'sixth parser: no_blanks=1 still strips whitespace' );
}
