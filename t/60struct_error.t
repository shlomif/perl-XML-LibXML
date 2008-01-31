# $Id: 29_struct_errors.t,v 1.1.2.2 2006/06/22 14:34:47 pajas Exp $
# First version of the new structured error test suite

use Test;
BEGIN { 
    use XML::LibXML;
    if ( XML::LibXML::HAVE_STRUCT_ERRORS() ) {
        plan tests => 6;
    } else {
        plan tests => 1;
    }

}

eval {
  use XML::LibXML::Error;
  use XML::LibXML::ErrNo;
  $loaded = 1;
};
ok(!$@ && $loaded);

if (XML::LibXML::HAVE_STRUCT_ERRORS() ) {
  my $p = XML::LibXML->new();
  my $xmlstr = '<X></Y>';

  eval {
    my $doc = $p->parse_string( $xmlstr );
  };
  my $err = $@;
  ok(defined $err);
  if ($err) {
    ok(ref($err), "XML::LibXML::Error");
    ok($err->domain(), "parser");
    ok($err->line(), 1);
    ok($err->code == XML::LibXML::ErrNo::ERR_TAG_NAME_MISMATCH);
  } else {
    fail() for 1..3;
  }

} # HAVE_STRUCT_ERRORS
