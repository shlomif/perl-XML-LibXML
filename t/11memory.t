use Test;
use Devel::Peek;

BEGIN { plan tests => 7 }
use XML::LibXML;
ok(1);

sub make_doc {
    my ($r, $cgi) = @_;
    my $document = XML::LibXML::Document->createDocument("1.0", "UTF-8");
    # warn("document: $document\n");
    my ($parent);

    {
        my $elem = $document->createElement(q(p));
        $document->setDocumentElement($elem);     
        $parent = $elem;
    }
    $parent->setAttribute("xmlns:" . q(param), q(http://axkit.org/XSP/param));
    { 
        my $elem = $document->createElement(q(param:foo));$parent->appendChild($elem); $parent = $elem; 
    }
    $parent = $parent->getParentNode;
    # warn("parent now: $parent\n");
    $parent = $parent->getParentNode;
    # warn("parent now: $parent\n");

    return $document
}

my $doc = make_doc();
ok($doc);

ok( $doc->toString() );

# some tests for document fragments
sub make_doc_elem {
    my $doc = shift;
    my $dd = XML::LibXML::Document->new();
    my $node1 = $doc->createElement('test1');
    my $node2 = $doc->createElement('test2');
    $doc->setDocumentElement( $node1 );
}

$doc2 = XML::LibXML::Document->new();
make_doc_elem( $doc2 );
ok( $doc2 );
ok( $doc2->documentElement );
# warn $doc2->toString();

ok(1); ok(1);


