
use strict;
use warnings;

=head1 DESCRIPTION

Getting wrong result when parsing HTML string as a scalar reference.

See L<https://rt.cpan.org/Ticket/Display.html?id=87089> .

=cut

use Test::More tests => 2;

use XML::LibXML;

my $parser = XML::LibXML->new();

# Parse HTML string as scalar
{
    my $dom = $parser->load_html(string => '<!DOCTYPE html><html>');
    # TEST
    is ($dom->toStringHTML, "<!DOCTYPE html>\n<html></html>\n",
        "Parse HTML string as scalar");
}

# Parse HTML string as scalar reference
{
    my $dom = $parser->load_html(string => \'<!DOCTYPE html><html>');
    # TEST
    is ($dom->toStringHTML, "<!DOCTYPE html>\n<html></html>\n",
        "Parse HTML string as scalar reference");
}
