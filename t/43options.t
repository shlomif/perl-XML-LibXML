# -*- cperl -*-

use Test;
use strict;
use warnings;
BEGIN { plan tests => 289}

use XML::LibXML;

my @all = qw(
  recover
  expand_entities
  load_ext_dtd
  complete_attributes
  validation
  suppress_errors
  suppress_warnings
  pedantic_parser
  no_blanks
  expand_xinclude
  xinclude
  no_network
  clean_namespaces
  no_cdata
  no_xinclude_nodes
  old10
  no_base_fix
  huge
  oldsax
  line_numbers
  URI
  base_uri
  gdome
);
my %old = map { $_=> 1 } qw(
recover
pedantic_parser
line_numbers
load_ext_dtd
complete_attributes
expand_xinclude
gdome_dom
clean_namespaces
no_network
);


{
  my $p = XML::LibXML->new();
  for (@all) {
    my $ret = /^(?:load_ext_dtd|expand_entities|huge)$/ ? 1 : 0;
    ok(($p->get_option($_)||0) == $ret);
  }
  ok(! $p->option_exists('foo'));

  ok( $p->keep_blanks() == 1 );
  ok( $p->set_option(no_blanks => 1) == 1);
  ok( ! $p->keep_blanks() );
  ok( $p->keep_blanks(1) == 1 );
  ok( ! $p->get_option('no_blanks') );

  my $uri = 'http://foo/bar';

  ok( $p->set_option(URI => $uri) eq $uri);
  ok ($p->base_uri() eq $uri);
  ok ($p->base_uri($uri.'2') eq $uri.'2');
  ok( $p->get_option('URI') eq $uri.'2');
  ok( $p->get_option('base_uri') eq $uri.'2');
  ok( $p->set_option(base_uri => $uri) eq $uri);
  ok( $p->set_option(URI => $uri) eq $uri);
  ok ($p->base_uri() eq $uri);

  ok( ! $p->recover_silently() );
  $p->set_option(recover => 1);

  ok( $p->recover_silently() == 0 );
  $p->set_option(recover => 2);
  ok( $p->recover_silently() == 1 );
  ok( $p->recover_silently(0) == 0 );
  ok( $p->get_option('recover') == 0 );
  ok( $p->recover_silently(1) == 1 );
  ok( $p->get_option('recover') == 2 );

  ok( $p->expand_entities() == 1 );
  ok( $p->load_ext_dtd() == 1 );
  $p->load_ext_dtd(0);
  ok( $p->load_ext_dtd() == 0 );
  $p->expand_entities(0);
  ok( $p->expand_entities() == 0 );
  $p->expand_entities(1);
  ok( $p->expand_entities() == 1 );
}

{
  my $p = XML::LibXML->new(map { $_=>1 } @all);
  for (@all) {
    ok($p->get_option($_)==1);
    ok($p->$_()==1) if $old{$_};
  }
  for (@all) {
    ok($p->option_exists($_));
    ok($p->set_option($_,0)==0);
    ok($p->get_option($_)==0);
    ok($p->set_option($_,1)==1);
    ok($p->get_option($_)==1);
    if ($old{$_}) {
      ok($p->$_()==1);
      ok($p->$_(0)==0);
      ok($p->$_()==0);
      ok($p->$_(1)==1);
    }

  }
}

{
  my $p = XML::LibXML->new(map { $_=>0 } @all);
  for (@all) {
    ok($p->get_option($_)==0);
    ok($p->$_()==0) if $old{$_};
  }
}

{
  my $p = XML::LibXML->new({map { $_=>1 } @all});
  for (@all) {
    ok($p->get_option($_)==1);
    ok($p->$_()==1) if $old{$_};
  }
}
