# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

use Test;
BEGIN { plan tests=>15; }
END {ok(0) unless $loaded;}
use XML::LibXML;
$loaded = 1;
ok($loaded);

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

# this performs general dom tests

my $vers    = "1.0";
my $enc     = "iso-8859-1";
my $testtxt = "test";
my $file    = "example/dromeds.xml";

my $dom = XML::LibXML::Document->createDocument( $vers, $enc );
ok($dom);

# this feature is for dirty people ;)
my $dom2 = XML::LibXML::Document->createDocument( );
ok( $dom2 );

my $xs = "<?xml version=\"$vers\" encoding=\"$enc\"?>\n";
my $str = $dom->toString;
ok( $str eq $xs );

my $elem = $dom->createElement( "element" );
ok( defined $elem && $elem->getName() eq "element" );

$dom->setDocumentElement( $elem );
my $te = $dom->getDocumentElement();
ok( defined $te && $te->getName() eq $elem->getName() );

my $node;
{
    my $dom3 = XML::LibXML::Document->createDocument( $vers, $enc );
    $node   = $dom3->createElement( $testtxt );
    $dom3->setDocumentElement( $node );
}

# this ends scope and older versions should segfault here 
ok( defined $node && $node->getName() eq $testtxt );

{ 
    my $dom3 = $node->getOwnerDocument();
    ok( defined $dom3 && $dom3->isa( 'XML::LibXML::Document' ) ); 
}

# this ends scope and older versions should segfault here 
ok( defined $node && $node->getName() eq $testtxt );


$node = $dom2->createElement( $testtxt );
$dom2->setDocumentElement( $node );
my $node2 = $dom->importNode( $node );
{
    warn "node not defined " unless defined $node2;
    my $tdoc = $node2->getOwnerDocument();
    warn "doc not defined " unless defined $tdoc;
    warn "wrong doc" if $tdoc->isEqual( $dom2 );
    ok( defined $node2 && defined $tdoc && $tdoc->isEqual( $dom ) == 1 );
}

my $text = $dom->createTextNode( $testtxt );
ok( defined $text && $text->isa( "XML::LibXML::Text" ) );

$text = $dom->createComment( $testtxt );
ok( defined $text && $text->isa( "XML::LibXML::Comment" ) );

$text = $dom->createCDATASection( $testtxt );
ok( defined $text && $text->isa( "XML::LibXML::CDATASection" ) );

# parse tests

# init the file parser
my $parser = XML::LibXML->new();
$dom    = $parser->parse_file( $file );

ok( defined $dom );
if ( defined $dom ) {
  $elem   = $dom->getDocumentElement();
  ok( defined $elem && 
      $elem->getType() == XML_ELEMENT_NODE &&
      $elem->isa( "XML::LibXML::Element" ) );
}
