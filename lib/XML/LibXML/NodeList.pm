# $Id$

package XML::LibXML::NodeList;
use strict;
use XML::LibXML::Boolean;
use XML::LibXML::Literal;
use XML::LibXML::Number;

use overload 
		'""' => \&to_literal,
                'bool' => \&to_boolean,
        ;

sub new {
	my $class = shift;
	bless [@_], $class;
}

sub pop {
	my $self = CORE::shift;
	CORE::pop @$self;
}

sub push {
	my $self = CORE::shift;
	CORE::push @$self, @_;
}

sub append {
	my $self = CORE::shift;
	my ($nodelist) = @_;
	CORE::push @$self, $nodelist->get_nodelist;
}

sub shift {
	my $self = CORE::shift;
	CORE::shift @$self;
}

sub unshift {
	my $self = CORE::shift;
	CORE::unshift @$self, @_;
}

sub prepend {
	my $self = CORE::shift;
	my ($nodelist) = @_;
	CORE::unshift @$self, $nodelist->get_nodelist;
}

sub size {
	my $self = CORE::shift;
	scalar @$self;
}

sub get_node {
    # uses array index starting at 1, not 0
    # this is mainly because of XPath.
	my $self = CORE::shift;
	my ($pos) = @_;
	$self->[$pos - 1];
}

*item = \&get_node;

sub get_nodelist {
	my $self = CORE::shift;
	@$self;
}

sub to_boolean {
	my $self = CORE::shift;
	return (@$self > 0) ? XML::LibXML::Boolean->True : XML::LibXML::Boolean->False;
}

# string-value of a nodelist is the string-value of the first node
sub string_value {
	my $self = CORE::shift;
	return '' unless @$self;
	return $self->[0]->string_value;
}

sub to_literal {
	my $self = CORE::shift;
	return XML::LibXML::Literal->new(
			join('', grep {defined $_} map { $_->string_value } @$self)
			);
}

sub to_number {
	my $self = CORE::shift;
	return XML::LibXML::Number->new(
			$self->to_literal
			);
}

sub iterator {
    my $self = CORE::shift;
    return XML::LibXML::NodeList::Iterator->new( $self );
}

1;

package XML::LibXML::NodeList::Iterator;

use strict;
use XML::NodeFilter qw(:results);

use overload
  '++' => sub { $_[0]->next;     $_[0]; },
  '--' => sub { $_[0]->previous; $_[0] },
  '<>'  =>  sub {
      if ( wantarray ) {
          my @rv = ();
          while ( $_[0]->next ){ push @rv,$_;}
          return @rv;
      } else {
          return $_[0]->next
      };
  },
;

sub new {
    my $class = shift;
    my $list  = shift;
    my $self  = undef;
    if ( defined $list ) {
        $self = bless [
                       $list,
                       0,
                       [],
                      ], $class;
    }

    return $self;
}

sub set_filter {
    my $self = shift;
    $self->[2] = [ @_ ];
}

sub add_filter {
    my $self = shift;
    push @{$self->[2]}, @_;
}

# helper function.
sub accept_node {
    foreach ( @{$_[0][2]} ) {
        my $r = $_->accept_node($_[1]);
        return $r if $r;
    }
    # no filters or all decline ...
    return FILTER_ACCEPT;
}

sub first    { $_[0][1]=0;
               my $s = scalar(@{$_[0][0]});
               while ( $_[0][1] < $s ) {
                   last if $_[0]->accept_node($_[0][0][$_[0][1]]) == FILTER_ACCEPT;
                   $_[0][1]++;
               }
               return undef if $_[0][1] == $s;
               return $_[0][0][$_[0][1]]; }

sub last     {
    my $i = scalar(@{$_[0][0]})-1;
    while($i >= 0){
        if ( $_[0]->accept_node($_[0][0][$i] == FILTER_ACCEPT) ) {
            $_[0][1] = $i;
            last;
        }
        $i--;
    }

    if ( $i < 0 ) {
        # this costs a lot, but is more safe
        return $_[0]->first;
    }
    return $_[0][0][$i];
}

sub current  { return $_[0][0][$_[0][1]]; }
sub index    { return $_[0][1]; }

sub next     {
    if ( (scalar @{$_[0][0]}) <= ($_[0][1] + 1)) {
        return undef;
    }
    my $i = $_[0][1];
    while ( 1 ) {
        $i++;
        return undef if $i >= scalar @{$_[0][0]};
        if ( $_[0]->accept_node( $_[0][0]->[$i] ) == FILTER_ACCEPT ) {
            $_[0][1] = $i;
            last;
        }
    }
    return $_[0][0]->[$_[0][1]];
}

sub previous {
    if ( $_[0][1] <= 0 ) {
        return undef;
    }
    my $i = $_[0][1];
    while ( 1 ) {
        $i--;
        return undef if $i < 0;
        if ( $_[0]->accept_node( $_[0][0]->[$i] ) == FILTER_ACCEPT ) {
            $_[0][1] = $i;
            last;
        }
    }
    return $_[0][0][$_[0][1]];
}

sub iterate  {
    my $self = shift;
    my $funcref = shift;
    return unless defined $funcref && ref( $funcref ) eq 'CODE';
    $self->[1] = -1;
    my $rv;
    while ( $self->next ) {
        $rv = $funcref->( $self, $_ );
    }
    return $rv;
}

1;
__END__

=head1 NAME

XML::LibXML::NodeList - a list of XML document nodes

=head1 DESCRIPTION

An XML::LibXML::NodeList object contains an ordered list of nodes, as
detailed by the W3C DOM documentation of Node Lists.

=head1 SYNOPSIS

  my $results = $dom->findnodes('//somepath');
  foreach my $context ($results->get_nodelist) {
    my $newresults = $context->findnodes('./other/element');
    ...
  }

=head1 API

=head2 new()

You will almost never have to create a new NodeSet object, as it is all
done for you by XPath.

=head2 get_nodelist()

Returns a list of nodes, the contents of the node list, as a perl list.

=head2 string_value()

Returns the string-value of the first node in the list.
See the XPath specification for what "string-value" means.

=head2 to_literal()

Returns the concatenation of all the string-values of all
the nodes in the list.

=head2 get_node($pos)

Returns the node at $pos. The node position in XPath is based at 1, not 0.

=head2 size()

Returns the number of nodes in the NodeSet.

=head2 pop()

Equivalent to perl's pop function.

=head2 push(@nodes)

Equivalent to perl's push function.

=head2 append($nodelist)

Given a nodelist, appends the list of nodes in $nodelist to the end of the
current list.

=head2 shift()

Equivalent to perl's shift function.

=head2 unshift(@nodes)

Equivalent to perl's unshift function.

=head2 prepend($nodeset)

Given a nodelist, prepends the list of nodes in $nodelist to the front of
the current list.

=head2 iterator()

Will return a new nodelist iterator for the current nodelist. A
nodelist iterator is usefull if more complex nodelist processing is
needed.

=cut
