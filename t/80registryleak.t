
use strict;
use warnings;

use Test;
BEGIN { plan tests => 2; }
use XML::LibXML;

my $p = XML::LibXML->new();
ok($p);

my $xml = <<EOX;
<?xml version="1.0"?>
<root><child/></root>
EOX

{
my $doc = $p->parse_string($xml);
my $root = $doc->documentElement;
my $child = $root->firstChild;
}

ok(&XML::LibXML::_leaked_nodes == 0);
