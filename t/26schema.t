# $Id$

##
# Testcases for the XML Schema interface
#

use strict;
use warnings;

use lib './t/lib';
use TestHelpers;

use Test::More;

use XML::LibXML;

if ( XML::LibXML::LIBXML_VERSION >= 20510 ) {
    plan tests => 8;
}
else {
    plan skip_all => 'No Schema Support compiled.';
}

my $xmlparser = XML::LibXML->new();

my $file         = "test/schema/schema.xsd";
my $badfile      = "test/schema/badschema.xsd";
my $validfile    = "test/schema/demo.xml";
my $invalidfile  = "test/schema/invaliddemo.xml";


# 1 parse schema from a file
{
    my $rngschema = XML::LibXML::Schema->new( location => $file );
    # TEST
    ok ( $rngschema, 'Good XML::LibXML::Schema was initialised' );

    eval { $rngschema = XML::LibXML::Schema->new( location => $badfile ); };
    # TEST
    ok( $@, 'Bad XML::LibXML::Schema throws an exception.' );
}

# 2 parse schema from a string
{
    my $string = slurp($file);

    my $rngschema = XML::LibXML::Schema->new( string => $string );
    # TEST
    ok ( $rngschema, 'RNG Schema initialized from string.' );

    $string = slurp($badfile);
    eval { $rngschema = XML::LibXML::Schema->new( string => $string ); };
    # TEST
    ok( $@, 'Bad string schema throws an excpetion.' );
}

# 3 validate a document
{
    my $doc       = $xmlparser->parse_file( $validfile );
    my $rngschema = XML::LibXML::Schema->new( location => $file );

    my $valid = 0;
    eval { $valid = $rngschema->validate( $doc ); };
    # TEST
    is( $valid, 0, 'validate() returns 0 to indicate validity of valid file.' );

    $doc       = $xmlparser->parse_file( $invalidfile );
    $valid     = 0;
    eval { $valid = $rngschema->validate( $doc ); };
    # TEST
    ok ( $@, 'Invalid file throws an excpetion.');
}

# 4 validate a node
{
    my $doc = $xmlparser->load_xml(string => <<'EOF');
<shiporder orderid="889923">
  <orderperson>John Smith</orderperson>
  <shipto>
    <name>Ola Nordmann</name>
  </shipto>
</shiporder>
EOF

    my $schema = XML::LibXML::Schema->new(string => <<'EOF');
<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
  <xs:element name="shiporder">
    <xs:complexType>
      <xs:sequence>
        <xs:element name="orderperson" type="xs:string"/>
        <xs:element ref="shipto"/>
      </xs:sequence>
      <xs:attribute name="orderid" type="xs:string" use="required"/>
    </xs:complexType>
  </xs:element>
  <xs:element name="shipto">
    <xs:complexType>
      <xs:sequence>
        <xs:element name="name" type="xs:string"/>
      </xs:sequence>
    </xs:complexType>
  </xs:element>
</xs:schema>
EOF

    my $nodelist = $doc->findnodes('/shiporder/shipto');
    my $result = 1;
    eval { $result = $schema->validate($nodelist->get_node(1)); };
    # TEST
    is( $@, '', 'validate() with element doesn\'t throw' );
    # TEST
    is( $result, 0, 'validate() with element returns 0' );
}

