# $Id$

package XML::LibXML::SAX::Builder;

use XML::LibXML;
use XML::NamespaceSupport;

sub new {
    my $class = shift;
    return bless {@_}, $class;
}

sub done {
    my ($self) = @_;
    my $dom = $self->{DOM};
    $dom = $self->{Parent} unless defined $dom; # this is for parsing document chunks
    delete $self->{NamespaceStack};
    delete $self->{Parent};
    delete $self->{DOM};

    return $dom;
}


sub start_document {
    my ($self, $doc) = @_;

    $self->{DOM} = XML::LibXML::Document->createDocument();

    if ( defined $self->{Encoding} ) {
        $self->xml_decl({Version => ($self->{Version} || '1.0') , Encoding => $self->{Encoding}});
    }

    $self->{NamespaceStack} = XML::NamespaceSupport->new;
    $self->{NamespaceStack}->push_context;
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
    my $d = $self->done();
    return $d;
}

sub start_prefix_mapping {
    my $self = shift;
    my $ns = shift;

    unless ( defined $self->{DOM} or defined $self->{Parent} ) {
        $self->{Parent} = XML::LibXML::DocumentFragment->new();
        $self->{NamespaceStack} = XML::NamespaceSupport->new;
        $self->{NamespaceStack}->push_context;
    }

    $self->{USENAMESPACESTACK} = 1;

    $self->{NamespaceStack}->declare_prefix( $ns->{Prefix}, $ns->{NamespaceURI} );
}


sub end_prefix_mapping {
    my $self = shift;
    my $ns = shift;
    $self->{NamespaceStack}->undeclare_prefix( $ns->{Prefix} );
}


sub start_element {
    my ($self, $el) = @_;
    my $node;

    unless ( defined $self->{DOM} or defined $self->{Parent} ) {
        $self->{Parent} = XML::LibXML::DocumentFragment->new();
        $self->{NamespaceStack} = XML::NamespaceSupport->new;
        $self->{NamespaceStack}->push_context;
    }

    if ($el->{NamespaceURI}) {
        if ( defined $self->{DOM} ) {
            $node = $self->{DOM}->createElementNS($el->{NamespaceURI},
                                                  $el->{Name});
        }
        else {
            $node = XML::LibXML::Element->new( $el->{Name} );
            $node->setNamespace( $el->{NamespaceURI},
                                 $el->{Prefix} , 1 );
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

    # build namespaces
    my $skip_ns= 0;
    foreach my $p ( $self->{NamespaceStack}->get_declared_prefixes() ) {
         $skip_ns= 1;
        my $uri = $self->{NamespaceStack}->get_uri($p);
        my $nodeflag = 0;
        if ( defined $uri
             and defined $el->{NamespaceURI}
             and $uri eq $el->{NamespaceURI} ) {
#            $nodeflag = 1;
            next;
        }
        $node->setNamespace($uri, $p, 0 );
    }

    # append
    if ($self->{Parent}) {
        $self->{Parent}->addChild($node);
        $self->{Parent} = $node;
    }
    else {
        $self->{DOM}->setDocumentElement($node);
        $self->{Parent} = $node;
    }

     $self->{NamespaceStack}->push_context;

    # do attributes
    foreach my $key (keys %{$el->{Attributes}}) {
        my $attr = $el->{Attributes}->{$key};
        if (ref($attr)) {
            # catch broken name/value pairs
            next unless $attr->{Name} ;
            next if $self->{USENAMESPACESTACK}
                    and ( $attr->{Name} eq "xmlns"
                          or ( defined $attr->{Prefix}
                               and $attr->{Prefix} eq "xmlns" ) );


            if ( defined $attr->{Prefix}
                 and $attr->{Prefix} eq "xmlns" and $skip_ns == 0 ) {
                # ok, the generator does not set namespaces correctly!
                my $uri = $attr->{Value};
                $node->setNamespace($uri,
                                    $attr->{Localname},
                                    $uri eq $el->{NamespaceURI} ? 1 : 0 );
            }
            else {
                $node->setAttributeNS($attr->{NamespaceURI} || "",
                                      $attr->{Name}, $attr->{Value});
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

    $self->{NamespaceStack}->pop_context;
    $self->{Parent} = $self->{Parent}->parentNode();
}

sub start_cdata {
    my $self = shift;
    $self->{IN_CDATA} = 1;
}

sub end_cdata {
    my $self = shift;
    $self->{IN_CDATA} = 0;
}

sub characters {
    my ($self, $chars) = @_;
    if ( not defined $self->{DOM} and not defined $self->{Parent} ) {
        $self->{Parent} = XML::LibXML::DocumentFragment->new();
        $self->{NamespaceStack} = XML::NamespaceSupport->new;
        $self->{NamespaceStack}->push_context;
    }
    return unless $self->{Parent};
    my $node;

    unless ( defined $chars and defined $chars->{Data} ) {
        return;
    }

    if ( defined $self->{DOM} ) {
        if ( defined $self->{IN_CDATA} and $self->{IN_CDATA} == 1 ) {
            $node = $self->{DOM}->createCDATASection($chars->{Data});
        }
        else {
            $node = $self->{DOM}->createTextNode($chars->{Data});
        }
    }
    elsif ( defined $self->{IN_CDATA} and $self->{IN_CDATA} == 1 ) {
        $node = XML::LibXML::CDATASection->new($chars->{Data});
    }
    else {
        $node = XML::LibXML::Text->new($chars->{Data});
    }

    $self->{Parent}->addChild($node);
}

sub comment {
    my ($self, $chars) = @_;
    my $comment;
    if ( not defined $self->{DOM} and not defined $self->{Parent} ) {
        $self->{Parent} = XML::LibXML::DocumentFragment->new();
        $self->{NamespaceStack} = XML::NamespaceSupport->new;
        $self->{NamespaceStack}->push_context;
    }

    unless ( defined $chars and defined $chars->{Data} ) {
        return;
    }

    if ( defined $self->{DOM} ) {
        $comment = $self->{DOM}->createComment( $chars->{Data} );
    }
    else {
        $comment = XML::LibXML::Comment->new( $chars->{Data} );
    }

    if ( defined $self->{Parent} ) {
        $self->{Parent}->addChild($comment);
    }
    else {
        $self->{DOM}->addChild($comment);
    }
}

sub processing_instruction {
    my ( $self,  $pi ) = @_;
    my $PI;
    return unless  defined $self->{DOM};
    $PI = $self->{DOM}->createPI( $pi->{Target}, $pi->{Data} );

    if ( defined $self->{Parent} ) {
        $self->{Parent}->addChild( $PI );
    }
    else {
        $self->{DOM}->addChild( $PI );
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
    delete $self->{NamespaceStack};
    delete $self->{Parent};
    delete $self->{DOM};
    $error->throw;
}

sub fatal_error {
    my $self = shift;
    my $error = shift;
    delete $self->{NamespaceStack};
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
