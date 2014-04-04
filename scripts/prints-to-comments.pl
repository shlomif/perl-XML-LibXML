#!perl -ln -i.bak

use strict;
use warnings;

if (/\A( *)print "(#.*?)\\n";\z/)
{
    $_ = "$1$2";
}
print $_;
