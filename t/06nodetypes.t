# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

use Test;
use Devel::Peek;
BEGIN { plan tests=>86; }
END {ok(0) unless $loaded;}
use XML::LibXML;
$loaded = 1;
ok($loaded);

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

# this script performs element node tests

my $version = "1.0";
my $enc1    = "iso-8859-1";
my $enc2    = "iso-8859-2";

my $aname  = "test";
my $avalue = "the value";
my $bvalue = "other value";
my $testtxt= "text";
my $comment= "comment";
my $cdata  = "unparsed";

print "# document tests\n";
my $dom = XML::LibXML::Document->createDocument( $version, $enc1 );
ok($dom);

ok( $dom->getVersion, $version );
ok( $dom->getEncoding, $enc1 );

$dom->setEncoding($enc2);
ok( $dom->getEncoding, $enc2 );
$dom->setVersion( "2.0" );
ok( $dom->getVersion, "2.0" );

print "# node creation 1 (bound element)\n";

my $elem1 = $dom->createElement( "A" );
ok( $elem1 );
ok( $elem1->getType(), XML_ELEMENT_NODE );
ok( $elem1->getName(), "A" );

$elem1->setAttribute( $aname, $avalue );
ok( $elem1->getAttribute( $aname ) eq $avalue );
ok( $elem1->hasAttribute( $aname ) );
 
# toString test
my $estr = $elem1->toString();
my $tstr = "<A $aname=\"$avalue\"/>";
ok( $estr, $tstr );  

$dom->setDocumentElement( $elem1 );
my $te = $dom->getDocumentElement();
  
# in the first version it cause a method not found ... 
ok( $estr, $te->toString() );
ok( $elem1->isSameNode( $te ) );

#####################################################
print "# attribute tests\n";

$elem1->setAttribute( $aname, $bvalue );
ok( $elem1->hasAttribute( $aname ) );
ok( $elem1->getAttribute( $aname ), $bvalue );
$elem1->removeAttribute( $aname );
ok( not $elem1->hasAttribute( $aname ) );

my $attr = XML::LibXML::Attr->new( 'test', 'value' );
ok( defined $attr && $attr->name() eq 'test' && $attr->getValue() eq 'value' );

$attr->setValue( 'other' );
ok( $attr->getValue(), 'other' );

###################################################
print "# text node tests\n";

my $textnode = $dom->createTextNode("test");
ok( $textnode );
ok( $textnode->nodeValue(), "test" );

# DOM spec stuff

my $tnstr = $textnode->substringData( 1,2 );
ok( $tnstr , "es" );
ok( $textnode->nodeValue(), "test" );

$textnode->appendData( "test" );
ok( $textnode->nodeValue(), "testtest" );

# this should always work
$textnode->insertData( 4, "TesT" );
ok( $textnode->nodeValue(), "testTesTtest" );
# this should append
$textnode->setData( "test" );
$textnode->insertData( 6, "Test" );
ok( $textnode->nodeValue(), "testTest" );
$textnode->setData( "test" );
$textnode->insertData( 3, "" );
ok( $textnode->nodeValue(), "test" );

# delete data
$textnode->deleteData( 1,2 );
ok( $textnode->nodeValue(), "tt" );
$textnode->setData( "test" );
$textnode->deleteData( 1,10 );
ok( $textnode->nodeValue(), "t" );
$textnode->setData( "test" );
$textnode->deleteData( 10,1 );
ok( $textnode->nodeValue(), "test" );
$textnode->deleteData( 1,0 );
ok( $textnode->nodeValue(), "test" );
$textnode->deleteData( 0,0 );
ok( $textnode->nodeValue(), "test" );
$textnode->deleteData( 0,2 );
ok( $textnode->nodeValue(), "st" );

$textnode->setData( "test" );
$textnode->replaceData( 1,2, "phish" );
ok( $textnode->nodeValue(), "tphisht" );
$textnode->setData( "test" );
$textnode->replaceData( 1,4, "phish" );
ok( $textnode->nodeValue(), "tphish" );
$textnode->setData( "test" );
$textnode->replaceData( 1,0, "phish" );
ok( $textnode->nodeValue(), "tphishest" );

