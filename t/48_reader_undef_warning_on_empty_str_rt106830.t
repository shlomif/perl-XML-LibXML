# This is a test for:
# https://rt.cpan.org/Ticket/Display.html?id=106830

=head1 DESCRIPTION

XML::LibXML::Reader emits a warning on empty string.

=head1 THANKS.

Rich.

=cut

use strict;
use warnings;

use Test::More tests => 2;

use lib './t/lib';
use TestHelpers ( qw(eq_or_diff) );

use XML::LibXML::Reader;

{
    my @warnings;

    local $SIG{__WARN__} = sub { push @warnings, [@_] };

    my $empty_xml_doc = '';
    my $xml_reader = XML::LibXML::Reader->new(string => $empty_xml_doc);

    # TEST
    SKIP:
    {
        if (XML::LibXML::LIBXML_VERSION() >= 20905)
        {
            skip 'libxml2 accepts empty strings since 2.9.5 version', 1;
        }
        ok (scalar(!defined($xml_reader)), 'xml_reader is undef', );
    }

    # TEST
    eq_or_diff(
        \@warnings,
        [],
        'no warnigns were emitted.'
    );
}


=head1 COPYRIGHT & LICENSE

Copyright 2015 by Shlomi Fish

This program is distributed under the MIT (Expat) License:
L<http://www.opensource.org/licenses/mit-license.php>

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

=cut
