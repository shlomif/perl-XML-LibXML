# $Id$

use strict;
use warnings;

# Should be 54.
use Test::More tests => 54;

use lib './t/lib';
use TestHelpers;

use XML::LibXML;
use XML::LibXML::Common qw(:libxml);

my $htmlPublic = "-//W3C//DTD XHTML 1.0 Transitional//EN";
my $htmlSystem = "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd";

{
    my $doc = XML::LibXML::Document->new;
    my $dtd = $doc->createExternalSubset( "html",
                                          $htmlPublic,
                                          $htmlSystem
                                        );

    # TEST
    ok( $dtd->isSameNode(  $doc->externalSubset ), ' TODO : Add test name' );
    # TEST
    is( $dtd->publicId, $htmlPublic, ' TODO : Add test name' );
    # TEST
    is( $dtd->systemId, $htmlSystem, ' TODO : Add test name' );
    # TEST
    is( $dtd->getName, 'html', ' TODO : Add test name' );

}

{
    my $doc = XML::LibXML::Document->new;
    my $dtd = $doc->createInternalSubset( "html",
                                          $htmlPublic,
                                          $htmlSystem
                                        );
    # TEST
    ok( $dtd->isSameNode( $doc->internalSubset ), ' TODO : Add test name' );

    $doc->setExternalSubset( $dtd );
    # TEST
    ok(!defined ($doc->internalSubset), ' TODO : Add test name' );
    # TEST
    ok( $dtd->isSameNode( $doc->externalSubset ), ' TODO : Add test name' );

    # TEST

    is( $dtd->getPublicId, $htmlPublic, ' TODO : Add test name' );
    # TEST
    is( $dtd->getSystemId, $htmlSystem, ' TODO : Add test name' );

    $doc->setInternalSubset( $dtd );
    # TEST
    ok(!defined ($doc->externalSubset), ' TODO : Add test name' );
    # TEST
    ok( $dtd->isSameNode( $doc->internalSubset ), ' TODO : Add test name' );

    my $dtd2 = $doc->createDTD( "huhu",
                                "-//W3C//DTD XHTML 1.0 Transitional//EN",
                                "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd"
                              );

    $doc->setInternalSubset( $dtd2 );
    # TEST
    ok( !defined($dtd->parentNode), ' TODO : Add test name' );
    # TEST
    ok( $dtd2->isSameNode( $doc->internalSubset ), ' TODO : Add test name' );


    my $dtd3 = $doc->removeInternalSubset;
    # TEST
    ok( $dtd3->isSameNode($dtd2), ' TODO : Add test name' );
    # TEST
    ok( !defined($doc->internalSubset), ' TODO : Add test name' );

    $doc->setExternalSubset( $dtd2 );

    $dtd3 = $doc->removeExternalSubset;
    # TEST
    ok( $dtd3->isSameNode($dtd2), ' TODO : Add test name' );
    # TEST
    ok( !defined($doc->externalSubset), ' TODO : Add test name' );
}

{
    my $parser = XML::LibXML->new();

    my $doc = $parser->parse_file( "example/dtd.xml" );

    # TEST

    ok($doc, ' TODO : Add test name');

    my $dtd = $doc->internalSubset;
    # TEST
    is( $dtd->getName, 'doc', ' TODO : Add test name' );
    # TEST
    is( $dtd->publicId, undef, ' TODO : Add test name' );
    # TEST
    is( $dtd->systemId, undef, ' TODO : Add test name' );

    my $entity = $doc->createEntityReference( "foo" );
    # TEST
    ok($entity, ' TODO : Add test name');
    # TEST
    is($entity->nodeType, XML_ENTITY_REF_NODE, ' TODO : Add test name' );

    # TEST

    ok( $entity->hasChildNodes, ' TODO : Add test name' );
    # TEST
    is( $entity->firstChild->nodeType, XML_ENTITY_DECL, ' TODO : Add test name' );
    # TEST
    is( $entity->firstChild->nodeValue, " test ", ' TODO : Add test name' );

    my $edcl = $entity->firstChild;
    # TEST
    is( $edcl->previousSibling->nodeType, XML_ELEMENT_DECL, ' TODO : Add test name' );

    {
        my $doc2  = XML::LibXML::Document->new;
        my $e = $doc2->createElement("foo");
        $doc2->setDocumentElement( $e );

        my $dtd2 = $doc->internalSubset->cloneNode(1);
        # TEST
        ok($dtd2, ' TODO : Add test name');

#        $doc2->setInternalSubset( $dtd2 );
#        warn $doc2->toString;

#        $e->appendChild( $entity );
#        warn $doc2->toString;
    }
}


