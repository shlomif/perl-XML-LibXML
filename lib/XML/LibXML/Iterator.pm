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
        if  ( not defined $node ) {
            $node = $self->{CURRENT}->parentNode;
        }
        elsif ( $node->hasChildNodes ) {
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
            unless ( defined $node ) {
                $node = $self->{CURRENT}->parentNode;
                $node = $node->nextSibling if defined $node;
            }
        }
    }

    return $node;
}

1;
__END__

=head1 NAME

XML::LibXML::Iterator - Simple Tree Iteration Class for XML::LibXML

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

An iterator allows to operate on a document tree as it would be a
linear sequence of nodes.

=head2 Functions

=over 4

=item new($first_node)

=item first()

=item next()

=item previous()

=item last()

=item current()

=item index()

=item iterator_function($funcion_ref);

=item iterate($function_ref);

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
