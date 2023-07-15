#!/usr/bin/perl
#
# Having 'XML_PARSE_HUGE' enabled can make an application vulnerable to
# denial of service through entity expansion attacks.  This test script
# confirms that huge document mode is disabled by default and that this
# does not adversely affect expansion of sensible entity definitions.
#

use strict;
use warnings;

use Test::More;

use XML::LibXML;

if (XML::LibXML::LIBXML_VERSION() < 20700) {
    plan skip_all => "XML_PARSE_HUGE option not supported for libxml2 < 2.7.0";
}
else {
    plan tests => 5;
}

my $benign_xml = <<'EOF';
<?xml version="1.0"?>
<!DOCTYPE lolz [
  <!ENTITY lol "haha">
]>
<lolz>&lol;</lolz>
EOF

my $evil_xml = <<'EOF';
<!DOCTYPE root [
  <!ENTITY ha "Ha !">
  <!ENTITY ha2 "&ha; &ha;">
EOF

foreach my $i (2 .. 47)
{
    $evil_xml .= sprintf(qq#  <!ENTITY ha%d "&ha%d; &ha%d;">\n#, $i+1, $i, $i);
}

$evil_xml .= <<'EOF';
]>
<root>&ha48;</root>
EOF

my ($parser, $doc, $err);

$parser = XML::LibXML->new;
#$parser->set_option(huge => 0);
# TEST
ok(!$parser->get_option('huge'), "huge mode disabled by default");

$doc = eval { $parser->parse_string($evil_xml); };

$err = $@;

# TEST
isnt("$err", "", "exception thrown during parse");
# TEST
like($err, qr/entity/si, "exception refers to entity maximum loop (libxml2 <= 2.10) or depth (>= 2.11)");


$parser = XML::LibXML->new;

$doc = eval { $parser->parse_string($benign_xml); };

$err = $@;

# TEST
is("$err", "", "no exception thrown during parse");

my $body = $doc->findvalue( '/lolz' );
# TEST
is($body, 'haha', 'entity was parsed and expanded correctly');

exit;

