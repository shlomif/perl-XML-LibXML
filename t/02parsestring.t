use Test;
use Devel::Peek;

BEGIN { plan tests => 13 };
use XML::LibXML;
ok(1);

my $parser = XML::LibXML->new();
ok($parser);
{
my $doc = $parser->parse_string(<<'EOT');
<test/>
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

eval { my $fail = $parser->parse_string(""); };
# warn "# $@\n";
ok($@);

## 
# phish: parse_xml_chunk tests

my $chunk = "foo<a>bar<b/>foobar</a>" ;
my $fragment = $parser->parse_xml_chunk( $chunk );
ok( $fragment );

my $doc = $parser->parse_string(<<'EOT');
<test/>
EOT

ok($doc);

my $r = $doc->getDocumentElement();
ok($r);

#warn "append fragment to dom\n";

$r->appendChild( $fragment );
# warn "appended!\n";
my $str = $r->toString();

# for some reason this does not work without an encoding ... 
ok( "$str", encodeToUTF8("iso-8859-1","<test>$chunk</test>") );

# bad fragment:

my $badchunk = "foo<bar>";
$fragment = $parser->parse_xml_chunk( $badchunk );
ok( !$fragment );

$badchunk = "foo</bar>foobar";
$fragment = $parser->parse_xml_chunk( $badchunk );
ok( !$fragment );

$badchunk = "";
eval {
    $fragment = $parser->parse_xml_chunk( $badchunk );
};
ok( !$fragment );

$badchunk = undef;
eval {
    local $^W; # turn off uninitialised value warnings
    $fragment = $parser->parse_xml_chunk( $badchunk );
};
ok( !$fragment );
