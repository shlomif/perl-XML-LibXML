use strict;
use warnings;

use Test::More tests => 3;

use XML::LibXML;

# TEST
ok(1, 'Loaded fine');

my $p = XML::LibXML->new();
# TEST
ok ($p, 'Can initialize a new XML::LibXML instance');

# TEST
if (!is (
    XML::LibXML::LIBXML_VERSION, XML::LibXML::LIBXML_RUNTIME_VERSION,
    'LIBXML__VERSION == LIBXML_RUNTIME_VERSION',
))
{
   diag("DO NOT REPORT THIS FAILURE: Your setup of library paths is incorrect!");
}

diag( "\n\nCompiled against libxml2 version: ",XML::LibXML::LIBXML_VERSION,
     "\nRunning libxml2 version:          ",XML::LibXML::LIBXML_RUNTIME_VERSION,
     "\n\n");
