use Test;
BEGIN { plan tests => 4 };
use XML::LibXML;
ok(1);

my $parser = XML::LibXML->new();
ok($parser);

my $doc = $parser->parse_file("example/dromeds.xml");

ok($doc);

eval {
    $parser->parse_file("example/bad.xml");
};
ok($@);

# warn "doc is: ", $doc->toString, "\n";
