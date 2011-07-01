
use strict;
use warnings;

use Test::More tests => 13;

use XML::LibXML;
use IO::Handle;

# TEST
ok(1, ' TODO : Add test name');

my $dom = XML::LibXML->new->parse_fh(*DATA);

# TEST
ok($dom, ' TODO : Add test name');

my @nodelist = $dom->findnodes('//BBB');

# TEST
is(scalar(@nodelist), 5, ' TODO : Add test name');

my $nodelist = $dom->findnodes('//BBB');
# TEST
is($nodelist->size, 5, ' TODO : Add test name');

# TEST
is($nodelist->string_value, "OK", ' TODO : Add test name'); # first node in set

# TEST
is($nodelist->to_literal, "OKNOT OK", ' TODO : Add test name');

{
    my $other_nodelist = $dom->findnodes('//BBB');
    while ($other_nodelist->to_literal() !~ m/\ANOT OK/)
    {
        $other_nodelist->shift();
    }

    # This is a test for:
    # https://rt.cpan.org/Ticket/Display.html?id=57737

    # TEST
    ok (scalar(($other_nodelist) lt ($nodelist)), "Comparison is OK.");

    # TEST
    ok (scalar(($nodelist) gt ($other_nodelist)), "Comparison is OK.");
}

# TEST
is($dom->findvalue("//BBB"), "OKNOT OK", ' TODO : Add test name');

# TEST
is(ref($dom->find("1 and 2")), "XML::LibXML::Boolean", ' TODO : Add test name');

# TEST
is(ref($dom->find("'Hello World'")), "XML::LibXML::Literal", ' TODO : Add test name');

# TEST
is(ref($dom->find("32 + 13")), "XML::LibXML::Number", ' TODO : Add test name');

# TEST
is(ref($dom->find("//CCC")), "XML::LibXML::NodeList", ' TODO : Add test name');

__DATA__
<AAA>
<BBB>OK</BBB>
<CCC/>
<BBB/>
<DDD><BBB/></DDD>
<CCC><DDD><BBB/><BBB>NOT OK</BBB></DDD></CCC>
</AAA>
