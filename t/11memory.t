use Test;
BEGIN { 
    if ($^O eq 'linux' && $ENV{MEMORY_TEST}) {
        plan tests => 9;
    }
    else {
        print "1..0 # Skipping test on this platform\n";
    }
}
use XML::LibXML;
if ($^O eq 'linux' && $ENV{MEMORY_TEST}) {
    require Devel::Peek;
    my $peek = 0;
    
    ok(1);

    my $times_through = $ENV{MEMORY_TIMES} || 100_000;
    
    print("# BASELINE\n");
    check_mem(1);

    print("# MAKE DOC IN SUB\n");
    {
        my $doc = make_doc();
        ok($doc);
    
        ok($doc->toString);
    }
    check_mem();

    print("# SET DOCUMENT ELEMENT\n");
    {
        my $doc2 = XML::LibXML::Document->new();
        make_doc_elem( $doc2 );
        ok( $doc2 );
        ok( $doc2->documentElement );
    }
    check_mem();

    # multiple parsers:
    print("# MULTIPLE PARSERS\n");
    for (1..$times_through) {
        my $parser = XML::LibXML->new();
    }
    ok(1);

    check_mem();

    # multiple parses
    print("# MULTIPLE PARSES\n");
    for (1..$times_through) {
        my $parser = XML::LibXML->new();
        my $dom = $parser->parse_string("<sometag>foo</sometag>");
    }
    ok(1);

    check_mem();

    # multiple failing parses
    print("# MULTIPLE FAILURES\n");
    for (1..$times_through) {
        # warn("$_\n") unless $_ % 100;
        my $parser = XML::LibXML->new();
        eval {
        my $dom = $parser->parse_string("<sometag>foo</somtag>"); # Thats meant to be an error, btw!
        };
    }
    ok(1);
    
    check_mem();

    # building custom docs
    print("# CUSTOM DOCS\n");
    my $doc = XML::LibXML::Document->new();
    for (1..$times_through) {
        {
            my $elem = $doc->createElement('x');
            
            if($peek) {
            warn("Doc before elem\n");
            Devel::Peek::Dump($doc);
            warn("Elem alone\n");
            Devel::Peek::Dump($elem);
            }
            
            # $doc->setDocumentElement($elem);
            
            if ($peek) {
            warn("Elem after attaching\n");
            Devel::Peek::Dump($elem);
            warn("Doc after elem\n");
            Devel::Peek::Dump($doc);
            }
        }
        if ($peek) {
        warn("Doc should be freed\n");
        Devel::Peek::Dump($doc);
        }
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
    my $initialise = shift;
    # Log Memory Usage
    local $^W;
    my %mem;
    if (open(FH, "/proc/self/status")) {
        my $units;
        while (<FH>) {
            if (/^VmSize.*?(\d+)\W*(\w+)$/) {
                $mem{Total} = $1;
                $units = $2;
            }
            if (/^VmRSS:.*?(\d+)/) {
                $mem{Resident} = $1;
            }
        }
        close FH;

        if ($LibXML::TOTALMEM != $mem{Total}) {
            warn("LEAK! : ", $mem{Total} - $LibXML::TOTALMEM, " $units\n") unless $initialise;
            $LibXML::TOTALMEM = $mem{Total};
        }

        print("# Mem Total: $mem{Total} $units, Resident: $mem{Resident} $units\n");
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

