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
    XML_READER_TYPE_XML_DECLARATION => 17,

    XML_READER_NONE      => -1,
    XML_READER_START     =>  0,
    XML_READER_ELEMENT   =>  1,
    XML_READER_END       =>  2,
    XML_READER_EMPTY     =>  3,
    XML_READER_BACKTRACK =>  4,
    XML_READER_DONE      =>  5,
    XML_READER_ERROR     =>  6
};
use vars qw( @EXPORT @EXPORT_OK %EXPORT_TAGS );

BEGIN {

%EXPORT_TAGS = (
  types =>
  [qw(
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
    )],
  states =>
  [qw(
    XML_READER_NONE
    XML_READER_START
    XML_READER_ELEMENT
    XML_READER_END
    XML_READER_EMPTY
    XML_READER_BACKTRACK
    XML_READER_DONE
    XML_READER_ERROR
   )]
);
@EXPORT    = (@{$EXPORT_TAGS{types}},@{$EXPORT_TAGS{states}});
@EXPORT_OK = @EXPORT;
$EXPORT_TAGS{all}=\@EXPORT_OK;

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

    my ($key, $value);
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
    return $flags;
  }
  my %props = (
    load_ext_dtd => 1,		 # load the external subset
    complete_attributes => 2,	 # default DTD attributes
    validation => 3,		 # validate with the DTD
    expand_entities => 4,	 # substitute entities
  );
  sub getParserProp {
    my ($self, $name) = @_;
    my $prop = $props{$name};
    return undef unless defined $prop;
    return $self->_getParserProp($prop);
  }
  sub setParserProp {
    my $self = shift;
    my %args = map { ref($_) eq 'HASH' ? (%$_) : $_ } @_;
    my ($key, $value);
    while (($key,$value) = each %args) {
      my $prop = $props{ $key };
      $self->_setParserProp($prop,$value);
    }
    return;
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
    if ($args{RelaxNG}) {
      $self->_setRelaxNGFile($args{RNG});
    }
    if ($args{Schema}) {
      $self->_setXSDFile($args{XSD});
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
    $reader->_preservePattern($pattern,[reverse %$ns_map]);
  } else {
    $reader->_preservePattern(@_);
  }
}

1;
__END__


=head1 NAME

XML::LibXML::Reader - interface to libxml2 pull parser

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

or

  $reader = new XML::LibXML::Reader("file.xml")
       or die "cannot read file.xml\n";
  $reader->preservePattern('//table/tr');
  $reader->finish;
  print $reader->document->toString(1);

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

The naming of methods compared to libxml2 and C# XmlTextReader has
been changed slightly to match the conventions of XML::LibXML. Some
functions have been changed or added with respect to the C interface.

=head1 CONSTRUCTOR

Depending on the XML source, the Reader object can be created with
either of:

  my $reader = XML::LibXML::Reader->new( location => "file.xml", ... );
  my $reader = XML::LibXML::Reader->new( string => $xml_string, ... );
  my $reader = XML::LibXML::Reader->new( IO => $file_handle, ... );
  my $reader = XML::LibXML::Reader->new( DOM => $dom, ... );

where ... are (optional) reader options described below in L<PARSER OPTIONS>. The
constructor recognizes the following XML sources:

=head2 SOURCE SPECIFICATION

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

=head2 PARSING OPTIONS

=over 4

=item URI

can be used to provide baseURI when parsing strings or filehandles.

=item encoding

override document encoding.

=item RNG

can be used to specify a path to a RelaxNG schema which is then used
to validate the document as it is processed.

=item XSD

can be used to specify a path to a W3C XSD schema which is then used
to validate the document as it is processed. 

=item recover

recover on errors (0/1)

=item expand_entities

substitute entities (0/1)

=item load_ext_dtd

load the external subset (0/1)

=item complete_attributes

default DTD attributes (0/1)

=item validation

validate with the DTD (0/1)

=item suppress_errors

suppress error reports (0/1)

=item suppress_warnings

suppress warning reports (0/1)

=item pedantic_parser

pedantic error reporting (0/1)

=item no_blanks

remove blank nodes (0/1)

=item expand_xinclude

Implement XInclude substitition (0/1)

=item no_network

Forbid network access (0/1)

=item clean_namespaces

remove redundant namespaces declarations (0/1)

=item no_cdata

merge CDATA as text nodes (0/1)

=item no_xinclude_nodes

do not generate XINCLUDE START/END nodes (0/1)

=back

=head1 METHODS (CONTROLLING PARSING PROGRESS)

=over 4

=item read()

Moves the position to the next node in the stream, exposing its
properties.

Returns 1 if the node was read successfully, 0 if there is no more
nodes to read, or -1 in case of error

=item readAttributeValue()

Parses an attribute value into one or more Text and EntityReference nodes.

