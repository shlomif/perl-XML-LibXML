use Test;
BEGIN { plan tests => 5 };
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

eval {
    $parser->parse_file("does_not_exist.xml");
};
ok($@);

# warn "doc is: ", $doc->toString, "\n";
