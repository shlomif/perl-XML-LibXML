# $Id$

##
# this test checks the parsing capabilities of XML::LibXML
# it relies on the success of t/01basic.t

use Test;
use IO::File;

BEGIN { plan tests => 351};
use XML::LibXML;
use XML::LibXML::Common qw(:libxml);
use XML::LibXML::SAX;
use XML::LibXML::SAX::Builder;

use constant XML_DECL => "<?xml version=\"1.0\"?>\n";

##
# test values
my @goodWFStrings = (
'<foobar/>',
'<foobar></foobar>',
XML_DECL . "<foobar></foobar>",
'<?xml version="1.0" encoding="UTF8"?>'."\n<foobar></foobar>",
'<?xml version="1.0" encoding="ISO-8859-1"?>'."\n<foobar></foobar>",
XML_DECL. "<foobar> </foobar>\n",
XML_DECL. '<foobar><foo/></foobar> ',
XML_DECL. '<foobar> <foo/> </foobar> ',
XML_DECL. '<foobar><![CDATA[<>&"\']]></foobar>',
XML_DECL. '<foobar>&lt;&gt;&amp;&quot;&apos;</foobar>',
XML_DECL. '<foobar>&#x20;&#160;</foobar>',
XML_DECL. '<!--comment--><foobar>foo</foobar>',
XML_DECL. '<foobar>foo</foobar><!--comment-->',
XML_DECL. '<foobar>foo<!----></foobar>',
XML_DECL. '<foobar foo="bar"/>',
XML_DECL. '<foobar foo="\'bar>"/>',
XML_DECL. '<bar:foobar foo="bar"><bar:foo/></bar:foobar>',
                    );

my @goodWFNSStrings = (
XML_DECL. '<foobar xmlns:bar="foo" bar:foo="bar"/>',
XML_DECL. '<foobar xmlns="foo" foo="bar"><foo/></foobar>',
XML_DECL. '<bar:foobar xmlns:bar="foo" foo="bar"><bar:foo/></bar:foobar>',
XML_DECL. '<bar:foobar xmlns:bar="foo" foo="bar"><foo/></bar:foobar>',
XML_DECL. '<bar:foobar xmlns:bar="foo" bar:foo="bar"><bar:foo/></bar:foobar>',
                      );

my @goodWFDTDStrings = (
XML_DECL. '<!DOCTYPE foobar ['."\n".'<!ENTITY foo " test ">'."\n".']>'."\n".'<foobar>&foo;</foobar>',
XML_DECL. '<!DOCTYPE foobar [<!ENTITY foo "bar">]><foobar>&foo;</foobar>',
XML_DECL. '<!DOCTYPE foobar [<!ENTITY foo "bar">]><foobar>&foo;&gt;</foobar>',
XML_DECL. '<!DOCTYPE foobar [<!ENTITY foo "bar=&quot;foo&quot;">]><foobar>&foo;&gt;</foobar>',
XML_DECL. '<!DOCTYPE foobar [<!ENTITY foo "bar">]><foobar>&foo;&gt;</foobar>',
XML_DECL. '<!DOCTYPE foobar [<!ENTITY foo "bar">]><foobar foo="&foo;"/>',
XML_DECL. '<!DOCTYPE foobar [<!ENTITY foo "bar">]><foobar foo="&gt;&foo;"/>',
                       );