Returns 1 in case of success, 0 if the reader was not positionned on
an attribute node or all the attribute values have been read, or -1 in
case of error.

=item readState()

Gets the read state of the reader. Returns the state value, or -1 in
case of error. The module exports constants for the Reader states, see
C<STATES> below.

=item depth()

The depth of the node in the tree, starts at 0 for the root node.

=item next()

Skip to the node following the current one in the document order while
avoiding the subtree if any.  Returns 1 if the node was read
successfully, 0 if there is no more nodes to read, or -1 in case of
error.

=item nextElement(localname?,nsURI?)

Skip nodes following the current one in the document order until a
specific element is reached.  The element's name must be equal to a
given localname if defined, and its namespace must equal to a given
nsURI if defined. Either of the arguments can be undefined (or
omitted, in case of the latter or both).

Returns 1 if the element was found, 0 if there is no more nodes to
read, or -1 in case of error.

=item skipSiblings()

Skip all nodes on the same or lower level until the first node on a
higher level is reached.  In particular, if the current node occurs in
an element, the reader stops at the end tag of the parent element,
otherwise it stops at a node immediately following the parent node.

Returns 1 if successful, 0 if end of the document is reached, or -1 in
case of error.

=item nextSibling()

It skips to the node following the current one in the document order
while avoiding the subtree if any.

Returns 1 if the node was read successfully, 0 if there is no more
nodes to read, or -1 in case of error

=item nextSiblingElement(name?,nsURI?)

Like nextElement but only processes sibling elements of the current
node (moving forward using nextSibling() rather than read(),
internally).

Returns 1 if the element was found, 0 if there is no more sibling
nodes, or -1 in case of error.

=item finish()

Skip all remaining nodes in the document, reaching end of the
document.

Returns 1 if successful, 0 in case of error.

=item close()

This method releases any resources allocated by the current instance
and closes any underlying input. It returns 0 on failure and 1 on
success. This method is automatically called by the destructor when
the reader is forgotten, therefore you do not have to call it
directly.

=back

=head1 METHODS (EXTRACTING INFORMATION)

=over 4

=item name()

Returns the qualified name of the current node, equal to (Prefix:)LocalName.

=item nodeType()

Returns the type of the current node. See L<NODE TYPES> below.

=item localName()

Returns the local name of the node.

=item prefix()

Returns the prefix of the namespace associated with the node.

=item namespaceURI()

Returns the URI defining the namespace associated with the node.

=item isEmptyElement()

Check if the current node is empty, this is a bit bizarre in the sense
that <a/> will be considered empty while <a></a> will not.

=item hasValue()

Returns true if the node can have a text value.

=item value()

Provides the text value of the node if present or undef if not
available.

=item readInnerXml()

Reads the contents of the current node, including child nodes and
markup. Returns a string containing the XML of the node's content, or
undef if the current node is neither an element nor attribute, or has
no child nodes.

=item readOuterXml()

Reads the contents of the current node, including child nodes and markup.

Returns a string containing the XML of the node including its content,
or undef if the current node is neither an element nor attribute.

=back

=head1 METHODS (EXTRACTING DOM NODES)

=over 4

=item document()

Provides access to the document tree built by the reader. This
function can be used to collect the preserved nodes (see
preserveNode() and preservePattern).

CAUTION: Never use this function to modify the tree unless reading of
the whole document is completed!

=item copyCurrentNode(deep)

This function is similar a DOM function copyNode(). It returns a copy
of the currently processed node as a corresponding DOM object. Use
deep = 1 to obtain the full subtree.

=item preserveNode()

This tells the XML Reader to preserve the current node in the document
tree. A document tree consisting of the preserved nodes and their
content can be obtained using the method document() once parsing is
finished.

Returns the node or NULL in case of error.

=item preservePattern(pattern,\%ns_map)

This tells the XML Reader to preserve all nodes matched by the pattern
(which is a streaming XPath subset).  A document tree consisting of
the preserved nodes and their content can be obtained using the method
document() once parsing is finished.

An optional second argument can be used to provide a HASH reference
mapping prefixes used by the XPath to namespace URIs.

The XPath subset available with this function is described at

  http://www.w3.org/TR/xmlschema-1/#Selector

and matches the production

   Path ::= ('.//')? ( Step '/' )* ( Step | '@' NameTest )

Returns a positive number in case of success and -1 in case of error

=back

=head1 METHODS (PROCESSING ATTRIBUTES)

=over 4

=item attributeCount()

Provides the number of attributes of the current node.

=item hasAttributes()

Whether the node has attributes.

=item getAttribute(name)

Provides the value of the attribute with the specified qualified name.

Returns a string containing the value of the specified attribute, or
undef in case of error.

=item getAttributeNs(localName, namespaceURI)

Provides the value of the specified attribute.

