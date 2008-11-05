use Test;
BEGIN { plan tests => 79 };

use XML::LibXML;
use XML::LibXML::XPathContext;

my $doc = XML::LibXML->new->parse_string(<<'XML');
<foo><bar a="b"></bar></foo>
XML

# test findnodes() in list context
my $xpath = '/*';
for my $exp ($xpath, XML::LibXML::XPathExpression->new($xpath)) {
  my @nodes = XML::LibXML::XPathContext->new($doc)->findnodes($exp);
  ok(@nodes == 1);
  ok($nodes[0]->nodeName eq 'foo');
  ok((XML::LibXML::XPathContext->new($nodes[0])->findnodes('bar'))[0]->nodeName
       eq 'bar');
}


# test findnodes() in scalar context
for my $exp ($xpath, XML::LibXML::XPathExpression->new($xpath)) {
  my $nl = XML::LibXML::XPathContext->new($doc)->findnodes($exp);
  ok($nl->pop->nodeName eq 'foo');
  ok(!defined($nl->pop));
}

# test findvalue()
ok(XML::LibXML::XPathContext->new($doc)->findvalue('1+1') == 2);
ok(XML::LibXML::XPathContext->new($doc)->findvalue(XML::LibXML::XPathExpression->new('1+1')) == 2);
ok(XML::LibXML::XPathContext->new($doc)->findvalue('1=2') eq 'false');
ok(XML::LibXML::XPathContext->new($doc)->findvalue(XML::LibXML::XPathExpression->new('1=2')) eq 'false');

# test find()
ok(XML::LibXML::XPathContext->new($doc)->find('/foo/bar')->pop->nodeName eq 'bar');
ok(XML::LibXML::XPathContext->new($doc)->find(XML::LibXML::XPathExpression->new('/foo/bar'))->pop->nodeName eq 'bar');

ok(XML::LibXML::XPathContext->new($doc)->find('1*3')->value == '3');
ok(XML::LibXML::XPathContext->new($doc)->find('1=1')->to_literal eq 'true');

my $doc1 = XML::LibXML->new->parse_string(<<'XML');
<foo xmlns="http://example.com/foobar"><bar a="b"></bar></foo>
XML

# test registerNs()
my $compiled = XML::LibXML::XPathExpression->new('/xxx:foo');
my $xc = XML::LibXML::XPathContext->new($doc1);
$xc->registerNs('xxx', 'http://example.com/foobar');
ok($xc->findnodes('/xxx:foo')->pop->nodeName eq 'foo');
ok($xc->findnodes($compiled)->pop->nodeName eq 'foo');
ok($xc->lookupNs('xxx') eq 'http://example.com/foobar');

# test unregisterNs()
$xc->unregisterNs('xxx');
eval { $xc->findnodes('/xxx:foo') };
ok($@);
ok(!defined($xc->lookupNs('xxx')));

eval { $xc->findnodes($compiled) };
ok($@);
ok(!defined($xc->lookupNs('xxx')));

# test getContextNode and setContextNode
ok($xc->getContextNode->isSameNode($doc1));
$xc->setContextNode($doc1->getDocumentElement);
ok($xc->getContextNode->isSameNode($doc1->getDocumentElement));
ok($xc->findnodes('.')->pop->isSameNode($doc1->getDocumentElement));

# test xpath context preserves the document
my $xc2 = XML::LibXML::XPathContext->new(
	  XML::LibXML->new->parse_string(<<'XML'));
<foo/>
XML
ok($xc2->findnodes('*')->pop->nodeName eq 'foo');

# test xpath context preserves context node
my $doc2 = XML::LibXML->new->parse_string(<<'XML');
<foo><bar/></foo>
XML
my $xc3 = XML::LibXML::XPathContext->new($doc2->getDocumentElement);
$xc3->find('/');
ok($xc3->getContextNode->toString() eq '<foo><bar/></foo>');

# check starting with empty context
my $xc4 = XML::LibXML::XPathContext->new();
ok(!defined($xc4->getContextNode));
eval { $xc4->find('/') };
ok($@);
my $cn=$doc2->getDocumentElement;
$xc4->setContextNode($cn);
ok($xc4->find('/'));
ok($xc4->getContextNode->isSameNode($doc2->getDocumentElement));
$cn=undef;
ok($xc4->getContextNode);
ok($xc4->getContextNode->isSameNode($doc2->getDocumentElement));

# check temporarily changed context node
my ($bar)=$xc4->findnodes('foo/bar',$doc2);
ok($bar->nodeName eq 'bar');
ok($xc4->getContextNode->isSameNode($doc2->getDocumentElement));

