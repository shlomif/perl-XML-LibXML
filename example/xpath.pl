#!/usr/bin/perl

# $Id$

use XML::LibXML;

use strict;
use warnings;

my $parser = XML::LibXML->new();
my $xpath = shift @ARGV;

if ( scalar @ARGV ) {
    foreach ( @ARGV ) {
        my $doc = $parser->parse_file( $_ );
        my $result = $doc->find( $xpath );
        handle_result( $result );
        undef $doc;
    }
}
else {
    # read from std in
    my @doc = <STDIN>;
    my $string = join "", @doc;
    my $doc = $parser->parse_string( $string );
    my $result = $doc->find( $xpath );
    exit handle_result( $result );
}

sub handle_result {
    my $result = shift;

    return 1 unless defined $result;

    if ( $result->isa( 'XML::LibXML::NodeList' ) ) {
        foreach ( @$result ) {
            print $_->toString(1) , "\n";
        }
        return 0;
    }

    if ( $result->isa( 'XML::LibXML::Literal' ) ) {
        print $result->value , "\n";
        return 0;
    }

    if ( $result->isa( 'XML::LibXML::Boolean' ) ){
        print $result->to_literal , "\n";
        return 0;
    }

    return 1;
}
