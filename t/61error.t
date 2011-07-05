
use strict;
use warnings;

use Test::More tests => 3;
use XML::LibXML;

if (! XML::LibXML::HAVE_STRUCT_ERRORS() ) {
    plan skip_all => 'XML::LibXML does not have struct errrors.';
}

use XML::LibXML::Error;

my $p = XML::LibXML->new();

my $xmlstr = <<EOX;
<X></Y>
EOX

eval {
    my $doc = $p->parse_string( $xmlstr );
};

my $err = $@;
# TEST
isa_ok ($err, "XML::LibXML::Error", 'Exception is of type error.');
# TEST
is ($err->domain(), 'parser', 'Error is in the parser domain');
# TEST
is ($err->line(), 1, 'Error is on line 1.');
# warn "se: ", $@;
