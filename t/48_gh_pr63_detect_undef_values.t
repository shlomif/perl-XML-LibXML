
use strict;
use warnings;

=head1 DESCRIPTION

L<https://github.com/shlomif/perl-XML-LibXML/pull/63>

This test program

    use warnings;
    use XML::LibXML;

    my $test = XML::LibXML::Text->new({}->{bar});

produces the following warning:

    $ perl ~/test.pl
    Use of uninitialized value in subroutine entry at /home/sven/test.pl line 4.

This apparently happens, because Sv2C tries to catch undef values by comparing the memory location of the scalar in question to &PL_sv_undef. While PL_sv_undef certainly is an undef value, not all undef values share its memory location. The added commit fixes this, by using SvOK to correctly detect all undef values.

=cut

use Test::More tests => 1;

use XML::LibXML;

$SIG{__WARN__} = sub { die "warning " . shift . "!"; };

my $test = XML::LibXML::Text->new( {}->{bar} );

# TEST
pass("success");