# now the cool functions they can't do in java :)
$textnode->setData( "test" );

$textnode->replaceDataString( "es", "new" );   
ok( $textnode->nodeValue(), "tnewt" );

$textnode->replaceDataRegEx( 'n(.)w', '$1s' );
ok( $textnode->nodeValue(), "test" );

$textnode->setData( "blue phish, white phish, no phish" );
$textnode->replaceDataRegEx( 'phish', 'test' );
ok( $textnode->nodeValue(), "blue test, white phish, no phish" );

# replace them all!
$textnode->replaceDataRegEx( 'phish', 'test', 'g' );
ok( $textnode->nodeValue(), "blue test, white test, no test" );


###################################################
print "# child node functions:\n";

my $text = $dom->createTextNode( $testtxt );
ok( $text );
ok( $text->getType, XML_TEXT_NODE );
ok( $text->getData(), $testtxt );

$elem1->appendChild( $text );
ok( $elem1->hasChildNodes() );

my $tt = $elem1->getFirstChild();
ok( $tt );
ok( $text->isSameNode($tt) );

$tt = $elem1->getLastChild();
ok( $tt );
ok( $tt->isSameNode($text) ) ;

my @children = $elem1->getChildnodes();
ok( scalar( @children ) == 1 ); 

# test bugs in classification
ok( $tt->isa("XML::LibXML::Text") );
  
$text = $dom->createComment( $comment ); 
ok( $text->isa("XML::LibXML::Comment") );
$elem1->appendChild( $text );


$text = $dom->createCDATASection( $cdata ); 
ok( $text->isa("XML::LibXML::CDATASection") );
$elem1->appendChild( $text );
 
my $str = "";

print "# traversing tests\n";

my $c = $elem1->getFirstChild();
while ( $c ) {
    if( $c->getType() == XML_TEXT_NODE ){
    	ok( $c->isa( "XML::LibXML::Text" ) );
	    $str .='t';
    }
    elsif( $c->getType() == XML_COMMENT_NODE ){
    	ok( $c->isa( "XML::LibXML::Comment" ) );
	    $str .='c';
    }
    elsif( $c->getType() == XML_CDATA_SECTION_NODE ){
    	ok( $c->isa( "XML::LibXML::CDATASection" ) );
	    $str .='d';
    }
    else{
    	$str .= '?';
    }
    $c = $c->getNextSibling();
}

ok( $str, 'tcd' ); 

# reverse traversing
$str = "";
my $rem = undef;
$c = $elem1->getLastChild();
while ( $c ) {
    if( $c->getType() == XML_TEXT_NODE ){
	    ok( $c->isa( "XML::LibXML::Text" ) );
      	$str .='t';
    }
    elsif( $c->getType() == XML_COMMENT_NODE ){
	    ok( $c->isa( "XML::LibXML::Comment" ) );
	    $rem = $c;
	    $str .='c';
    }
    elsif( $c->getType() == XML_CDATA_SECTION_NODE ){
      	ok( $c->isa( "XML::LibXML::CDATASection" ) );
      	$str .='d';
    }
    else{
	    $str .= '?';
    }
    $c = $c->getPreviousSibling();
}

ok( $str , 'dct' ); 


print "# replace test\n";

my $elem3 = $dom->createElement( "C" );
my $tn = $elem1->replaceChild( $elem3, $rem );
ok( $tn->isSameNode( $rem ) );

$str = "";
$c = $elem1->getLastChild();

while ( $c ) {
    if( $c->getType() == XML_TEXT_NODE )            {$str .='t';}
    elsif( $c->getType() == XML_COMMENT_NODE )      {$str .='c';}
    elsif( $c->getType() == XML_CDATA_SECTION_NODE ){$str .='d';}
    elsif( $c->getType() == XML_ELEMENT_NODE )      {$str .='e';}
    else{$str .= '?';}
    $c = $c->getPreviousSibling();
}
ok( $str, 'det' );    
ok( not defined $rem->getParentNode() && 
    not defined $rem->getNextSibling() &&
    not defined $rem->getPreviousSibling() );


# remove test
print "# remove test\n";

