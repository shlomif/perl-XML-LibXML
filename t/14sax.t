use Test;
BEGIN { plan tests => 33 }
use XML::LibXML;
use XML::LibXML::SAX::Parser;
use XML::LibXML::SAX::Builder;
use XML::SAX;
use IO::File;
ok(1);

ok(XML::SAX->add_parser(q(XML::LibXML::SAX::Parser)));

local $XML::SAX::ParserPackage = 'XML::LibXML::SAX::Parser';

my $sax = SAXTester->new;
ok($sax);

my $str = join('', IO::File->new("example/dromeds.xml")->getlines);
my $doc = XML::LibXML->new->parse_string($str);
ok($doc);

my $generator = XML::LibXML::SAX::Parser->new(Handler => $sax);
ok($generator);

$generator->generate($doc);

my $builder = XML::LibXML::SAX::Builder->new();
ok($builder);
my $gen2 = XML::LibXML::SAX::Parser->new(Handler => $builder);
my $dom2 = $gen2->generate($doc);
ok($dom2);

ok($dom2->toString, $str);
# warn($dom2->toString);

########### XML::SAX Tests ###########
my $parser = XML::SAX::ParserFactory->parser(Handler => $sax);
ok($parser);
$parser->parse_uri("example/dromeds.xml");

########### Helper class #############

package SAXTester;
use Test;

sub new {
    my $class = shift;
    return bless {}, $class;
}

sub start_document {
  ok(1);
}

sub end_document {
  ok(1);
}

sub start_element {
  my ($self, $el) = @_;
  ok($el->{Name}, qr{^(dromedaries|species|humps|disposition)$});
  foreach my $attr (keys %{$el->{Attributes}}) {
    # warn("Attr: $attr = $el->{Attributes}->{$attr}\n");
  }
# warn("start_element: $el->{Name}\n");
}

sub end_element {
  my ($self, $el) = @_;
  # warn("end_element: $el->{Name}\n");
}

sub characters {
  my ($self, $chars) = @_;
  # warn("characters: $chars->{Data}\n");
}
