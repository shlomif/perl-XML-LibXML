use Test;
BEGIN { plan tests => 19 }
use XML::LibXML;
use XML::LibXML::SAX::Generator;
use XML::LibXML::SAX::Builder;
use IO::File;
ok(1);

my $sax = SAXTester->new;
ok($sax);

my $str = join('', IO::File->new("example/dromeds.xml")->getlines);
my $doc = XML::LibXML->new->parse_string($str);
ok($doc);

my $generator = XML::LibXML::SAX::Generator->new(Handler => $sax);
ok($generator);

$generator->generate($doc);

my $builder = XML::LibXML::SAX::Builder->new();
ok($builder);
my $gen2 = XML::LibXML::SAX::Generator->new(Handler => $builder);
my $dom2 = $gen2->generate($doc);
ok($dom2);

ok($dom2->toString, $str);
# warn($dom2->toString);

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
