#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 1;

use XML::LibXML;

my $xml = <<'EOF';
<!DOCTYPE crash [
<!ATTLIST foo bar CDATA "baz">
]>
<crash/>
EOF

my $src = XML::LibXML->load_xml (string => $xml);
my $dest = XML::LibXML->load_xml (string => $xml);
my $src_dtd = $src->firstChild;
my $dest_dtd = $dest->firstChild;
$dest_dtd->replaceNode($src_dtd);

# TEST
ok(1, "Did not crash.");
