use Test;
BEGIN { plan tests => 5 }
use XML::LibXML;
use IO::File;
ok(1);

my $html = "example/test.html";

my $parser = XML::LibXML->new();
{
    my $doc = $parser->parse_html_file($html);
    ok($doc);
}

my $fh = IO::File->new($html) || die "Can't open $html: $!";

my $string;
{
    local $/;
    $string = <$fh>;
}

seek($fh, 0, 0);

ok($string);

$doc = $parser->parse_html_string($string);

ok($doc);

undef $doc;

$doc = $parser->parse_html_fh($fh);

ok($doc);

#warn($doc->toStringHTML);

