#########################

use Test;
BEGIN { plan tests => 13 };
use XML::LibXML;

my $regex = '[0-9]{5}(-[0-9]{4})?';
my $bad_regex = '[0-9]{5}(-[0-9]{4}?';
my $nondet_regex = '(bc)|(bd)';
my $re = XML::LibXML::RegExp->new($regex);
ok( $re );
ok( ! $re->matches('00') );
ok( ! $re->matches('00-') );
ok( $re->matches('12345') );
ok( !$re->matches('123456') );

ok( $re->matches('12345-1234') );
ok( ! $re->matches(' 12345-1234') );
ok( ! $re->matches(' 12345-12345') );
ok( ! $re->matches('12345-1234 ') );

ok( $re->isDeterministic );

my $re2 = XML::LibXML::RegExp->new($nondet_regex);
ok( $re2 );
ok( ! $re2->isDeterministic );

eval { XML::LibXML::RegExp->new($bad_regex); };
ok( $@ );
