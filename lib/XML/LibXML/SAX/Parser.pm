# $Id$

package XML::LibXML::SAX::Parser;

use strict;
use vars qw($VERSION @ISA);

use XML::LibXML;
use XML::SAX::Base;

$VERSION = '1.00';
@ISA = ('XML::SAX::Base');

sub _parse_characterstream {
    my ($self, $fh, $options) = @_;
    die "parsing a characterstream is not supported at this time";
}

sub _parse_bytestream {
    my ($self, $fh, $options) = @_;
    my $parser = XML::LibXML->new();
    my $doc = $parser->parse_fh($fh);
    $self->generate($doc);
}

sub _parse_string {
    my ($self, $str, $options) = @_;
    my $parser = XML::LibXML->new();
    my $doc = $parser->parse_string($str);
    $self->generate($doc);
}

sub _parse_systemid {
    my ($self, $sysid, $options) = @_;
    my $parser = XML::LibXML->new();
    my $doc = $parser->parse_file($sysid);
    $self->generate($doc);
}

sub generate {
    my $self = shift;
    my ($node) = @_;
    
    $self->start_document({});
    
    $self->process_node($node);
    
    $self->end_document({});
}

sub process_node {
    my ($self, $node) = @_;
    
    my $node_type = $node->getType();
    if ($node_type == XML_COMMENT_NODE) {
        $self->comment( { Data => $node->getData } );
    }
    elsif ($node_type == XML_TEXT_NODE || $node_type == XML_CDATA_SECTION_NODE) {
        # warn($node->getData . "\n");
        $self->characters( { Data => $node->getData } );
    }
    elsif ($node_type == XML_ELEMENT_NODE) {
        # warn("<" . $node->getName . ">\n");
        $self->process_element($node);
        # warn("</" . $node->getName . ">\n");
    }
    elsif ($node_type == XML_ENTITY_REF_NODE) {
        foreach my $kid ($node->getChildnodes) {
            # warn("child of entity ref: " . $kid->getType() . " called: " . $kid->getName . "\n");
            $self->process_node($kid);
        }
    }
    elsif ($node_type == XML_DOCUMENT_NODE) {
        # just get root element. Ignore other cruft.
        foreach my $kid ($node->getChildnodes) {
            if ($kid->getType() == XML_ELEMENT_NODE) {
                $self->process_element($kid);
                last;
            }
        }
    }
    else {
        warn("unsupported node type: $node_type");
    }
}

sub process_element {
    my ($self, $element) = @_;
    
    my $attribs = {};
    
    foreach my $attr ($element->getAttributes) {
        my $key;
        if (my $ns = $attr->getNamespaceURI) {
            $key = "{$ns}".$attr->getLocalName;
        }
        else {
            $key = $attr->getLocalName;
        }
        $attribs->{$key} =
                {
                    Name => $attr->getName,
                    Value => $attr->getData,
                    NamespaceURI => $attr->getNamespaceURI,
                    Prefix => $attr->getPrefix,
                    LocalName => $attr->getLocalName,
                };
    }
    
    my $node = {
        Name => $element->getName,
        Attributes => $attribs,
        NamespaceURI => $element->getNamespaceURI,
        Prefix => $element->getPrefix,
        LocalName => $element->getLocalName,
    };
    
    $self->start_element($node);
    
    foreach my $child ($element->getChildnodes) {
        $self->process_node($child);
    }
    
    $self->end_element($node);
}

1;

__END__

=head1 NAME

XML::LibXML::SAX::Parser - LibXML DOM based SAX Parser

=head1 SYNOPSIS

  my $handler = MySAXHandler->new();
  my $parser = XML::LibXML::SAX::Parser->new(Handler => $handler);
  $parser->parse_uri("foo.xml");

=head1 DESCRIPTION

This class allows you to generate SAX2 events using LibXML. Note
that this is B<not> a stream based parser, instead it parses
documents into a DOM and traverses the DOM tree. The reason being
that libxml2's stream based parsing is extremely primitive,
and would require an extreme amount of work to allow SAX2
parsing in a stream manner.

=head1 API

The API is exactly the same as any other Perl SAX2 parser. See
L<XML::SAX::Intro> for details.

Aside from the regular parsing methods, you can access the
DOM tree traverser directly, using the generate() method:

  my $parser = XML::LibXML::SAX::Parser->new(...);
  $parser->generate($dom_tree);

This is useful for serializing DOM trees, for example that
you might have done prior processing on, or that you have
as a result of XSLT processing.

=cut