my @badWFStrings = (
"",                                        # totally empty document
XML_DECL,                                  # only XML Declaration
"<!--ouch-->",                             # comment only is like an empty document 
'<!DOCTYPE ouch [<!ENTITY foo "bar">]>',   # no good either ...
"<ouch>",                                  # single tag (tag mismatch)
"<ouch/>foo",                              # trailing junk
"foo<ouch/>",                              # leading junk
"<ouch foo=bar/>",                         # bad attribute
'<ouch foo="bar/>',                        # bad attribute
"<ouch>&</ouch>",                          # bad char
"<ouch>&#0x20;</ouch>",                    # bad char
"<foobär/>",                               # bad encoding
"<ouch>&foo;</ouch>",                      # undefind entity
"<ouch>&gt</ouch>",                        # unterminated entity
XML_DECL. '<!DOCTYPE foobar [<!ENTITY foo "bar">]><foobar &foo;="ouch"/>',          # bad placed entity
XML_DECL. '<!DOCTYPE foobar [<!ENTITY foo "bar=&quot;foo&quot;">]><foobar &foo;/>', # even worse 
"<ouch><!---></ouch>",                     # bad comment
'<ouch><!-----></ouch>',                   # bad either... (is this conform with the spec????)
                    );

my @goodWBStrings = (
" ",
"<!--good-->",
"<![CDATA[>&<]]>",
"foo<bar/>foo",
"foo<bar/>",
"<bar/>foo",
"&gt;&#160;",
'<foo bar="&gt;"/>',
'<foo/>&gt;',
'<foo/><bar/>',
'<bar:foobar xmlns:bar="foo" bar:foo="bar"/><foo/>',
                    );

my @badWBStrings = (
"",
"<ouch>",
"<ouch>bar",
"bar</ouch>",
"<ouch/>&foo;", # undefined entity
"&",            # bad char
"häh?",         # bad encoding
"<!--->",       # bad stays bad ;)
"<!----->",     # bad stays bad ;)
);


    my %goodPushWF = (
single1 => ['<foobar/>'],
single2 => ['<foobar>','</foobar>'],
single3 => [ XML_DECL, "<foobar>", "</foobar>" ],
single4 => ["<foo", "bar/>"],
single5 => ["<", "foo","bar", "/>"],
single6 => ['<?xml version="1.0" encoding="UTF8"?>',"\n<foobar/>"],
single7 => ['<?xml',' version="1.0" ','encoding="UTF8"?>',"\n<foobar/>"],
single8 => ['<foobar', ' foo=', '"bar"', '/>'],
single9 => ['<?xml',' versio','n="1.0" ','encodi','ng="U','TF8"?>',"\n<foobar/>"],
multiple1 => [ '<foobar>','<foo/>','</foobar> ', ],
multiple2 => [ '<foobar','><fo','o','/><','/foobar> ', ],
multiple3 => [ '<foobar>','<![CDATA[<>&"\']]>','</foobar>'],
multiple4 => [ '<foobar>','<![CDATA[', '<>&', ']]>', '</foobar>' ],
multiple5 => [ '<foobar>','<!','[CDA','TA[', '<>&', ']]>', '</foobar>' ],
multiple6 => ['<foobar>','&lt;&gt;&amp;&quot;&apos;','</foobar>'],
multiple6 => ['<foobar>','&lt',';&','gt;&a','mp;','&quot;&ap','os;','</foobar>'],
multiple7 => [ '<foobar>', '&#x20;&#160;','</foobar>' ],
multiple8 => [ '<foobar>', '&#x','20;&#1','60;','</foobar>' ],
multiple9 => [ '<foobar>','moo','moo','</foobar> ', ],
multiple10 => [ '<foobar>','moo','</foobar> ', ],
comment1  => [ '<!--comment-->','<foobar/>' ],
comment2  => [ '<foobar/>','<!--comment-->' ],
comment3  => [ '<!--','comment','-->','<foobar/>' ],
comment4  => [ '<!--','-->','<foobar/>' ],
comment5  => [ '<foobar>fo','o<!---','-><','/foobar>' ],
attr1     => [ '<foobar',' foo="bar"/>'],
attr2     => [ '<foobar',' foo','="','bar','"/>'],
attr3     => [ '<foobar',' fo','o="b','ar"/>'],
prefix1   => [ '<bar:foobar/>' ],
prefix2   => [ '<bar',':','foobar/>' ],
prefix3   => [ '<ba','r:fo','obar/>' ],
ns1       => [ '<foobar xmlns:bar="foo"/>' ],
ns2       => [ '<foobar ','xmlns:bar="foo"','/>' ],
ns3       => [ '<foo','bar x','mlns:b','ar="foo"/>' ],
ns4       => [ '<bar:foobar xmlns:bar="foo"/>' ],
ns5       => [ '<bar:foo','bar xm','lns:bar="fo','o"/>' ],
ns6       => [ '<bar:fooba','r xm','lns:ba','r="foo"','><bar',':foo/','></bar'.':foobar>'],
dtd1      => [XML_DECL, '<!DOCTYPE ','foobar [','<!ENT','ITY foo " test ">',']>','<foobar>&f','oo;</foobar>',],
dtd2      => [XML_DECL, '<!DOCTYPE ','foobar [','<!ENT','ITY foo " test ">',']>','<foobar>&f','oo;&gt;</foobar>',],
                    );

