# $Id$

package XML::LibXML::SAX::Parser;

use strict;
use vars qw($VERSION @ISA);

use XML::LibXML;
use XML::LibXML::Common qw(:libxml);
use XML::SAX::Base;
use XML::SAX::DocumentLocator;

$VERSION = '1.50';
@ISA = ('XML::SAX::Base');

sub _parse_characterstream {
    my ($self, $fh, $options) = @_;
    die "parsing a characterstream is not supported at this time";
}

sub _parse_bytestream {
    my ($self, $fh, $options) = @_;
    my $parser = XML::LibXML->new();
    my $doc = exists($options->{Source}{SystemId}) ? $parser->parse_fh($fh, $options->{Source}{SystemId}) : $parser->parse_fh($fh);
    $self->generate($doc);
}

sub _parse_string {
    my ($self, $str, $options) = @_;
    my $parser = XML::LibXML->new();
    my $doc = exists($options->{Source}{SystemId}) ? $parser->parse_string($str, $options->{Source}{SystemId}) : $parser->parse_string($str);
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

    if ( $node->nodeType() == XML_DOCUMENT_NODE
         || $node->nodeType == XML_HTML_DOCUMENT_NODE ) {
        $self->start_document({});
        $self->xml_decl({Version => $node->getVersion, Encoding => $node->getEncoding});
        $self->process_node($node);
        $self->end_document({});
    }
}

sub process_node {
    my ($self, $node) = @_;

    my $node_type = $node->nodeType();
    if ($node_type == XML_COMMENT_NODE) {
        $self->comment( { Data => $node->getData } );
    }
    elsif ($node_type == XML_TEXT_NODE
           || $node_type == XML_CDATA_SECTION_NODE) {
        # warn($node->getData . "\n");
        $self->characters( { Data => $node->nodeValue } );
    }
    elsif ($node_type == XML_ELEMENT_NODE) {
        # warn("<" . $node->getName . ">\n");
        $self->process_element($node);
        # warn("</" . $node->getName . ">\n");
    }
    elsif ($node_type == XML_ENTITY_REF_NODE) {
        foreach my $kid ($node->childNodes) {
            # warn("child of entity ref: " . $kid->getType() . " called: " . $kid->getName . "\n");
            $self->process_node($kid);
        }
    }
    elsif ($node_type == XML_DOCUMENT_NODE
           || $node_type == XML_HTML_DOCUMENT_NODE
           || $node_type == XML_DOCUMENT_FRAG_NODE) {
        # some times it is just usefull to generate SAX events from
        # a document fragment (very good with filters).
        foreach my $kid ($node->childNodes) {
            $self->process_node($kid);
        }
    }
    elsif ($node_type == XML_PI_NODE) {
        $self->processing_instruction( { Target =>  $node->getName, Data => $node->getData } );
    }
    elsif ($node_type == XML_COMMENT_NODE) {
        $self->comment( { Data => $node->getData } );
    }
    elsif ( $node_type == XML_XINCLUDE_START
            || $node_type == XML_XINCLUDE_END ) {
        # ignore!
        # i may want to handle this one day, dunno yet
    }
    elsif ($node_type == XML_DTD_NODE ) {
        # ignore!
        # i will support DTDs, but had no time yet.
    }
    else {
        # warn("unsupported node type: $node_type");
    }
}

sub process_element {
    my ($self, $element) = @_;

    my $attribs = {};
    my @ns_maps = $element->getNamespaces;

    foreach my $ns (@ns_maps) {
        $self->start_prefix_mapping(
            {
                NamespaceURI => $ns->href,
                Prefix       => ( defined $ns->localname  ? $ns->localname : ''),
            }
        );
    }

    foreach my $attr ($element->attributes) {
        my $key;
        # warn("Attr: $attr -> ", $attr->getName, " = ", $attr->getData, "\n");
        # this isa dump thing...
        if ($attr->isa('XML::LibXML::Namespace')) {
            # TODO This needs fixing modulo agreeing on what
            # is the right thing to do here.
            unless ( defined $attr->name ) {
                ## It's an atter like "xmlns='foo'"
                $attribs->{"{}xmlns"} =
                  {     
                   Name         => "xmlns",
                   LocalName    => "xmlns",
                   Prefix       => "",     
                   Value        => $attr->href,
                   NamespaceURI => "",
                  };
            }
            else {
                my $prefix = "xmlns";
                my $localname = $attr->localname;
                my $key = "{http://www.w3.org/2000/xmlns/}";
                my $name = "xmlns";

                if ( defined $localname ) {
                    $key .= $localname;
                    $name.= ":".$localname;
                }

                $attribs->{$key} =
                  {
                   Name         => $name,
                   Value        => $attr->href,
                   NamespaceURI => "http://www.w3.org/2000/xmlns/",
                   Prefix       => $prefix,
                   LocalName    => $localname,
                  };
            }
        }
        else {
            my $ns = $attr->namespaceURI;
            my $ns = $attr->namespaceURI;
            $ns = '' unless defined $ns;
            $key = "{$ns}".$attr->localname;
            ## Not sure why, but $attr->name is coming through stripped
            ## of its prefix, so we need to hand-assemble a real name.
            my $name = $attr->name;
            $name = "" unless defined $name;

            my $prefix = $attr->prefix;
            $prefix = "" unless defined $prefix;
            $name = "$prefix:$name"
              if index( $name, ":" ) < 0 && length $prefix;

            $attribs->{$key} =
                {
                    Name => $name,
                    Value => $attr->value,
                    NamespaceURI => $ns,
                    Prefix => $prefix,
                    LocalName => $attr->localname,
                };
        }
        # use Data::Dumper;
        # warn("Attr made: ", Dumper($attribs->{$key}), "\n");
    }

    my $node = {
        Name => $element->nodeName,
        Attributes => $attribs,
        NamespaceURI => $element->namespaceURI,
        Prefix => $element->prefix || "",
        LocalName => $element->localname,
    };

    $self->start_element($node);

    foreach my $child ($element->childNodes) {
        $self->process_node($child);
    }

    my $end_node = { %$node };

    delete $end_node->{Attributes};

    $self->end_element($end_node);

    foreach my $ns (@ns_maps) {
        $self->end_prefix_mapping(
            {
                NamespaceURI => $ns->href,
                Prefix       => ( defined $ns->localname  ? $ns->localname : ''),
            }
        );
    }
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

=head1 WARNING

WARNING WARNING WARNING

This is NOT a streaming SAX parser. As I said above, this parser
reads the entire document into a DOM and serialises it. Some
people couldn't read that in the paragraph above so I've added
this warning.

There are many reasons, but if you want to write a proper SAX
parser using the libxml2 library, please feel free and send it
along to me.

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
