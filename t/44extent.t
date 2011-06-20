# Test file created outside of h2xs framework.
# Run this like so: `perl 44extent.t'
#   pajas@ufal.mff.cuni.cz     2009/09/24 13:18:43

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test;
BEGIN { plan tests => 7 };

use warnings;
use strict;
use XML::LibXML;
$|=1;

if (20627 > XML::LibXML::LIBXML_VERSION) {
    skip("skipping for libxml2 < 2.6.27") for 1..7;
} else {

my $parser = XML::LibXML->new({
  expand_entities => 1,
  ext_ent_handler => \&handler,
});

sub handler {
  return join(",",@_);
}

my $xml = <<'EOF';
<?xml version="1.0"?>
<!DOCTYPE foo [
<!ENTITY a PUBLIC "//foo/bar/b" "file:/dev/null">
<!ENTITY b SYSTEM "file:///dev/null">
]>
<root>
  <a>&a;</a>
  <b>&b;</b>
</root>
EOF
my $xml_out = $xml;
$xml_out =~ s{&a;}{file:/dev/null,//foo/bar/b};
$xml_out =~ s{&b;}{file:///dev/null,};

my $doc = $parser->parse_string($xml);

ok( $doc->toString() eq $xml_out );

my $xml_out2 = $xml; $xml_out2 =~ s{&[ab];}{<!-- -->}g;

$parser->set_option( ext_ent_handler => sub { return '<!-- -->' } );
$doc = $parser->parse_string($xml);
ok( $doc->toString() eq $xml_out2 );

$parser->set_option( ext_ent_handler=>sub{ '' } );
$parser->set_options({
  expand_entities => 0,
  recover => 2,
});
$doc = $parser->parse_string($xml);
ok( $doc->toString() eq $xml );

foreach my $el ($doc->findnodes('/root/*')) {
  ok ($el->hasChildNodes);
  ok ($el->firstChild->nodeType == XML_ENTITY_REF_NODE);
}

#########################

# Insert your test code below, the Test::More module is used here so read
# its man page ( perldoc Test::More ) for help writing this test script.


}