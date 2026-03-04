use strict;
use warnings;

use Test::More tests => 44;

use XML::LibXML;
use XML::LibXML::AttributeHash;

my $NS = 'http://example.com/ns';

# ================================================================
# Helper: create a fresh element with attributes
# ================================================================

sub make_element {
    my $doc = XML::LibXML::Document->new('1.0', 'UTF-8');
    my $root = $doc->createElement('root');
    $doc->setDocumentElement($root);
    $root->setAttribute('plain', 'value1');
    $root->setAttributeNS($NS, 'pfx:nsattr', 'value2');
    return $root;
}

# ================================================================
# TIEHASH and basic construction
# ================================================================

{
    my $elem = make_element();
    tie my %hash, 'XML::LibXML::AttributeHash', $elem;

    ok(tied(%hash), 'tie succeeds');
    isa_ok(tied(%hash), 'XML::LibXML::AttributeHash', 'tied to correct class');
}

# ================================================================
# element() accessor
# ================================================================

{
    my $elem = make_element();
    tie my %hash, 'XML::LibXML::AttributeHash', $elem;
    my $tied = tied(%hash);
    is($tied->element, $elem, 'element() returns original element');
}

# ================================================================
# from_clark() parsing
# ================================================================

{
    my $elem = make_element();
    my $ah = tied(%{ $elem }); # use overloading
    isa_ok($ah, 'XML::LibXML::AttributeHash');

    my ($ns, $local) = $ah->from_clark('{http://example.com}foo');
    is($ns, 'http://example.com', 'from_clark extracts namespace');
    is($local, 'foo', 'from_clark extracts local name');

    my ($ns2, $local2) = $ah->from_clark('bar');
    is($ns2, undef, 'from_clark returns undef ns for plain name');
    is($local2, 'bar', 'from_clark returns plain name');
}

# ================================================================
# to_clark() formatting
# ================================================================

{
    my $elem = make_element();
    my $ah = tied(%{ $elem });

    is($ah->to_clark('http://example.com', 'foo'), '{http://example.com}foo',
       'to_clark with namespace');
    is($ah->to_clark(undef, 'bar'), 'bar',
       'to_clark without namespace');
}

# ================================================================
# FETCH - non-namespaced and namespaced
# ================================================================

{
    my $elem = make_element();
    tie my %hash, 'XML::LibXML::AttributeHash', $elem;

    is($hash{'plain'}, 'value1', 'FETCH non-namespaced');
    is($hash{"{$NS}nsattr"}, 'value2', 'FETCH namespaced');
    is($hash{'nonexistent'}, undef, 'FETCH missing attribute returns undef');
}

# ================================================================
# STORE - non-namespaced and namespaced
# ================================================================

{
    my $elem = make_element();
    tie my %hash, 'XML::LibXML::AttributeHash', $elem;

    # Update existing
    $hash{'plain'} = 'updated';
    is($elem->getAttribute('plain'), 'updated', 'STORE updates existing attr');

    # Create new
    $hash{'newattr'} = 'newval';
    is($elem->getAttribute('newattr'), 'newval', 'STORE creates new attr');

    # Namespaced store
    my $NS2 = 'http://other.example.com';
    $hash{"{$NS2}other"} = 'nsval';
    is($elem->getAttributeNS($NS2, 'other'), 'nsval', 'STORE namespaced creates attr');
}

# ================================================================
# EXISTS
# ================================================================

{
    my $elem = make_element();
    tie my %hash, 'XML::LibXML::AttributeHash', $elem;

    ok(exists $hash{'plain'}, 'EXISTS for present attr');
    ok(!exists $hash{'missing'}, 'EXISTS for absent attr');
    ok(exists $hash{"{$NS}nsattr"}, 'EXISTS for namespaced attr');
    ok(!exists $hash{"{$NS}missing"}, 'EXISTS for absent namespaced attr');
}

# ================================================================
# DELETE
# ================================================================