my $goodfile = "example/dromeds.xml";
my $badfile1 = "example/bad.xml";
my $badfile2 = "does_not_exist.xml";


my $parser = XML::LibXML->new();

print "# 1 NON VALIDATING PARSER\n";
print "# 1.1 WELL FORMED STRING PARSING\n";
print "# 1.1.1 DEFAULT VALUES\n";

{
    foreach my $str ( @goodWFStrings,@goodWFNSStrings,@goodWFDTDStrings ) {
        my $doc = $parser->parse_string($str);
        ok($doc);
    }
}

eval { my $fail = $parser->parse_string(undef); };
ok($@);

foreach my $str ( @badWFStrings ) {
    eval { my $fail = $parser->parse_string($str); };  
    ok($@);
}


print "# 1.1.2 NO KEEP BLANKS\n";

$parser->keep_blanks(0);

{
    foreach my $str ( @goodWFStrings,@goodWFNSStrings,@goodWFDTDStrings ) {
        my $doc = $parser->parse_string($str);
        ok($doc);
    }
}

eval { my $fail = $parser->parse_string(undef); };
ok($@);

foreach my $str ( @badWFStrings ) {
    eval { my $fail = $parser->parse_string($str); };  
    ok($@);
}

$parser->keep_blanks(1);

print "# 1.1.3 EXPAND ENTITIES\n";

$parser->expand_entities(0);

{
    foreach my $str ( @goodWFStrings,@goodWFNSStrings,@goodWFDTDStrings ) {
        my $doc = $parser->parse_string($str);
        ok($doc);
    }
}

eval { my $fail = $parser->parse_string(undef); };
ok($@);

foreach my $str ( @badWFStrings ) {
    eval { my $fail = $parser->parse_string($str); };  
    ok($@);
}

$parser->expand_entities(1);

print "# 1.1.4 PEDANTIC\n";

$parser->pedantic_parser(1);

{
    foreach my $str ( @goodWFStrings,@goodWFNSStrings,@goodWFDTDStrings ) {
        my $doc = $parser->parse_string($str);
        ok($doc);
    }
}

eval { my $fail = $parser->parse_string(undef); };
ok($@);

foreach my $str ( @badWFStrings ) {
    eval { my $fail = $parser->parse_string($str); };  
    ok($@);
}

$parser->pedantic_parser(0);



print "# 1.2 WELL BALLANCED STRING PARSING\n";

print "# 1.2.1 DEFAULT VALUES\n";
{
    foreach my $str ( @goodWBStrings ) {
        my $fragment = $parser->parse_xml_chunk($str);
        ok($fragment);
    }
}

eval { my $fail = $parser->parse_xml_chunk(undef); };
ok($@);

eval { my $fail = $parser->parse_xml_chunk(undef); };
ok($@);

foreach my $str ( @badWBStrings ) {
    eval { my $fail = $parser->parse_xml_chunk($str); };  
    ok($@);
}


