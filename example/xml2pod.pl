#!/usr/bin/perl -w
use XML::LibXML;
use XML::LibXML::Common qw(:libxml);
use File::Path;
use File::Basename;

# (c) 2001 christian p. glahn

# This is an example how to use the DOM interface of XML::LibXML The
# script reads a XML File with a module specification. If the module
# contains several classes, the script fetches them and stores the
# data into different POD Files.

my $xml_file = "example/libxml.xml";

# init the file parser
my $parser = XML::LibXML->new();

my $target_dir = "XML-LibXML-${XML::LibXML::VERSION}/lib";
if ( scalar @ARGV == 1 ){
    $xml_file = $ARGV[0];
}
elsif ( @ARGV == 2 ) {
    $xml_file = $ARGV[0];
    $target_dir = $ARGV[1];
}

# read the DOM
my $dom    = $parser->parse_file( $xml_file );

# get the ROOT Element of the DOM
my $elem   = $dom->getDocumentElement();

# test if the element has the correct node type ...
if ( $elem->getType() == XML_ELEMENT_NODE ) {

    # ... and the correct name
    if ( $elem->getName() eq "module" ) {

        # find class definitions without XPath :-P
        foreach my $class ( $elem->getChildrenByTagName("package") ) {
            handle_package( $class, $target_dir ); # handle the class
        }
    }
    else {
        warn "ERROR> document is not a module! \n";
    }
}
else {
    warn "ERROR> not an element as root\n";
}


sub endl() { "\n\n"; } # helper for c++ programmer ;)

sub handle_package {
    my $node = shift; # node to handle (<class ..>)
    my $target_dir = shift;

    # open traget file
    my $fn = $node->getAttribute("name") . ".pod";
    $fn =~ s/^XML::LibXML::// if $target_dir =~ /XML\/LibXML\//;

    open(OSTDOUT , ">&STDOUT");
    open(STDOUT,"> $target_dir/$fn")|| die "cannot create file $fn ($!)";

    print "=head1 NAME" . endl;
    print $node->getAttribute("name") . " - ";
    my ( $tnode ) = $node->getChildrenByTagName( "short" );
    print  $tnode->string_value;
    my @methods = $node->getElementsByTagName( "method" );
    if ( scalar @methods ) {
        print endl . "=head1 synopsis" . endl;
        print " use XML::LibXML". endl;

        foreach my $m ( @methods ) {
            print " " . $m->getAttribute( "synopsis" ) . "\n";
        }
    }

    print endl . "=head1 DESCRIPTION" . endl;
    my $mflag = 0;
    my ($dnode) = $node->getChildrenByTagName("description");
    foreach $tnode ( $dnode->childNodes ) {
        if ( $tnode->nodeName eq "p" ) {
            handle_paragraph( $tnode );
        }
        if ( $tnode->nodeName eq "example" ) {
            print $tnode->string_value();
        }
        if ( $tnode->nodeName eq "method" ) {
            unless ( $mflag ) {
                print endl . "=head2 Methods". endl . "=over 4" .endl;
                $mflag = 1;
            }
            handle_method( $tnode );
            print endl;
        }
        if ( $tnode->nodeName eq "section" ) {
            handle_section( $tnode );
        }
    }
    print endl."=back" if $mflag == 1;

    print endl . "=head1 AUTHOR" . endl;
    print join ", ", map { $_->string_value } ($node->findnodes("/module/authors/author"));
    print endl;

    my @refs = $node->getElementsByTagName( "item" );
    if ( scalar @refs ) {
        print "=head1 SEE ALSO". endl;
        print join ", ", map { $_->getAttribute("name") } @refs;
        print endl;
    }

    print "=head1 VERSION". endl;
    my ($version) = $node->findnodes( "/module/version" );
    print $version->string_value . endl;
    close(STDOUT);
    *STDOUT = *OSTDOUT;
    # open(STDOUT, ">&OSTDOUT");
}

sub handle_paragraph {
    my $node = shift;
    print endl;
    foreach my $e ( $node->childNodes ) {
        if ( $e->getType == XML_TEXT_NODE ) {
            my $data;
            ( $data = $e->string_value() ) =~ s/(\s)\s+/$1/g;
            print $data;
        }
        if ( $e->getType == XML_ELEMENT_NODE ) {
            if ( $e->nodeName eq "st" ) {
                print "B<". $e->string_value .">";
            }
            elsif ( $e->nodeName eq "em" ) {
                print "I<". $e->string_value .">";
            }
        }
    }
    print endl;
}

sub handle_method {
    my $node = shift;
#    return "" unless $node;

    print "=item B<".$node->getAttribute("name").">". endl;
    foreach my $tnode ( $node->childNodes ) {
        if ( $tnode->nodeName eq "p" ) {
            handle_paragraph( $tnode );
        }
        if ( $tnode->nodeName eq "example" ) {
            print $tnode->string_value();
        }
    }
}

sub handle_section {
    my $node = shift;
    print "=head2 ".$node->getAttribute("name"). endl;
    foreach my $tnode ( $node->childNodes ) {
        if ( $tnode->nodeName eq "p" ) {
            handle_paragraph( $tnode );
        }
        if ( $tnode->nodeName eq "example" ) {
            print $tnode->string_value();
        }
    }
}
