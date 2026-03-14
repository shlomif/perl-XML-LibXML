use warnings;
use strict;

use Test::More;

use XML::LibXML;

use IO::Handle;

STDOUT->autoflush(1);
STDERR->autoflush(1);

if (XML::LibXML::LIBXML_VERSION() < 20627)
{
    plan skip_all => "skipping for libxml2 < 2.6.27";
}
else
{
    plan tests => 5;
}

sub handler_global {
  return join(",","global",@_);
}


my $xml = <<'EOF';
<?xml version="1.0"?>
<!DOCTYPE foo [
<!ENTITY a PUBLIC "//foo/bar/b" "http:///invalid-url">
]>
<root>
  <a>&a;</a>
</root>
EOF
my ($xml_out_global) = ($xml);
$xml_out_global =~ s{&a;}{global,http:///invalid-url,//foo/bar/b};

subtest "initial parse with network" => sub {
  my $parser = XML::LibXML->new({ expand_entities => 1 });
  my ($doc);
  eval { $doc = $parser->parse_string($xml); };
  my $err = $@;
  like($err, qr/^http error/, "http error");
  is($doc, undef, "doc is undef");
};

is (XML::LibXML::externalEntityLoader(sub { handler_global(@_) }), undef, "previous handler is undef");

subtest "parse with global ext_ent_handler" => sub {
  my $parser = XML::LibXML->new({ expand_entities => 1 });
  my ($doc);
  eval { $doc = $parser->parse_string($xml); };
  my $err = $@;
  is($err || 0, 0, "error not set");
  is($doc && $doc->toString(), $xml_out_global, "document matches");
};

is(ref(XML::LibXML::externalEntityLoader(undef)), "CODE", "previous handler is code ref");

subtest "afterwards parse without network" => sub {
  my $parser = XML::LibXML->new({ expand_entities => 1, no_network => 1 });
  my ($doc);
  eval { $doc = $parser->parse_string($xml); };
  my $err = $@;
  like($err, qr/^I\/O error/, "no_network error");
  is($doc, undef, "doc is undef");
};
