use Test;
BEGIN { plan tests=>21; }
END {ok(0) unless $loaded;}
use XML::LibXML;
$loaded = 1;
ok($loaded);

my $xml = <<EOX;
<a xmlns:b="http://whatever"
><x b:href="out.xml"
/><b:c/></a>
EOX

my $doc = XML::LibXML->new()->parse_string($xml);
my $docElem = $doc->getDocumentElement();
  
my $child = ($docElem->getChildnodes())[0];
    ok($child->hasAttributeNS('http://whatever','href'));
    ok(not defined $child->getAttribute("abc"));
    ok(defined($child->getLocalName()));
    ok(!defined($child->getPrefix()));
    ok(!defined($child->getNamespaceURI()));

    my $val = $child->getAttributeNS('http://whatever','href');
    ok($val,'out.xml');

$child = ($docElem->getChildnodes())[1];
    ok($child->getLocalName() eq 'c');
    ok($child->getPrefix() eq 'b');
    ok($child->getNamespaceURI() eq 'http://whatever');
    

    $child->removeAttributeNS('http://whatever','href');
    ok(!$child->hasAttributeNS('http://whatever','href'));

    my $added_attr = 'added.xml';
    $child->setAttributeNS('http://whatever', 'b2:href', $added_attr);

    ok($child->hasAttributeNS('http://whatever','href')
        && $child->getAttributeNS('http://whatever','href') eq $added_attr);
 
my @bytag = $docElem->getChildrenByTagName('x');
ok(scalar(@bytag) == 1);

@bytag = $docElem->getChildrenByTagNameNS('http://whatever','c');
ok(scalar(@bytag) == 1);

my $tag = pop @bytag;
ok($tag->getLocalName() eq 'c');
ok($tag->getPrefix() eq 'b');
ok($tag->getNamespaceURI() eq 'http://whatever');

my $newElem = $doc->createElementNS('http://whatever','d:newElem');
ok(defined($newElem));
ok($newElem->getLocalName, 'newElem');
ok($newElem->getPrefix, 'd');
ok($newElem->getNamespaceURI, 'http://whatever');
