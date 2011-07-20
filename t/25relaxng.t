# $Id$

##
# Testcases for the RelaxNG interface
#

use strict;
use warnings;

use lib './t/lib';
use TestHelpers;

use Test::More;

BEGIN { 
    use XML::LibXML;

    if ( XML::LibXML::LIBXML_VERSION >= 20510 ) {
        plan tests => 17;
    }
    else {
        plan skip_all => 'Skip No RNG Support compiled';
    }
};

if ( XML::LibXML::LIBXML_VERSION >= 20510 ) {

my $xmlparser = XML::LibXML->new();

my $file         = "test/relaxng/schema.rng";
my $badfile      = "test/relaxng/badschema.rng";
my $validfile    = "test/relaxng/demo.xml";
my $invalidfile  = "test/relaxng/invaliddemo.xml";
my $demo4        = "test/relaxng/demo4.rng";
my $namespace    = "test/relaxng/ns.rng";

print "# 1 parse schema from a file\n";
{
    my $rngschema = XML::LibXML::RelaxNG->new( location => $file );
    # TEST
    ok ( $rngschema, ' TODO : Add test name' );
    
    eval { $rngschema = XML::LibXML::RelaxNG->new( location => $badfile ); };
    # TEST
    ok( $@, ' TODO : Add test name' );
}

print "# 2 parse schema from a string\n";
{
    my $string = slurp($file);

    my $rngschema = XML::LibXML::RelaxNG->new( string => $string );
    # TEST
    ok ( $rngschema, ' TODO : Add test name' );

    $string = slurp($badfile);

    eval { $rngschema = XML::LibXML::RelaxNG->new( string => $string ); };
    # TEST
    ok( $@, ' TODO : Add test name' );
}

print "# 3 parse schema from a document\n";
{
    my $doc       = $xmlparser->parse_file( $file );
    my $rngschema = XML::LibXML::RelaxNG->new( DOM => $doc );
    # TEST
    ok ( $rngschema, ' TODO : Add test name' );
   
    $doc       = $xmlparser->parse_file( $badfile );
    eval { $rngschema = XML::LibXML::RelaxNG->new( DOM => $doc ); };
    # TEST
    ok( $@, ' TODO : Add test name' );
}

print "# 4 validate a document\n";
{
    my $doc       = $xmlparser->parse_file( $validfile );
    my $rngschema = XML::LibXML::RelaxNG->new( location => $file );

    my $valid = 0;
    eval { $valid = $rngschema->validate( $doc ); };
    # TEST
    is( $valid, 0, ' TODO : Add test name' );

    $doc       = $xmlparser->parse_file( $invalidfile );
    $valid     = 0;
    eval { $valid = $rngschema->validate( $doc ); };
    # TEST
    ok ( $@, ' TODO : Add test name' );
}

print "# 5 re-validate a modified document\n";
{
  my $rng = XML::LibXML::RelaxNG->new(location => $demo4);
  my $seed_xml = <<'EOXML';
<?xml version="1.0" encoding="UTF-8"?>
<root/>
EOXML

  my $doc = $xmlparser->parse_string($seed_xml);
  my $rootElem = $doc->documentElement;
  my $bogusElem = $doc->createElement('bogus-element');

  eval{$rng->validate($doc);};
  # TEST
  ok ($@, ' TODO : Add test name');

  $rootElem->setAttribute('name', 'rootElem');
  eval{ $rng->validate($doc); };
  # TEST
  ok (!$@, ' TODO : Add test name');

  $rootElem->appendChild($bogusElem);
  eval{$rng->validate($doc);};
  # TEST
  ok ($@, ' TODO : Add test name');

  $bogusElem->unlinkNode();
  eval{$rng->validate($doc);};
  # TEST
  ok (!$@, ' TODO : Add test name');

  $rootElem->removeAttribute('name');
  eval{$rng->validate($doc);};
  # TEST
  ok ($@, ' TODO : Add test name');

}

# 6 re-validate a modified document
{
    my $parser = new XML::LibXML();

    my $rngschema = XML::LibXML::RelaxNG->new(location => $namespace);
    my $doc = $parser->parse_string(<<EOD);
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE datastore SYSTEM "//test/test/datastore" [
<!ATTLIST element id ID #IMPLIED>
]>
<!-- datastore -->
<datastore xmlns="http://xmlns.example.com/2007/test/datastore">
  <data>
    <active>
      <element id="uuidtest1">
        <title>Ze element</title>
        <payload>Ze element payload</payload>
      </element>
    </active>
  </data>
</datastore>
EOD
    eval{$rngschema->validate($doc);}; 
    # TEST
    ok (!$@);

    my $node = $doc->createElement("element");

    my $title = $doc->createElement("title");
    $title->appendText("Annoying tests are annoying");
    $node->appendChild($title);

    my $payload = $doc->createElement("payload");
    $payload->appendText("some payload");
    $node->appendChild($payload);

    $node->setAttribute('id', 'uuidIamAtestElement');

    my ($active) = $doc->getElementsByTagName("active");
    eval{$rngschema->validate($doc);}; 
    # TEST
    ok (!$@);
    $active->appendChild($node);

    # If there's a bug in the dynamically-generated content, this test
    # will always fail no matter what. Hence, we reparse the document
    # and validate that (that always works) to make sure our
    # modifications are really valid
    my $reparsed_doc = $parser->parse_string($doc->toString);
    eval{$rngschema->validate($reparsed_doc);}; 
    # TEST
    ok (!$@);

    eval{$rngschema->validate($doc);}; 
    # TEST
    ok (!$@);
}


} # Version >= 20510 test 
