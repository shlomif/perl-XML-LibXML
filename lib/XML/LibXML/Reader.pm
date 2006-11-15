package XML::LibXML::Reader;
use XML::LibXML;

use strict;
use warnings;
use vars qw/$VERSION/;
use Carp;
use base qw(Exporter);
use constant {
    XML_READER_TYPE_NONE => 0,
    XML_READER_TYPE_ELEMENT => 1,
    XML_READER_TYPE_ATTRIBUTE => 2,
    XML_READER_TYPE_TEXT => 3,
    XML_READER_TYPE_CDATA => 4,
    XML_READER_TYPE_ENTITY_REFERENCE => 5,
    XML_READER_TYPE_ENTITY => 6,
    XML_READER_TYPE_PROCESSING_INSTRUCTION => 7,
    XML_READER_TYPE_COMMENT => 8,
    XML_READER_TYPE_DOCUMENT => 9,
    XML_READER_TYPE_DOCUMENT_TYPE => 10,
    XML_READER_TYPE_DOCUMENT_FRAGMENT => 11,
    XML_READER_TYPE_NOTATION => 12,
    XML_READER_TYPE_WHITESPACE => 13,
    XML_READER_TYPE_SIGNIFICANT_WHITESPACE => 14,
    XML_READER_TYPE_END_ELEMENT => 15,
    XML_READER_TYPE_END_ENTITY => 16,
    XML_READER_TYPE_XML_DECLARATION => 17
};
use vars qw( @EXPORT @EXPORT_OK );

BEGIN {

@EXPORT = qw(
    XML_READER_TYPE_NONE
    XML_READER_TYPE_ELEMENT
    XML_READER_TYPE_ATTRIBUTE
    XML_READER_TYPE_TEXT
    XML_READER_TYPE_CDATA
    XML_READER_TYPE_ENTITY_REFERENCE
    XML_READER_TYPE_ENTITY
    XML_READER_TYPE_PROCESSING_INSTRUCTION
    XML_READER_TYPE_COMMENT
    XML_READER_TYPE_DOCUMENT
    XML_READER_TYPE_DOCUMENT_TYPE
    XML_READER_TYPE_DOCUMENT_FRAGMENT
    XML_READER_TYPE_NOTATION
    XML_READER_TYPE_WHITESPACE
    XML_READER_TYPE_SIGNIFICANT_WHITESPACE
    XML_READER_TYPE_END_ELEMENT
    XML_READER_TYPE_END_ENTITY
    XML_READER_TYPE_XML_DECLARATION
);
@EXPORT_OK = @EXPORT;

$VERSION = 0.02;
}

{
  my %flags = (
    recover => 1,		 # recover on errors
    expand_entities => 2,	 # substitute entities
    load_ext_dtd => 4,		 # load the external subset
    complete_attributes => 8,	 # default DTD attributes
    validation => 16,		 # validate with the DTD
    suppress_errors => 32,	 # suppress error reports
    suppress_warnings => 64,	 # suppress warning reports
    pedantic_parser => 128,	 # pedantic error reporting
    no_blanks => 256,		 # remove blank nodes
    expand_xinclude => 1024,	 # Implement XInclude substitition
    xinclude => 1024,		 # ... alias
    no_network => 2048,		 # Forbid network access
    clean_namespaces => 8192,    # remove redundant namespaces declarations
    no_cdata => 16384,		 # merge CDATA as text nodes
    no_xinclude_nodes => 32768,	 # do not generate XINCLUDE START/END nodes
  );
  sub _parser_options {
    my ($opts) = @_;

    # currently dictionaries break XML::LibXML memory management
    my $no_dict = 4096;
    my $flags = $no_dict;     # safety precaution

    my ($key, $value)=@_;
    while (($key,$value) = each %$opts) {
      my $f = $flags{ $key };
      if (defined $f) {
	if ($value) {
	  $flags |= $f
	} else {
	  $flags &= ~$f;
	}
      }
    }
  }
}


sub new {
    my ($class) = shift;
    my %args = map { ref($_) eq 'HASH' ? (%$_) : $_ } @_;
    my $encoding = $args{encoding};
    my $URI = $args{URI};
    my $options = _parser_options(\%args);

    my $self = undef;
    if ( defined $args{location} ) {
      $self = $class->_newForFile( $args{location}, $encoding, $options );
    }
    elsif ( defined $args{string} ) {
      $self = $class->_newForString( $args{string}, $URI, $encoding, $options );
    }
    elsif ( defined $args{IO} ) {
      $self = $class->_newForIO( $args{IO}, $URI, $encoding, $options  );
    }
    elsif ( defined $args{DOM} ) {
      croak("DOM must be a XML::LibXML::Document node")
	unless UNIVERSAL::isa($args{DOM}, 'XML::LibXML::Document');
      $self = $class->_newForDOM( $args{DOM} );
    }
    elsif ( defined $args{FD} ) {
      my $fd = fileno($args{FD});
      $self = $class->_newForFd( $fd, $URI, $encoding, $options  );
    }
    else {
      croak("XML::LibXML::Reader->new: specify location, string, IO, DOM, or FD");
    }
    return $self;
}

