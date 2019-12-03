# $Id$

##
# Testcases for the RelaxNG interface
#

use strict;
use warnings;

use lib './t/lib';
use TestHelpers qw(slurp);

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
my $netfile      = "test/relaxng/net.rng";

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

print "# 6 check that no_network => 1 works\n";
{
    my $rng = eval { XML::LibXML::RelaxNG->new( location => $netfile, no_network => 1 ) };
    # TEST
    like( $@, qr{I/O error : Attempt to load network entity}, 'RNG from file location with external import and no_network => 1 throws an exception.' );
    # TEST
    ok( !defined $rng, 'RNG from file location with external import and no_network => 1 is not loaded.' );
}
{
    my $rng = eval { XML::LibXML::RelaxNG->new( string => <<'EOF', no_network => 1 ) };
<?xml version="1.0" encoding="iso-8859-1"?>
<grammar xmlns="http://relaxng.org/ns/structure/1.0" datatypeLibrary="http://www.w3.org/2001/XMLSchema-datatypes">
  <include href="http://example.com/xml.rng"/>
  <start>
    <ref name="include"/>
  </start>
  <define name="include">
    <element name="include">
      <text/>
    </element>
  </define>
</grammar>
EOF
    # TEST
    like( $@, qr{I/O error : Attempt to load network entity}, 'RNG from buffer with external import and no_network => 1 throws an exception.' );
    # TEST
    ok( !defined $rng, 'RNG from buffer with external import and no_network => 1 is not loaded.' );
}


} # Version >= 20510 test