$tt = $elem1->removeChild( $elem3 );
ok( $tt->isSameNode( $elem3 ) );

$str = "";
$c = $elem1->getLastChild();
while ( $c ) {
    if( $c->getType() == XML_TEXT_NODE )            {$str .='t';}
    elsif( $c->getType() == XML_COMMENT_NODE )      {$str .='c';}
    elsif( $c->getType() == XML_CDATA_SECTION_NODE ){$str .='d';}
    elsif( $c->getType() == XML_ELEMENT_NODE )      {$str .='e';}
    else{$str .= '?';}
    $c = $c->getPreviousSibling();
}
ok( $str, 'dt' );    

ok( not defined $elem3->getParentNode() && 
    not defined $elem3->getNextSibling() &&
    not defined $elem3->getPreviousSibling() ); 

# node moving in the tree ...

$elem1->appendChild( $elem3 );
$elem3->appendChild( $text );
$str = "";
$c = $elem1->getLastChild();

while ( $c ) {
    if( $c->getType() == XML_TEXT_NODE )            {$str .='t';}
    elsif( $c->getType() == XML_COMMENT_NODE )      {$str .='c';}
    elsif( $c->getType() == XML_CDATA_SECTION_NODE ){$str .='d';}
    elsif( $c->getType() == XML_ELEMENT_NODE )      {$str .='e';}
    else{$str .= '?';}
    $c = $c->getPreviousSibling();
}
ok( $str, 'et' );

ok( $elem3->hasChildNodes() && 
    $elem3->getFirstChild()->getType() == XML_CDATA_SECTION_NODE && 
    $elem3->getFirstChild()->getData() eq $cdata );

#################################################
# explicit document fragment test
print "# fragment tests \n";

$elem4 = $dom->createElement("D");

$frag = $dom->createDocumentFragment();
#   $frag = XML::LibXML::DocumentFragment->new();
ok( $frag );
$frag->appendChild( $elem4 );

ok( $frag->hasChildNodes() );
ok( ($frag->childNodes)[0]->nodeName, "D" );

$domroot = $dom->documentElement;

# @ta = $domroot->childNodes;
# warn "root has ",scalar( @ta ) ," elements\n"; 
$domroot->appendChild( $frag );
@ta =$frag->childNodes;
ok( scalar(@ta), 0 );

@ta =$domroot->childNodes;
ok( scalar(@ta), 3 );
# ok( ($domroot->childNodes)[2]->nodeName, $elem4->nodeName );

$frag->appendChild( ($domroot->childNodes)[1] );
$frag->appendChild( ($domroot->childNodes)[1] );
  
$cnode = ($domroot->childNodes)[0];

ok( $cnode );
ok( $cnode->nodeValue, $testtxt);

ok( scalar($domroot->childNodes), 1 );
$domroot->replaceChild( $frag, $cnode );
ok( scalar($frag->childNodes), 0 );
ok( scalar($domroot->childNodes), 2 ); 

# warn $domroot->toString();

print "# node creation 2 (unbound element)\n";

# NOTE!
#
# this should only be a virtual thing! you should never everdo such a
# thing. create nodes allways through a document, otherwise the node
# might not be in UTF-8 which confuses XSLT, toString etc.
#
# these tests are ment to test logical correctness!

my $elem2 = XML::LibXML::Element->new( "B" );

ok( $elem2 );
ok( defined $elem2 && $elem2->getType() == XML_ELEMENT_NODE );
ok( defined $elem2 && $elem2->getName() eq "B" );

# much easier to test if no owner document is set ...
ok( not defined $elem2->getOwnerDocument() );

$elem2->setAttribute( $aname, $avalue );
ok( $elem2->getAttribute( $aname ), $avalue );
$elem2->setAttribute( $aname, $bvalue );
ok( $elem2->getAttribute( $aname ), $bvalue );
$elem2->removeAttribute( $aname );
ok( not $elem2->hasAttribute( $aname ) );


print "# document switching!\n";

$elem3 = $dom->createElement( "C" );
$elem2->appendChild( $elem3 );
ok( not defined $elem3->getOwnerDocument() );

print "# end tests \n";
