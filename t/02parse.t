# $Id$

##
# this test checks the parsing capabilities of XML::LibXML
# it relies on the success of t/01basic.t

use Test;
use IO::File;

BEGIN { plan tests => 42 };
use XML::LibXML;

##
# test values
my $goodWFString = "<foobar/>";
my $badWFString1 = "<foo>&</foo>";
my $badWFString2 = "<foo>";
my $badWFString3 = '<?xml version="1.0">';

my $goodWBString = "foo<bar/>foo";
my $badWBString1 = "<foo>bar";
my $badWBString2 = "foo</bar>";

my $goodfile = "example/dromeds.xml";
my $badfile1 = "example/bad.xml";
my $badfile2 = "does_not_exist.xml";

my $parser = XML::LibXML->new();

print "# 1. Well Formed String Parsing\n";

{
    my $doc = $parser->parse_string($goodWFString);
    ok(defined $doc);
    my $str = $doc->toString();
    $str =~ s/\<\?xml[^\?]*\?\>//;
    $str =~ s/\n//g;
    ok($str, $goodWFString );    
}

eval { my $fail = $parser->parse_string($badWFString1); };
ok($@);

eval { my $fail = $parser->parse_string($badWFString2); };
ok($@);

eval { my $fail = $parser->parse_string($badWFString3); };
ok($@);


eval { my $fail = $parser->parse_string(""); };
ok($@);

eval { my $fail = $parser->parse_string(undef); };
ok($@);

print "# 2. Well Ballanced String Parsing\n";

{
    my $fragment;
    eval { $fragment = $parser->parse_xml_chunk( $goodWBString ); };
    ok( $fragment );
    ok( $fragment->toString(), $goodWBString );
}

eval { my $fail = $parser->parse_xml_chunk($badWBString1); };
ok($@);

eval { my $fail = $parser->parse_xml_chunk($badWBString2); };
ok($@);

eval { my $fail = $parser->parse_xml_chunk(""); };
ok($@);

eval { my $fail = $parser->parse_xml_chunk(undef); };
ok($@);

print "# 3. Parse A File\n";

{
    my $doc = $parser->parse_file($goodfile);
    ok($doc);
}
 
eval {my $fail = $parser->parse_file($badfile1);};
ok($@);

eval { $parser->parse_file($badfile2); };
ok($@);

{
    my $str = "<a>    <b/> </a>";
    my $tstr= "<a><b/></a>";
    $parser->keep_blanks(0);
    my $docA = $parser->parse_string($str);
    my $docB = $parser->parse_file("example/test3.xml");
    $XML::LibXML::skipXMLDeclaration = 1;
    ok( $docA->toString, $tstr );
    ok( $docB->toString, $tstr );
    $XML::LibXML::skipXMLDeclaration = 0;
}

print "# 4. Parse A Handle\n";

my $fh = IO::File->new($goodfile);
ok($fh);

my $doc = $parser->parse_fh($fh);
ok($doc);

$fh = IO::File->new($badfile1);
ok($fh);

eval { my $doc = $parser->parse_fh($fh); };
ok($@);

$fh = IO::File->new($badfile2);

eval { my $doc = $parser->parse_fh($fh); };
ok($@);

{
    $parser->expand_entities(1);
    my $doc = $parser->parse_file( "example/dtd.xml" );
    my @cn = $doc->documentElement->childNodes;
    ok( scalar @cn, 1 );

    $doc = $parser->parse_file( "example/complex/complex2.xml" );
    @cn = $doc->documentElement->childNodes;
    ok( scalar @cn, 1 );

    $parser->expand_entities(0);
}

print "# 5. x-include processing\n";

my $goodXInclude = q{
<x>
<xinclude:include 
 xmlns:xinclude="http://www.w3.org/2001/XInclude"
 href="test2.xml"/>
</x>
};


my $badXInclude = q{
<x xmlns:xinclude="http://www.w3.org/2001/XInclude">
<xinclude:include href="bad.xml"/>
</x>
};

{
    $parser->base_uri( "example/" );
    $parser->keep_blanks(0);
    my $doc = $parser->parse_string( $goodXInclude );
    ok($doc);

    my $i;
    eval { $i = $parser->processXIncludes($doc); };
    ok( $i );

    $doc = $parser->parse_string( $badXInclude );
    $i= undef;
    eval { $i = $parser->processXIncludes($doc); };
    ok($@);
    
    # auto expand
    $parser->expand_xinclude(1);
    $doc = $parser->parse_string( $goodXInclude );
    ok($doc);

    $doc = undef;
    eval { $doc = $parser->parse_string( $badXInclude ); };
    ok($@);
    ok(!$doc);

    # some bad stuff 
    eval{ $parser->processXIncludes(undef); };
    ok($@);
    eval{ $parser->processXIncludes("blahblah"); };
    ok($@);
}

print "# 6. push parser\n";

{
    my @good_strings = ("<foo>", "bar", "</foo>" );
    my @bad_strings  = ("<foo>", "bar");

    my $parser = XML::LibXML->new;
    {
        
        $parser->push( @good_strings );
        my $doc = $parser->finish_push;
        ok($doc);
    }

    {
        foreach ( @bad_strings ) {
            $parser->push( $_);
        }

        eval { my $doc = $parser->finish_push; };
        ok( $@ );
    }

    {
        $parser->init_push;

        foreach ( @bad_strings ) {
            $parser->push( $_);
        }

        my $doc;
        eval { $doc = $parser->finish_push(1); };
        ok( $doc );
    }
}

print "# 7. SAX parser\n";

{
    use XML::LibXML::SAX;
    use XML::LibXML::SAX::Builder;
    my $handler = XML::LibXML::SAX::Builder->new();
    my $generator = XML::LibXML::SAX->new( Handler=>$handler );


    my $string1  = q{<bar>foo</bar>};

    $doc = $generator->parse_string( $string1 );
    ok( $doc );

    my $string  = q{<bar foo="bar">foo</bar>};

    $doc = $generator->parse_string( $string );
    ok( $doc );

    my $string2 = q{<foo xmlns:bar="http://foo.bar">bar<bar:bi/></foo>};

    $doc = $generator->parse_string( $string2 );
    ok($doc);

    my $root = $doc->documentElement;
    my @attrs = $root->attributes;
    ok( scalar @attrs );
    if ( scalar @attrs ) {
        ok( $attrs[0]->nodeType, XML_NAMESPACE_DECL );
    }
    else {
        ok(0);
    }

    $doc = $generator->parse_uri( "example/test.xml" );

    ok($doc);
}