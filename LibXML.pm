# $Id$

package XML::LibXML;

use strict;
use vars qw($VERSION @ISA @EXPORT);
use Carp;

$VERSION = "0.96";
require Exporter;
require DynaLoader;

@ISA = qw(DynaLoader Exporter);

bootstrap XML::LibXML $VERSION;

@EXPORT = qw( XML_ELEMENT_NODE 
              XML_ATTRIBUTE_NODE
              XML_TEXT_NODE
              XML_CDATA_SECTION_NODE
              XML_ENTITY_REF_NODE
              XML_ENTITY_NODE
              XML_PI_NODE
              XML_COMMENT_NODE
              XML_DOCUMENT_NODE
              XML_DOCUMENT_TYPE_NODE
              XML_DOCUMENT_FRAG_NODE
              XML_NOTATION_NODE
              XML_HTML_DOCUMENT_NODE
              XML_DTD_NODE
              XML_ELEMENT_DECL
              XML_ATTRIBUTE_DECL
              XML_ENTITY_DECL
              XML_NAMESPACE_DECL
              XML_XINCLUDE_START
              XML_XINCLUDE_END
              encodeToUTF8
              decodeFromUTF8
            );


sub new {
    my $class = shift;
    my %options = @_;
    my $self = bless \%options, $class;
    return $self;
}

sub parse_string {
    my $self = shift;
    croak("parse already in progress") if $self->{_State_};
    $self->{_State_} = 1;
    my $result;
    eval {
        $result = $self->_parse_string(@_);
    };
    my $err = $@;
    $self->{_State_} = 0;
    if ($err) {
        croak $err;
    }
    return $result;
}

sub parse_fh {
    my $self = shift;
    croak("parse already in progress") if $self->{_State_};
    $self->{_State_} = 1;
    my $result;
    eval {
        $result = $self->_parse_fh(@_);
    };
    my $err = $@;
    $self->{_State_} = 0;
    if ($err) {
        croak $err;
    }
    return $result;
}

sub parse_file {
    my $self = shift;
    croak("parse already in progress") if $self->{_State_};
    $self->{_State_} = 1;
    my $result;
    eval {
        $result = $self->_parse_file(@_);
    };
    my $err = $@;
    $self->{_State_} = 0;
    if ($err) {
        croak $err;
    }
    return $result;
}

sub XML_ELEMENT_NODE(){1;}
sub XML_ATTRIBUTE_NODE(){2;}
sub XML_TEXT_NODE(){3;}
sub XML_CDATA_SECTION_NODE(){4;}
sub XML_ENTITY_REF_NODE(){5;}
sub XML_ENTITY_NODE(){6;}
sub XML_PI_NODE(){7;}
sub XML_COMMENT_NODE(){8;}
sub XML_DOCUMENT_NODE(){9;}
sub XML_DOCUMENT_TYPE_NODE(){10;}
sub XML_DOCUMENT_FRAG_NODE(){11;}
sub XML_NOTATION_NODE(){12;}
sub XML_HTML_DOCUMENT_NODE(){13;}
sub XML_DTD_NODE(){14;}
sub XML_ELEMENT_DECL_NODE(){15;}
sub XML_ATTRIBUTE_DECL_NODE(){16;}
sub XML_ENTITY_DECL_NODE(){17;}
sub XML_NAMESPACE_DECL_NODE(){18;}
sub XML_XINCLUDE_START(){19;}
sub XML_XINCLUDE_END(){20;}

@XML::LibXML::Document::ISA         = 'XML::LibXML::Node';
@XML::LibXML::Element::ISA          = 'XML::LibXML::Node';
@XML::LibXML::Text::ISA             = 'XML::LibXML::Node';
@XML::LibXML::Comment::ISA          = 'XML::LibXML::Text';
@XML::LibXML::CDATASection::ISA     = 'XML::LibXML::Text';
@XML::LibXML::Attr::ISA             = 'XML::LibXML::Node';
@XML::LibXML::DocumentFragment::ISA = 'XML::LibXML::Node';


sub XML::LibXML::Node::iterator {
    my $self = shift;
    my $funcref = shift;
    my $child = undef;

    my $rv = $funcref->( $self );
    foreach $child ( $self->childNodes() ){
        $rv = $child->iterator( $funcref );
    }
    return $rv;
}

