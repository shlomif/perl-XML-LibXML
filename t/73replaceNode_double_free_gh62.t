use strict;
use warnings;
use Test::More tests => 8;
use XML::LibXML;

# GH#62: replaceNode() use-after-free when parent proxy has no Perl reference
#
# The bug: replaceNode cached the old node's owner proxy before calling
# LibXML_reparent_removed_node(). That call could free the parent proxy
# (when its Perl refcount dropped to zero), leaving a dangling pointer.
# The subsequent PmmFixOwner then used freed memory -> segfault.

# Test 1-2: Original issue — Element->new (no document), parent not held
{
    my $dom;
    my $foo;

    sub setup_no_parent_ref {
        $dom = XML::LibXML::Document->new;
        my $root = $dom->createElement('root');
        $dom->setDocumentElement($root);
        $foo = XML::LibXML::Element->new('foo');
        $root->appendChild($foo);
        # $root goes out of scope — its proxy may be freed
    }

    setup_no_parent_ref();
    my $bar = XML::LibXML::Element->new('bar');
    $foo->replaceNode($bar);
    undef $bar;

    ok(1, 'replaceNode with Element->new — no crash after undef replacement');
    is($dom->documentElement->toString, '<root><bar/></root>',
        'replacement node is correctly in the tree');
    undef $foo;
    undef $dom;
}

# Test 3-4: replaceNode where replacement node is from same document
{
    my $dom;
    my $foo;

    sub setup_same_doc {
        $dom = XML::LibXML::Document->new;
        my $root = $dom->createElement('root');
        $dom->setDocumentElement($root);
        $foo = $dom->createElement('foo');
        $root->appendChild($foo);
    }

    setup_same_doc();
    my $bar = $dom->createElement('bar');
    $foo->replaceNode($bar);
    undef $bar;

    ok(1, 'replaceNode with createElement (same doc) — no crash');
    is($dom->documentElement->toString, '<root><bar/></root>',
        'same-doc replacement is correct');
    undef $foo;
    undef $dom;
}

# Test 5-6: replacement node survives after document ref is dropped
{
    my $dom = XML::LibXML::Document->new;
    my $root = $dom->createElement('root');
    $dom->setDocumentElement($root);
    my $foo = XML::LibXML::Element->new('foo');
    $root->appendChild($foo);

    my $bar = XML::LibXML::Element->new('bar');
    $foo->replaceNode($bar);

    undef $foo;
    undef $dom;
    # $bar should still be accessible — the document must stay alive
    # because $bar's proxy holds a reference to it
    is($bar->nodeName, 'bar',
        'replacement node accessible after document ref dropped');
    ok($bar->ownerDocument, 'replacement node still has an owner document');
}

# Test 7-8: replaceNode with children on the replacement node
{
    my $dom;
    my $foo;

    sub setup_with_children {
        $dom = XML::LibXML::Document->new;
        my $root = $dom->createElement('root');
        $dom->setDocumentElement($root);
        $foo = XML::LibXML::Element->new('foo');
        $root->appendChild($foo);
    }

    setup_with_children();
    my $bar = XML::LibXML::Element->new('bar');
    my $child = XML::LibXML::Element->new('child');
    $bar->appendChild($child);
    $foo->replaceNode($bar);
    undef $bar;
    undef $child;

    ok(1, 'replaceNode with child elements — no crash');
    is($dom->documentElement->toString, '<root><bar><child/></bar></root>',
        'replacement with children is correct');
    undef $foo;
    undef $dom;
}
