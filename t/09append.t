use Test;
BEGIN { plan tests=>11; }
END {ok(0) unless $loaded;}
use XML::LibXML;
$loaded = 1;
ok($loaded);

# this script tests if insertBefore and insertAfter functions work properly

my ( $dom, $root, $node1, $node2, $node3 );

$dom = XML::LibXML::Document->new( "1.0", "iso-8859-1" );

$root  = $dom->createElement( "R" );
$node1 = $dom->createElement( "a" );
$node2 = $dom->createElement( "b" );
$node3 = $dom->createElement( "c" );

$dom->setDocumentElement( $root ); 
$root->appendChild( $node1 );

my @children = $root->getChildnodes();
ok( scalar( @children ), 1 );
ok( ( $children[0]->getName() eq "a" ) );

$root->insertBefore( $node2 , $node1 );
@children = $root->getChildnodes();
ok( scalar( @children ),2 ) ;
ok( ( $children[0]->getName() eq "b" ) &&
    ( $children[1]->getName() eq "a" ) );

$root->insertAfter( $node3 , $node1 );
 @children = $root->getChildnodes();
ok( scalar( @children ), 3 );
ok( ( $children[0]->getName() eq "b" ) &&
    ( $children[2]->getName() eq "c" ) &&
    ( $children[1]->getName() eq "a" ) );
 
$root->removeChild( $node3 );
@children = $root->getChildnodes();
ok( scalar( @children ),  2  );
ok( ( $children[0]->getName() eq "b" ) &&
    ( $children[1]->getName() eq "a" ) );

# lets switch two nodes :)
$root->insertAfter( $node2, $node1 ); 
@children = $root->getChildnodes();
ok( scalar( @children ) , 2 );
ok( ( $children[1]->getName() eq "b" ) &&
    ( $children[0]->getName() eq "a" ) );

