use strict;
use warnings;

use XML::LibXML;
use Test::More tests => 8;

ok(my $doc = XML::LibXML::Document->new(), 'new document');
ok(my $elm = $doc->createElement('D:element'), 'create element');
ok($elm->setAttribute('xmlns:D', 'attribute'), 'set attribute');
$doc->setDocumentElement($elm); # XXX does not return true if successful
ok(my $str = $doc->toString(0), 'to string');
ok(my $par = XML::LibXML->new(), 'new parser');
ok( eval { $par->parse_string($str) } , 'parse string');
is($@, "", 'parse error');
like($str, qr{<D:element xmlns:D="attribute"/>}, 'xml element');
