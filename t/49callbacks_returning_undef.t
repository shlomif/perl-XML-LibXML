
# This is a bug fix for:
# https://rt.cpan.org/Ticket/Display.html?id=70321
#
# When the match callback returns 1 and the open callback returns undef, then the
# read callback (inside the XS code) warnings about:
# "Use of uninitialized value in subroutine entry at".
#
# This is due to the value returned being undef and processed by SvPV.

use strict;
use warnings;

use lib './t/lib';

use Test::More tests => 1;

use XML::LibXML;

my $string = <<EOF;
<?xml version="1.0" encoding="us-ascii"?>
<!DOCTYPE foo [
    <!ENTITY foo SYSTEM "file:///etc/passwd">
]>
<methodCall>
  <methodName>metaWeblog.newPost</methodName>
  <params>
    <param>
      <value><string>Entity test: &foo;</string></value>
    </param>
  </params>
</methodCall>
EOF

my $icb    = XML::LibXML::InputCallback->new();

my $match_ret = 1;
$icb->register_callbacks( [ 
        sub { my $to_ret = $match_ret; $match_ret = 0; return $to_ret; }, 
        sub { return undef; },
        undef,
        undef 
    ] 
);

my $parser = XML::LibXML->new();
$parser->input_callbacks($icb);
my $num_warnings = 0;
{
    local $^W = 1;
    local $SIG{__WARN__} = sub {
        $num_warnings++;
    };
    my $doc = $parser->parse_string($string);
}
# TEST
is ($num_warnings, 0, "No warnings were recorded.");