sub close {
    my ($reader) = @_;
    # _close return -1 on failure, 0 on success
    # perl close returns 0 on failure, 1 on success
    return $reader->_close == 0 ? 1 : 0;
}

sub preservePattern {
  my $reader=shift;
  my ($pattern,$ns_map)=@_;
  if (ref($ns_map) eq 'HASH') {
    # translate prefix=>URL hash to a (URL,prefix) list
    $reader->_preservePattern($pattern,[reverse %$ns_map])
  } else {
    $reader->_preservePattern(@_);
  }
}

1;
__END__


=head1 NAME

XML::LibXML::Reader - libXml pull parser

=head1 SYNOPSIS

  use XML::LibXML::Reader;

  $reader = new XML::LibXML::Reader("file.xml")
       or die "cannot read file.xml\n";
  while ($reader->read) {
      processNode($reader);
  }

  sub processNode {
      $reader = shift;
      printf "%d %d %s %d\n", ($reader->depth,
                                $reader->nodeType,
                                $reader->name,
			        $reader->isEmptyElement);
  }

=head1 DESCRIPTION

This is a perl interface to libxml2's pull-parser implementation
xmlTextReader L<http://xmlsoft.org/html/libxml-xmlreader.html>. 
Pull-parser (StAX in Java, XmlReader in C#) use an iterator approach to parse a
xml-file. They are easier to program than event-based parser (SAX)
and much more lightweight than tree-based parser (DOM), which load the
complete tree into memory. 

The Reader acts as a cursor going forward on the document stream and
stopping at each node in the way. At every point DOM-like methods of
the Reader object allow to examine the current node (name, namespace,
attributes, etc.)

The user's code keeps control of the progress and simply calls the
read() function repeatedly to progress to the next node in the
document order. Other functions provide means for skipping complete
subtrees, or nodes until a specific element, etc. 

At every time, only a very limitted portion of the document is kept in
the memory, which makes the API more memory-efficient than using DOM.
However, it is also possible to mix Reader with DOM. At every point
the user may copy the current node (optionally expanded into a
complete subtree) from the processed document to another DOM tree, or
to instruct the Reader to collect sub-document in form of a DOM tree
consisting of selected nodes.

Reader API also supports namespaces, xml:base, entity handling, and
DTD validation. Schema and RelaxNG validation support will probably be
added in some later revision of the Perl interface.

=head2 ADDITIONAL INFORMATION

L<http://dotgnu.org/pnetlib-doc/System/Xml/XmlTextReader.html>

=over 4

=head1 PUBLIC METHODS

Please find a complete overview and descripton of functions in
L<http://xmlsoft.org/html/libxml-xmlreader.html>. The naming has been
changed slightly to match the conventions of XML::LibXML.

For example, C:

  xmlTextReaderPtr reader = xmlNewTextReaderFilename("file.xml");
  xmlChar* baseUri = xmlTextReaderBaseUri(reader);

is in perl:

  my $reader = XML::LibXML::Reader->new(location => "file.xml");
  my $baseURI = $reader->baseURI;

Some functions have been changed or added with respect to the C
interface.

=over 4

=item new()

Creates a new reader object.

  my $reader = XML::LibXML::Reader->new( location => "file.xml", ... );
  my $reader = XML::LibXML::Reader->new( string => $xml_string, ... );
  my $reader = XML::LibXML::Reader->new( IO => $file_handle, ... );
  my $reader = XML::LibXML::Reader->new( DOM => $dom, ... );

where ... are (optional) reader options described below.  The
constructor recognizes the following XML sources:

=over 8

=item location

Read XML from a local file or URL.

=item string

Read XML from a string.

=item IO

Read XML a Perl IO filehandle.

=item FD

Read XML from a file descriptor (bypasses Perl I/O layer, only
applicable to filehandles for regular files or pipes). Possibly faster
than IO.

=item DOM

Use reader API to walk through a preparsed XML::LibXML::Document.

=back

=item read()

=item readAttributeValue()

=item readInnerXml()

=item readOuterXml()

=item readState()


=item next()

=item nextSibling()

=item nextElement(name?,nsURI?)

=item nextTag(name?,nsURI?)

=item skipSiblings()

=item finish()



=item name()

The qualified name of the current node, equal to (Prefix:)LocalName.

=item nodeType()

Type of the current node. See L<NODE TYPES> below.

=item localName()

The local name of the node.

=item prefix()

The prefix of the namespace associated with the node.

=item namespaceURI()

The URI defining the namespace associated with the node.

=item isEmptyElement()

Check if the current node is empty, this is a bit bizarre in the sense
that <a/> will be considered empty while <a></a> will not.


=item document()

=item copyCurrentNode(reader,expand=0)

=item preserveNode()

=item preservePattern(reader,pattern,%ns_map)



=item attributeCount()

Provides the number of attributes of the current node.

=item hasAttributes()

Whether the node has attributes.



=item getAttribute(name)

=item getAttributeNo(no)

=item getAttributeNs(localName, namespaceURI)

=item isDefault()

Whether an Attribute node was generated from the default value defined
in the DTD or schema (not yet supported).


=item hasValue()

Whether the node can have a text value.

=item value()

Provides the text value of the node if present.


=item moveToAttribute(name)

=item moveToAttributeNo(no)

=item moveToAttributeNs(localName,namespaceURI)

=item moveToFirstAttribute()

=item moveToNextAttribute()

=item moveToElement()


=item isNamespaceDecl()

=item isValid()

=item normalization()

=item quoteChar()

=item lookupNamespace(prefix)


=item encoding()

=item standalone()

=item xmlVersion()

=item baseURI()

The base URI of the node. See the XML Base W3C specification.

=item depth()

The depth of the node in the tree, starts at 0 for the root node.

=item xmlLang()

The xml:lang scope within which the node resides.


=item columnNumber()

=item lineNumber()

=item byteConsumed()

=item setParserProp(prop,value)

=item getParserProp(prop)

=item close

This method releases any resources allocated by the current instance
and closes any underlying input. It returns 0 on failure and 1 on
success. This method is automatically called by the destructor,
therefore you do not have to call it directly.

=head2 DESTRUCTION

XML::LibXML takes care of the reader object destruction when the last
reference to the reader object goes out of scope. The document tree is
preserved, though, if either of $reader->document or
$reader->preserveNode was used and references to the document tree
exist.


=back

=head2 NODE TYPES

The reader interface uses the following node types (exported by
default as constants).

  XML_READER_TYPE_NONE                    => 0
  XML_READER_TYPE_ELEMENT                 => 1
  XML_READER_TYPE_ATTRIBUTE               => 2
  XML_READER_TYPE_TEXT                    => 3
  XML_READER_TYPE_CDATA                   => 4
  XML_READER_TYPE_ENTITY_REFERENCE        => 5
  XML_READER_TYPE_ENTITY                  => 6
  XML_READER_TYPE_PROCESSING_INSTRUCTION  => 7
  XML_READER_TYPE_COMMENT                 => 8
  XML_READER_TYPE_DOCUMENT                => 9
  XML_READER_TYPE_DOCUMENT_TYPE           => 10
  XML_READER_TYPE_DOCUMENT_FRAGMENT       => 11
  XML_READER_TYPE_NOTATION                => 12
  XML_READER_TYPE_WHITESPACE              => 13
  XML_READER_TYPE_SIGNIFICANT_WHITESPACE  => 14
  XML_READER_TYPE_END_ELEMENT             => 15
  XML_READER_TYPE_END_ENTITY              => 16
  XML_READER_TYPE_XML_DECLARATION         => 17

=head2 MISSING FUNCTIONS

Function missing compared to libxml2 can be grouped into the following
categories:

=over 4

=item functions working with Schema/RelaxNG

=item functions enabling low-level interoperability between libxml components

=item libxml-specific error-handling

=back

Below, find the functions listed by name:

=over 4

=item xmlTextReaderGetErrorHandler

=item xmlTextReaderGetRemainder

=item xmlTextReaderLocatorBaseURI	

=item xmlTextReaderLocatorLineNumber	

=item xmlTextReaderRelaxNGSetSchema

=item xmlTextReaderRelaxNGValidate	

=item xmlTextReaderSchemaValidate

=item xmlTextReaderSchemaValidateCtxt

=item xmlTextReaderSetErrorHandler

=item xmlTextReaderSetSchema	

=item xmlTextReaderSetStructuredErrorHandler	

=back

=head1 VERSION

0.02

=head1 AUTHOR

Heiko Klein, E<lt>H.Klein@gmx.net<gt>

=head1 MAINTAINER

Petr Pajas, E<lt>pajas@matfyz.cz<gt>

=head1 SEE ALSO

L<http://xmlsoft.org/html/libxml-xmlreader.html>

=cut
