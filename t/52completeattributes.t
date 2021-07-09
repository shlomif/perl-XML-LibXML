use strict;
use warnings;

use Test::More 0.98;

my $dtdattr = << "END";
<?xml version="1.0"?>
<!DOCTYPE root [
<!ELEMENT root (elem)*>
<!ELEMENT elem EMPTY>
<!ATTLIST elem a (b | c) "b">
]>
<root>
	<elem/>
</root>
END

my $completed = << "END";
<?xml version="1.0"?>
<!DOCTYPE root [
<!ELEMENT root (elem)*>
<!ELEMENT elem EMPTY>
<!ATTLIST elem a (b | c) "b">
]>
<root>
	<elem a="b"/>
</root>
END

my $notcompleted = << "END";
<?xml version="1.0"?>
<!DOCTYPE root [
<!ELEMENT root (elem)*>
<!ELEMENT elem EMPTY>
<!ATTLIST elem a (b | c) "b">
]>
<root>
	<elem/>
</root>
END

use XML::LibXML;

my $parser = new XML::LibXML;
$parser->complete_attributes(1);

my $dom = $parser->load_xml(string => $dtdattr);
is($dom, $completed, "Complete attributes from DTD using setter");

$dom = XML::LibXML->load_xml(string => $dtdattr, complete_attributes => 1);
is($dom, $completed, "Complete attributes from DTD passing hash");

$dom = XML::LibXML->load_xml(string => $dtdattr, expand_entities => 1, complete_attributes => 1);
is($dom, $completed, "Complete attributes from DTD passing hash (+ another option)");

$dom = XML::LibXML->load_xml(string => $dtdattr, expand_entities => 1, complete_attributes => 0);
is($dom, $notcompleted, "Do not complete attributes (complete_attributes set to false)");

$dom = XML::LibXML->load_xml(string => $dtdattr, complete_attributes => 0);
is($dom, $notcompleted, "Do not complete attributes (only one option, complete_attributes set to false)");

$dom = XML::LibXML->load_xml(string => $dtdattr, expand_entities => 1);
is($dom, $notcompleted, "Do not complete attributes (one dtd related option, but complete_attributes not given)");

$dom = XML::LibXML->load_xml(string => $dtdattr);
is($dom, $notcompleted, "Do not complete attributes (no option)");


done_testing;