1;
__END__

=head1 NAME

XML::LibXML - Interface to the gnome libxml2 library

=head1 SYNOPSIS

  use XML::LibXML;
  my $parser = XML::LibXML->new();

  my $doc = $parser->parse_string(<<'EOT');
  <xml/>
  EOT

=head1 DESCRIPTION

This module is an interface to the gnome libxml2 DOM parser (no SAX
parser support yet), and the DOM tree. It also provides an
XML::XPath-like findnodes() interface, providing access to the XPath
API in libxml2.

=head1 OPTIONS

LibXML options are global (unfortunately this is a limitation of the
underlying implementation, not this interface). They can either be set
using C<$parser-E<gt>option(...)>, or C<XML::LibXML-E<gt>option(...)>, both
are treated in the same manner. Note that even two forked processes
will share some of the same options, so be careful out there!

Every option returns the previous value, and can be called without
parameters to get the current value.

=head2 validation

  XML::LibXML->validation(1);

Turn validation on (or off). Defaults to off.

=head2 expand_entities

  XML::LibXML->expand_entities(0);

Turn entity expansion on or off, enabled by default. If entity expansion
is off, any external parsed entities in the document are left as entities.
Probably not very useful for most purposes.

=head2 keep_blanks

  XML::LibXML->keep_blanks(0);

Allows you to turn off XML::LibXML's default behaviour of maintaining
whitespace in the document.

=head2 pedantic_parser

  XML::LibXML->pedantic_parser(1);

You can make XML::LibXML more pedantic if you want to.

=head2 load_ext_dtd

  XML::LibXML->load_ext_dtd(1);

Load external DTD subsets while parsing.

=head2 match_callback

  XML::LibXML->match_callback($subref);

Sets a "match" callback. See L<"Input Callbacks"> below.

=head2 open_callback

  XML::LibXML->open_callback($subref);

Sets an open callback. See L<"Input Callbacks"> below.

=head2 read_callback

  XML::LibXML->read_callback($subref);

Sets a read callback. See L<"Input Callbacks"> below.

=head2 close_callback

  XML::LibXML->close_callback($subref);

Sets a close callback. See L<"Input Callbacks"> below.

=head1 CONSTRUCTOR

The XML::LibXML constructor, C<new()>, takes the following parameters:

=head2 ext_ent_handler

  my $parser = XML::LibXML->new(ext_ent_handler => sub { ... });

The ext_ent_handler sub is called whenever libxml needs to load an external
parsed entity. The handler sub will be passed two parameters: a
URL (SYSTEM identifier) and an ID (PUBLIC identifier). It should return
a string containing the resource at the given URI.

Note that you do not need to enable this - if not supplied libxml will
get the resource either directly from the filesystem, or using an internal
http client library.

=head1 PARSING

There are three ways to parse documents - as a string, as a Perl filehandle,
or as a filename. The return value from each is a XML::LibXML::Document
object, which is a DOM object (although no DOM methods are implemented
yet). See L<"XML::LibXML::Document"> below for more details on the methods
available on documents.

Each of the below methods will throw an exception if the document is invalid.
To prevent this causing your program exiting, wrap the call in an eval{}
block.

=head2 parse_string

  my $doc = $parser->parse_string($string);

=head2 parse_fh

  my $doc = $parser->parse_fh($fh);

Here, C<$fh> can be an IOREF, or a subclass of IO::Handle.

=head2 parse_file

  my $doc = $parser->parse_file($filename);

=head1 PARSING HTML

As of version 0.96, XML::LibXML is capable of parsing HTML into a regular
XML DOM. This gives you the full power of XML::LibXML on HTML documents.

The methods work in exactly the same way as the methods above, and return
exactly the same type of object. If you wish to dump the resulting document
as HTML again, you can use C<$doc->toStringHTML()> to do that.

=head2 parse_html_string

  my $doc = $parser->parse_html_string($string);

=head2 parse_html_fh

  my $doc = $parser->parse_html_fh($fh);

=head2 parse_html_file

  my $doc = $parser->parse_html_file($filename);

=head1 XML::LibXML::Document

The objects returned above have a few methods available to them:

=head2 C<$doc-E<gt>toString>

