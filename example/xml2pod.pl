#!/usr/bin/perl -w
use XML::LibXML;
use File::Path;
use File::Basename;

# (c) 2001 christian p. glahn

# This is an example how to use the DOM interface of XML::LibXML
# The script reads a XML File with a module specification. If the 
# module contains several classes, the script fetches them and stores
# the data into different POD Files. 

{
  my $xml_file = "example/libxml.xml";

  # init the file parser
  my $parser = XML::LibXML->new();

  my $target_dir = "XML-LibXML-${XML::LibXML::VERSION}/lib";
  if ( scalar @ARGV == 1 ){
    $xml_file = $ARGV[0];
  }
  elsif ( @ARGV == 2 ) {
      $xml_file = $ARGV[0];
      $target_dir = $ARGV[1];
  }

  # read the DOM
  my $dom    = $parser->parse_file( $xml_file );

  # get the ROOT Element of the DOM
  my $elem   = $dom->getDocumentElement();

  # test if the element has the correct node type ...
  if ( $elem->getType() == XML_ELEMENT_NODE ) {

    # ... and the correct name
    if ( $elem->getName() eq "module" ) {

      # find class definitions without XPath :-P
      foreach my $child ( $elem->getElementsByTagName("class") ) { 
        handle_class( $child, $target_dir ); # handle the class
      }
    }
    else {
      warn "ERROR> document is not a module! \n";
    }
  }
  else {
    warn "ERROR> not an element as root\n";
  }
}

sub endl() { "\n"; } # helper for c++ programmer ;)

sub handle_class {
  my $node = shift; # node to handle (<class ..>)
  my $target_dir = shift;
  
  my $name ="";         # for POD - NAME Section
  my $description = ""; # for POD - DESCRIPTION and SYNOPSIS Section
  my $version ="";      # for POD - VERSION Section 
  my $seealso ="";      # for POD - SEE ALSO Section

  # find the information for the different sections
  my $cld = undef; 

  # we'll ignore any other node than Element nodes!
  ( $cld ) = $node->getElementsByTagName( "short" );
  if( defined $cld ) {
    my $data = $cld->getFirstChild();
    if( $data && $data->getType == XML_TEXT_NODE ) {
      $name = "=head1 NAME".endl.endl.$node->getAttribute( "name" )." - ";
      $name .= $data->getData().endl.endl;
    }
  }
  
  ( $cld ) = $node->getElementsByTagName( "description" );
  if( defined $cld ) {
	# collect synopsis and descriptions
	$description = handle_descr( $cld );
  }
  
  ( $cld ) = $node->getElementsByTagName( "also" );
  if ( defined $cld  ) {
	# build the see also list.
	$seealso = "=head1 SEE ALSO".endl. endl;
	my $str  = "";
	foreach my $item ( $cld->getChildnodes() ) {
	  if ( $item->getType == XML_ELEMENT_NODE && 
	       $item->getName() eq "item" ) {
	    $str .=", " if ( length $str );
	    $str .= $item->getAttribute("name");
	  }
	}
	$seealso .= $str. endl. endl;
  }
  ( $cld ) = $node->getElementsByTagName( "version" );
  if ( defined $cld ) {
	# handle VERSION information
	$version = "=head1 VERSION".endl.endl;
	if ( $cld->getFirstChild() ){
	  $version .= $cld->getFirstChild()->getData() . endl. endl;
	}
  }
  
  # print the data to a separated POD File
  my $filename = $node->getAttribute("name");
  $filename =~ s/::/\//g;
  print("writing file: ${target_dir}/${filename}.pod\n");
  mkpath([dirname("${target_dir}/${filename}.pod")]);
  open FILE , "> ${target_dir}/${filename}.pod" ||
    do{
      warn "cannot open file...\n"; 
      return ; # don't proceed if there is no open descriptor
    };
  
  print FILE  $name. $description, $seealso, $version;
  close FILE;
}

sub handle_descr {
  my $node = shift;
  return "" if not $node;
  my ( @synop, @methods, $description );

  $description ="";

  my $child = $node->getFirstChild();
  while ( $child ) {
    if ( $child->getType() == XML_TEXT_NODE ) {
      my $s = $child->getData();
      if ( $s !~ /^[\s\n\r]*$/ ){ # if not only whitespaces ...
	$description .= $s;
      }
    }
    elsif( $child->getType == XML_ELEMENT_NODE ) {
      my $name = $child->getName();
      # translate bold and italic information for POD
      if( $name eq "b" || $name eq "i" ) {
	$description .= uc( $name )."<";
	$description .= $child->getFirstChild()->getData() . ">" ;
      }
      elsif ( $name eq "method" ) {
	push @synop, $child->getAttribute("synopsis") ;
	push @methods, $child;
      }
    }
    $child = $child->getNextSibling();
  }

  # ok, this look not very beautyfull ... :-|
  my $rv = "=head1 SYNOPSIS".endl. endl;
  $rv .= "  "."use ".$node->getParentNode()->getAttribute( "name" ) . ";";
  $rv .= endl. endl;
  # now print the synopsissies... 
  foreach ( @synop ) {
    $rv .= "  ". $_. endl; # print leading whitespace for the correct format in POD
  }
  $rv .= endl;
  
  $rv .= "=head1 DESCRIPTION". endl. endl;
  $description =~ s/([\s\n\r])[\s\n\r]*/$1/g;
  $description =~ s/^\s*//; $description =~ s/\s*$//;
      

  $rv .= $description. endl. endl;
  if ( scalar @methods ) { # handle the method list 
    $rv .= "=head2 Methods". endl.endl;
    $rv .= "=over 4".endl. endl;
    foreach my $mn ( @methods ) { 
      $rv .= handle_method( $mn ); 
    }
    $rv .= "=back". endl.endl;
  }
  return $rv;
}

sub handle_method {
  my $node = shift;
  return "" unless $node;

  my $rv = "=item B<".$node->getAttribute("name").">". endl. endl;
  my $child = $node->getFirstChild();
  my $str = "";
  while ( $child ) {
    if ( $child->getType() == XML_TEXT_NODE &&
	 $child->getData() !~ /^[\s\n\r]*$/ ) {
        my $ds = $child->getData();
	$ds =~ s/([\s\n\r])[\s\n\r]*/$1/g;
	$ds =~ s/^\s*//; $ds =~ s/\s*$//; 
	$str .= " " if length $str;
	$str .= $ds;
    }
    elsif( $child->getType == XML_ELEMENT_NODE ) {
      my $n = $child->getName();
      if( $n eq "b" || $n eq "i" ) {
	$str .= " " if ( length $str );
	$str .= uc($n)."<".$child->getFirstChild()->getData().">" ;
      }
      elsif ( $n eq "example" ) {

	$rv .= $str .endl. endl;
	# if we found an example for a method we should display it as CODE! 
	# but if the CDATA section contains more than a line, this won't work 
	# anymore :-(
	$rv .= "  ". $child->getFirstChild()->getData(). endl.endl  ;
	$str = "";
      }
    }
    $child = $child->getNextSibling();
  }
  $rv .= $str .endl. endl if length $str;
  return $rv;
}