{
    my $parser = XML::LibXML->new();
    $parser->validation(1);
    $parser->keep_blanks(1);
    my $doc=$parser->parse_string(<<'EOF');
<?xml version='1.0'?>
<!DOCTYPE test [
 <!ELEMENT test (#PCDATA)>
]>
<test>
</test>
EOF

    # TEST
    ok($doc->validate(), ' TODO : Add test name');

    # TEST
    ok($doc->is_valid(), ' TODO : Add test name');

}

{
    my $parser = XML::LibXML->new();
    $parser->validation(0);
    $parser->load_ext_dtd(0); # This should make libxml not try to get the DTD

    my $xml = '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://localhost/does_not_exist.dtd">
    <html xmlns="http://www.w3.org/1999/xhtml"><head><title>foo</title></head><body><p>bar</p></body></html>';
    my $doc = eval {
        $parser->parse_string($xml);
    };

    # TEST
    ok(!$@, ' TODO : Add test name');
    if ($@) {
        warn "Parsing error: $@\n";
    }

    # TEST
    ok($doc, ' TODO : Add test name');
}

{
    my $bad = 'example/bad.dtd';
    # TEST
    ok( -f $bad, ' TODO : Add test name' );
    eval { XML::LibXML::Dtd->new("-//Foo//Test DTD 1.0//EN", 'example/bad.dtd') };
    # TEST
    ok ($@, ' TODO : Add test name');

    undef $@;
    my $dtd = slurp($bad);

    # TEST
    ok( length($dtd) > 5, ' TODO : Add test name' );
    eval { XML::LibXML::Dtd->parse_string($dtd) };
    # TEST
    ok ($@, ' TODO : Add test name');

    my $xml = "<!DOCTYPE test SYSTEM \"example/bad.dtd\">\n<test/>";

    {
        my $parser = XML::LibXML->new;
        $parser->load_ext_dtd(0);
        $parser->validation(0);
        my $doc = $parser->parse_string($xml);
        # TEST
        ok( $doc, ' TODO : Add test name' );
    }
    {
        my $parser = XML::LibXML->new;
        $parser->load_ext_dtd(1);
        $parser->validation(0);
        undef $@;
        eval { $parser->parse_string($xml) };
        # TEST
        ok( $@, ' TODO : Add test name' );
    }
}

{
    # RT #71076: https://rt.cpan.org/Public/Bug/Display.html?id=71076

    my $parser = XML::LibXML->new();
    my $doc = $parser->parse_string(<<'EOF');
<!DOCTYPE test [
 <!ELEMENT test (#PCDATA)>
 <!ATTLIST test
  attr CDATA #IMPLIED
 >
]>
<test>
</test>
EOF
    my $dtd = $doc->internalSubset;

    # TEST
    ok( !$dtd->hasAttributes, 'hasAttributes' );
    # TEST
    is_deeply( [ $dtd->attributes ], [], 'attributes' );
}

# Remove DTD nodes

sub test_remove_dtd {
    my ($test_name, $remove_sub) = @_;

    my $parser = XML::LibXML->new;
    my $doc    = $parser->parse_file('example/dtd.xml');
    my $dtd    = $doc->internalSubset;

    $remove_sub->($doc, $dtd);

    # TEST*3
    ok( !$doc->internalSubset, "remove DTD via $test_name" );
}

test_remove_dtd( "unbindNode", sub {
    my ($doc, $dtd) = @_;
    $dtd->unbindNode;
} );
test_remove_dtd( "removeChild", sub {
    my ($doc, $dtd) = @_;
    $doc->removeChild($dtd);
} );
test_remove_dtd( "removeChildNodes", sub {
    my ($doc, $dtd) = @_;
    $doc->removeChildNodes;
} );

# Insert DTD nodes

sub test_insert_dtd {
    my ($test_name, $insert_sub) = @_;

    my $parser  = XML::LibXML->new;
    my $src_doc = $parser->parse_file('example/dtd.xml');
    my $dtd     = $src_doc->internalSubset;
    my $doc     = $parser->parse_file('example/dtd.xml');

    $insert_sub->($doc, $dtd);

    # TEST*11
    ok( $doc->internalSubset->isSameNode($dtd), "insert DTD via $test_name" );
}

test_insert_dtd( "insertBefore internalSubset", sub {
    my ($doc, $dtd) = @_;
    $doc->insertBefore($dtd, $doc->internalSubset);
} );
test_insert_dtd( "insertBefore documentElement", sub {
    my ($doc, $dtd) = @_;
    $doc->insertBefore($dtd, $doc->documentElement);
} );
test_insert_dtd( "insertAfter internalSubset", sub {
    my ($doc, $dtd) = @_;
    $doc->insertAfter($dtd, $doc->internalSubset);
} );
test_insert_dtd( "insertAfter documentElement", sub {
    my ($doc, $dtd) = @_;
    $doc->insertAfter($dtd, $doc->documentElement);
} );
test_insert_dtd( "replaceChild internalSubset", sub {
    my ($doc, $dtd) = @_;
    $doc->replaceChild($dtd, $doc->internalSubset);
} );
test_insert_dtd( "replaceChild documentElement", sub {
    my ($doc, $dtd) = @_;
    $doc->replaceChild($dtd, $doc->documentElement);
} );
test_insert_dtd( "replaceNode internalSubset", sub {
    my ($doc, $dtd) = @_;
    $doc->internalSubset->replaceNode($dtd);
} );
test_insert_dtd( "replaceNode documentElement", sub {
    my ($doc, $dtd) = @_;
    $doc->documentElement->replaceNode($dtd);
} );
test_insert_dtd( "appendChild", sub {
    my ($doc, $dtd) = @_;
    $doc->appendChild($dtd);
} );
test_insert_dtd( "addSibling internalSubset", sub {
    my ($doc, $dtd) = @_;
    $doc->internalSubset->addSibling($dtd);
} );
test_insert_dtd( "addSibling documentElement", sub {
    my ($doc, $dtd) = @_;
    $doc->documentElement->addSibling($dtd);
} );

