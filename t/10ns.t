use Test;
BEGIN { plan tests=>16; }
use XML::LibXML;

my $parser = XML::LibXML->new();

my $xml1 = <<EOX;
<a xmlns:b="http://whatever"
><x b:href="out.xml"
/><b:c/></a>
EOX

my $xml2 = <<EOX;
<a xmlns:b="http://whatever" xmlns:c="http://kungfoo"
><x b:href="out.xml"
/><b:c/><c:b/></a>
EOX

my $xml3 = <<EOX;
<a xmlns:b="http://whatever">
    <x b:href="out.xml"/>
    <x>
    <c:b xmlns:c="http://kungfoo">
        <c:d/>
    </c:b>
    </x>
    <x>
    <c:b xmlns:c="http://foobar">
        <c:d/>
    </c:b>
    </x>
</a>
EOX

print "# 1.   single namespace \n";

{
    my $doc1 = $parser->parse_string( $xml1 );
    my $elem = $doc1->documentElement;
    ok($elem->lookupNamespaceURI( "b" ), "http://whatever" );
    my @cn = $elem->childNodes;
    ok($cn[0]->lookupNamespaceURI( "b" ), "http://whatever" );
    ok($cn[1]->namespaceURI, "http://whatever" );
}

print "# 2.    multiple namespaces \n";

{
    my $doc2 = $parser->parse_string( $xml2 );

    my $elem = $doc2->documentElement;
    ok($elem->lookupNamespaceURI( "b" ), "http://whatever");
    ok($elem->lookupNamespaceURI( "c" ), "http://kungfoo");
    my @cn = $elem->childNodes;

    ok($cn[0]->lookupNamespaceURI( "b" ), "http://whatever" );
    ok($cn[0]->lookupNamespaceURI( "c" ), "http://kungfoo");

    ok($cn[1]->namespaceURI, "http://whatever" );
    ok($cn[2]->namespaceURI, "http://kungfoo" );
}

print "# 3.   nested names \n";

{
    my $doc3 = $parser->parse_string( $xml3 );    
    my $elem = $doc3->documentElement;
    my @cn = $elem->childNodes;
    my @xs = grep { $_->nodeType == XML_ELEMENT_NODE } @cn;

    my @x1 = $xs[1]->childNodes; my @x2 = $xs[2]->childNodes;

    ok( $x1[1]->namespaceURI , "http://kungfoo" );    
    ok( $x2[1]->namespaceURI , "http://foobar" );    

    # namespace scopeing
    ok( not defined $elem->lookupNamespacePrefix( "http://kungfoo" ) );
    ok( not defined $elem->lookupNamespacePrefix( "http://foobar" ) );
}

print "# 4. post creation namespace setting\n";
{
    my $e1 = XML::LibXML::Element->new("foo");
    my $e2 = XML::LibXML::Element->new("bar:foo");
    my $e3 = XML::LibXML::Element->new("foo");
    $e3->setAttribute( "kung", "foo" );
    my $a = $e3->getAttributeNode("kung");

    $e1->appendChild($e2);
    $e2->appendChild($e3);
    ok( $e2->setNamespace("http://kungfoo", "bar") );
    ok( $a->setNamespace("http://kungfoo", "bar") );
    ok( $a->nodeName, "bar:kung" );
}