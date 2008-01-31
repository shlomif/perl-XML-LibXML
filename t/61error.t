use Test;
BEGIN { use XML::LibXML;
        if ( XML::LibXML::HAVE_STRUCT_ERRORS() ) {
            plan tests => 4;
        }else{
            plan tests => 2;
        }
}
END { ok(0) unless $loaded }

use XML::LibXML::Error;
$loaded = 1;
ok(1);

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



