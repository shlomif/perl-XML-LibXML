# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

use Test;
BEGIN { plan tests=>23 }
END {ok(0) unless $loaded;}
use XML::LibXML;
$loaded = 1;
ok($loaded);

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

# this performs general dom tests

my $version = "1.0";
my $enc     = "iso-8859-1";
my $testtxt = "test";
my $file    = "example/dromeds.xml";

my $dom = XML::LibXML::Document->createDocument( $version, $enc );
ok($dom);

# this feature is for quick and dirty people ;)
my $dom2 = XML::LibXML::Document->createDocument( );
ok( $dom2
    && $dom2->getEncoding() eq 'UTF-8' 
    && $dom2->getVersion() eq $version );

my $xs = "<?xml version=\"$version\" encoding=\"$enc\"?>\n";
my $str = $dom->toString;
ok( $str eq $xs );

my $elem = $dom->createElement( "element" );
ok( defined $elem && $elem->getName() eq "element" );

$dom->setDocumentElement( $elem );
ok( $elem->isEqual( $dom->getDocumentElement() ) );

# lets test if we can overwrite the document element with an 
# invalid element type
my $attr = $dom->createAttribute( "test", "test" );
ok( defined $attr && $attr->getValue() eq "test" );

$dom->setDocumentElement( $attr );
ok( $elem->isEqual( $dom->getDocumentElement() ) );

my $node;
{
    my $dom3 = XML::LibXML::Document->createDocument( $version, $enc );
    $node   = $dom3->createElement( $testtxt );
    $dom3->setDocumentElement( $node );
}

# this ends scope and older versions should segfault here 
ok( defined $node && $node->getName() eq $testtxt );

{ 
    use Devel::Peek;
    my $dom3 = $node->getOwnerDocument();
    ok( defined $dom3 && $dom3->isa( 'XML::LibXML::Document' ) ); 
}

# this ends scope and older versions should segfault here 
ok( defined $node && $node->getName() eq $testtxt );

$node = $dom2->createElement( $testtxt );
$dom2->setDocumentElement( $node );
my $node2 = $dom->importNode( $node );
if ( defined $node2 ){
    warn " # node not defined " unless defined $node2;
    my $tdoc = $node2->getOwnerDocument();
    warn "# doc not defined " unless defined $tdoc;
    warn "# wrong doc" if $tdoc->isEqual( $dom2 );
    ok( defined $node2 && defined $tdoc && $tdoc->isEqual( $dom ) == 1 );
}
else {
    ok(0);
}

my $text = $dom->createTextNode( $testtxt );
ok( defined $text && $text->isa( "XML::LibXML::Text" ) );

$text = $dom->createComment( $testtxt );
ok( defined $text && $text->isa( "XML::LibXML::Comment" ) );

$text = $dom->createCDATASection( $testtxt );
ok( defined $text && $text->isa( "XML::LibXML::CDATASection" ) );

# PI tests
my $pi = $dom->createPI( "test", "test" );
ok( $pi );


$dom->appendChild( $pi );
my @clds = $dom->childNodes();
my $cnt_dn = scalar( @clds );
ok( $cnt_dn > 1 );

$node = $dom2->createElement( $testtxt );
$dom->appendChild( $node );
@clds = $dom->childNodes();
ok( scalar( @clds ), $cnt_dn );

# parse tests

# init the file parser
{
    my $parser = XML::LibXML->new();
    my $dom3    = $parser->parse_file( $file );
    ok( defined $dom3 );
    if ( defined $dom3 ) {
      $elem   = $dom3->getDocumentElement();
      ok( defined $elem && 
          $elem->getType() == XML_ELEMENT_NODE &&
          $elem->isa( "XML::LibXML::Element" ) );
      ok( $dom3->URI, $file );
      my $oldURI = $dom3->URI("foo.xml");
      ok( $dom3->URI, "foo.xml" );
      ok( $oldURI, $file );
    }
}

