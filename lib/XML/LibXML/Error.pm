package XML::LibXML::Error;

use strict;
use vars qw($AUTOLOAD @error_domains $ERROR);
use Carp;
use overload
  '""' => \&as_string;

use constant XML_ERR_NONE	     => 0;
use constant XML_ERR_WARNING	     => 1; # A simple warning
use constant XML_ERR_ERROR	     => 2; # A recoverable error
use constant XML_ERR_FATAL	     => 3; # A fatal error

use constant XML_ERR_FROM_NONE	     => 0;
use constant XML_ERR_FROM_PARSER     => 1; # The XML parser
use constant XML_ERR_FROM_TREE	     => 2; # The tree module
use constant XML_ERR_FROM_NAMESPACE  => 3; # The XML Namespace module
use constant XML_ERR_FROM_DTD	     => 4; # The XML DTD validation
use constant XML_ERR_FROM_HTML	     => 5; # The HTML parser
use constant XML_ERR_FROM_MEMORY     => 6; # The memory allocator
use constant XML_ERR_FROM_OUTPUT     => 7; # The serialization code
use constant XML_ERR_FROM_IO	     => 8; # The Input/Output stack
use constant XML_ERR_FROM_FTP	     => 9; # The FTP module
use constant XML_ERR_FROM_HTTP	     => 10; # The FTP module
use constant XML_ERR_FROM_XINCLUDE   => 11; # The XInclude processing
use constant XML_ERR_FROM_XPATH	     => 12; # The XPath module
use constant XML_ERR_FROM_XPOINTER   => 13; # The XPointer module
use constant XML_ERR_FROM_REGEXP     => 14;	# The regular expressions module
use constant XML_ERR_FROM_DATATYPE   => 15; # The W3C XML Schemas Datatype module
use constant XML_ERR_FROM_SCHEMASP   => 16; # The W3C XML Schemas parser module
use constant XML_ERR_FROM_SCHEMASV   => 17; # The W3C XML Schemas validation module
use constant XML_ERR_FROM_RELAXNGP   => 18; # The Relax-NG parser module
use constant XML_ERR_FROM_RELAXNGV   => 19; # The Relax-NG validator module
use constant XML_ERR_FROM_CATALOG    => 20; # The Catalog module
use constant XML_ERR_FROM_C14N	     => 21; # The Canonicalization module
use constant XML_ERR_FROM_XSLT	     => 22; # The XSLT engine from libxslt
use constant XML_ERR_FROM_VALID	     => 23; # The validaton module

@error_domains = ("", "parser", "tree", "namespace", "validity",
		  "HTML parser", "memory", "output", "I/O", "ftp",
		  "http", "XInclude", "XPath", "xpointer", "regexp",
		  "Schemas datatype", "Schemas parser", "Schemas validity", 
		  "Relax-NG parser", "Relax-NG validity",
		  "Catalog", "C14N", "XSLT", "validity");


sub _callback_error {
    my $xE = shift;

    my $terr =bless {
        domain  => $xE->domain(),
        level   => $xE->level(),
        code    => $xE->code(),
        message => $xE->message(),
        file    => $xE->file(),
        line    => $xE->line(),
        str1    => $xE->str1(),
        str2    => $xE->str2(),
        str3    => $xE->str3(),
        int1    => $xE->num1(),
        int2    => $xE->num2(),
    }, "XML::LibXML::Error";

    unless ( defined $terr->{file} and length $terr->{file} ) {
        $terr->{file} = 'string()'; # make it easier to recognize parsed strings
    }

    if ( defined $ERROR ) {
        $terr->{prev} = $ERROR;
    }

    $ERROR = $terr;
}

sub _report_error {
    die $ERROR;
}


sub AUTOLOAD {
  my $self=shift;
  return undef unless ref($self);
  my $sub = $AUTOLOAD;
  $sub =~ s/.*:://;
  if ($sub=~/^(?:code|_prev|level|file|line|domain|nodename|message|str[123]|int[12])$/) {
    return $self->{$sub};
  } else {
    croak("Unknown error field $sub");
  }
}

sub DESTROY {}

sub domain {
    my ($self)=@_;
    return undef unless ref($self);
    return $error_domains[$self->{domain}];
}

sub as_string {
    my ($self)=@_;
    my $msg = "";
    my $level;
    
    if (defined($self->{_prev})) {
        $msg = $self->{_prev}->as_string;
    }
    
    if ($self->{level} == XML_ERR_NONE) {
        $level = "";
    } elsif ($self->{level} == XML_ERR_WARNING) {
        $level = "warning";
    } elsif ($self->{level} == XML_ERR_ERROR ||
             $self->{level} == XML_ERR_FATAL) {
        $level = "error";
    }
    my $where="";
    if (defined($self->{file})) {
        $where="$self->{file}:$self->{line}";
    } elsif (($self->{domain} == XML_ERR_FROM_PARSER)
             and
             $self->{line})  {
        $where="Entity: line $self->{line}";
    }
    if ($self->{nodename}) {
        $where.=": element ".$self->{nodename};
    }
    $msg.=$where.": " if $where ne "";
    $msg.=$error_domains[$self->{domain}]." ".$level." :";
    my $str=$self->{message};
    chomp($str);
    $msg.=" ".$str."\n";
    if (($self->{domain} == XML_ERR_FROM_XPATH) and
        defined($self->{str1})) {
        $msg.=$self->{str1}."\n";
        $msg.=(" " x $self->{int1})."^\n";
    }
    return $msg;
}

sub dump {
  my ($self)=@_;
  return join "\n", map { "'$_' => '$self->{$_}'" } keys %$self;
}

1;
