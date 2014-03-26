# -*- cperl -*-

##
# This test checks that the XS code handles the perl stack correctly
# when the module loads.  This failed in 5.19.6+.
#
# See: https://rt.cpan.org/Ticket/Display.html?id=92606 .

use Test::More tests => 1;

for (1) {
    for (1,0) {
        require XML::LibXML;
    }
}

# If we get this far, then all is fine.
# TEST
pass("Loading XML::LibXML works inside multiple foreach loops");
