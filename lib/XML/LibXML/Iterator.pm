# $Id$
#

package XML::LibXML::Iterator;
use strict;

use overload
  '++' => sub { $_[0]->next; $_[0]; },
  '--' => sub { $_[0]->previous; $_[0]; },
  '<>' => sub {
      if ( wantarray ) {
          my @rv = ();
          while ( $_[0]->next ){
              push @rv;
          }
          return @rv;
      } else {
          return $_[0]->next
      };
  },
;

sub new {
    my $class = shift;
    my $node  = shift;

    return undef unless defined $node;

    my $self = bless {}, $class;

    $self->{FIRST} = $node;
    $self->first;
    $self->{ITERATOR} = \&default_iterator;

    return $self;
}

sub iterator_function {
    my $self = shift;
    my $func = shift;

    return if defined $func and ref( $func ) ne "CODE";

    $self->first;
    if ( defined $func ) {
        $self->{ITERATOR} = $func;
    }
    else {
        $self->{ITERATOR} = \&default_iterator;
    }
}

sub current  { return $_[0]->{CURRENT}; }
sub index    { return $_[0]->{INDEX}; }

sub next     {
    my $self = shift;
    my $node = $self->{ITERATOR}->( $self, 1 );

    if ( defined $node ) {
        $self->{CURRENT} = $node;
        $self->{INDEX}++;
    }

    return $node;
}

sub previous {
    my $self = shift;

    my $node = $self->{ITERATOR}->( $self, -1 );

    if ( defined $node ) {
        $self->{CURRENT} = $node;
        $self->{INDEX}--;
    }

    return $node;
}


sub first {
    my $self = shift;
    if ( scalar @_ ) {
        $self->{FIRST} = shift;
    }
    $self->{CURRENT} = $self->{FIRST};
    $self->{INDEX}   = 0;
    return $self->current;
}

sub last  {
    my $self = shift;
    while ($self->next) {}
    return $self->current;
}

sub iterate {
    my $self = shift;
    my $function = shift;
    return unless defined $function and ref( $function ) eq 'CODE' ;
    my $rv;
    my $node = $self->first;
    while ( $node ) {
        $rv = $function->($self,$node);
        $node = $self->next;
    }
    return $rv;
}

sub default_iterator {
    my $self = shift;
    my $dir  = shift;
    my $node = undef;


    if ( $dir < 0 ) {
        return undef if $self->{CURRENT}->isSameNode( $self->{FIRST} )
          and $self->{INDEX} <= 0;

        $node = $self->{CURRENT}->previousSibling;
        return $self->{CURRENT}->parentNode unless defined $node;

        while ( $node->hasChildNodes ) {
            $node = $node->lastChild;
        }
    }
    else {
        return undef if $self->{CURRENT}->isSameNode( $self->{FIRST} )
          and $self->{INDEX} > 0;

        if ( $self->{CURRENT}->hasChildNodes ) {
            $node = $self->{CURRENT}->firstChild;
        }
        else {
            $node = $self->{CURRENT}->nextSibling;
            my $pnode = $self->{CURRENT}->parentNode;
            while ( not defined $node ) {
                last unless defined $pnode;
                $node = $pnode->nextSibling;
                $pnode = $pnode->parentNode unless defined $node;
            }
        }
    }

    return $node;
}

1;
__END__

=head1 NAME

XML::LibXML::Iterator - XML::LibXML's Simple Tree Iteration Class

=head1 SYNOPSIS

  use XML::LibXML;
  use XML::LibXML::Iterator;

  my $doc = XML::LibXML->new->parse_string( $somedata );
  my $iter= XML::LibXML::Iterator->new( $doc );

  $iter->iterator_function( \&iterate );

  # more control on the flow
  while ( $iter->next ) {
      # do something
  }

  # operate on the entire tree
  $iter->iterate( \&operate );

=head1 DESCRIPTION

XML::LibXML::Iterator is an iterator class for XML::LibXML parsed
documents. This class allows to iterate the document tree as it were a
linear data structure. It is possible to step back and forth between
the nodes of the tree and do certain operations on that
nodes. Different to XPath the nodes are not prefetched but will be
calculated for each step. Therefore an iterator is sensible towards
the current state of a document tree on each step, while XPath is only
per query executed.

=head2 What is an iterator?

XML::LibXML offers by default a W3C DOM interface on the parsed XML
documents. This tree has per definition four directions to be
traversed: Up, down, foreward and backward. Therefore a tree can be
considered two dimensional. Although a tree is still one more simple
datastructure it is way to complex for some operations. So the
XML::LibXML::Iterator class breaks the for operations down to only
two: backward and forward. For some people this easier to understand
than DOM or SAX as this follows more the way one actually reads an XML
document.

Therefore an iterator has three basic functions:

=over 4

=item * next()

=item * current()

=item * previous()

=back

That's it. With an iterator one does not have to decide when to dive
into a subtree or find a parent. It is not even required to care about
the boundaries of a certain level. The iterator will get the next node
for you until there is no node left to handle.

In short: An iterator will answer the question about what is next to
do.

=head2 How to use XML::LibXML::Iterator?

XML::LibXML::Iterator requires a parsed document or at least a node to
operate on. This node is passed to the iterator class and will be used
as the B<first> node of the iteration. One can allways reset the
iterator to the first node by using the first()-function.

Once XML::LibXML::Iterator is initialized the tree can be traversed by
using either next() or previous(). Both function will return a
XML::LibXML::Node object if there is such object available.

Since the current object in the iterator is always available via the
current() function, the position of the iterator can be changed inside
a method or function.


=head2 Functions

=over 4

=item new($first_node)

=item first()

=item next()

=item previous()

=item last()

=item current()

=item index()

=item iterator_function($funcion_ref)

=item iterate($function_ref)

=back


XML::LibXML::Iterator knows two types of callback. One is knows as the
iterator function, the other is used by iterate(). The first function
will be called for each call of next() or previous(). It is used to
find out about the next node recognized by the iterator.

The iterator function has to take two parameters: As the first
parameter it will recieve the iterator object, as second the direction
of the iteration will be passed. The direction is either 1 (for next())
or -1 (for previous()).

The iterators iterate() function will take a function reference that
takes as well two parameters. The first parameter is again the
iterator object. The second parameter is the node to operate on. The
iterate function can do any operation on the node as
prefered. Appending new nodes or removing the current node will not
confuse the iteration process: The iterator preloads the next object
before calling the iteration function. Thus the Iterator will not find
nodes appended by the iteration function.
