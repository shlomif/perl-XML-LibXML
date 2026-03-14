use strict;
use warnings;
use Test::More tests => 9;

use XML::LibXML;

# GH#50 - Parse HTML string crashes on invalid charset meta
#
# When an HTML document contains a meta tag like:
#   <meta content="text/html; charset=UTF-8; X-Content-Type-Options=nosniff" ...>
# libxml2 extracts the entire value after "charset=" as the encoding,
# including semicolons and extra parameters. This invalid encoding causes
# serialization to fail with an "output error" on stderr.

my $parser = XML::LibXML->new();
$parser->recover_silently(1);

# Test 1-3: Original bug report - charset with extra Content-Type params
{
    my $html = q~<!DOCTYPE html>
<html lang="en">
<head>
<meta content="text/html; charset=UTF-8; X-Content-Type-Options=nosniff" http-equiv="Content-Type" />
</head>
<body>
</body>
</html>~;

    my $dom = $parser->parse_html_string($html, { no_network => 1 });
    ok(defined $dom, "parse succeeds with bogus charset in meta tag");
    is($dom->encoding, "UTF-8", "encoding sanitized to UTF-8");

    my $output = $dom->serialize();
    ok(length($output) > 0, "serialize produces non-empty output");
}

# Test 4-5: Normal charset should be unaffected
{
    my $html = q~<!DOCTYPE html>
<html><head>
<meta content="text/html; charset=UTF-8" http-equiv="Content-Type" />
</head><body>hello</body></html>~;

    my $dom = $parser->parse_html_string($html, { no_network => 1 });
    ok(defined $dom, "parse succeeds with normal charset");
    is($dom->encoding, "UTF-8", "normal charset preserved");
}

# Test 6-7: iso-8859-1 with extra params
{
    my $html = q~<!DOCTYPE html>
<html><head>
<meta content="text/html; charset=iso-8859-1; boundary=something" http-equiv="Content-Type" />
</head><body>hello</body></html>~;

    my $dom = $parser->parse_html_string($html, { no_network => 1 });
    ok(defined $dom, "parse succeeds with iso-8859-1 + extra params");
    is($dom->encoding, "iso-8859-1", "encoding sanitized to iso-8859-1");
}

# Test 8-9: Serialization round-trip produces valid output
{
    my $html = q~<!DOCTYPE html>
<html><head>
<meta content="text/html; charset=UTF-8; X-Content-Type-Options=nosniff" http-equiv="Content-Type" />
</head><body><p>test content</p></body></html>~;

    my $dom = $parser->parse_html_string($html, { no_network => 1 });
    my $output = $dom->serialize();
    like($output, qr/test content/, "serialized output contains body text");

    # Re-parse the serialized output to verify it's valid
    my $dom2 = $parser->parse_html_string($output, { no_network => 1 });
    ok(defined $dom2, "re-parsed serialized output successfully");
}
