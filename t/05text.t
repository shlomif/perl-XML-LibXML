# $Id$

##
# this test checks the DOM Characterdata interface of XML::LibXML

use strict;
use warnings;

use Test::More tests => 36;

use XML::LibXML;

my $doc = XML::LibXML::Document->new();

{
    print "# 1. creation\n";
    my $foo = "foobar";
    my $textnode = $doc->createTextNode($foo);
    # TEST
    ok( $textnode, ' TODO : Add test name' );
    # TEST
    is( $textnode->nodeName(), '#text', ' TODO : Add test name' );
    # TEST
    is( $textnode->nodeValue(), $foo, ' TODO : Add test name' );

    print "# 2. substring\n";
    my $tnstr = $textnode->substringData( 1,2 );
    # TEST
    is( $tnstr , "oo", ' TODO : Add test name' );
    # TEST
    is( $textnode->nodeValue(), $foo, ' TODO : Add test name' );

    print "# 3. Expansion\n";
    $textnode->appendData( $foo );
    # TEST
    is( $textnode->nodeValue(), $foo . $foo, ' TODO : Add test name' );

    $textnode->insertData( 6, "FOO" );
    # TEST
    is( $textnode->nodeValue(), $foo."FOO".$foo, ' TODO : Add test name' );

    $textnode->setData( $foo );
    $textnode->insertData( 6, "FOO" );
    # TEST
    is( $textnode->nodeValue(), $foo."FOO", ' TODO : Add test name' );
    $textnode->setData( $foo );
    $textnode->insertData( 3, "" );
    # TEST
    is( $textnode->nodeValue(), $foo, ' TODO : Add test name' );

    print "# 4. Removement\n";
    $textnode->deleteData( 1,2 );
    # TEST
    is( $textnode->nodeValue(), "fbar", ' TODO : Add test name' );
    $textnode->setData( $foo );
    $textnode->deleteData( 1,10 );
    # TEST
    is( $textnode->nodeValue(), "f", ' TODO : Add test name' );
    $textnode->setData( $foo );
    $textnode->deleteData( 10,1 );
    # TEST
    is( $textnode->nodeValue(), $foo, ' TODO : Add test name' );
    $textnode->deleteData( 1,0 );
    # TEST
    is( $textnode->nodeValue(), $foo, ' TODO : Add test name' );
    $textnode->deleteData( 0,0 );
    # TEST
    is( $textnode->nodeValue(), $foo, ' TODO : Add test name' );
    $textnode->deleteData( 0,2 );
    # TEST
    is( $textnode->nodeValue(), "obar", ' TODO : Add test name' );

    print "# 5. Replacement\n";
    $textnode->setData( "test" );
    $textnode->replaceData( 1,2, "phish" );
    # TEST
    is( $textnode->nodeValue(), "tphisht", ' TODO : Add test name' );
    $textnode->setData( "test" );
    $textnode->replaceData( 1,4, "phish" );
    # TEST
    is( $textnode->nodeValue(), "tphish", ' TODO : Add test name' );
    $textnode->setData( "test" );
    $textnode->replaceData( 1,0, "phish" );
    # TEST
    is( $textnode->nodeValue(), "tphishest", ' TODO : Add test name' );


    print "# 6. XML::LibXML features\n";
    $textnode->setData( "test" );

    $textnode->replaceDataString( "es", "new" );   
    # TEST
    is( $textnode->nodeValue(), "tnewt", ' TODO : Add test name' );

    $textnode->replaceDataRegEx( 'n(.)w', '$1s' );
    # TEST
    is( $textnode->nodeValue(), "test", ' TODO : Add test name' );

    $textnode->setData( "blue phish, white phish, no phish" );
    $textnode->replaceDataRegEx( 'phish', 'test' );
    # TEST
    is( $textnode->nodeValue(), "blue test, white phish, no phish", ' TODO : Add test name' );

    # replace them all!
    $textnode->replaceDataRegEx( 'phish', 'test', 'g' );
    # TEST
    is( $textnode->nodeValue(), "blue test, white test, no test", ' TODO : Add test name' );

    # check if special chars are encoded properly 
    $textnode->setData( "te?st" );
    $textnode->replaceDataString( "e?s", 'ne\w' );   
    # TEST
    is( $textnode->nodeValue(), 'tne\wt', ' TODO : Add test name' );

    # check if "." is encoded properly 
    $textnode->setData( "h.thrt");
    $textnode->replaceDataString( "h.t", 'new', 1 );   
    # TEST
    is( $textnode->nodeValue(), 'newhrt', ' TODO : Add test name' );

    # check if deleteDataString does not delete dots.
    $textnode->setData( 'hitpit' );
    $textnode->deleteDataString( 'h.t' );   
    # TEST
    is( $textnode->nodeValue(), 'hitpit', ' TODO : Add test name' );

    # check if deleteDataString works
    $textnode->setData( 'hitpithit' );
    $textnode->deleteDataString( 'hit' );   
    # TEST
    is( $textnode->nodeValue(), 'pithit', ' TODO : Add test name' );

    # check if deleteDataString all works
    $textnode->setData( 'hitpithit' );
    $textnode->deleteDataString( 'hit', 1 );   
    # TEST
    is( $textnode->nodeValue(), 'pit', ' TODO : Add test name' );

    # check if entities don't get translated
    $textnode->setData(q(foo&amp;bar));
    # TEST
    is ( $textnode->getData(), q(foo&amp;bar), ' TODO : Add test name' );
}

{
    print "# standalone test\n";
    my $node = XML::LibXML::Text->new("foo");
    # TEST
    ok($node, ' TODO : Add test name');
    # TEST
    is($node->nodeValue, "foo", ' TODO : Add test name' );
}

{
    print "# CDATA node name test\n";

    my $node = XML::LibXML::CDATASection->new("test");

    # TEST

    is( $node->string_value(), "test", ' TODO : Add test name' );
    # TEST
    is( $node->nodeName(), "#cdata-section", ' TODO : Add test name' );
}

{
    print "# Comment node name test\n";

    my $node = XML::LibXML::Comment->new("test");

    # TEST

    is( $node->string_value(), "test", ' TODO : Add test name' );
    # TEST
    is( $node->nodeName(), "#comment", ' TODO : Add test name' );
}

{
    print "# Document node name test\n";

    my $node = XML::LibXML::Document->new();

    # TEST

    is( $node->nodeName(), "#document", ' TODO : Add test name' );
}
{
    print "# Document fragment node name test\n";

    my $node = XML::LibXML::DocumentFragment->new();

    # TEST

    is( $node->nodeName(), "#document-fragment", ' TODO : Add test name' );
}
