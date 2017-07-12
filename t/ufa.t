#test bug use after free in function replaceChild
use Test::More;
use XML::LibXML;

BEGIN { $| = 1 }
my $data='<mipu94><pwn4fun><ufanode>-------------------------------------------------------tadinhsung-at-gmail-dot-com-----------------------------------------------------</ufanode></pwn4fun></mipu94>';
my $parser = XML::LibXML->new();
my $info = $parser->load_xml(string=>$data) or die;
my $root = $info->findnodes("mipu94")->[0];
my $ufanode = $root->findnodes("pwn4fun/ufanode")->[0];
ok(!$root->replaceChild($ufanode,$ufanode),"Test UFA in replaceChild");
done_testing();
