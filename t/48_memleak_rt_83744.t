
use strict;
use warnings;

=head1 DESCRIPTION

XPathContext memory leak on registerFunction.

See L<https://rt.cpan.org/Ticket/Display.html?id=83744>.

=cut

use constant HAS_LEAKTRACE => eval{ require Test::LeakTrace };
use Test::More HAS_LEAKTRACE ? (tests => 2) : (skip_all => 'Test::LeakTrace is required for memory leak tests.');
use Test::LeakTrace;

# TEST
no_leaks_ok {
    use XML::LibXML::XPathContext;
} 'load XPathContext without leaks';

# TEST
no_leaks_ok {
    my $context = XML::LibXML::XPathContext->new();
    $context->registerFunction('match-font', sub {1;});
    $context->unregisterFunction('match-font');
} 'register an XPath function and unregister it, without leaks';