Returns a string containing the value of the specified attribute, or
undef in case of error.

=item getAttributeNo(no)

Provides the value of the attribute with the specified index relative
to the containing element.

Returns a string containing the value of the specified attribute, or
undef in case of error.

=item isDefault()

Returns true if the current attribute node was generated from the
default value defined in the DTD.

=item moveToAttribute(name)

Moves the position to the attribute with the
specified local name and namespace URI.

Returns 1 in case of success, -1 in case of error, 0 if not found

=item moveToAttributeNo(no)

Moves the position to the attribute with the
specified index relative to the containing element.

Returns 1 in case of success, -1 in case of error, 0 if not found

=item moveToAttributeNs(localName,namespaceURI)

Moves the position to the attribute with the
specified local name and namespace URI.

Returns 1 in case of success, -1 in case of error, 0 if not found

=item moveToFirstAttribute()

Moves the position to the first attribute
associated with the current node.

Returns 1 in case of success, -1 in case of error, 0 if not found

=item moveToNextAttribute()

Moves the position to the next attribute
associated with the current node.

Returns 1 in case of success, -1 in case of error, 0 if not found

=item moveToElement()

Moves the position to the node that contains the current attribute
node.

Returns 1 in case of success, -1 in case of error, 0 if not moved

=item isNamespaceDecl()

Determine whether the current node is a namespace declaration rather
than a regular attribute.

Returns 1 if the current node is a namespace declaration, 0 if it is a
regular attribute or other type of node, or -1 in case of error.

=back

=head1 OTHER METHODS

=over 4

=item lookupNamespace(prefix)

Resolves a namespace prefix in the scope of the current element.

Returns a string containing the namespace URI to which the prefix maps
or undef in case of error.

=item encoding()

Returns a string containing the encoding of the document or undef in
case of error.

=item standalone()

Determine the standalone status of the document being read.  Returns 1
if the document was declared to be standalone, 0 if it was declared to
be not standalone, or -1 if the document did not specify its
standalone status or in case of error.

=item xmlVersion()

Determine the XML version of the document being read. Returns a
string containing the XML version of the document or undef in case of
error.

=item baseURI()

The base URI of the node. See the XML Base W3C specification.

=item isValid()

Retrieve the validity status from the parser.

Returns 1 if valid, 0 if no, and -1 in case of error.

=item xmlLang()

The xml:lang scope within which the node resides.

=item lineNumber()

Provide the line number of the current parsing point.
Available if libxml2 >= 2.6.17.

=item columnNumber()

Provide the column number of the current parsing point.
Available if libxml2 >= 2.6.17.

=item byteConsumed()

This function provides the current index of the parser relative to the
start of the current entity. This function is computed in bytes from
the beginning starting at zero and finishing at the size in bytes of
the file if parsing a file. The function is of constant cost if the
input is UTF-8 but can be costly if run on non-UTF-8 input.
Available if libxml2 >= 2.6.18.

=item setParserProp(prop => value, ...)

Change the parser processing behaviour by changing some of its
internal properties.  The following properties are available with this
function: "load_ext_dtd", "complete_attributes", "validation",
"expand_entities".  

Since some of the properties can only be changed before any read has
been done, it is best to set the parsing properties at the
constructor.

Returns 0 if the call was successful, or -1 in case of error

=item getParserProp(prop)

Get value of an parser internal property. The following property names
can be used: "load_ext_dtd", "complete_attributes", "validation",
"expand_entities".

Returns the value, usually 0 or 1, or -1 in case of error.

=back

=head1 DESTRUCTION

XML::LibXML takes care of the reader object destruction when the last
reference to the reader object goes out of scope. The document tree is
preserved, though, if either of $reader->document or
$reader->preserveNode was used and references to the document tree
exist.

=head1 NODE TYPES

The reader interface provides the following constants for node types
(the constant symbols are exported by default or if tag C<:types> is
used).

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

=head1 STATES

The following constants represent the values returned by
readState(). They are exported by default, or if tag C<:states> is
used:

  XML_READER_NONE      => -1
  XML_READER_START     =>  0
  XML_READER_ELEMENT   =>  1
  XML_READER_END       =>  2
  XML_READER_EMPTY     =>  3
  XML_READER_BACKTRACK =>  4
  XML_READER_DONE      =>  5
  XML_READER_ERROR     =>  6

=head1 VERSION

0.02

=head1 AUTHOR

Heiko Klein, E<lt>H.Klein@gmx.net<gt>

=head1 MAINTAINER

Petr Pajas, E<lt>pajas@matfyz.cz<gt>

=head1 SEE ALSO

L<http://xmlsoft.org/html/libxml-xmlreader.html>

L<http://dotgnu.org/pnetlib-doc/System/Xml/XmlTextReader.html>

=cut
