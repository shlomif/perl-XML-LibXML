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
    my $tests        = 2;
    my $basics       = 1;
    my $magic        = 6;    

    $tests += $basics;  
    $tests += $magic if $] >= 5.006;

    if ( defined $ENV{TEST_LANGUAGES} ) {
        if ( $ENV{TEST_LANGUAGES} eq "all" ) {
            $tests += 2*$basics;
            $tests += 2*$magic if $] >= 5.006;
        }
        elsif ( $ENV{TEST_LANGUAGES} eq "EUC-JP"
                or $ENV{TEST_LANGUAGES} eq "KIO8-R" ) {
            $tests += $basics;  
            $tests += $magic if $] >= 5.006;
        }
        
    }

    $tests = 1 if $] > 5.007;

    plan tests => $tests;
}

END { ok(0) unless $loaded }
use XML::LibXML;
$loaded = 1;
ok(1);

warn "skip tests on this platform\n" if $] > 5.007;

my $p = XML::LibXML->new();

# encoding tests
# ok there is the UTF16 test still missing

my $tstr_utf8       = 'test';
my $tstr_iso_latin1 = "täst";

my $domstrlat1 = q{<?xml version="1.0" encoding="iso-8859-1"?>
<täst>täst</täst>
};

print "# simple encoding interface\n";

ok( decodeFromUTF8( 'UTF-8' ,
                     encodeToUTF8('UTF-8', $tstr_utf8 ) ),
    $tstr_utf8 );

ok( decodeFromUTF8( 'iso-8859-1' ,
                     encodeToUTF8('iso-8859-1', $tstr_iso_latin1 ) ),
    $tstr_iso_latin1 );

if ( $] < 5.006 ) {
    warn "\nskip magic encoding tests on this platform\n";
    exit(0);
}
else {
    print "# magic encoding tests\n";

    my $dom_latin1 = XML::LibXML::Document->new('1.0', 'iso-8859-1');
    my $elemlat1   = $dom_latin1->createElement( $tstr_iso_latin1 );

    ok( decodeFromUTF8( 'iso-8859-1' ,
                        $elemlat1->nodeName()),
        $tstr_iso_latin1 );

    $dom_latin1->setDocumentElement( $elemlat1 );
    
    ok( decodeFromUTF8( 'iso-8859-1' ,$elemlat1->toString()),
        "<$tstr_iso_latin1/>");
    ok( $elemlat1->toString(1), "<$tstr_iso_latin1/>");

    $elemlat1->appendText( $tstr_iso_latin1 );

    ok( decodeFromUTF8( 'iso-8859-1' ,$elemlat1->string_value()),
        $tstr_iso_latin1);
    ok( $elemlat1->string_value(1), $tstr_iso_latin1);

    ok( $dom_latin1->toString(), $domstrlat1 );

}

exit(0) unless defined $ENV{TEST_LANGUAGES};

if ( $ENV{TEST_LANGUAGES} eq 'all' or $ENV{TEST_LANGUAGES} eq "EUC-JP" ) {
    print "# japanese encoding (EUC-JP)\n";

    my $tstr_euc_jp     = 'À¸ÇþÀ¸ÊÆÀ¸Íñ';
    my $domstrjp = q{<?xml version="1.0" encoding="EUC-JP"?>
<À¸ÇþÀ¸ÊÆÀ¸Íñ>À¸ÇþÀ¸ÊÆÀ¸Íñ</À¸ÇþÀ¸ÊÆÀ¸Íñ>
};

    ok( decodeFromUTF8( 'EUC-JP' , encodeToUTF8('EUC-JP', $tstr_euc_jp ) ),
        $tstr_euc_jp );
    

    if ( $] >= 5.006 ) {
        my $dom_euc_jp = XML::LibXML::Document->new('1.0', 'EUC-JP');
        $elemjp = $dom_euc_jp->createElement( $tstr_euc_jp );


        ok( decodeFromUTF8( 'EUC-JP' , $elemjp->nodeName()),
            $tstr_euc_jp );
        ok( decodeFromUTF8( 'EUC-JP' ,$elemjp->toString()),
            "<$tstr_euc_jp/>");
        ok( $elemjp->toString(1), "<$tstr_euc_jp/>");

        $dom_euc_jp->setDocumentElement( $elemjp );
        $elemjp->appendText( $tstr_euc_jp );

        ok( decodeFromUTF8( 'EUC-JP' ,$elemjp->string_value()),
            $tstr_euc_jp);
        ok( $elemjp->string_value(1), $tstr_euc_jp);

        ok( $dom_euc_jp->toString(), $domstrjp );
    }   

}

if ( $ENV{TEST_LANGUAGES} eq 'all' or $ENV{TEST_LANGUAGES} eq "KIO8-R" ) {
    print "# cyrillic encoding (KIO8-R)\n";

    my $tstr_kio8r       = 'ÐÒÏÂÁ';
    my $domstrkio = q{<?xml version="1.0" encoding="KIO8-R"?>
<ÐÒÏÂÁ>ÐÒÏÂÁ</ÐÒÏÂÁ>
};
    
    ok( decodeFromUTF8( 'KIO8-R' , 
                         encodeToUTF8('KIO8-R', $tstr_kio8r ) ),
        $tstr_kio8r );    

    if ( $] >= 5.006 ) {
        my ($dom_kio8, $elemkio8);

        $dom_kio8 = XML::LibXML::Document->new('1.0', 'KIO8-R');
        $elemkio8 = $dom_kio8->createElement( $tstr_kio8r );

        ok( decodeFromUTF8( 'KIO8-R' ,$elemkio8->nodeName()), 
            $tstr_kio8r );

        ok( decodeFromUTF8( 'KIO8-R' ,$elemkio8->toString()), 
            "<$tstr_kio8r/>");
        ok( $elemkio8->toString(1), "<$tstr_kio8r/>");

        $elemkio8->appendText( $tstr_kio8r );

        ok( decodeFromUTF8( 'KIO8-R' ,$elemkio8->string_value()),
            $tstr_kio8r);
        ok( $elemkio8->string_value(1),
            $tstr_kio8r);
        $dom_kio8->setDocumentElement( $elemkio8 );

        ok( $dom_kio8->toString(),
            $domstrkio );
        
    }
}
