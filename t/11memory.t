use Test;
BEGIN { plan tests => 5 }
use XML::LibXML;
ok(1);

sub make_doc {
    my ($r, $cgi) = @_;
    my $document = XML::LibXML::Document->createDocument("1.0", "UTF-8");
    # warn("document: $document\n");
    my ($parent);

    {
        my $elem = $document->createElement(q(p));$document->setDocumentElement($elem); $parent = $elem; 
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

ok(1); ok(1);
