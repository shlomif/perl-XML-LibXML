use Test;
use Devel::Peek;

BEGIN { plan tests => 10 };
use XML::LibXML;
ok(1);

my $parser = XML::LibXML->new();
ok($parser);
{
my $doc = $parser->parse_string(<<'EOT');
<xml/>
EOT

ok($doc);
}

eval {
    my $fail = $parser->parse_string(<<'EOT');
<foo>&</foo>
EOT
};
ok($@);

# warn "doc is: ", $doc2->toString, "\n";

## 
# phish: parse_xml_chunk tests

my $chunk = "foo<a>bar<b/>foobar</a>" ;
my $fragment = $parser->parse_xml_chunk( $chunk );
ok( $fragment );

my $doc = $parser->parse_string(<<'EOT');
<xml/>
EOT

ok($doc);

my $r = $doc->getDocumentElement();
ok($r);

#warn "append fragment to dom\n";

$r->appendChild( $fragment );
# warn "appended!\n";
# warn $r->toString();
ok( $r->toString(), "<xml>$chunk</xml>" );

# bad fragment:

my $badchunk = "foo<bar>";
$fragment = $parser->parse_xml_chunk( $badchunk );
ok( !$fragment );

$badchunk = "foo</bar>foobar";
$fragment = $parser->parse_xml_chunk( $badchunk );
ok( !$fragment );
