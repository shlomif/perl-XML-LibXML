# $Id$

##
# this test checks the DOM Document interface of XML::LibXML
# it relies on the success of t/01basic.t and t/02parse.t

# it will ONLY test the DOM capabilities as specified in DOM Level3
# XPath tests should be done in another test file

# since all tests are run on a preparsed 

use Test;
use strict;

BEGIN { plan tests => 78 };
use XML::LibXML;
use XML::LibXML::Common qw(:libxml);

{
    print "# 1. Document Attributes\n";

    my $doc = XML::LibXML::Document->createDocument();
    ok($doc);
    ok( not defined $doc->encoding); 
    ok( $doc->version,  "1.0" );
    ok( $doc->standalone, -1 );  # is the value we get for undefined,
                                 # actually the same as 0 but just not set.
    ok( not defined $doc->URI);  # should be set by default.
    ok( $doc->compression, -1 ); # -1 indicates NO compression at all!
                                 # while 0 indicates just no zip compression 
                                 # (big difference huh?)

    $doc->setEncoding( "iso-8859-1" );
    ok( $doc->encoding, "iso-8859-1" );

    $doc->setVersion(12.5);
    ok( $doc->version, "12.5" );

    $doc->setStandalone(1);
    ok( $doc->standalone, 1 );

    $doc->setBaseURI( "localhost/here.xml" );
    ok( $doc->URI, "localhost/here.xml" );

    my $doc2 = XML::LibXML::Document->createDocument("1.1", "iso-8859-2");
    ok( $doc2->encoding, "iso-8859-2" );
    ok( $doc2->version,  "1.1" );
}

{
    print "# 2. Creating Elements\n";
    my $doc = XML::LibXML::Document->new();
    {
        my $node = $doc->createDocumentFragment();
        ok($node);
        ok($node->nodeType, XML_DOCUMENT_FRAG_NODE);
    }

    {
        my $node = $doc->createElement( "foo" );
        ok($node);
        ok($node->nodeType, XML_ELEMENT_NODE );
        ok($node->nodeName, "foo" );
    }

    {
        # namespaced element test
        my $node = $doc->createElementNS( "http://kungfoo", "foo:bar" );
        ok($node);
        ok($node->nodeType, XML_ELEMENT_NODE);
        ok($node->nodeName, "foo:bar");
        ok($node->prefix, "foo");
        ok($node->localname, "bar");
        ok($node->namespaceURI, "http://kungfoo");
    }

    {
        my $node = $doc->createTextNode( "foo" );
        ok($node);
        ok($node->nodeType, XML_TEXT_NODE );
        ok($node->nodeValue, "foo" );
    }

    {
        my $node = $doc->createComment( "foo" );
        ok($node);
        ok($node->nodeType, XML_COMMENT_NODE );
        ok($node->nodeValue, "foo" );
        ok($node->toString, "<!--foo-->");
    }

    {
        my $node = $doc->createCDATASection( "foo" );
        ok($node);
        ok($node->nodeType, XML_CDATA_SECTION_NODE );
        ok($node->nodeValue, "foo" );
        ok($node->toString, "<![CDATA[foo]]>");
    }

    {
        my $attr = $doc->createAttribute("foo", "bar");
        ok($attr);
        ok($attr->nodeType, XML_ATTRIBUTE_NODE );
        ok($attr->name, "foo");
        ok($attr->value, "bar" );
        ok($attr->hasChildNodes, 0);
        my $content = $attr->firstChild;
        ok( $content );
    }

    {
        eval {
            my $attr = $doc->createAttributeNS("http://kungfoo", "kung:foo","bar");
        };
        ok($@);

        my $root = $doc->createElement( "foo" );
        $doc->setDocumentElement( $root );

        my $attr;
        eval {
           $attr = $doc->createAttributeNS("http://kungfoo", "kung:foo","bar");
        };
        ok($attr);
        ok($attr->nodeName, "kung:foo");
        ok($attr->name,"foo" );
        ok($attr->value, "bar" );
        
    }

    {
        my $pi = $doc->createProcessingInstruction( "foo", "bar" );
        ok($pi);
        ok($pi->nodeType, XML_PI_NODE);
        ok($pi->nodeName, "foo");
        ok($pi->textContent, "bar");
    }

    {
        my $pi = $doc->createProcessingInstruction( "foo" );
        ok($pi);
        ok($pi->nodeType, XML_PI_NODE);
        ok($pi->nodeName, "foo");
        ok( $pi->textContent, undef);
    }

}

{
    print "# 3.  Document Manipulation\n";
    print "# 3.1 Document Elements\n"; 

    my $doc = XML::LibXML::Document->new();
    my $node = $doc->createElement( "foo" );
    $doc->setDocumentElement( $node );
    my $tn = $doc->documentElement;
    ok($tn);
    ok($node->isSameNode($tn));

    my $node2 = $doc->createElement( "bar" );
    
    $doc->appendChild($node2);
    my @cn = $doc->childNodes;
    ok( scalar(@cn) , 1);
    ok($cn[0]->isSameNode($node));

    $doc->insertBefore($node2, $node);
    @cn = $doc->childNodes;
    ok( scalar(@cn) , 1);
    ok($cn[0]->isSameNode($node));

    $doc->removeChild($node);
    @cn = $doc->childNodes;
    ok( scalar(@cn) , 0);

    for ( 1..2 ) {
        my $nodeA = $doc->createElement( "x" );
        $doc->setDocumentElement( $nodeA );
    }
    ok(1); # must not segfault here :)

    $doc->setDocumentElement( $node2 );
    @cn = $doc->childNodes;
    ok( scalar(@cn) , 1);
    ok($cn[0]->isSameNode($node2));

    my $node3 = $doc->createElementNS( "http://foo", "bar" );
    ok($node3);

    print "# 3.2 Processing Instructions\n"; 
    {
        my $pi = $doc->createProcessingInstruction( "foo", "bar" );
        $doc->appendChild( $pi );
        @cn = $doc->childNodes;
        ok( $pi->isSameNode($cn[-1]) );
        $pi->setData( 'bar="foo"' );
        ok( $pi->textContent, 'bar="foo"');
        $pi->setData( foo=>"foo" );
        ok( $pi->textContent, 'foo="foo"');
        
    }

    print "# 3.3 Comment Nodes\n"; 

    print "# 3.4 DTDs\n";
}

{
    print "# 4. Document Storeing\n";
    my $parser = XML::LibXML->new;
    my $doc = $parser->parse_string("<foo>bar</foo>");  

    ok( $doc );

    print "# 4.1 to file handle\n";
    {
        require IO::File;
        my $fh = new IO::File;
        if ( $fh->open( "> example/testrun.xml" ) ) {
            $doc->toFH( $fh );
            $fh->close;
            ok(1);
            # now parse the file to check, if succeeded
            my $tdoc = $parser->parse_file( "example/testrun.xml" );
            ok( $tdoc );
            ok( $tdoc->documentElement );
            ok( $tdoc->documentElement->nodeName, "foo" );
            ok( $tdoc->documentElement->textContent, "bar" );
            unlink "example/testrun.xml" ;
        }
    }

    print "# 4.2 to named file\n";
    {
        $doc->toFile( "example/testrun.xml" );
        ok(1);
        # now parse the file to check, if succeeded
        my $tdoc = $parser->parse_file( "example/testrun.xml" );
        ok( $tdoc );
        ok( $tdoc->documentElement );
        ok( $tdoc->documentElement->nodeName, "foo" );
        ok( $tdoc->documentElement->textContent, "bar" );
        unlink "example/testrun.xml" ;        
    }
}
