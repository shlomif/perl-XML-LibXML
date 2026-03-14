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

sub handler_private {
  return join(",","private",@_);
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
my ($xml_out_private, $xml_out_global) = ($xml, $xml);
$xml_out_private =~ s{&a;}{private,http:///invalid-url,//foo/bar/b};
$xml_out_global =~ s{&a;}{global,http:///invalid-url,//foo/bar/b};

subtest "initial parse with private ext_ent_handler" => sub {
  my $parser = XML::LibXML->new({ expand_entities => 1, ext_ent_handler => \&handler_private });
  my $doc;
  eval { $doc = $parser->parse_string($xml); };
  my $err = $@;
  is($err || 0, 0, "error not set");
  is($doc && $doc->toString(), $xml_out_private, "document matches");
};

subtest "second parse without any handlers" => sub {
  my $parser = XML::LibXML->new({ expand_entities => 1 });
  my $doc;
  eval { $doc = $parser->parse_string($xml); };
  my $err = $@;
  like($err,qr/^http error/,"http error");
};

XML::LibXML::externalEntityLoader(sub { handler_global(@_) });

subtest "global ext_ent_handler overrides private ext_ent_handler" => sub {
  my $parser = XML::LibXML->new({ expand_entities => 1 });
  my $doc;
  eval { $doc = $parser->parse_string($xml); };
  my $err = $@;
  is($err || 0, 0, "error not set");
  is($doc && $doc->toString(), $xml_out_global, 'document matches' );
};

XML::LibXML::externalEntityLoader(undef);

subtest "afterwards parse with private ext_ent_handler" => sub {
  my $parser = XML::LibXML->new({ expand_entities => 1, ext_ent_handler => \&handler_private });
  my $doc;
  eval { $doc = $parser->parse_string($xml); };
  my $err = $@;
  is($err || 0, 0, "error not set");
  is($doc && $doc->toString(), $xml_out_private, "document matches");
};

subtest "afterwards parse without any handlers" => sub {
  my $parser = XML::LibXML->new({ expand_entities => 1 });
  my $doc;
  eval { $doc = $parser->parse_string($xml); };
  my $err = $@;
  like($err,qr/^http error/,"http error");
};
