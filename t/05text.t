# $Id$

##
# this test checks the DOM Characterdata interface of XML::LibXML

use strict;
use warnings;

use Test::More tests => 59;

use XML::LibXML;

my $doc = XML::LibXML::Document->new();

{
    # 1. creation
    my $foo = "foobar";
    my $textnode = $doc->createTextNode($foo);
    # TEST
    ok( $textnode, 'creation 1');
    # TEST
    is( $textnode->nodeName(), '#text',  'creation 2');
    # TEST
    is( $textnode->nodeValue(), $foo,  'creation 3',);

    {
        # Test for https://rt.cpan.org/Ticket/Display.html?id=112470
        my @attributes = $textnode->attributes();
        # TEST
        is_deeply(
            (\@attributes),
            [],
            '::Text->attributes() returns an empty list in list context (RT#112470)',
        );
    }

    # 2. substring
    my $tnstr = $textnode->substringData( 1,2 );
    # TEST
    is( $tnstr , "oo", 'substring 1');
    $tnstr = $textnode->substringData( 0,3 );
    # TEST
    is( $tnstr , "foo", 'substring 2');
    # TEST
    is( $textnode->nodeValue(), $foo,  'substring - text node unchanged' );

    # 3. Expansion
    $textnode->appendData( $foo );
    # TEST
    is( $textnode->nodeValue(), $foo . $foo, 'expansion 1');

    $textnode->insertData( 6, "FOO" );
    # TEST
    is( $textnode->nodeValue(), $foo."FOO".$foo, 'expansion 2' );

    $textnode->setData( $foo );
    $textnode->insertData( 6, "FOO" );
    # TEST
    is( $textnode->nodeValue(), $foo."FOO", 'expansion 3');
    $textnode->setData( $foo );
    $textnode->insertData( 3, "" );
    # TEST
    is( $textnode->nodeValue(), $foo, 'Empty insertion does not change value');

    # 4. Removal
    $textnode->deleteData( 1,2 );
    # TEST
    is( $textnode->nodeValue(), "fbar", 'Removal 1');
    $textnode->setData( $foo );
    $textnode->deleteData( 1,10 );
    # TEST
    is( $textnode->nodeValue(), "f", 'Removal 2');
    $textnode->setData( $foo );
    $textnode->deleteData( 10,1 );
    # TEST
    is( $textnode->nodeValue(), $foo, 'Removal 3');
    $textnode->deleteData( 1,0 );
    # TEST
    is( $textnode->nodeValue(), $foo, 'Removal 4');
    $textnode->deleteData( 0,0 );
    # TEST
    is( $textnode->nodeValue(), $foo, 'Removal 5');
    $textnode->deleteData( 0,2 );
    # TEST
    is( $textnode->nodeValue(), "obar", 'Removal 6');

    # 5. Replacement
    $textnode->setData( "test" );
    $textnode->replaceData( 1,2, "phish" );
    # TEST
    is( $textnode->nodeValue(), "tphisht", 'Replacement 1');
    $textnode->setData( "test" );
    $textnode->replaceData( 1,4, "phish" );
    # TEST
    is( $textnode->nodeValue(), "tphish",  'Replacement 2');
    $textnode->setData( "test" );
    $textnode->replaceData( 1,0, "phish" );
    # TEST
    is( $textnode->nodeValue(), "tphishest",  'Replacement 3');


    # 6. XML::LibXML features
    $textnode->setData( "test" );

    $textnode->replaceDataString( "es", "new" );
    # TEST
    is( $textnode->nodeValue(), "tnewt", 'replaceDataString() 1');

    $textnode->replaceDataRegEx( 'n(.)w', '$1s' );
    # TEST
    is( $textnode->nodeValue(), "test", 'replaceDataRegEx() 2');

    $textnode->setData( "blue phish, white phish, no phish" );
    $textnode->replaceDataRegEx( 'phish', 'test' );
    # TEST
    is( $textnode->nodeValue(), "blue test, white phish, no phish",
        'replaceDataRegEx 3',);

    # replace them all!
    $textnode->replaceDataRegEx( 'phish', 'test', 'g' );
    # TEST
    is( $textnode->nodeValue(), "blue test, white test, no test",
        'replaceDataRegEx g',);

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
    # UTF-8 tests

    my $test_str  = "te\xDFt";
    # Latin1 strings still fail.
    utf8::upgrade($test_str);

    # 1. creation
    my $textnode = $doc->createTextNode($test_str);
    # TEST
    ok( $textnode, 'UTF-8 creation 1');
    # TEST
    is( $textnode->nodeValue(), $test_str,  'UTF-8 creation 2',);
    my $foo_str = "\x{0444}oo\x{0431}ar";
    $textnode = $doc->createTextNode($foo_str);
    # TEST
    ok( $textnode, 'UTF-8 creation 3');
    # TEST
    is( $textnode->nodeValue(), $foo_str,  'UTF-8 creation 4',);

    # 2. substring
    my $tnstr = $textnode->substringData( 1,2 );
    # TEST
    is( $tnstr , "oo", 'UTF-8 substring 1');
    $tnstr = $textnode->substringData( 0,3 );
    # TEST
    is( $tnstr , "\x{0444}oo", 'UTF-8 substring 2');

    # 3. Expansion
    $textnode->appendData( $foo_str );
    # TEST
    is( $textnode->nodeValue(), $foo_str . $foo_str, 'UTF-8 expansion 1');

    my $ins_str = "\x{0424}OO";
    $textnode->insertData( 6, $ins_str );
    # TEST
    is( $textnode->nodeValue(), $foo_str.$ins_str.$foo_str,
        'UTF-8 expansion 2' );

    $textnode->setData( $foo_str );
    $textnode->insertData( 6, $ins_str );
    # TEST
    is( $textnode->nodeValue(), $foo_str.$ins_str, 'UTF-8 expansion 3');

    # 4. Removal
    $textnode->setData( $foo_str );
    $textnode->deleteData( 1,3 );
    # TEST
    is( $textnode->nodeValue(), "\x{0444}ar", 'UTF-8 Removal 1');
    $textnode->setData( $foo_str );
    $textnode->deleteData( 1,10 );
    # TEST
    is( $textnode->nodeValue(), "\x{0444}", 'UTF-8 Removal 2');
    $textnode->setData( $foo_str );
    $textnode->deleteData( 6,100 );
    # TEST
    is( $textnode->nodeValue(), $foo_str, 'UTF-8 Removal 3');

    # 5. Replacement
    my $phish_str = "ph\x{2160}sh";
    $textnode->setData( $test_str );
    $textnode->replaceData( 1,2, $phish_str );
    # TEST
    is( $textnode->nodeValue(), "t".$phish_str."t", 'UTF-8 Replacement 1');
    $textnode->setData( $test_str );
    $textnode->replaceData( 1,4, $phish_str );
    # TEST
    is( $textnode->nodeValue(), "t".$phish_str, 'UTF-8 Replacement 2');
    $textnode->setData( $test_str );
    $textnode->replaceData( 1,0, $phish_str );
    # TEST
    is( $textnode->nodeValue(), "t".$phish_str."e\xDFt",
        'UTF-8 Replacement 3');

    # 6. XML::LibXML features
    $textnode->setData( $test_str );

    my $new_str = "n\x{1D522}w";
    $textnode->replaceDataString( "e\xDF", $new_str );
    # TEST
    is( $textnode->nodeValue(), "t".$new_str."t",
        'UTF-8 replaceDataString() 1');

    $textnode->replaceDataRegEx( 'n(.)w', '$1s' );
    # TEST
    is( $textnode->nodeValue(), "t\x{1D522}st", 'UTF-8 replaceDataRegEx() 2');

    $textnode->setData( "blue $phish_str, white $phish_str, no $phish_str" );
    $textnode->replaceDataRegEx( $phish_str, $test_str );
    # TEST
    is( $textnode->nodeValue(),
        "blue $test_str, white $phish_str, no $phish_str",
        'UTF-8 replaceDataRegEx 3',);

    # replace them all!
    $textnode->replaceDataRegEx( $phish_str, $test_str, 'g' );
    # TEST
    is( $textnode->nodeValue(),
        "blue $test_str, white $test_str, no $test_str",
        'UTF-8 replaceDataRegEx g',);

    # check if deleteDataString works
    my $hit_str = "hi\x{1D54B}";
    my $pit_str = "\x{2119}it";
    $textnode->setData( "$hit_str$pit_str$hit_str" );
    $textnode->deleteDataString( $hit_str );
    # TEST
    is( $textnode->nodeValue(), "$pit_str$hit_str", 'UTF-8 deleteDataString 1' );

    # check if deleteDataString all works
    $textnode->setData( "$hit_str$pit_str$hit_str" );
    $textnode->deleteDataString( $hit_str, 1 );
    # TEST
    is( $textnode->nodeValue(), $pit_str, 'UTF-8 deleteDataString 2' );
}

{
    # standalone test
    my $node = XML::LibXML::Text->new("foo");
    # TEST
    ok($node, ' TODO : Add test name');
    # TEST
    is($node->nodeValue, "foo", ' TODO : Add test name' );
}

{
    # CDATA node name test

    my $node = XML::LibXML::CDATASection->new("test");

    # TEST
    is( $node->string_value(), "test", ' TODO : Add test name' );
    # TEST
    is( $node->nodeName(), "#cdata-section", ' TODO : Add test name' );
}

{
    # Comment node name test

    my $node = XML::LibXML::Comment->new("test");

    # TEST
    is( $node->string_value(), "test", ' TODO : Add test name' );
    # TEST
    is( $node->nodeName(), "#comment", ' TODO : Add test name' );
}

{
    # Document node name test

    my $node = XML::LibXML::Document->new();

    # TEST
    is( $node->nodeName(), "#document", ' TODO : Add test name' );
}
{
    # Document fragment node name test

    my $node = XML::LibXML::DocumentFragment->new();

    # TEST
    is( $node->nodeName(), "#document-fragment", ' TODO : Add test name' );
}
