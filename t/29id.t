#!/usr/bin/perl

use Test;
use XML::LibXML;

BEGIN {
    if (XML::LibXML::LIBXML_VERSION() >= 20623) {
        plan tests => 21;
    }
    else {
        plan tests => 0;
        print "# Skipping ID tests on libxml2 <= 2.6.23\n";
	exit;
    }
}

my $parser = XML::LibXML->new;

my $xml1 = <<'EOF';
<!DOCTYPE root [
<!ELEMENT root (root?)>
<!ATTLIST root id ID #REQUIRED>
]>
<root id="foo"/>
EOF

my $xml2 = <<'EOF';
<root2 xml:id="foo"/>
EOF

sub _debug {
  my ($msg,$n)=@_;
  print "$msg\t$$n\n'",(ref $n ? $n->toString : "NULL"),"'\n";
}

for my $do_validate (0..1) {
  my ($n,$doc,$root);
  ok( $doc = $parser->parse_string($xml1) );
  $root = $doc->getDocumentElement;
  ($n) = $doc->getElementsById('foo');
  ok( $root->isSameNode( $n ) );
  # _debug("1: foo: ",$n);
  $doc->getDocumentElement->setAttribute('id','bar');
  ok( $doc->validate ) if $do_validate;
  ($n) = $doc->getElementsById('bar');
  ok( $root->isSameNode( $n ) );
  # _debug("1: bar: ",$n);
  ($n) = $doc->getElementsById('foo');
  ok( !defined($n) );
  # _debug("1: !foo: ",$n);

  my $test = $doc->createElement('root');
  $root->appendChild($test);
  $test->setAttribute('id','new');
  ok( $doc->validate ) if $do_validate;
  ($n) = $doc->getElementsById('new');
  ok( $test->isSameNode( $n ) );
  # _debug("1: new: ",$n);
}

{
  my ($n,$doc,$root);
  ok( $doc = $parser->parse_string($xml2) );
  $root = $doc->getDocumentElement;

  ($n) = $doc->getElementsById('foo');
  ok( $root->isSameNode( $n ) );
  # _debug("1: foo: ",$n);

  $doc->getDocumentElement->setAttribute('xml:id','bar');
  ($n) = $doc->getElementsById('foo');
  ok( !defined($n) );
  # _debug("1: !foo: ",$n);
  ($n) = $doc->getElementsById('bar');
  ok( $root->isSameNode( $n ) );
  # _debug("1: bar: ",$n);

  $doc->getDocumentElement->setAttributeNS('http://www.w3.org/XML/1998/namespace','id','baz');
  ($n) = $doc->getElementsById('bar');
  ok( !defined($n) );
  # _debug("1: !bar: ",$n);

  ($n) = $doc->getElementsById('baz');
  ok( $root->isSameNode( $n ) );
  # _debug("1: baz: ",$n);

  $doc->getDocumentElement->setAttributeNS('http://www.w3.org/XML/1998/namespace','xml:id','bag');
  ($n) = $doc->getElementsById('baz');
  ok( !defined($n) );
  # _debug("1: !baz: ",$n);

  ($n) = $doc->getElementsById('bag');
  ok( $root->isSameNode( $n ) );
  # _debug("1: bag: ",$n);
  ok( $root->toString eq '<root2 xml:id="bag"/>' );
}

1;