ok($xc4->findnodes('parent::*',$bar)->pop->nodeName eq 'foo');
ok($xc4->getContextNode->isSameNode($doc2->getDocumentElement));

# testcase for segfault found by Steve Hay
my $xc5 = XML::LibXML::XPathContext->new();
$xc5->registerNs('pfx', 'http://www.foo.com');
$doc = XML::LibXML->new->parse_string('<foo xmlns="http://www.foo.com" />');
$xc5->setContextNode($doc);
$xc5->findnodes('/');
$xc5->setContextNode(undef);
$xc5->getContextNode();
$xc5->setContextNode($doc);
$xc5->findnodes('/');
ok(1);

# check setting context position and size
ok($xc4->getContextPosition() == -1);
ok($xc4->getContextSize() == -1);
eval { $xc4->setContextPosition(4); };
ok($@);
eval { $xc4->setContextPosition(-4); };
ok($@);
eval { $xc4->setContextSize(-4); };
ok($@);
eval { $xc4->findvalue('position()') };
ok($@);
eval { $xc4->findvalue('last()') };
ok($@);

$xc4->setContextSize(0);
ok($xc4->getContextSize() == 0);
ok($xc4->getContextPosition() == 0);
ok($xc4->findvalue('position()')==0);
ok($xc4->findvalue('last()')==0);

$xc4->setContextSize(4);
ok($xc4->getContextSize() == 4);
ok($xc4->getContextPosition() == 1);
ok($xc4->findvalue('last()')==4);
ok($xc4->findvalue('position()')==1);
eval { $xc4->setContextPosition(5); };
ok($@);
ok($xc4->findvalue('position()')==1);
ok($xc4->getContextSize() == 4);
$xc4->setContextPosition(4);
ok($xc4->findvalue('position()')==4);
ok($xc4->findvalue('position()=last()'));

$xc4->setContextSize(-1);
ok($xc4->getContextPosition() == -1);
ok($xc4->getContextSize() == -1);
eval { $xc4->findvalue('position()') };
ok($@);
eval { $xc4->findvalue('last()') };
ok($@);

{
 my $d = XML::LibXML->new()->parse_string(q~<x:a xmlns:x="http://x.com" xmlns:y="http://x1.com"><x1:a xmlns:x1="http://x1.com"/></x:a>~);
 {
   my $x = XML::LibXML::XPathContext->new;

   # use the document's declaration
   ok( $x->findvalue('count(/x:a/y:a)',$d->documentElement)==1 );

   $x->registerNs('x', 'http://x1.com');
   # x now maps to http://x1.com, so it won't match the top-level element
   ok( $x->findvalue('count(/x:a)',$d->documentElement)==0 );

   $x->registerNs('x1', 'http://x.com');
   # x1 now maps to http://x.com
   # x1:a will match the first element
   ok( $x->findvalue('count(/x1:a)',$d->documentElement)==1 );
   # but not the second 
   ok( $x->findvalue('count(/x1:a/x1:a)',$d->documentElement)==0 );
   # this will work, though
   ok( $x->findvalue('count(/x1:a/x:a)',$d->documentElement)==1 );
   # the same using y for http://x1.com
   ok( $x->findvalue('count(/x1:a/y:a)',$d->documentElement)==1 );
   $x->registerNs('y', 'http://x.com');
   # y prefix remapped
   ok( $x->findvalue('count(/x1:a/y:a)',$d->documentElement)==0 );
   ok( $x->findvalue('count(/y:a/x:a)',$d->documentElement)==1 );
   $x->registerNs('y', 'http://x1.com');
   # y prefix remapped back
   ok( $x->findvalue('count(/x1:a/y:a)',$d->documentElement)==1 );
   $x->unregisterNs('x');
   ok( $x->findvalue('count(/x:a)',$d->documentElement)==1 );
   $x->unregisterNs('y');
   ok( $x->findvalue('count(/x:a/y:a)',$d->documentElement)==1 );
 }
}

if (XML::LibXML::LIBXML_VERSION >= 20617) {
  # 37332

  my $frag = XML::LibXML::DocumentFragment->new;
  my $foo = XML::LibXML::Element->new('foo');
  my $xpc = XML::LibXML::XPathContext->new;
  $frag->appendChild($foo);
  $foo->appendTextChild('bar', 'quux');
  {
    my @n = $xpc->findnodes('./foo', $frag);
    ok ( @n == 1 );
  }
  {
    my @n = $xpc->findnodes('./foo/bar', $frag);
    ok ( @n == 1 );
  }
  {
    my @n = $xpc->findnodes('./bar', $foo);
    ok ( @n == 1 );
  }
} else {
  skip('xpath does not work on nodes without a document in libxml2 < 2.6.17') for 1..3;
}
