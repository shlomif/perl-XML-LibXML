##
# $Id$
#
# This should test the XML::LibXML internal encoding/ decoding.
# Since most of the internal encoding code is depentend to 
# the perl version the module is build for. only the encodeToUTF8() and 
# decodeFromUTF8() functions are supposed to be general, while all the 
# magic code is only available for more recent perl version (5.6+)
#
use Test;

BEGIN { 
    my $tests = 25;  
    $tests = 5 if $] < 5.006;
    plan tests => $tests;
}

END { ok(0) unless $loaded }
use XML::LibXML;
$loaded = 1;
ok(1);

my $p = XML::LibXML->new();
ok($p);

# encoding tests
# ok there is the UTF16 test still missing

my $do_kio8r = 1;

my $tstr_utf8       = 'test';
my $tstr_iso_latin1 = 'täst';
my $tstr_euc_jp     = 'À¸ÇþÀ¸ÊÆÀ¸Íñ';
my $tstr_kio8r       = 'ÐÒÏÂÁ';

my $domstrlat1 = q{<?xml version="1.0" encoding="iso-8859-1"?>
<täst>täst</täst>
};

my $domstrjp = q{<?xml version="1.0" encoding="EUC-JP"?>
<À¸ÇþÀ¸ÊÆÀ¸Íñ>À¸ÇþÀ¸ÊÆÀ¸Íñ</À¸ÇþÀ¸ÊÆÀ¸Íñ>
};

my $domstrkio=q{<?xml version="1.0" encoding="KIO8-R"?>
<ÐÒÏÂÁ>ÐÒÏÂÁ</ÐÒÏÂÁ>
};

# simple encoding interface
ok( decodeFromUTF8( 'UTF-8' ,
                     encodeToUTF8('UTF-8', $tstr_utf8 ) ),
    $tstr_utf8 );

ok( decodeFromUTF8( 'iso-8859-1' ,
                     encodeToUTF8('iso-8859-1', $tstr_iso_latin1 ) ),
    $tstr_iso_latin1 );

if ( decodeFromUTF8( 'KIO8-R' , 
                      encodeToUTF8('KIO8-R', $tstr_kio8r ) ),
     $tstr_kio8r ) {
    ok(1);
}
else {
    warn "# skip kio8-r tests no encoder!\n";
    ok(1);
    $do_kio8r = 0;
}

ok( decodeFromUTF8( 'EUC-JP' , encodeToUTF8('EUC-JP', $tstr_euc_jp ) ),
    $tstr_euc_jp );


if ( $] < 5.006 ) {
    warn "\nskip magic encoding tests on this platform\n";
    exit(0);
}
else {
    warn "\n# magic encoding tests\n";
}

my $dom_latin1 = XML::LibXML::Document->new('1.0', 'iso-8859-1');
my $elemlat1 = $dom_latin1->createElement( $tstr_iso_latin1 );

ok( decodeFromUTF8( 'iso-8859-1' ,
                    $elemlat1->nodeName()),
    $tstr_iso_latin1 );

$dom_latin1->setDocumentElement( $elemlat1 );

my $dom_euc_jp = XML::LibXML::Document->new('1.0', 'EUC-JP');
$elemjp = $dom_euc_jp->createElement( $tstr_euc_jp );

ok( decodeFromUTF8( 'EUC-JP' , $elemjp->nodeName()),
    $tstr_euc_jp );

$dom_euc_jp->setDocumentElement( $elemjp );


my ($dom_kio8, $elemkio8);

if ( $do_kio8r == 1 ) {
    $dom_kio8 = XML::LibXML::Document->new('1.0', 'KIO8-R');
    $elemkio8 = $dom_kio8->createElement( $tstr_kio8r );

    ok( decodeFromUTF8( 'KIO8-R' ,$elemkio8->nodeName()), 
        $tstr_kio8r );

    $dom_kio8->setDocumentElement( $elemkio8 );
}
else {
    ok(1);ok(1);ok(1);ok(1);ok(1);ok(1);ok(1);
}

# "magic" decoding 

ok( decodeFromUTF8( 'iso-8859-1' ,$elemlat1->toString()),
    "<$tstr_iso_latin1/>");
ok( decodeFromUTF8( 'EUC-JP' ,$elemjp->toString()),
    "<$tstr_euc_jp/>");

if ( $do_kio8r == 1 ) {
    ok( decodeFromUTF8( 'KIO8-R' ,$elemkio8->toString()), 
    "<$tstr_kio8r/>");
}

ok( $elemlat1->toString(1), "<$tstr_iso_latin1/>");
ok( $elemjp->toString(1), "<$tstr_euc_jp/>");
if ( $do_kio8r == 1 ) {
    ok( $elemkio8->toString(1), "<$tstr_kio8r/>");
}

$elemlat1->appendText( $tstr_iso_latin1 );
$elemjp->appendText( $tstr_euc_jp );

if ( $do_kio8r == 1 ) {
    $elemkio8->appendText( $tstr_kio8r );
}

ok( decodeFromUTF8( 'iso-8859-1' ,$elemlat1->string_value()),
    $tstr_iso_latin1);
ok( decodeFromUTF8( 'EUC-JP' ,$elemjp->string_value()),
    $tstr_euc_jp);

if ( $do_kio8r == 1 ) {
    ok( decodeFromUTF8( 'KIO8-R' ,$elemkio8->string_value()),
        $tstr_kio8r);
}

ok( $elemlat1->string_value(1), $tstr_iso_latin1);
ok( $elemjp->string_value(1), $tstr_euc_jp);

if ( $do_kio8r == 1 ) {
    ok( $elemkio8->string_value(1),
        $tstr_kio8r);
}

ok( $dom_latin1->toString(), $domstrlat1 );
ok( $dom_euc_jp->toString(), $domstrjp );

if ( $do_kio8r == 1 ) {
    ok( $dom_kio8->toString(),
        $domstrkio );
}
