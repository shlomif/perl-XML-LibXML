# $Id$

##
# Testcases for the RelaxNG interface
#

use Test;
use strict;

BEGIN { 
    use XML::LibXML;

    if ( XML::LibXML::LIBXML_VERSION >= 20510 ) {
        plan tests => 13;
    }
    else {
        plan tests => 0;
        print( "# Skip No RNG Support compiled\n" );
    }
};

if ( XML::LibXML::LIBXML_VERSION >= 20510 ) {

my $xmlparser = XML::LibXML->new();

my $file         = "test/relaxng/schema.rng";
my $badfile      = "test/relaxng/badschema.rng";
my $validfile    = "test/relaxng/demo.xml";
my $invalidfile  = "test/relaxng/invaliddemo.xml";
my $demo4        = "test/relaxng/demo4.rng";

print "# 1 parse schema from a file\n";
{
    my $rngschema = XML::LibXML::RelaxNG->new( location => $file );
    ok ( $rngschema );
    
    eval { $rngschema = XML::LibXML::RelaxNG->new( location => $badfile ); };
    ok( $@ );
}

print "# 2 parse schema from a string\n";
{
    open RNGFILE, "<$file";
    my $string = join "", <RNGFILE>;
    close RNGFILE;

    my $rngschema = XML::LibXML::RelaxNG->new( string => $string );
    ok ( $rngschema );

    open RNGFILE, "<$badfile";
    $string = join "", <RNGFILE>;
    close RNGFILE;
    eval { $rngschema = XML::LibXML::RelaxNG->new( string => $string ); };
    ok( $@ );
}

print "# 3 parse schema from a document\n";
{
    my $doc       = $xmlparser->parse_file( $file );
    my $rngschema = XML::LibXML::RelaxNG->new( DOM => $doc );
    ok ( $rngschema );
   
    $doc       = $xmlparser->parse_file( $badfile );
    eval { $rngschema = XML::LibXML::RelaxNG->new( DOM => $doc ); };
    ok( $@ );
}

print "# 4 validate a document\n";
{
    my $doc       = $xmlparser->parse_file( $validfile );
    my $rngschema = XML::LibXML::RelaxNG->new( location => $file );

    my $valid = 0;
    eval { $valid = $rngschema->validate( $doc ); };
    ok( $valid, 0 );

    $doc       = $xmlparser->parse_file( $invalidfile );
    $valid     = 0;
    eval { $valid = $rngschema->validate( $doc ); };
    ok ( $@ );
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
  ok ($@);

  $rootElem->setAttribute('name', 'rootElem');
  eval{ $rng->validate($doc); };
  ok (!$@);

  $rootElem->appendChild($bogusElem);
  eval{$rng->validate($doc);};
  ok ($@);

  $bogusElem->unlinkNode();
  eval{$rng->validate($doc);};
  ok (!$@);

  $rootElem->removeAttribute('name');
  eval{$rng->validate($doc);};
  ok ($@);

}


} # Version >= 20510 test 
