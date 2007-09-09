use Test;
BEGIN { plan tests => 3}
END { ok(0) unless $loaded }
use XML::LibXML;
$loaded = 1;
ok(1);

my $p = XML::LibXML->new();
ok($p);

ok(XML::LibXML::LIBXML_VERSION, XML::LibXML::LIBXML_RUNTIME_VERSION);

# warn "# $tstr2\n";
