use strict;
use warnings;

use Test::More tests => 3;

use XML::LibXML;

sub test_one {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ($ns, $name) = @_;
    my $doc = XML::LibXML::Document->new;
    my $foo = $doc->createElement('foo');
    $foo->appendChild(
        # we need to access the aliased SV directly, assigning it to a
        # different variable hides the problem
        $doc->createElementNS( $$ns, 'bar' ),
    );

    return is(
        $foo->toString,
        qq[<foo><bar xmlns="$$ns"/></foo>],
        "$name: namespace should be in force",
    );
}

my $ns1 = \'urn:a';
my $ns2 = \substr($$ns1, 0);

# TEST
test_one $ns1, 'plain scalar';
# TEST
test_one $ns2, 'magic scalar';
# TEST
test_one \"$$ns2", 'copy of magic scalar';
