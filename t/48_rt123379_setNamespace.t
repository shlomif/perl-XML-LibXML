use strict;
use warnings;

use XML::LibXML;
use Test::More tests => 8;

# TEST
ok(my $doc = XML::LibXML::Document->new(), 'new document');
# TEST
ok(my $elm = $doc->createElement('D:element'), 'create element');
# TEST
ok($elm->setAttribute('xmlns:D', 'attribute'), 'set attribute');
$doc->setDocumentElement($elm); # XXX does not return true if successful
# TEST
ok(my $str = $doc->toString(0), 'to string');
# TEST
ok(my $par = XML::LibXML->new(), 'new parser');
# TEST
ok( eval { $par->parse_string($str) } , 'parse string');
# TEST
is($@, "", 'parse error');
# TEST
like($str, qr{<D:element xmlns:D="attribute"/>}, 'xml element');
