use Test;
BEGIN { plan tests => 4 }
END { ok(0) unless $loaded }
use XML::LibXML;
$loaded = 1;
ok(1);

my $p = XML::LibXML->new();
ok($p);

# encoding tests
my $tstr1 = "test";
my $tstr2 = "täst";

ok( decodeFromUTF8( 'UTF-8' , encodeToUTF8('UTF-8', $tstr1 ) ) eq $tstr1 );
ok( decodeFromUTF8( 'iso-8859-1' , encodeToUTF8('iso-8859-1', $tstr2 ) ) eq $tstr2 );
