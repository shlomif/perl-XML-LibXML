
use strict;
use warnings;
use Scalar::Util qw(blessed);

=head1 DESCRIPTION

Double free on RHEL-5-x86_64.

See L<https://rt.cpan.org/Ticket/Display.html?id=83779>.

=cut

use constant HAS_LEAKTRACE => eval{ require Test::LeakTrace };
use Test::More HAS_LEAKTRACE ? (tests => 6) : (skip_all => 'Test::LeakTrace is required.');
use Test::LeakTrace;
use XML::LibXML::Reader;

my $xml = <<'EOF';
<html>
  <head>
    <title>David vs. Goliath - Part I</title>
  </head>
  <body>
  </body>
</html>
EOF

my $xml_decl = <<'EOF';
<?xml version="1.0"?>
EOF

{
    my $r = XML::LibXML::Reader->new(string => $xml);
    my @nodes;
    while ($r->read) {
        push @nodes, $r->name;
    }
    # TEST
    is(
        join(',', @nodes),
        'html,#text,head,#text,title,#text,title,#text,head,#text,body,#text,body,#text,html',
        'Check reader'
    );
}

{
    my $r = XML::LibXML::Reader->new(string => $xml);
    while ($r->read) {
        $r->preserveNode();
    }
    # TEST
    is(
        $r->document->toString(),
        $xml_decl . $xml,
        'Check reader with using preserveNode'
    );
}

{
    my $r = XML::LibXML::Reader->new(string => $xml);
    my $copy;
    while ($r->read) {
        $copy = $r->copyCurrentNode() if $r->name eq 'body';
    }
    # TEST
    is(
        $copy->toString(),
        '<body/>',
        'Check reader with using copyCurrentNode'
    );
}

# TEST
no_leaks_ok {
    my $r = XML::LibXML::Reader->new(string => $xml);
    while ($r->read) {
        # nothing
    }
} 'Check reader, without leaks';

# TEST
no_leaks_ok {
    my $node;
    {
        my $r = XML::LibXML::Reader->new(string => $xml);
        while ($r->read) {
            $node ||= $r->preserveNode();
        }
        my $doc = $r->document();
    }
} 'Check reader with using preserveNode, without leaks';

# TEST
no_leaks_ok {
    my $r = XML::LibXML::Reader->new(string => $xml);
    while ($r->read) {
        my $copy = $r->copyCurrentNode();
    }
} 'Check reader with using copyCurrentNode, without leaks';
