use Test;
BEGIN { plan tests => 6 };
use XML::LibXML;
use IO::File;
ok(1);

my $parser = XML::LibXML->new();
ok($parser);

my $fh = IO::File->new("example/dromeds.xml");

ok($fh);

my $doc = $parser->parse_fh($fh);

ok($doc);

$fh = IO::File->new("example/bad.xml");

ok($fh);

eval {
    my $doc = $parser->parse_fh($fh);
};
ok($@);

