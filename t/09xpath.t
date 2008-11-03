use Test;
use strict;

BEGIN { plan tests => 48 };
use XML::LibXML;

my $xmlstring = <<EOSTR;
<foo>
    <bar>
        test 1
    </bar>
    <bar>
        test 2
    </bar>
</foo>
EOSTR

my $parser = XML::LibXML->new();

my $doc = $parser->parse_string( $xmlstring );
ok($doc);

{
    my @nodes = $doc->findnodes( "/foo/bar" );
    ok( @nodes );
    ok( scalar( @nodes ), 2 );

    ok( $doc->isSameNode($nodes[0]->ownerDocument) );

    my $compiled = XML::LibXML::XPathExpression->new("/foo/bar");
    for (1..3) {
      @nodes = $doc->findnodes( $compiled );
      ok( @nodes );
      ok( scalar( @nodes ), 2 );
    }

    ok( $doc->isSameNode($nodes[0]->ownerDocument) );

    my $n = $doc->createElement( "foobar" );

    my $p = $nodes[1]->parentNode;
    $p->insertBefore( $n, $nodes[1] );

    ok( $p->isSameNode( $doc->documentElement ) );
    @nodes = $p->childNodes;
    ok( scalar( @nodes ), 6 );
}

{
    my $result = $doc->find( "/foo/bar" );
    ok( $result );
    ok( $result->isa( "XML::LibXML::NodeList" ) );
    ok( $result->size, 2 );

    ok( $doc->isSameNode($$result[0]->ownerDocument) );

    $result = $doc->find( XML::LibXML::XPathExpression->new("/foo/bar") );
    ok( $result );
    ok( $result->isa( "XML::LibXML::NodeList" ) );
    ok( $result->size, 2 );

    ok( $doc->isSameNode($$result[0]->ownerDocument) );

    $result = $doc->find( "string(/foo/bar)" );
    ok( $result );
    ok( $result->isa( "XML::LibXML::Literal" ) );
    ok( $result->string_value =~ /test 1/ );

    $result = $doc->find( "string(/foo/bar)" );
    ok( $result );
    ok( $result->isa( "XML::LibXML::Literal" ) );
    ok( $result->string_value =~ /test 1/ );

    $result = $doc->find( XML::LibXML::XPathExpression->new("count(/foo/bar)") );
    ok( $result );
    ok( $result->isa( "XML::LibXML::Number" ) );
    ok( $result->value, 2 );

    $result = $doc->find( "contains(/foo/bar[1], 'test 1')" );
    ok( $result );
    ok( $result->isa( "XML::LibXML::Boolean" ) );
    ok( $result->string_value, "true" );

    $result = $doc->find( XML::LibXML::XPathExpression->new("contains(/foo/bar[1], 'test 1')") );
    ok( $result );
    ok( $result->isa( "XML::LibXML::Boolean" ) );
    ok( $result->string_value, "true" );

    $result = $doc->find( "contains(/foo/bar[3], 'test 1')" );
    ok( $result == 0 );
}

{
    # test the strange segfault after xpathing
    my $root = $doc->documentElement();
    foreach my $bar ( $root->findnodes( 'bar' )  ) {
        $root->removeChild($bar);
    }
    ok(1);
    # warn $root->toString();
    

    $doc =  $parser->parse_string( $xmlstring );
    my @bars = $doc->findnodes( '//bar' );
    
    foreach my $node ( @bars ) {
        $node->parentNode()->removeChild( $node );
    }
    ok(1);
}

{
  # from #39178
  my $p = XML::LibXML->new;
  my $doc = $p->parse_file("example/utf-16-2.xml");
  ok($doc);
  my @nodes = $doc->findnodes("/cml/*");
  ok (@nodes == 2);
  ok ($nodes[1]->textContent, "utf-16 test with umlauts: \x{e4}\x{f6}\x{fc}\x{c4}\x{d6}\x{dc}\x{df}");
}

{
  # from #36576
  my $p = XML::LibXML->new;
  my $doc = $p->parse_html_file("example/utf-16-1.html");
  ok($doc);
  use utf8;
  my @nodes = $doc->findnodes("//p");
  ok (@nodes == 1);
  skip(
    (20700 > XML::LibXML::LIBXML_RUNTIME_VERSION)
	? "UTF-16 and HTML broken in libxml2 < 2.7"
	: 0,
    $nodes[0]->textContent, "utf-16 test with umlauts: \x{e4}\x{f6}\x{fc}\x{c4}\x{d6}\x{dc}\x{df}");
}

{
  # from #36576
  my $p = XML::LibXML->new;
  my $doc = $p->parse_html_file("example/utf-16-2.html");
  ok($doc);
  my @nodes = $doc->findnodes("//p");
  ok (@nodes == 1);
  skip(
    (20700 > XML::LibXML::LIBXML_RUNTIME_VERSION)
	? "UTF-16 and HTML broken in libxml2 < 2.7"
	: 0,
    $nodes[0]->textContent, "utf-16 test with umlauts: \x{e4}\x{f6}\x{fc}\x{c4}\x{d6}\x{dc}\x{df}");
}
