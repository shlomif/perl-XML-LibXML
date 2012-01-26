use strict;
use warnings;
use Test::More tests => 6;
use XML::LibXML;

my $root = XML::LibXML->load_xml( IO => \*DATA )->documentElement;

isa_ok
	$root->[0],
	'XML::LibXML::Text',
	'text nodes in array deref';

isa_ok
	$root->[1],
	'XML::LibXML::Element',
	'element nodes in array deref';

is
	$root->[1]{'attr1'},
	'foo',
	'non-namespaced attribute';

is
	$root->[1]{'{http://localhost/}attr2'},
	'bar',
	'namespaced attribute';

is
	$root->[3][0]->textContent,
	'Hello world',
	'more deeply nested';

is
	$root->[3]{'attr1'},
	'baz',
	'things can overload @{} and %{} simultaneously';

__DATA__
<root>
	<elem1 attr1="foo" xmlns:x="http://localhost/" x:attr2="bar" />
	<elem2 attr1="baz">Hello world</elem2>
</root>
