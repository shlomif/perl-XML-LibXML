# $Id$

##
# this test checks the DOM element and attribute interface of XML::LibXML

use Test;
use Devel::Peek;

use strict;
use warnings;

BEGIN { plan tests => 41 };
use XML::LibXML;

my $foo       = "foo";
my $bar       = "bar";
my $nsURI     = "http://foo";
my $prefix    = "x";
my $attname1  = "A";
my $attvalue1 = "a";
my $attname2  = "B";
my $attvalue2 = "b";

print "# 1. bound node\n";
{
    my $doc = XML::LibXML::Document->new();
    my $elem = $doc->createElement( $foo );
    ok($elem);
    ok($elem->tagName, $foo);
    
    $elem->setAttribute( $attname1, $attvalue1 );
    ok( $elem->hasAttribute($attname1) );
    ok( $elem->getAttribute($attname1), $attvalue1);

    my $attr = $elem->getAttributeNode($attname1);
    ok($attr);
    ok($attr->name, $attname1);
    ok($attr->value, $attvalue1);

    $elem->setAttribute( $attname1, $attvalue2 );
    ok($elem->getAttribute($attname1), $attvalue2);
    ok($attr->value, $attvalue2);

    my $attr2 = $doc->createAttribute($attname2, $attvalue1);
    ok($attr2);

    $elem->setAttributeNode($attr2);
    ok($elem->hasAttribute($attname2) );
    ok($elem->getAttribute($attname2),$attvalue1);

    my $tattr = $elem->getAttributeNode($attname2);
    ok($tattr->isSameNode($attr2));

    print "# 1.1 Namespaced Attributes\n";

    $elem->setAttributeNS( $nsURI, $prefix . ":". $foo, $attvalue2 );
    ok( $elem->hasAttributeNS( $nsURI, $foo ) );
    # warn $elem->toString() , "\n";
    $tattr = $elem->getAttributeNodeNS( $nsURI, $foo );
    ok($tattr);
    ok($tattr->name, $foo);
    ok($tattr->nodeName, $prefix .":".$foo);
    ok($tattr->value, $attvalue2 );

    $elem->removeAttributeNode( $tattr );
    ok( !$elem->hasAttributeNS($nsURI, $foo) );

    # node based functions
    my $e2 = $doc->createElement($foo);
    $doc->setDocumentElement($e2);
    my $nsAttr = $doc->createAttributeNS( $nsURI.".x", $prefix . ":". $foo, $bar);
    ok( $nsAttr );
    $elem->setAttributeNodeNS($nsAttr);
    ok( $elem->hasAttributeNS($nsURI.".x", $foo) );    
    $elem->removeAttributeNS( $nsURI.".x", $foo);
    ok( !$elem->hasAttributeNS($nsURI.".x", $foo) );

    $elem->setAttributeNS( $nsURI, $prefix . ":". $attname1, $attvalue2 );

    $elem->removeAttributeNS("",$attname1);
    ok( $elem->hasAttribute($attname1) );
    ok( $elem->hasAttributeNS($nsURI,$attname1) );
} 

print "# 2. unbound node\n";
{
    my $elem = XML::LibXML::Element->new($foo);
    ok($elem);
    ok($elem->tagName, $foo);

    $elem->setAttribute( $attname1, $attvalue1 );
    ok( $elem->hasAttribute($attname1) );
    ok( $elem->getAttribute($attname1), $attvalue1);

    my $attr = $elem->getAttributeNode($attname1);
    ok($attr);
    ok($attr->name, $attname1);
    ok($attr->value, $attvalue1);

    $elem->setAttributeNS( $nsURI, $prefix . ":". $foo, $attvalue2 );
    ok( $elem->hasAttributeNS( $nsURI, $foo ) );
    # warn $elem->toString() , "\n";
    my $tattr = $elem->getAttributeNodeNS( $nsURI, $foo );
    ok($tattr);
    ok($tattr->name, $foo);
    ok($tattr->nodeName, $prefix .":".$foo);
    ok($tattr->value, $attvalue2 );

    $elem->removeAttributeNode( $tattr );
    ok( !$elem->hasAttributeNS($nsURI, $foo) );
    # warn $elem->toString() , "\n";
}

print "# 3. Namespace switching\n";
{
    my $elem = XML::LibXML::Element->new($foo);
    ok($elem);

    my $doc = XML::LibXML::Document->new();
    my $e2 = $doc->createElement($foo);
    $doc->setDocumentElement($e2);
    my $nsAttr = $doc->createAttributeNS( $nsURI, $prefix . ":". $foo, $bar);
    ok( $nsAttr );

    $elem->setAttributeNodeNS($nsAttr);
    ok( $elem->hasAttributeNS($nsURI, $foo) );    

    ok( $nsAttr->ownerDocument, undef);
    # warn $elem->toString() , "\n";
} 
