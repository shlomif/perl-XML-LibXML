use Test;
BEGIN { plan tests => 4 };
use XML::LibXML;
ok(1);

my $parser = XML::LibXML->new();
ok($parser);

my $doc = $parser->parse_string(<<'EOT');
<xml/>
EOT

ok($doc);

eval {
    my $fail = $parser->parse_string(<<'EOT');
<foo>&</foo>
EOT
};
ok($@);

# warn "doc is: ", $doc2->toString, "\n";
