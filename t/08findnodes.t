use Test;
BEGIN { plan tests=>5; }
END {ok(0) unless $loaded;}
use XML::LibXML;
$loaded = 1;
ok($loaded);

# to test if findnodes works.
# i added findnodes to the node class, so a query can be started
# everywhere. Since I use only the 

my $file    = "example/dromeds.xml";

# init the file parser
my $parser = XML::LibXML->new();
$dom    = $parser->parse_file( $file );

if ( defined $dom ) {
  # get the root document
  $elem   = $dom->getDocumentElement();
  
  # first very simple path starting at root
  my @list   = $elem->findnodes( "species" );
  ok( scalar(@list) == 3 );

  # a simple query starting somewhere ...
  my $node = $list[0];
  my @slist = $node->findnodes( "humps" );
  ok( scalar(@slist) == 1 );

  # find a single node
  @list   = $elem->findnodes( "species[\@name='Llama']" );
  ok( scalar( @list ) == 1 );
  
  # find with not conditions
  @list   = $elem->findnodes( "species[\@name!='Llama']/disposition" );
  ok( scalar(@list) == 2 );
}
