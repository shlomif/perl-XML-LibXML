
use strict;
use warnings;

use Test;
BEGIN { use XML::LibXML;
        if ( XML::LibXML::HAVE_STRUCT_ERRORS() ) {
            plan tests => 3;
        }else{
            plan tests => 1;
        }
}

use XML::LibXML::Error;

my $p = XML::LibXML->new();

my $xmlstr = <<EOX;
<X></Y>
EOX

    eval {
        my $doc = $p->parse_string( $xmlstr );
    };
    if ( $@ ) {
        if ( ref( $@ ) ) {
            ok(ref($@), "XML::LibXML::Error");
            ok($@->domain(), "parser");
            ok($@->line(), 1);
            # warn "se: ", $@;
    
        }
        else {
            # warn "me: ", $@;
            ok(1);
        }
    }