print "# 1.3 PARSE A FILE\n";

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

print "# 1.4 PARSE A HANDLE\n";

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
    $doc = $parser->parse_file( "example/dtd.xml" );
    @cn = $doc->documentElement->childNodes;
    ok( scalar @cn, 3 );
}

print "# 1.5 x-include processing\n";

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

print "# 2 push parser\n";

{
    foreach my $key ( keys %goodPushWF ) {
        foreach ( @{$goodPushWF{$key}} ) {
            $parser->push( $_);
        }

        my $doc;
        eval {$doc = $parser->finish_push; };
        ok($doc && !$@);                    
    }

    my @good_strings = ("<foo>", "bar", "</foo>" );
    my @bad_strings  = ("<foo>", "bar");

    my $parser = XML::LibXML->new;
    {
        for ( @good_strings ) {        
            $parser->push( $_ );
        }
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

print "# 3 SAX PARSER\n";

{
    my $handler = XML::LibXML::SAX::Builder->new();
    my $generator = XML::LibXML::SAX->new( Handler=>$handler );

    my $string  = q{<bar foo="bar">foo</bar>};

    $doc = $generator->parse_string( $string );
    ok( $doc );

    print "# 3.1 GENERAL TESTS \n";
    foreach my $str ( @goodWFStrings ) {
        my $doc = $generator->parse_string( $str );
        ok( $doc );
    }

    print "# CDATA Sections\n";

    $string = q{<foo><![CDATA[&foo<bar]]></foo>};
    $doc = $generator->parse_string( $string );
    my @cn = $doc->documentElement->childNodes();
    ok( scalar @cn );
    ok( $cn[0]->nodeType, XML_CDATA_SECTION_NODE );
    ok( $cn[0]->textContent, "&foo<bar" );

    print "# 3.2 NAMESPACE TESTS\n";

    foreach my $str ( @goodWFNSStrings ) {
        my $doc = $generator->parse_string( $str );
        ok( $doc );
    }

    print "# DATA CONSISTENCE\n";    
    # find out if namespaces are there
    my $string2 = q{<foo xmlns:bar="http://foo.bar">bar<bar:bi/></foo>};

    $doc = $generator->parse_string( $string2 );

    my @attrs = $doc->documentElement->attributes;

    ok( scalar @attrs );
    if ( scalar @attrs ) {
        ok( $attrs[0]->nodeType, XML_NAMESPACE_DECL );
    }
    else {
        ok(0);
    }

    print "# 3.3 INTERNAL SUBSETS\n";

    foreach my $str ( @goodWFDTDStrings ) {
        my $doc = $generator->parse_string( $str );
        ok( $doc );
    }

    print "# 3.5 PARSE URI\n"; 
    $doc = $generator->parse_uri( "example/test.xml" );
    ok($doc);

    print "# 3.6 PARSE CHUNK\n";
    
}

print "# 4 SAXY PUSHER\n";

{
    my $handler = XML::LibXML::SAX::Builder->new();
    my $parser = XML::LibXML->new;

    $parser->set_handler( $handler );
    $parser->push( '<foo/>' );
    my $doc = $parser->finish_push;
    ok($doc);

    foreach my $key ( keys %goodPushWF ) {
        foreach ( @{$goodPushWF{$key}} ) {
            $parser->push( $_);
        }

        my $doc;
        eval {$doc = $parser->finish_push; };
        ok($doc);                    
    }
}

sub tsub {
    my $doc = shift;

    my $th = {};
    $th->{d} = XML::LibXML::Document->createDocument;
    my $e1  = $th->{d}->createElementNS("x","X:foo");

    $th->{d}->setDocumentElement( $e1 );
    my $e2 = $th->{d}->createElementNS( "x","X:bar" );

    $e1->appendChild( $e2 );

    $e2->appendChild( $th->{d}->importNode( $doc->documentElement() ) );

    return $th->{d};
}