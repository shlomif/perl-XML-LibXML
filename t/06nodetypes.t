# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

use Test;
use Devel::Peek;
BEGIN { plan tests=>60; }
END {ok(0) unless $loaded;}
use XML::LibXML;
$loaded = 1;
ok($loaded);

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

# this script performs element node tests

my $vers   = "1.0";
my $enc    = "iso-8859-1";
my $aname  = "test";
my $avalue = "the value";
my $bvalue = "other value";
my $testtxt= "text";
my $comment= "comment";
my $cdata  = "unparsed";

my $dom = XML::LibXML::Document->createDocument( $vers, $enc );
if( defined $dom ) {

# node creation 1 (bound element)
my $elem1 = $dom->createElement( "A" );
if ( defined $elem1 ) {
  ok( $elem1->getType() == XML_ELEMENT_NODE );
  ok( $elem1->getName() eq "A" );

  # set, reset and remove attribute
  $elem1->setAttribute( $aname, $avalue );
  ok( $elem1->getAttribute( $aname ) eq $avalue );
  ok( $elem1->hasAttribute( $aname ) );
 
  # toString test
  my $estr = $elem1->toString();
  my $tstr = "<A $aname=\"$avalue\"/>";
  ok( $estr eq $tstr );  

  $dom->setDocumentElement( $elem1 );
  my $te = $dom->getDocumentElement();
  
  # in the first version it cause a method not found ... 
  ok( $estr eq $te->toString() );

  #####################################################
  # attribute tests

  $elem1->setAttribute( $aname, $bvalue );
  ok( $elem1->getAttribute( $aname ) eq $bvalue );
  $elem1->removeAttribute( $aname );
  ok( not $elem1->hasAttribute( $aname ) );

    my $attr = XML::LibXML::Attr->new( 'test', 'value' );
    ok( defined $attr
        && $attr->getName() eq 'test'
        && $attr->getValue() eq 'value' );

    $attr->setValue( 'other' );
    # warn $attr->value . "\n";
    ok( $attr->getValue() eq 'other' );

    my $attr2 = $dom->createAttribute( "deutsch", "überflieger" );
    ok( defined $attr2 &&
        $attr2->getName() eq "deutsch" &&
        $attr2->getValue() eq "überflieger" );

    $attr2->setValue( "drückeberger" );
    # warn "> '". $attr2->getValue() . "'\n";
    ok( $attr2->getValue() eq "drückeberger" );
     
  ###################################################
  # child node functions:
  my $text = $dom->createTextNode( $testtxt );
  ok( defined $text && $text->getType == XML_TEXT_NODE );
  ok( defined $text && $text->getData() eq $testtxt );

  $elem1->appendChild( $text );
  ok( $elem1->hasChildNodes() );

  # test if first child works
  my $tt = $elem1->getFirstChild();
  ok( defined $tt && ( $tt->getData() eq $text->getData() ) ) ;

  # test if last child works 
  $tt = $elem1->getLastChild();
  ok( defined $tt && ( $tt->getData() eq $text->getData() ) ) ;

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

  # forward traversing
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
  ok( $str eq 'tcd' ); 

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

  # replace test
  my $elem3 = $dom->createElement( "C" );
  $elem1->replaceChild( $elem3, $rem );
	
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

  $elem1->removeChild( $elem3 );
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

  my $testtxt = "täst";
  my $elem = $dom->createElement( $testtxt );
  ok( $elem->getName() eq $testtxt );
  $elem->appendTextNode( $testtxt );
  $elem->appendTextChild($testtxt, $testtxt);
  $elem->setAttribute( 'test', $testtxt );

  @ta = $elem->getChildnodes();
    # warn Devel::Peek::DumpArray(2 ,@ta );
    # warn "\@TA HAS " , scalar( @ta), " ITEMS\n"; 
  my ( $n1, $n2 ) = $elem->getChildnodes();
  ok( $n1 && $n1->getData() eq $testtxt );
  ok( $n2 && $n2->getName() eq $testtxt );
  ok( $n2 && $n2->getLocalName() eq $testtxt );

  ok( $elem->getAttribute( 'test' ) eq $testtxt );

  #################################################
  # explicit document fragment test
    print "# fragment tests \n";
  $frag = $dom->createDocumentFragment();
#   $frag = XML::LibXML::DocumentFragment->new();
  ok( $frag );
#  Devel::Peek::Dump( $frag );
  $frag->appendChild( $n1 );
  ok( $frag->hasChildNodes() );
  ok( ($frag->childNodes)[0]->nodeValue, $testtxt );
  ok( ($elem->childNodes)[0]->nodeName, $testtxt );
  $frag->appendChild( $elem );
    @ta = $frag->childNodes;
  ok( scalar(@ta) , 2 );

  $domroot = $dom->documentElement;

  # @ta = $domroot->childNodes;
  # warn "root has ",scalar( @ta ) ," elements\n"; 
  $domroot->appendChild( $frag );
  @ta =$frag->childNodes;
  ok( scalar(@ta), 0 );
  @ta =$domroot->childNodes;
  ok( scalar(@ta), 4 );
  ok( ($domroot->childNodes)[2]->nodeValue, $testtxt );
  #  warn $domroot->toString();
  $frag->appendChild( ($domroot->childNodes)[2] );
  $frag->appendChild( ($domroot->childNodes)[2] );
  
   # warn scalar( $frag->childNodes ), "\n";

  $cnode = ($domroot->childNodes)[1];
  ok( $cnode );
  ok( $cnode->nodeName, 'C');
  $domroot->replaceChild( $frag, $cnode );
  ok( scalar($frag->childNodes), 0 );
  ok( scalar($domroot->childNodes), 3 ); # its 2 because the first node in the fragment is text
                        # and so is the preceeding node in domroot
  # warn $domroot->toString();

}
print "# end fragment tests\n";


# node creation 2 (unbound element)
#
# NOTE!
#
# this should only be a virtual thing! you should never everdo such a
# thing. create nodes allways through a document, otherwise the node
# might not be in UTF-8 which confuses XSLT, toString etc.
#
#
# these tests are ment to test logical correctness!

 my $elem2 = XML::LibXML::Element->new( "B" );

 if ( defined $elem2 ) {
  ok( defined $elem2 && $elem2->getType() == XML_ELEMENT_NODE );
  ok( defined $elem2 && $elem2->getName() eq "B" );
  # much easier to test if no owner document is set ...
  ok( defined $elem2 && not defined $elem2->getOwnerDocument() );

  $elem2->setAttribute( $aname, $avalue );
  ok( $elem2->getAttribute( $aname ) eq $avalue );
  $elem2->setAttribute( $aname, $bvalue );
  ok( $elem2->getAttribute( $aname ) eq $bvalue );
  $elem2->removeAttribute( $aname );
  ok( not $elem2->hasAttribute( $aname ) );


  # nessecary document switch test!
  my $elem3 = $dom->createElement( "C" );
  if ( defined $elem3 ) {
	$elem2->appendChild( $elem3 );
	ok( not defined $elem3->getOwnerDocument() );
  }
 }
}
