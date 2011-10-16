use Test::More;
BEGIN { plan tests => 3 };

use warnings;
use strict;

BEGIN {$ENV{'DEBUG_MEMORY'} = 1;}
use XML::LibXML;
use XML::LibXML::Devel qw(:all);

$|=1;

# Base line
{
  my $raw;
  my $doc = XML::LibXML::Document->new();
  my $mem_before = mem_used();
  {
    my $node = $doc->createTextNode("Hello");
  
    $raw = node_from_perl($node);
    refcnt_inc($raw);
  }
  
  cmp_ok(mem_used(), '>', $mem_before);

  is(1, refcnt_dec($raw));

  is($mem_before, mem_used());

}


