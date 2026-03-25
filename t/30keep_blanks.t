#!/usr/bin/perl

# This is a regression test for this bug:
#
# https://rt.cpan.org/Ticket/Display.html?id=76696
#
# <<<
# Specifying ->keep_blanks(0) has no effect on parse_balanced_chunk anymore.
# The script below used to pass with XML::LibXML 1.69, but is broken since
# 1.70 and also with the newest 1.96.
# >>>
#
# Thanks to SREZIC for the report, the test and a patch.

use strict;
use warnings;

use Test::More tests => 7;

use XML::LibXML;

my $xml = <<'EOF';
<bla> <foo/> </bla>
EOF

my $p = XML::LibXML->new;
$p->keep_blanks(0);

# TEST
is (
    scalar( $p->parse_balanced_chunk($xml)->serialize() ),
    "<bla><foo/></bla>\n",
    'keep_blanks(0) removes the blanks after a roundtrip.',
);

# Regression test for https://github.com/shlomif/perl-XML-LibXML/issues/88
# no_blanks global state leak: creating a parser with no_blanks should not
# affect subsequent parser instances that use keep_blanks.
{
    my $xmlstring = <<'EOM';
<?xml version="1.0"?>
<hello><bold>Line1</bold>
<bold>Line2</bold></hello>
EOM

    my $expected_with_blanks = <<'EOM';
<?xml version="1.0"?>
<hello><bold>Line1</bold>
<bold>Line2</bold></hello>
EOM

    my $expected_no_blanks = <<'EOM';
<?xml version="1.0"?>
<hello><bold>Line1</bold><bold>Line2</bold></hello>
EOM

    # TEST
    my $parser1 = XML::LibXML->new( keep_blanks => 1 );
    my $dom1 = $parser1->load_xml( string => $xmlstring );
    is( $dom1->serialize, $expected_with_blanks,
        'first parser with keep_blanks preserves whitespace' );

    # TEST
    my $parser2 = XML::LibXML->new( no_blanks => 1 );
    my $dom2 = $parser2->load_xml( string => $xmlstring );
    is( $dom2->serialize, $expected_no_blanks,
        'second parser with no_blanks strips whitespace' );

    # TEST - this is the actual bug from issue #88
    my $parser3 = XML::LibXML->new( keep_blanks => 1 );
    my $dom3 = $parser3->load_xml( string => $xmlstring );
    is( $dom3->serialize, $expected_with_blanks,
        'third parser with keep_blanks preserves whitespace (no global state leak)' );

    # TEST - verify it works the other direction too
    my $parser4 = XML::LibXML->new( no_blanks => 1 );
    my $dom4 = $parser4->load_xml( string => $xmlstring );
    is( $dom4->serialize, $expected_no_blanks,
        'fourth parser with no_blanks still strips whitespace' );

    # TEST - and one more keep_blanks to be sure
    my $parser5 = XML::LibXML->new( keep_blanks => 1 );
    my $dom5 = $parser5->load_xml( string => $xmlstring );
    is( $dom5->serialize, $expected_with_blanks,
        'fifth parser with keep_blanks preserves whitespace (stable)' );

    # TEST - default parser (keep_blanks) after no_blanks
    my $parser6 = XML::LibXML->new( no_blanks => 1 );
    $parser6->load_xml( string => $xmlstring );
    my $parser7 = XML::LibXML->new();
    my $dom7 = $parser7->load_xml( string => $xmlstring );
    is( $dom7->serialize, $expected_with_blanks,
        'default parser after no_blanks preserves whitespace' );
}
