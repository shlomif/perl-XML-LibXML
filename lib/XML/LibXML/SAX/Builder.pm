# $Id$

package XML::LibXML::SAX::Builder;

use XML::LibXML;

sub new {
    my $class = shift;
    return bless {}, $class;
}

sub start_document {
    my ($self, $doc) = @_;
    $self->{DOM} = XML::LibXML::Document->createDocument( );
    $self->{Parent} = undef;
}

sub end_document {
    my ($self, $doc) = @_;
    my $dom = delete $self->{DOM};
    delete $self->{Parent};
    return $dom;
}

sub start_element {
    my ($self, $el) = @_;
    my $node;
    if ($el->{NamespaceURI}) {
        $node = $self->{DOM}->createElementNS($el->{NamespaceURI}, $el->{Name});
    }
    else {
        $node = $self->{DOM}->createElement($el->{Name});
    }
    
    # do attributes
    foreach my $key (keys %{$el->{Attributes}}) {
        my $attr = $el->{Attributes}->{$key};
        if (ref($attr)) {
            # SAX2 attributes
            $node->setAttributeNS($attr->{NamespaceURI} || "", $attr->{Name} => $attr->{Value});
        }
        else {
            $node->setAttribute($key => $attr);
        }
    }
    
    # append
    if ($self->{Parent}) {
        $self->{Parent}->appendChild($node);
        $self->{Parent} = $node;
    }
    else {
        $self->{DOM}->setDocumentElement($node);
        $self->{Parent} = $node;
    }
}

sub end_element {
    my ($self, $el) = @_;
    return unless $self->{Parent};
    $self->{Parent} = $self->{Parent}->getParentNode();
}

sub characters {
    my ($self, $chars) = @_;
    return unless $self->{Parent};
    $self->{Parent}->appendText($chars->{Data});
}

1;

__END__

=head1 NAME

XML::LibXML::SAX::Builder - build a LibXML tree from SAX events

=head1 SYNOPSIS

  my $builder = XML::LibXML::SAX::Builder->new();
  my $gen = XML::Generator::DBI->new(Handler => $builder, dbh => $dbh);
  my $dom = $gen->execute("SELECT * FROM Users");

=head1 DESCRIPTION

This is a SAX handler that generates a DOM tree from SAX events. Usage
is as above. Input is accepted from any SAX1 or SAX2 event generator.

=cut