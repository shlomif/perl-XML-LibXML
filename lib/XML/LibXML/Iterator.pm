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

use XML::NodeFilter qw(:results);

sub new {
    my $class = shift;
    my $node  = shift;

    return undef unless defined $node;

    my $self = bless {}, $class;

    $self->{FIRST} = $node;
    $self->first;
    $self->{ITERATOR} = \&default_iterator;

    $self->{FILTERS} = [];

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

sub set_filter {
    my $self = shift;
    $self->{FILTERS} = [ @_ ];
}

sub add_filter {
    my $self = shift;
    push @{$self->{FILTERS}}, @_;
}

sub current  { return $_[0]->{CURRENT}; }
sub index    { return $_[0]->{INDEX}; }

sub next     {
    my $self = shift;
    my @filters = @{$self->{FILTERS}};
    my $node = undef;
    my $fv = FILTER_SKIP;
    unless ( scalar @filters > 0 ) {
        $fv = FILTER_DECLINED;
    }
    while ( 1 ) {
        $node = $self->{ITERATOR}->( $self, 1 );
        last unless defined $node;
        foreach my $f ( @filters ) {
            $fv = $f->accept_node( $node );
            last if $fv;
        }
        last if $fv == FILTER_ACCEPT or $fv == FILTER_DECLINED;
    }

    if ( defined $node ) {
        $self->{CURRENT} = $node;
        $self->{INDEX}++;
    }

    return $node;
}

sub previous {
    my $self = shift;
    my @filters = @{$self->{FILTERS}};
    my $node = undef;
    my $fv = FILTER_SKIP;
    unless ( scalar @filters > 0 ) {
        $fv = FILTER_DECLINED;
    }
    while ( 1 ) {
        $node = $self->{ITERATOR}->( $self, -1 );
        last unless defined $node;
        foreach my $f ( @filters ) {
            $fv = $f->accept_node( $node );
            last if $fv;
        }
        last if $fv == FILTER_ACCEPT or $fv == FILTER_DECLINED;
    }

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

    # this logic is required if the node is not allowed to be shown
    my @filters = @{$self->{FILTERS}||[]};
    my $fv = FILTER_DECLINED;

    foreach my $f ( @filters ) {
        $fv = $f->accept_node( $self->{CURRENT} );
        last if $fv;
    }

    $fv ||= FILTER_ACCEPT;

    unless ( $fv == FILTER_ACCEPT ) {
        return undef;
    }

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

In short: An iterator will answer the question about what to do next.

=head2 How to use XML::LibXML::Iterator?

XML::LibXML::Iterator requires a parsed document or at least a node to
operate on. This node is passed to the iterator class and will be used
as the B<first> node of the iteration. One can allways reset the
iterator to the first node by using the first()-function.

Once XML::LibXML::Iterator is initialized the tree can be traversed by
using either next() or previous(). Both function will return a
XML::LibXML::Node object if there is such object available.

Since the current object hold by the iterator class is always
available via the current() function.

The following example may clearify this:

  # get the document from wherever you like
  my $doc = XML::LibXML->new->parse_stream( *SOMEINPUT );

  # get the iterator for the document root.
  my $iter = XML::LibXML::Iterator->new( $doc->documentElement );

  # walk through the document
  while ( $iter->next() ) {
     my $curnode = $iter->current();
     print $curnode->nodeType();
  }

  # now get back to the beginning
  $iter->first();
  my $curnode = $iter->current();
  print $curnode->nodeType();

Actually the functions next(), previous(), first(), last() and
current() do return the node which is current after the
operation. E.g. next() moves to the next node if possible and then
returns the node. Thus the while-loop in the example can be written
as

  while ( $iter->next() ) {
     print $_->nodeType();
  }

Note, that just relieing on the return value of next() and previous()
is somewhat dangerous, because both functions return B<undef> in case
of reaching the iteration boundaries. That means it is not possible
to iterate past the last element or before the first one.

=head2 Node Filters

XML::LibXML::Iterator accepts XML::NodeFilters to limit the nodes made
available to the caller. Any nodefilter applied to
XML::LibXML::Iterator will test if a node returned by the iteration
function is visible to the caller.

Different to the DOM Traversal Specification, XML::LibXML::Iterator
allows filter stacks. This means it is possible to apply more than a
single node filter to your node iterator.

=head2 Complex Iterations

By default XML::LibXML::Iterator will access all nodes of a given DOM
tree. An interation based on the default iterator will access each
single node in the given subtree once. The order how the nodes will be
accessed is given by the following order:

  node -> node's childnodes -> node's next sibling

In combination with XML::Nodefilter this is best for a wide range of
scripts and applications. Nevertheless this is still to restrictive
for some applications. XML::LibXML::Iterator allows to change that
behaviour. This is done by resetting XML::LibXML::Iterator's iterator
function. By using the method iterator_function() to override the
default iterator function, it is possible to implement iterations
based on any iteration rule imaginable.

A valid iterator function has to take two parameters: As the first
parameter it will recieve the iterator object itself, as second the
direction of the iteration will be passed. The direction is either 1
(for next()) or -1 (for previous()). As the iterator-function is
called by next() and previous() the interator-function has to be aware
about the iteration boundaries. In case the iteration would pass the
boundary for that operation, the function has to return
undefined. Also the iterator function has to return the new current node,
instead of setting it itself.

*DEVELOPER NOTE* In order a single stepping is rather limited, the
direction is given by the sign of the passed integer value. The value
of the passed parameter will be used as an indication how many steps
should be done.  Therefor the interation direction should be tested
relative to '0' and not as a equation. A basic template for a iterator
function therefore will look like this:

   sub iterator_func_templ {
      my $iter = shift;
      my $step = shift;
      my $node = undef;
      my $current = $iter->current();

      if ( $step > 0 ) {
          # move forward
      }
      else {
          # move backward
          $step *= -1; # remove the sign
      }

      return $node;
   }

=head2 Repeated Operation

Another feature of XML::LibXML::Iterator is the ability to repeat a
single operation on all nodes in scope. Instead of writing a loop one
can specify the opeation as a function, that it applied on each node
found. The function that does the trick, is named iterate().

iterate() takes again two parameter: First the iterator object, second
the node to operate on. iterate() will iterate through the entire
document starting with the first node. If one has already started an
iteration, the internal position will be reset to the first node.

The following example will show how this works:

  $iter->iterate( sub {shift; map {$_->setNodeName( lc $_->nodeName ) if $_->nodeType != NAMESPACE_DECLARATION } ($_[0], $_[0]->attributes);  } );

This extra long line lowercases all tagnames and the names of the
attributes in a given subtree.

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

=item set_filter(@filter_list)

=item add_filter(@filter_list)

=item iterate($function_ref)

=back

=head1 SEE ALSO

L<XML::LibXML::Node>, L<XML::NodeFilter>

=head1 AUTHOR

Christian Glahn, E<lt>christian.glahn@uibk.ac.atE<gt>

=head1 COPYRIGHT

(c) 2002, Christian Glahn. All rights reserved.

This package is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
