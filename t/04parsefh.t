use Test;
BEGIN { plan tests => 4 };
use XML::LibXML;
use IO::File;
ok(1);

my $parser = XML::LibXML->new();
ok($parser);

my $fh = IO::File->new("example/dromeds.xml");

ok($fh);

my $doc = $parser->parse_fh($fh);

ok($doc);

# warn "doc is: ", $doc->toString, "\n";
