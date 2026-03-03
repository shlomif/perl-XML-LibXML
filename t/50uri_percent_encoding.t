# Test for GitHub issue #44:
# $document->URI is sometimes percent encoded, but not always
#
# libxml2 percent-encodes special characters in filenames that start with
# a digit (e.g., "1:b.xml" becomes "1%3Ab.xml"), but leaves other filenames
# alone. We work around this by preserving the original filename as the
# document URI.

use strict;
use warnings;

use Test::More;
use File::Temp qw(tempdir);
use Cwd qw(getcwd);
use XML::LibXML;

my $tmpdir = tempdir(CLEANUP => 1);
my $origdir = getcwd();

# chdir to tmpdir so we can use relative filenames
# (the bug only manifests with relative paths)
chdir $tmpdir or die "Cannot chdir to $tmpdir: $!";

# Test 1: filename starting with a digit and containing a colon
# This is the exact case from the bug report (issue #44)
{
    my $file = '1:b.xml';
    _write_file($file, '<root>1:b.xml</root>');
    my $dom = XML::LibXML->load_xml(location => $file);
    is($dom->URI, $file, 'URI preserves original filename with digit prefix and colon');
    unlink $file;
}

# Test 2: filename with percent-encoded characters (should stay as-is)
{
    my $file = '1%3Ab.xml';
    _write_file($file, '<root>1%3Ab.xml</root>');
    my $dom = XML::LibXML->load_xml(location => $file);
    is($dom->URI, $file, 'URI preserves filename with literal percent-encoded chars');
    unlink $file;
}

# Test 3: the two URIs should be different (core of the bug)
{
    my $file_colon = '1:c.xml';
    my $file_encoded = '1%3Ac.xml';
    _write_file($file_colon, '<root>colon</root>');
    _write_file($file_encoded, '<root>encoded</root>');

    my $dom_colon = XML::LibXML->load_xml(location => $file_colon);
    my $dom_encoded = XML::LibXML->load_xml(location => $file_encoded);

    isnt($dom_colon->URI, $dom_encoded->URI,
         'URIs for "1:c.xml" and "1%3Ac.xml" should differ');
    is($dom_colon->URI, $file_colon,
       'URI for 1:c.xml is the original filename');
    is($dom_encoded->URI, $file_encoded,
       'URI for 1%3Ac.xml is the original filename');

    unlink $file_colon, $file_encoded;
}

# Test 4: filename without digit prefix (should be unaffected by fix)
{
    my $file = 'normal.xml';
    _write_file($file, '<root>normal</root>');
    my $dom = XML::LibXML->load_xml(location => $file);
    is($dom->URI, $file, 'URI for normal filename is preserved');
    unlink $file;
}

# Test 5: parse_file method directly
{
    my $file = '2:test.xml';
    _write_file($file, '<root>test</root>');
    my $parser = XML::LibXML->new();
    my $dom = $parser->parse_file($file);
    is($dom->URI, $file, 'parse_file preserves original filename');
    unlink $file;
}

# Test 6: parse_html_file method
{
    my $file = '3:test.html';
    _write_file($file, '<html><body>test</body></html>');
    my $parser = XML::LibXML->new();
    my $dom = $parser->parse_html_file($file);
    is($dom->URI, $file, 'parse_html_file preserves original filename');
    unlink $file;
}

# Test 7: load_html with location
{
    my $file = '4:test.html';
    _write_file($file, '<html><body>test</body></html>');
    my $dom = XML::LibXML->load_html(location => $file, recover => 1);
    is($dom->URI, $file, 'load_html location preserves original filename');
    unlink $file;
}

# Test 8: setURI should still work after the fix
{
    my $file = '5:test.xml';
    _write_file($file, '<root>test</root>');
    my $dom = XML::LibXML->load_xml(location => $file);
    is($dom->URI, $file, 'URI initially correct');
    $dom->setURI('custom.xml');
    is($dom->URI, 'custom.xml', 'setURI still works');
    unlink $file;
}

chdir $origdir;
done_testing();

sub _write_file {
    my ($path, $content) = @_;
    open my $fh, '>', $path or die "Cannot write $path: $!";
    print {$fh} $content;
    close $fh;
}
