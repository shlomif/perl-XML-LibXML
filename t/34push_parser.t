use strict;
use warnings;

use Test::More tests => 31;

use XML::LibXML;

# ================================================================
# Basic push parsing workflow
# ================================================================

{
    my $parser = XML::LibXML->new;

    # Simple single-chunk push
    $parser->push('<root/>');
    my $doc = $parser->finish_push;
    isa_ok($doc, 'XML::LibXML::Document', 'single-chunk push parse');
    is($doc->documentElement->nodeName, 'root', 'root element name');
}

{
    my $parser = XML::LibXML->new;

    # Multi-chunk push: element split across chunks
    $parser->push('<root');
    $parser->push('>');
    $parser->push('<child/>');
    $parser->push('</root>');
    my $doc = $parser->finish_push;
    isa_ok($doc, 'XML::LibXML::Document', 'multi-chunk push parse');

    my @children = $doc->documentElement->childNodes;
    is(scalar @children, 1, 'one child element');
    is($children[0]->nodeName, 'child', 'child element name');
}

# ================================================================
# init_push / push / finish_push explicit workflow
# ================================================================

{
    my $parser = XML::LibXML->new;
    $parser->init_push;

    $parser->push('<doc>');
    $parser->push('<item id="1">first</item>');
    $parser->push('<item id="2">second</item>');
    $parser->push('</doc>');

    my $doc = $parser->finish_push;
    isa_ok($doc, 'XML::LibXML::Document', 'init_push/push/finish_push');

    my @items = $doc->findnodes('//item');
    is(scalar @items, 2, 'found 2 item elements');
    is($items[0]->getAttribute('id'), '1', 'first item id');
    is($items[1]->textContent, 'second', 'second item text');
}

# ================================================================
# Push parsing with text content split across chunks
# ================================================================

{
    my $parser = XML::LibXML->new;
    $parser->init_push;

    $parser->push('<msg>Hello');
    $parser->push(' World');
    $parser->push('</msg>');

    my $doc = $parser->finish_push;
    is($doc->documentElement->textContent, 'Hello World',
       'text content merged across chunks');
}

# ================================================================
# Push parsing with attributes
# ================================================================

{
    my $parser = XML::LibXML->new;
    $parser->push('<root attr="value" xmlns:ns="http://example.com" ns:foo="bar"/>');
    my $doc = $parser->finish_push;

    my $root = $doc->documentElement;
    is($root->getAttribute('attr'), 'value', 'non-namespaced attribute');
    is($root->getAttributeNS('http://example.com', 'foo'), 'bar',
       'namespaced attribute via push parse');
}

# ================================================================
# Push parsing with CDATA sections
# ================================================================

{
    my $parser = XML::LibXML->new;
    $parser->push('<root><![CDATA[some <special> & content]]></root>');
    my $doc = $parser->finish_push;

    my @children = $doc->documentElement->childNodes;
    is($children[0]->nodeType, XML::LibXML::XML_CDATA_SECTION_NODE,
       'CDATA section preserved in push parse');
    is($children[0]->textContent, 'some <special> & content',
       'CDATA content correct');
}

# ================================================================
# Push parsing with comments and PIs
# ================================================================

{
    my $parser = XML::LibXML->new;
    $parser->push('<?xml version="1.0"?>');
    $parser->push('<!-- a comment -->');
    $parser->push('<?mypi data?>');
    $parser->push('<root/>');
    my $doc = $parser->finish_push;

    my @children = $doc->childNodes;
    # Find comment and PI among child nodes
    my @comments = grep { $_->nodeType == XML::LibXML::XML_COMMENT_NODE } @children;
    my @pis = grep { $_->nodeType == XML::LibXML::XML_PI_NODE } @children;

    is(scalar @comments, 1, 'comment node found');
    is($comments[0]->textContent, ' a comment ', 'comment content');
    is(scalar @pis, 1, 'PI node found');
    is($pis[0]->nodeName, 'mypi', 'PI target name');
}

# ================================================================
# Push parsing error handling
# ================================================================

{
    my $parser = XML::LibXML->new;
    $parser->push('<root>');
    $parser->push('<unclosed>');

    my $doc;
    eval { $doc = $parser->finish_push; };
    ok($@, 'finish_push dies on malformed XML');
}

# ================================================================
# Push parsing with recovery mode
# ================================================================

{
    my $parser = XML::LibXML->new;
    $parser->init_push;
    $parser->push('<root>');
    $parser->push('<unclosed>text');

    my $doc;
    {
        local $SIG{'__WARN__'} = sub { };
        eval { $doc = $parser->finish_push(1); };
    }
    isa_ok($doc, 'XML::LibXML::Document', 'recovery mode produces document');
}

# ================================================================
# Multiple sequential push parses with same parser
# ================================================================

{
    my $parser = XML::LibXML->new;

    # First parse
    $parser->push('<first/>');
    my $doc1 = $parser->finish_push;
    is($doc1->documentElement->nodeName, 'first', 'first sequential parse');

    # Second parse
    $parser->push('<second/>');
    my $doc2 = $parser->finish_push;
    is($doc2->documentElement->nodeName, 'second', 'second sequential parse');

    # They should be independent documents
    isnt($doc1, $doc2, 'sequential parses produce different documents');
}

# ================================================================
# Push parsing with encoding
# ================================================================

{
    my $parser = XML::LibXML->new;
    $parser->push('<?xml version="1.0" encoding="UTF-8"?>');
    $parser->push('<root>café</root>');
    my $doc = $parser->finish_push;
    like($doc->documentElement->textContent, qr/caf/, 'UTF-8 content in push parse');
}

# ================================================================
# Push parsing with empty chunks
# ================================================================

{
    my $parser = XML::LibXML->new;
    $parser->init_push;
    $parser->push('');
    $parser->push('<root/>');
    $parser->push('');
    my $doc = $parser->finish_push;
    isa_ok($doc, 'XML::LibXML::Document', 'empty chunks are harmless');
}

# ================================================================
# Push parsing with deeply nested structure
# ================================================================

{
    my $parser = XML::LibXML->new;
    my $depth = 50;

    my $open = join('', map { "<level$_>" } 1..$depth);
    my $close = join('', map { "</level$_>" } reverse 1..$depth);

    $parser->push($open);
    $parser->push('<leaf/>');
    $parser->push($close);
    my $doc = $parser->finish_push;
    isa_ok($doc, 'XML::LibXML::Document', 'deeply nested push parse');

    my ($leaf) = $doc->findnodes('//leaf');
    ok($leaf, 'found leaf node in deep tree');
}

# ================================================================
# Push parsing with mixed content
# ================================================================

{
    my $parser = XML::LibXML->new;
    $parser->push('<root>text1<child/>text2</root>');
    my $doc = $parser->finish_push;

    my @children = $doc->documentElement->childNodes;
    is(scalar @children, 3, 'mixed content: 3 child nodes');
    is($children[0]->nodeType, XML::LibXML::XML_TEXT_NODE, 'first is text');
    is($children[1]->nodeType, XML::LibXML::XML_ELEMENT_NODE, 'second is element');
    is($children[2]->nodeType, XML::LibXML::XML_TEXT_NODE, 'third is text');
}
