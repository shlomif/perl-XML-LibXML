use Test;
BEGIN { plan tests => 17 }
END { ok(0) unless $loaded }
use XML::LibXML;
$loaded = 1;
ok(1);

my $p = XML::LibXML->new();
ok($p);

# encoding tests
# ok there is the UTF16 test still missing

my $tstr_utf8       = 'test';
my $tstr_iso_latin1 = 'täst';
my $tstr_euc_jp     = 'À¸ÇþÀ¸ÊÆÀ¸Íñ';

my $domstrlat1 = q{<?xml version="1.0" encoding="iso-8859-1"?>
<täst>täst</täst>
};
my $domstrjp = q{<?xml version="1.0" encoding="EUC-JP"?>
<À¸ÇþÀ¸ÊÆÀ¸Íñ>À¸ÇþÀ¸ÊÆÀ¸Íñ</À¸ÇþÀ¸ÊÆÀ¸Íñ>
};

# simple encoding interface

ok( decodeFromUTF8( 'UTF-8' , encodeToUTF8('UTF-8', $tstr_utf8 ) ),
    $tstr_utf8 );

ok( decodeFromUTF8( 'iso-8859-1' , encodeToUTF8('iso-8859-1', $tstr_iso_latin1 ) ),
    $tstr_iso_latin1 );

ok( decodeFromUTF8( 'EUC-JP' , encodeToUTF8('EUC-JP', $tstr_euc_jp ) ),
    $tstr_euc_jp );

# magic encoding

my $dom_latin1 = XML::LibXML::Document->new('1.0', 'iso-8859-1');
my $elemlat1 = $dom_latin1->createElement( $tstr_iso_latin1 );

ok( decodeFromUTF8( 'iso-8859-1' ,$elemlat1->nodeName()), $tstr_iso_latin1 );

$dom_latin1->setDocumentElement( $elemlat1 );

my $dom_euc_jp = XML::LibXML::Document->new('1.0', 'EUC-JP');
$elemjp = $dom_euc_jp->createElement( $tstr_euc_jp );

ok( decodeFromUTF8( 'EUC-JP' ,$elemjp->nodeName()), $tstr_euc_jp );

$dom_euc_jp->setDocumentElement( $elemjp );

# "magic" decoding 

ok( decodeFromUTF8( 'iso-8859-1' ,$elemlat1->toString()), "<$tstr_iso_latin1/>");
ok( decodeFromUTF8( 'EUC-JP' ,$elemjp->toString()), "<$tstr_euc_jp/>");

ok( $elemlat1->toString(1), "<$tstr_iso_latin1/>");
ok( $elemjp->toString(1), "<$tstr_euc_jp/>");

$elemlat1->appendText( $tstr_iso_latin1 );
$elemjp->appendText( $tstr_euc_jp );

ok( decodeFromUTF8( 'iso-8859-1' ,$elemlat1->string_value()), $tstr_iso_latin1);
ok( decodeFromUTF8( 'EUC-JP' ,$elemjp->string_value()), $tstr_euc_jp);

ok( $elemlat1->string_value(1), $tstr_iso_latin1);
ok( $elemjp->string_value(1), $tstr_euc_jp);

ok( $dom_latin1->toString(), $domstrlat1 );
ok( $dom_euc_jp->toString(), $domstrjp );
