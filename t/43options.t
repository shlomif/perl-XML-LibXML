# -*- cperl -*-

use strict;
use warnings;

use Test::More tests => 290;

use XML::LibXML;

# TEST:$all=23
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

# TEST:$old=8
my %old = map { $_=> 1 } qw(
recover
pedantic_parser
line_numbers
load_ext_dtd
complete_attributes
expand_xinclude
clean_namespaces
no_network
);


{
  my $p = XML::LibXML->new();
  for my $opt (@all) {
    my $ret = (($opt =~ /^(?:load_ext_dtd|expand_entities)$/) ? 1 : 0);
    # TEST*$all
    ok(
        ($p->get_option($opt)||0) == $ret
            ,
        "Testing option $opt",
    );
  }
  # TEST
  ok(! $p->option_exists('foo'), ' TODO : Add test name');

  # TEST
  ok( $p->keep_blanks() == 1, ' TODO : Add test name' );
  # TEST
  ok( $p->set_option(no_blanks => 1) == 1, ' TODO : Add test name');
  # TEST
  ok( ! $p->keep_blanks(), ' TODO : Add test name' );
  # TEST
  ok( $p->keep_blanks(1) == 1, ' TODO : Add test name' );
  # TEST
  ok( ! $p->get_option('no_blanks'), ' TODO : Add test name' );

  my $uri = 'http://foo/bar';

  # TEST
  ok( $p->set_option(URI => $uri) eq $uri, ' TODO : Add test name');
  # TEST
  ok ($p->base_uri() eq $uri, ' TODO : Add test name');
  # TEST
  ok ($p->base_uri($uri.'2') eq $uri.'2', ' TODO : Add test name');
  # TEST
  ok( $p->get_option('URI') eq $uri.'2', ' TODO : Add test name');
  # TEST
  ok( $p->get_option('base_uri') eq $uri.'2', ' TODO : Add test name');
  # TEST
  ok( $p->set_option(base_uri => $uri) eq $uri, ' TODO : Add test name');
  # TEST
  ok( $p->set_option(URI => $uri) eq $uri, ' TODO : Add test name');
  # TEST
  ok ($p->base_uri() eq $uri, ' TODO : Add test name');

  # TEST
  ok( ! $p->recover_silently(), ' TODO : Add test name' );
  $p->set_option(recover => 1);

  # TEST
  ok( $p->recover_silently() == 0, ' TODO : Add test name' );
  $p->set_option(recover => 2);
  # TEST
  ok( $p->recover_silently() == 1, ' TODO : Add test name' );
  # TEST
  ok( $p->recover_silently(0) == 0, ' TODO : Add test name' );
  # TEST
  ok( $p->get_option('recover') == 0, ' TODO : Add test name' );
  # TEST
  ok( $p->recover_silently(1) == 1, ' TODO : Add test name' );
  # TEST
  ok( $p->get_option('recover') == 2, ' TODO : Add test name' );

  # TEST
  ok( $p->expand_entities() == 1, ' TODO : Add test name' );
  # TEST
  ok( $p->load_ext_dtd() == 1, ' TODO : Add test name' );
  $p->load_ext_dtd(0);
  # TEST
  ok( $p->load_ext_dtd() == 0, ' TODO : Add test name' );
  $p->expand_entities(0);
  # TEST
  ok( $p->expand_entities() == 0, ' TODO : Add test name' );
  $p->expand_entities(1);
  # TEST
  ok( $p->expand_entities() == 1, ' TODO : Add test name' );
}

{
    my $XML = <<'EOT';
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE title [ <!ELEMENT title ANY >
<!ENTITY xxe SYSTEM "file:///etc/passwd" >]>
<rss version="2.0">
<channel>
    <link>example.com</link>
    <description>XXE</description>
    <item>
        <title>&xxe;</title>
        <link>example.com</link>
        <description>XXE here</description>
    </item>
</channel>
</rss>
EOT

    my $sys_line = <<'EOT';
<title>&xxe;</title>
EOT

    chomp ($sys_line);

    my $parser = XML::LibXML->new(
        expand_entities => 0,
        load_ext_dtd    => 0,
        no_network      => 1,
        expand_xinclude => 0,
    );
    my $XML_DOC = $parser->load_xml( string => $XML, );

    # TEST
    ok (scalar($XML_DOC->toString() =~ m{\Q$sys_line\E}),
        "expand_entities is preserved after _clone()/etc."
    );
}

{
  my $p = XML::LibXML->new(map { $_=>1 } @all);
  for my $opt (@all) {
    # TEST*$all
    ok($p->get_option($opt)==1, ' TODO : Add test name');
    # TEST*$old
    if ($old{$opt})
    {
        ok($p->$opt()==1, ' TODO : Add test name')
    }
  }

  for my $opt (@all) {
    # TEST*$all
    ok($p->option_exists($opt), ' TODO : Add test name');
    # TEST*$all
    ok($p->set_option($opt,0)==0, ' TODO : Add test name');
    # TEST*$all
    ok($p->get_option($opt)==0, ' TODO : Add test name');
    # TEST*$all
    ok($p->set_option($opt,1)==1, ' TODO : Add test name');
    # TEST*$all
    ok($p->get_option($opt)==1, ' TODO : Add test name');
    if ($old{$opt}) {
      # TEST*$old
      ok($p->$opt()==1, ' TODO : Add test name');
      # TEST*$old
      ok($p->$opt(0)==0, ' TODO : Add test name');
      # TEST*$old
      ok($p->$opt()==0, ' TODO : Add test name');
      # TEST*$old
      ok($p->$opt(1)==1, ' TODO : Add test name');
    }

  }
}

{
  my $p = XML::LibXML->new(map { $_=>0 } @all);
  for my $opt (@all) {
    # TEST*$all
    ok($p->get_option($opt)==0, ' TODO : Add test name');
    # TEST*$old
    if ($old{$opt})
    {
        ok($p->$opt()==0, ' TODO : Add test name');
    }
  }
}

{
    my $p = XML::LibXML->new({map { $_=>1 } @all});
    for my $opt (@all) {
        # TEST*$all
        ok($p->get_option($opt)==1, ' TODO : Add test name');
        # TEST*$old
        if ($old{$opt})
        {
            ok($p->$opt()==1, ' TODO : Add test name');
        }
    }
}
