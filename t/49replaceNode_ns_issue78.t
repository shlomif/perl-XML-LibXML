use Test::More;
use strict;
use warnings;

use XML::LibXML;
use XML::LibXML::XPathContext;

# Regression test for https://github.com/shlomif/perl-XML-LibXML/issues/78
# Namespace declaration gets removed when using replaceNode

my $xmlstring
    = q{<saml:foo xmlns:saml="foobar">bar<foobar/><saml:bar><saml:baz>foo</saml:baz></saml:bar></saml:foo>};

my $parser = XML::LibXML->new(clean_namespaces => 0);
my $doc    = $parser->parse_string($xmlstring);

my $replace = q{<saml:Assertion xmlns="foobar" xmlns:saml="foobar" ID="ID_af2d76cb-6e6b-4ad0-a1a0-ea85ee839dbc" IssueInstant="2022-03-27T12:06:56.740Z" Version="2.0">Some assertion data</saml:Assertion>};

my $rnode = $parser->parse_string($replace)->findnodes('//*')->[0];

# TEST
like($rnode->toString, qr/xmlns:saml="foobar"/, "Node has saml namespace declaration");
# TEST
like($rnode->toString, qr/xmlns="foobar"/, "Node has default namespace declaration");

my $xpc = XML::LibXML::XPathContext->new($doc);
$xpc->registerNs('saml', 'foobar');

my $bar = $xpc->findnodes('//saml:baz');
my $tbr = $bar->get_node(1);
$tbr->replaceNode($rnode);

my $assertion = $xpc->findnodes('//saml:Assertion')->[0];
# TEST - namespace declarations must survive replaceNode (issue #78)
like($assertion->toString, qr/xmlns:saml="foobar"/, "saml namespace declaration preserved after replaceNode");
# TEST
like($assertion->toString, qr/xmlns="foobar"/, "default namespace declaration preserved after replaceNode");

# Test appendChild also preserves namespace declarations
{
    my $parent_xml = q{<root xmlns:ns="urn:test"><child/></root>};
    my $child_xml  = q{<ns:item xmlns:ns="urn:test">content</ns:item>};

    my $pdoc = $parser->parse_string($parent_xml);
    my $cnode = $parser->parse_string($child_xml)->documentElement;

    $pdoc->documentElement->appendChild($cnode);

    my @items = $pdoc->documentElement->getElementsByTagName('ns:item');
    # TEST - appendChild should preserve ns declaration
    like($items[0]->toString, qr/xmlns:ns="urn:test"/, "appendChild preserves namespace declaration");
}

# Test insertBefore also preserves namespace declarations
{
    my $parent_xml = q{<root xmlns:x="urn:x"><first/></root>};
    my $new_xml    = q{<x:new xmlns:x="urn:x">data</x:new>};

    my $pdoc = $parser->parse_string($parent_xml);
    my $nnode = $parser->parse_string($new_xml)->documentElement;
    my $first = ($pdoc->documentElement->childNodes)[0];

    $pdoc->documentElement->insertBefore($nnode, $first);

    my @news = $pdoc->documentElement->getElementsByTagName('x:new');
    # TEST - insertBefore should preserve ns declaration
    like($news[0]->toString, qr/xmlns:x="urn:x"/, "insertBefore preserves namespace declaration");
}

done_testing;
