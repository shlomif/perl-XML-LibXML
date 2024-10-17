# -------------------------------------------------------------------------- #
# $Id$
# -------------------------------------------------------------------------- #
# Makefile.PL for XML::LibXML.
# This file is required to generate a localized Makefile
# -------------------------------------------------------------------------- #
#
#
# This is free software, you may use it and distribute it under the same terms as
# Perl itself.
#
# Copyright 2001-2003 AxKit.com Ltd., 2002-2006 Christian Glahn, 2006-2009 Petr Pajas
#

use strict;
use warnings;

require 5.008001;

use Alien::Base::Wrapper qw( Alien::Libxml2 );
use ExtUtils::MakeMaker;
use Config;

my $SKIP_SAX_INSTALL = $ENV{SKIP_SAX_INSTALL};

my %ConfigReqs = (
  "Alien::Libxml2" => '0.14',
  "Alien::Base::Wrapper" => 0,
  "Config" => 0,
  "ExtUtils::MakeMaker" => 0,
);
my %DevReqs = (
  'Test::CPAN::Changes' => 0,
  'Test::Kwalitee' => 0,
  'Test::Pod' => 0,
  'Test::TrailingSpace' => 0,
);
my %TestReqs = (
  "Config" => 0,
  "Errno" => 0,
  "IO::File" => 0,
  "IO::Handle" => 0,
  "POSIX" => 0,
  "Scalar::Util" => 0,
  "Test::More" => 0,
  "locale" => 0,
  "utf8" => 0,
);
my %prereqs = (
  "Carp" => 0,
  "DynaLoader" => 0,
  "Encode" => 0, # actually used in one module. requires Perl 5.8+
  "Exporter" => "5.57",
  'IO::Handle' => 0,
  'Scalar::Util' => 0,
  'Tie::Hash' => 0,
  'XML::NamespaceSupport' => '1.07',
  'XML::SAX' => '0.11',
  'XML::SAX::Base' => '0',
  'XML::SAX::DocumentLocator' => '0',
  'XML::SAX::Exception' => '0',
  "base" => 0,
  "constant" => 0,
  "overload" => 0,
  "parent" => 0,
  "strict" => 0,
  "warnings" => 0,
);

my %xsbuild_concat = (
  DEFINE  => '-DHAVE_UTF8',
  OBJECT  => '$(O_FILES)',
);
my %xsbuild = Alien::Base::Wrapper->mm_args;  # Might contain a definition of DEFINE, must thus concatenate.
while (my ($k, $v) = each %xsbuild_concat) {
  my $base_val = $xsbuild{$k};
  $xsbuild{$k} = (defined($base_val) ? ($base_val . ' ' . $v) : $v);
}

my %WriteMakefileArgs = (
  "NAME" => "XML::LibXML",
  "DISTNAME" => "XML-LibXML",
  "LICENSE" => "perl_5",
  "ABSTRACT" => "Interface to Gnome libxml2 xml parsing and DOM library",
  "AUTHOR" => "Petr Pajas <PAJAS\@cpan.org>",
  "MIN_PERL_VERSION" => '5.008001',
  "VERSION_FROM" => "LibXML.pm",
  'META_MERGE' => {
    'dynamic_config' => 0,
    'meta-spec' => {version => 2},
    'no_index' => {directory => ['xt']},
    'resources' => {
      repository => {
        type => 'git',
        url  => 'https://github.com/shlomif/perl-XML-LibXML.git',
        web  => 'https://github.com/shlomif/perl-XML-LibXML',
      },
    },
    'keywords' => [
      "dom",
      "html",
      "libxml",
      "object oriented",
      "oop",
      "parse",
      "parser",
      "parsing",
      "pullparser",
      "sax",
      "sgml",
      "xml",
      "xpath",
      "XPath",
      "xs",
    ],
  },
  "CONFIGURE_REQUIRES" => \%ConfigReqs,
  "TEST_REQUIRES" => \%TestReqs,
  "PREREQ_PM" => \%prereqs,
  "test" => {
    "TESTS" => "t/*.t"
  }
);

%WriteMakefileArgs = (
    %WriteMakefileArgs,
    %xsbuild,
);
unless ( eval { ExtUtils::MakeMaker->VERSION('6.63_03') } ) {
    my %fallback = (%prereqs, %TestReqs);
    delete $WriteMakefileArgs{TEST_REQUIRES};
    $WriteMakefileArgs{PREREQ_PM} = \%fallback;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION('6.52') };

delete $WriteMakefileArgs{MIN_PERL_VERSION}
  unless eval { ExtUtils::MakeMaker->VERSION('6.48') };

delete $WriteMakefileArgs{META_MERGE}
  unless eval { ExtUtils::MakeMaker->VERSION('6.46') };

delete $WriteMakefileArgs{LICENSE}
  unless eval { ExtUtils::MakeMaker->VERSION('6.31') };

WriteMakefile(%WriteMakefileArgs);

# append the install method to include the SAX parser INI file changes
sub MY::install {
   package MY;
   my $script = shift->SUPER::install(@_);
   if ( $SKIP_SAX_INSTALL ) {
       warn "Note: 'make install' will skip XML::LibXML::SAX registration with XML::SAX!\n";
   }
   else {
       $script =~ s/install :: (.*)$/install :: $1 install_sax_driver/m;
       $script .= <<"INSTALL";

install_sax_driver :
\t-\@\$(PERL) -I\$(INSTALLSITELIB) -I\$(INSTALLSITEARCH) -MXML::SAX -e "XML::SAX->add_parser(q(XML::LibXML::SAX::Parser))->save_parsers()"
\t-\@\$(PERL) -I\$(INSTALLSITELIB) -I\$(INSTALLSITEARCH) -MXML::SAX -e "XML::SAX->add_parser(q(XML::LibXML::SAX))->save_parsers()"

INSTALL
   }
   return $script;
}

# helper functions to build the Makefile
sub MY::manifypods {
  package MY;
  my $str = shift->SUPER::manifypods(@_);
#   warn $str;
#   $str =~ s/^manifypods : pure_all (.*)$/manifypods : pure_all docs $1/m;
  $str .= <<"EOF";
docs-fast :
\t\@$^X -pi~ -e 's{<edition>[0-9.]*</edition>}{<edition>'"\$(VERSION)"'</edition>}' docs/libxml.dbk
\t\@$^X -Iblib/arch -Iblib/lib example/xmllibxmldocs.pl docs/libxml.dbk lib/XML/LibXML/
docs : pure_all
\t\@$^X -pi~ -e 's{<edition>[0-9.]*</edition>}{<edition>'"\$(VERSION)"'</edition>}' docs/libxml.dbk
\t\@$^X -Iblib/arch -Iblib/lib example/xmllibxmldocs.pl docs/libxml.dbk lib/XML/LibXML/
\t\@$^X -pi.old -e 's/a/a/' Makefile.PL
\t\@echo "==> YOU MUST NOW RE-RUN $^X Makefile.PL <=="
\t\@false
EOF
  return $str;
}
