# $Id$

package XML::LibXML::SAX::Builder;

use XML::LibXML;

sub new {
    my $class = shift;
    return bless {@_}, $class;
}

sub start_document {
    my ($self, $doc) = @_;

    $self->{DOM} = XML::LibXML::Document->createDocument();

    if ( defined $self->{Encoding} ) {
        $self->xml_decl({Version => ($self->{Version} || '1.0') , Encoding => $self->{Encoding}});
    }

    $self->{Parent} = undef;
}

sub xml_decl {
    my $self = shift;
    my $decl = shift;

    if ( defined $decl->{Version} ) {
        $self->{DOM}->setVersion( $decl->{Version} );
    }
    if ( defined $decl->{Encoding} ) {
        $self->{DOM}->setEncoding( $decl->{Encoding} );
    }
}

sub end_document {
    my ($self, $doc) = @_;
    my $dom = $self->{DOM};
    $dom = $self->{Parent} unless defined $dom; # this is for parsing document chunks
    delete $self->{Parent};
    delete $self->{DOM};
    return $dom;
}

sub start_element {
    my ($self, $el) = @_;
    my $node;

    unless ( defined $self->{DOM} or defined $self->{Parent} ) {
        $self->{Parent} = XML::LibXML::DocumentFragment->new();
    }

    if ($el->{NamespaceURI}) {
        if ( defined $self->{DOM} ) {
            $node = $self->{DOM}->createElementNS($el->{NamespaceURI},
                                                  $el->{Name});
        }
        else {
            $node = XML::LibXML::Element->new( $el->{Name} );
            $node->setNamespace( $el->{NamespaceURI},$el->{Prefix} , 1 );
        }
    }
    else {
        if ( defined $self->{DOM} ) {
            $node = $self->{DOM}->createElement($el->{Name});
        }
        else {
            $node = XML::LibXML::Element->new( $el->{Name} );
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

    # do attributes
    foreach my $key (keys %{$el->{Attributes}}) {
        my $attr = $el->{Attributes}->{$key};
        if (ref($attr)) {
            if ( not defined $attr->{Prefix} or $attr->{Prefix} ne "xmlns" ) {
                # SAX2 attributes
                $node->setAttributeNS($attr->{NamespaceURI} || "",
                                      $attr->{Name}, $attr->{Value});
            }
            else {
                $node->setNamespace( $attr->{Value}, $attr->{LocalName},0 );
            }
        }
        else {
            $node->setAttribute($key => $attr);
        }
    }
}

sub end_element {
    my ($self, $el) = @_;
    return unless $self->{Parent};
    $self->{Parent} = $self->{Parent}->parentNode();
}

sub characters {
    my ($self, $chars) = @_;
    if ( not defined $self->{DOM} and not defined $self->{Parent} ) {
        $self->{Parent} = XML::LibXML::DocumentFragment->new();
    }
    return unless $self->{Parent};
    $self->{Parent}->appendText($chars->{Data});
}

sub comment {
    my ($self, $chars) = @_;
    my $comment;
    if ( not defined $self->{DOM} and not defined $self->{Parent} ) {
        $self->{Parent} = XML::LibXML::DocumentFragment->new();
    }

    if ( defined $self->{DOM} ) {
        $comment = $self->{DOM}->createComment( $chars->{Data} );
    }
    else {
        $comment = XML::LibXML::Comment->new( $chars->{Data} );
    }

    if ( defined $self->{Parent} ) {
        $self->{Parent}->appendChild($comment);
    }
    else {
        $self->{DOM}->appendChild($comment);
    }
}

sub processing_instruction {
    my ( $self,  $pi ) = @_;
    my $PI;
    return unless  defined $self->{DOM};
    $PI = $self->{DOM}->createPI( $pi->{Target}, $pi->{Data} );

    if ( defined $self->{Parent} ) {
        $self->{Parent}->appendChild( $PI );
    }
    else {
        $self->{DOM}->appendChild( $PI );
    }
}

sub warning {
    my $self = shift;
    my $error = shift;
    # fill $@ but do not die seriously
    eval { $error->throw; };
}

sub error {
    my $self = shift;
    my $error = shift;
    delete $self->{Parent};
    delete $self->{DOM};
    $error->throw;
}

sub fatal_error {
    my $self = shift;
    my $error = shift;
    delete $self->{Parent};
    delete $self->{DOM};
    $error->throw;
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
