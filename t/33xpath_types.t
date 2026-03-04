use strict;
use warnings;

use Test::More tests => 68;

use XML::LibXML;
use XML::LibXML::Boolean;
use XML::LibXML::Number;
use XML::LibXML::Literal;

# ================================================================
# XML::LibXML::Boolean
# ================================================================

{
    # new() constructor
    my $true = XML::LibXML::Boolean->new(1);
    isa_ok($true, 'XML::LibXML::Boolean', 'Boolean->new(1)');

    my $false = XML::LibXML::Boolean->new(0);
    isa_ok($false, 'XML::LibXML::Boolean', 'Boolean->new(0)');

    # new() with truthy/falsy values
    my $truthy = XML::LibXML::Boolean->new("hello");
    is($truthy->value, 1, 'Boolean->new("hello") is true');

    my $falsy = XML::LibXML::Boolean->new("");
    is($falsy->value, 0, 'Boolean->new("") is false');

    my $undef_bool = XML::LibXML::Boolean->new(undef);
    is($undef_bool->value, 0, 'Boolean->new(undef) is false');

    # True() and False() class methods
    my $T = XML::LibXML::Boolean->True;
    is($T->value, 1, 'Boolean->True returns true');

    my $F = XML::LibXML::Boolean->False;
    is($F->value, 0, 'Boolean->False returns false');

    # value()
    is($true->value, 1, 'true->value is 1');
    is($false->value, 0, 'false->value is 0');

    # stringification overload
    is("$true", 1, 'true stringifies to 1');
    is("$false", 0, 'false stringifies to 0');

    # cmp (<=>) overload
    ok($true > $false, 'true > false');
    ok(!($false > $true), 'not false > true');
    is($true <=> $false, 1, 'true <=> false is 1');
    is($false <=> $true, -1, 'false <=> true is -1');
    is($true <=> $true, 0, 'true <=> true is 0');

    # to_number()
    my $num = $true->to_number;
    isa_ok($num, 'XML::LibXML::Number', 'to_number returns Number');
    is($num->value, 1, 'true->to_number->value is 1');

    my $num0 = $false->to_number;
    is($num0->value, 0, 'false->to_number->value is 0');

    # to_boolean()
    ok($true->to_boolean->value == 1, 'to_boolean preserves true value');

    # to_literal()
    my $lit = $true->to_literal;
    isa_ok($lit, 'XML::LibXML::Literal', 'to_literal returns Literal');
    is($lit->value, 'true', 'true->to_literal is "true"');

    my $lit_f = $false->to_literal;
    is($lit_f->value, 'false', 'false->to_literal is "false"');

    # string_value()
    is($true->string_value, 'true', 'true->string_value is "true"');
    is($false->string_value, 'false', 'false->string_value is "false"');
}

# ================================================================
# XML::LibXML::Number
# ================================================================

{
    # new() with valid numbers
    my $int = XML::LibXML::Number->new(42);
    isa_ok($int, 'XML::LibXML::Number', 'Number->new(42)');
    is($int->value, 42, 'integer value');

    my $float = XML::LibXML::Number->new(3.14);
    is($float->value, 3.14, 'float value');

    my $neg = XML::LibXML::Number->new(-7);
    is($neg->value, -7, 'negative value');

    my $zero = XML::LibXML::Number->new(0);
    is($zero->value, 0, 'zero value');

    my $dot_start = XML::LibXML::Number->new(.5);
    is($dot_start->value, .5, 'number starting with dot');

    # new() with invalid input -> NaN
    my $nan = XML::LibXML::Number->new("abc");
    ok(!defined($nan->value), 'non-numeric string gives undef/NaN');

    my $nan2 = XML::LibXML::Number->new("12abc");
    ok(!defined($nan2->value), 'partially numeric string gives NaN');

    # as_string()
    is($int->as_string, '42', 'as_string for integer');
    is($nan->as_string, 'NaN', 'as_string for NaN');

    # as_xml()
    is($int->as_xml, "<Number>42</Number>\n", 'as_xml for integer');
    is($nan->as_xml, "<Number>NaN</Number>\n", 'as_xml for NaN');

    # stringification overload
    is("$int", 42, 'stringification overload');

    # cmp (<=>) overload
    my $a = XML::LibXML::Number->new(10);
    my $b = XML::LibXML::Number->new(20);
    is($a <=> $b, -1, '10 <=> 20 is -1');
    is($b <=> $a, 1, '20 <=> 10 is 1');
    is($a <=> $a, 0, '10 <=> 10 is 0');

    # evaluate()
    ok($int->evaluate->value == $int->value, 'evaluate returns self');

    # to_boolean()
    my $bool_true = $int->to_boolean;
    isa_ok($bool_true, 'XML::LibXML::Boolean', 'to_boolean returns Boolean');
    is($bool_true->value, 1, '42->to_boolean is true');

    my $bool_false = $zero->to_boolean;
    is($bool_false->value, 0, '0->to_boolean is false');

    # to_literal()
    my $lit = $int->to_literal;
    isa_ok($lit, 'XML::LibXML::Literal', 'to_literal returns Literal');
    is($lit->value, '42', '42->to_literal->value');

    # to_number() returns self
    ok($int->to_number->value == 42, 'to_number returns self');

    # string_value()
    is($int->string_value, 42, 'string_value');
}

# ================================================================
# XML::LibXML::Literal
# ================================================================

{
    # new()
    my $lit = XML::LibXML::Literal->new("hello world");
    isa_ok($lit, 'XML::LibXML::Literal', 'Literal->new("hello world")');
    is($lit->value, "hello world", 'value matches');

    my $empty = XML::LibXML::Literal->new("");
    is($empty->value, "", 'empty string value');

    # as_string() (escapes single quotes)
    my $with_quote = XML::LibXML::Literal->new("it's");
    is($with_quote->as_string, "'it&apos;s'", 'as_string escapes single quotes');

    my $plain = XML::LibXML::Literal->new("plain");
    is($plain->as_string, "'plain'", 'as_string wraps in quotes');

    # as_xml()
    is($plain->as_xml, "<Literal>plain</Literal>\n", 'as_xml output');

    # stringification overload
    is("$lit", "hello world", 'stringification');

    # cmp overload
    my $a = XML::LibXML::Literal->new("abc");
    my $b = XML::LibXML::Literal->new("xyz");
    ok($a lt $b, 'abc lt xyz');
    ok($b gt $a, 'xyz gt abc');
    is(($a cmp $b), -1, 'abc cmp xyz is -1');
    is(($a cmp $a), 0, 'abc cmp abc is 0');

    # evaluate()
    is($lit->evaluate->value, $lit->value, 'evaluate returns self');

    # to_boolean()
    my $bool = $lit->to_boolean;
    isa_ok($bool, 'XML::LibXML::Boolean', 'to_boolean returns Boolean');
    is($bool->value, 1, 'non-empty string to_boolean is true');

    my $empty_bool = $empty->to_boolean;
    is($empty_bool->value, 0, 'empty string to_boolean is false');

    # to_number()
    my $numeric_lit = XML::LibXML::Literal->new("42");
    my $num = $numeric_lit->to_number;
    isa_ok($num, 'XML::LibXML::Number', 'to_number returns Number');
    is($num->value, 42, '"42"->to_number->value is 42');

    # to_literal()
    is($lit->to_literal->value, $lit->value, 'to_literal returns self');

    # string_value()
    is($lit->string_value, "hello world", 'string_value');
}
