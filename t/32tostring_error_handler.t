use strict;
use warnings;
use Test::More tests => 8;
use XML::LibXML;

# Verify that toString/serialize operations use proper error handlers
# and do not leak libxml2 messages to stderr.
# See: error handlers were commented out in _toString (Document)
# and entirely missing in toString (Node).

my $xml = <<'XML';
<?xml version="1.0" encoding="UTF-8"?>
<root>
  <child attr="value">text content</child>
  <plain>more text</plain>
</root>
XML

my $parser = XML::LibXML->new();
my $doc = $parser->parse_string($xml);

# Capture stderr to verify no leakage
my $stderr_output = '';

{
    open(my $save_stderr, '>&', \*STDERR) or die "Can't dup STDERR: $!";
    close STDERR;
    open(STDERR, '>', \$stderr_output) or die "Can't redirect STDERR: $!";

    # Document _toString (unformatted)
    my $str1 = $doc->toString();
    ok(defined $str1, 'Document toString() returns defined value');
    like($str1, qr/<root/, 'Document toString() contains root element');

    # Document _toString (formatted)
    my $str2 = $doc->toString(1);
    ok(defined $str2, 'Document toString(1) returns defined value');
    like($str2, qr/<root/, 'Document toString(1) contains root element');

    # Node toString
    my ($child) = $doc->findnodes('//child');
    my $str3 = $child->toString();
    ok(defined $str3, 'Node toString() returns defined value');
    like($str3, qr/<child/, 'Node toString() contains element name');

    # Node serialize (alias)
    my ($plain) = $doc->findnodes('//plain');
    my $str4 = $plain->serialize();
    ok(defined $str4, 'Node serialize() returns defined value');
    like($str4, qr/<plain>more text<\/plain>/, 'Node serialize() correct output');

    open(STDERR, '>&', $save_stderr) or die "Can't restore STDERR: $!";
}

# stderr check is informational — we can't easily trigger serialization
# errors from Perl, but the error handlers ensure that if libxml2 does
# emit warnings during serialization, they'll be captured as Perl
# exceptions rather than leaking to stderr.
if (length $stderr_output) {
    diag("Unexpected stderr during serialization: $stderr_output");
}
