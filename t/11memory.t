use Test;
BEGIN { 
    if ($^O eq 'linux' && $ENV{MEMORY_TEST}) {
        plan tests => 8;
    }
    else {
        print "1..0 # Skipping test on this platform\n";
    }
}
use XML::LibXML;
if ($^O eq 'linux' && $ENV{MEMORY_TEST}) {
    ok(1);
    
    warn("BASELINE\n");
    check_mem();

    warn("MAKE DOC IN SUB\n");
    my $doc = make_doc();
    ok($doc);

    ok($doc->toString);
    
    check_mem();

    warn("SET DOCUMENT ELEMENT\n");
    $doc2 = XML::LibXML::Document->new();
    make_doc_elem( $doc2 );
    ok( $doc2 );
    ok( $doc2->documentElement );
    check_mem();

    # multiple parsers:
    warn("MULTIPLE PARSERS\n");
    for (1..100000) {
        my $parser = XML::LibXML->new();
    }
    ok(1);

    check_mem();

    # multiple parses
    warn("MULTIPLE PARSES\n");
    for (1..100000) {
        my $parser = XML::LibXML->new();
        my $dom = $parser->parse_string("<sometag>foo</sometag>");
    }
    ok(1);

    check_mem();

    # multiple failing parses
    warn("MULTIPLE FAILURES\n");
    for (1..100000) {
        # warn("$_\n") unless $_ % 100;
        my $parser = XML::LibXML->new();
        eval {
        my $dom = $parser->parse_string("<sometag>foo</somtag>"); # That's meant to be an error, btw!
        };
    }
    ok(1);
    
    check_mem();

}

sub make_doc {
    # code taken from an AxKit XSP generated page
    my ($r, $cgi) = @_;
    my $document = XML::LibXML::Document->createDocument("1.0", "UTF-8");
    # warn("document: $document\n");
    my ($parent);

    { my $elem = $document->createElement(q(p));$document->setDocumentElement($elem); $parent = $elem; }
    $parent->setAttribute("xmlns:" . q(param), q(http://axkit.org/XSP/param));
    { my $elem = $document->createElement(q(param:foo));$parent->appendChild($elem); $parent = $elem; }
    $parent = $parent->getParentNode;
    # warn("parent now: $parent\n");
    $parent = $parent->getParentNode;
    # warn("parent now: $parent\n");

    return $document
}

sub check_mem {
    # Log Memory Usage
    local $^W;
    my %mem;
    if (open(FH, "/proc/self/statm")) {
        @mem{qw(Total Resident Shared)} = split /\s+/, <FH>;
        close FH;

        if ($LibXML::TOTALMEM != $mem{Total}) {
            warn("Mem difference! : ", $mem{Total} - $LibXML::TOTALMEM, "\n");
            $LibXML::TOTALMEM = $mem{Total};
        }

        warn("Mem Total: $mem{Total} Shared: $mem{Shared}\n");
    }
}

# some tests for document fragments
sub make_doc_elem {
    my $doc = shift;
    my $dd = XML::LibXML::Document->new();
    my $node1 = $doc->createElement('test1');
    my $node2 = $doc->createElement('test2');
    $doc->setDocumentElement( $node1 );
}