{
    my $elem = make_element();
    tie my %hash, 'XML::LibXML::AttributeHash', $elem;

    ok(exists $hash{'plain'}, 'attr exists before delete');
    delete $hash{'plain'};
    ok(!exists $hash{'plain'}, 'DELETE removes non-namespaced attr');
    ok(!$elem->hasAttribute('plain'), 'element confirms deletion');

    # Namespaced delete
    ok(exists $hash{"{$NS}nsattr"}, 'ns attr exists before delete');
    delete $hash{"{$NS}nsattr"};
    ok(!exists $hash{"{$NS}nsattr"}, 'DELETE removes namespaced attr');
    ok(!$elem->hasAttributeNS($NS, 'nsattr'), 'element confirms ns deletion');
}

# ================================================================
# FIRSTKEY / NEXTKEY (iteration with each/keys)
# ================================================================

{
    my $elem = make_element();
    tie my %hash, 'XML::LibXML::AttributeHash', $elem;

    my @keys = sort keys %hash;
    ok(scalar @keys >= 2, 'keys returns at least 2 keys');
    ok((grep { $_ eq 'plain' } @keys), 'keys includes plain attr');
    ok((grep { $_ eq "{$NS}nsattr" } @keys), 'keys includes namespaced attr');
}

{
    my $elem = make_element();
    tie my %hash, 'XML::LibXML::AttributeHash', $elem;

    my %collected;
    while (my ($k, $v) = each %hash) {
        $collected{$k} = $v;
    }
    is($collected{'plain'}, 'value1', 'each yields correct non-ns value');
    is($collected{"{$NS}nsattr"}, 'value2', 'each yields correct ns value');
}

# ================================================================
# SCALAR
# ================================================================

{
    my $elem = make_element();
    tie my %hash, 'XML::LibXML::AttributeHash', $elem;
    my $scalar = tied(%hash)->SCALAR;
    is($scalar, $elem, 'SCALAR returns element');
}

# ================================================================
# CLEAR
# ================================================================

{
    my $elem = make_element();
    tie my %hash, 'XML::LibXML::AttributeHash', $elem;

    ok(scalar keys %hash >= 2, 'has attributes before clear');
    %hash = ();
    is(scalar keys %hash, 0, 'CLEAR removes all attributes');
    ok(!$elem->hasAttribute('plain'), 'element has no plain attr after clear');
    ok(!$elem->hasAttributeNS($NS, 'nsattr'), 'element has no ns attr after clear');
}

# ================================================================
# all_keys() method
# ================================================================

{
    my $elem = make_element();
    my $ah = tied(%{ $elem });

    my @keys = $ah->all_keys;
    ok(scalar @keys >= 2, 'all_keys returns keys');
    # Keys should be sorted
    my @sorted = sort @keys;
    is_deeply(\@keys, \@sorted, 'all_keys returns sorted keys');
}

# ================================================================
# weaken option
# ================================================================

SKIP: {
    eval { require Scalar::Util; Scalar::Util->import('weaken'); 1 }
        or skip 'Scalar::Util::weaken not available', 2;

    my $elem = make_element();
    tie my %hash, 'XML::LibXML::AttributeHash', $elem, weaken => 1;
    ok(tied(%hash), 'tie with weaken option');
    is($hash{'plain'}, 'value1', 'FETCH works with weaken option');
}

# ================================================================
# Overloaded hash dereference on Element
# ================================================================

{
    my $elem = make_element();

    # Direct hash access via overloading
    is($elem->{'plain'}, 'value1', 'overloaded hash FETCH');

    $elem->{'plain'} = 'overloaded';
    is($elem->getAttribute('plain'), 'overloaded', 'overloaded hash STORE');

    ok(exists $elem->{'plain'}, 'overloaded hash EXISTS');

    $elem->{'temp'} = 'tmp';
    delete $elem->{'temp'};
    ok(!$elem->hasAttribute('temp'), 'overloaded hash DELETE');
}
