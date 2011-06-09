# $Id: 29_struct_errors.t,v 1.1.2.2 2006/06/22 14:34:47 pajas Exp $
# First version of the new structured error test suite

use Test;
BEGIN { 
    use XML::LibXML;
    if ( XML::LibXML::HAVE_STRUCT_ERRORS() ) {
        plan tests => 8;
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

  my $fake_err = XML::LibXML::Error->new('fake error');
  my $domain_num = @XML::LibXML::Error::error_domains;      # too big
  $fake_err->{domain} = $domain_num;                        # white-box test
  ok($fake_err->domain, "domain_$domain_num",
     '$err->domain is reasonable on unknown domain');
  {
      my $warnings = 0;
      local $SIG{__WARN__} = sub { $warnings++; warn "@_\n" };
      my $s = $fake_err->as_string;
      ok($warnings, 0,
         'no warnings when stringifying unknown-domain error');
  }
} # HAVE_STRUCT_ERRORS