Convert the document to a string.

=head2 C<$doc-E<gt>is_valid>

Post parse validation. Returns true if the document is valid against the
DTD specified in the DOCTYPE declaration

=head2 C<$doc-E<gt>is_valid($dtd)>

Same as the above, but allows you to pass in a DTD created from 
L<"XML::LibXML::Dtd">.

=head2 C<$doc-E<gt>process_xinclude>

Process any xinclude tags in the file.

=head1 XML::LibXML::Dtd

This module allows you to parse and return a DTD object. It has one method
right now, C<new()>.

=head2 new()

  my $dtd = XML::LibXML::Dtd->new($public, $system);

Creates a new DTD object from the public and system identifiers. It will
automatically load the objects from the filesystem, or use the input
callbacks (see L<"Input Callbacks"> below) to load the DTD.

=head1 Input Callbacks

The input callbacks are used whenever LibXML has to get something B<other
than external parsed entities> from somewhere. The input callbacks in LibXML
are stacked on top of the original input callbacks within the libxml library.
This means that if you decide not to use your own callbacks (see C<match()>),
then you can revert to the default way of handling input. This allows, for
example, to only handle certain URI schemes.

The following callbacks are defined:

=head2 match(uri)

If you want to handle the URI, simply return a true value from this callback.

=head2 open(uri)

Open something and return it to handle that resource.

=head2 read(handle, bytes)

Read a certain number of bytes from the resource.

=head2 close(handle)

Close the handle associated with the resource.

=head2 Example

This is a purely fictitious example that uses a MyScheme::Handler object
that responds to methods similar to an IO::Handle.

  XML::LibXML->match_callback(\&match_uri);
  
  XML::LibXML->open_callback(\&open_uri);
  
  XML::LibXML->read_callback(\&read_uri);
  
  XML::LibXML->close_callback(\&close_uri);
  
  sub match_uri {
    my $uri = shift;
    return $uri =~ /^myscheme:/;
  }
  
  sub open_uri {
    my $uri = shift;
    return MyScheme::Handler->new($uri);
  }
  
  sub read_uri {
    my $handler = shift;
    my $length = shift;
    my $buffer;
    read($handler, $buffer, $length);
    return $buffer;
  }
  
  sub close_uri {
    my $handler = shift;
    close($handler);
  }

=head1 Encoding

All data will be stored UTF-8 encoded. Nevertheless the input and
output functions are aware about the encoding of the owner
document. By default all functions will assume, UTF-8 encoding of the
passed strings unless the owner document has a different encoding. In
such a case the functions will assume the encoding of the document to
be valid.

At the current state of implementation query functions like
B<findnodes()>, B<getElementsByTagName()> or B<getAttribute()> accept
B<only> UTF-8 encoded strings, even if the underlaying document has a
different encoding. At first this seems to be a limitation, but on
application level there is no way to make save asumptations about the
encoding of the strings.

Future releases will offer the opportunity to force an application
wide encoding, so make shure that you installed the latest version of
XML::LibXML.

To encode or decode a string to or from UTF-8 B<XML::LibXML> exports
two functions, which use the encoding mechanism of the underlaying
implementation. These functions should be used, if external encoding
is required (e.g. for queryfunctions).

=head2 encodeToUTF8

    $encodedstring = encodeToUTF8( $name_of_encoding, $sting_to_encode );

The function will encode a string from the specified encoding to UTF-8.

=head2 decodeFromUTF8

    $decodedstring = decodeFromUTF8($name_of_encoding, $string_to_decode );

This Function transforms an UTF-8 encoded string the specified
encoding.  While transforms to ISO encodings may cause errors if the
given stirng contains unsupported characters, this function can
transform to UTF-16 encodings as well.

=head1 AUTHOR

Matt Sergeant, matt@sergeant.org

Copyright 2001, AxKit.com Ltd. All rights reserved.

=head1 SEE ALSO

L<XML::LibXSLT>, L<XML::LibXML::Document>,
L<XML::LibXML::Element>, L<XML::LibXML::Node>,
L<XML::LibXML::Text>, L<XML::LibXML::Comment>,
L<XML::LibXML::CDATASection>, L<XML::LibXML::Attribute>
L<XML::LibXML::DocumentFragment>

=cut
