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

use ExtUtils::MakeMaker;

my $SKIP_SAX_INSTALL = $ENV{SKIP_SAX_INSTALL};

# -------------------------------------------------------------------------- #
# Detect libxml2 compiler/linker flags.
#
# Detection chain (first match wins):
#   1. User-provided INC/LIBS on the command line
#   2. pkg-config libxml-2.0
#   3. xml2-config
#   4. Alien::Libxml2 (if installed)
#
# This allows systems with libxml2-dev installed to skip the Alien dependency
# entirely (see GH#109).
# -------------------------------------------------------------------------- #

my %xsbuild;
my $libxml2_source;

# Check for user-provided INC/LIBS on the command line
my ($user_INC, $user_LIBS);
@ARGV = grep {
  if (/^INC=(.*)/) { $user_INC = $1; 0 }
  elsif (/^LIBS=(.*)/) { $user_LIBS = $1; 0 }
  else { 1 }
} @ARGV;

if (defined $user_INC || defined $user_LIBS) {
    # User explicitly provided flags — use them as-is
    %xsbuild = (
        INC  => $user_INC  || '',
        LIBS => [ $user_LIBS || '-lxml2' ],
    );
    $libxml2_source = "command line";
    print "Using user-provided INC/LIBS\n";
}

if (!$libxml2_source) {
    # Try pkg-config
    my $pkg_cflags = `pkg-config --cflags libxml-2.0 2>/dev/null`;
    my $pkg_libs   = `pkg-config --libs libxml-2.0 2>/dev/null`;
    if ($? == 0 && $pkg_libs =~ /\S/) {
        chomp $pkg_cflags;
        chomp $pkg_libs;
        %xsbuild = (
            INC  => $pkg_cflags,
            LIBS => [ $pkg_libs ],
        );
        $libxml2_source = "pkg-config";
        my $pkg_version = `pkg-config --modversion libxml-2.0 2>/dev/null`;
        chomp $pkg_version;
        print "Found libxml2 $pkg_version via pkg-config\n";
    }
}

if (!$libxml2_source) {
    # Try xml2-config
    my $xml2_prefix = $ENV{XMLPREFIX};
    my $xml2cfg = defined $xml2_prefix ? "$xml2_prefix/bin/xml2-config" : "xml2-config";
    my $xml2_cflags = `$xml2cfg --cflags 2>/dev/null`;
    my $xml2_libs   = `$xml2cfg --libs 2>/dev/null`;
    if ($? == 0 && $xml2_libs =~ /\S/) {
        chomp $xml2_cflags;
        chomp $xml2_libs;
        %xsbuild = (
            INC  => $xml2_cflags,
            LIBS => [ $xml2_libs ],
        );
        $libxml2_source = "xml2-config";
        my $xml2_version = `$xml2cfg --version 2>/dev/null`;
        chomp $xml2_version;
        print "Found libxml2 $xml2_version via xml2-config\n";
    }
}

if (!$libxml2_source) {
    # Fall back to Alien::Libxml2
    eval {
        require Alien::Base::Wrapper;
        Alien::Base::Wrapper->import('Alien::Libxml2');
        %xsbuild = Alien::Base::Wrapper->mm_args;
        $libxml2_source = "Alien::Libxml2";
        print "Found libxml2 via Alien::Libxml2\n";
    };
    if ($@) {
        die <<"DEATH";

ERROR: Could not find libxml2.

XML::LibXML requires libxml2 development files to be installed.
Please install them using one of:

  # Debian/Ubuntu
  sudo apt-get install libxml2-dev

  # Fedora/RHEL
  sudo dnf install libxml2-devel

  # macOS (Homebrew)
  brew install libxml2

  # macOS (Xcode Command Line Tools — usually pre-installed)
  xcode-select --install

Or specify the location manually:
  perl Makefile.PL INC="-I/path/to/include/libxml2" LIBS="-L/path/to/lib -lxml2"

Or install the Alien::Libxml2 Perl module as a last resort:
  cpanm Alien::Libxml2

DEATH
    }
}

# Build the xsbuild flags — always add -DHAVE_UTF8 and $(O_FILES)
my %xsbuild_final = %xsbuild;
{
    my $define = $xsbuild_final{DEFINE} || '';
    $define .= ' -DHAVE_UTF8' unless $define =~ /-DHAVE_UTF8/;
    $xsbuild_final{DEFINE} = $define;
    $xsbuild_final{OBJECT} = '$(O_FILES)';

}

# -------------------------------------------------------------------------- #
# Configure requirements depend on which detection method was used
# -------------------------------------------------------------------------- #
my %ConfigReqs = (
  "Config" => 0,
  "ExtUtils::MakeMaker" => 0,
);
if ($libxml2_source eq 'Alien::Libxml2') {
    $ConfigReqs{"Alien::Libxml2"} = '0.14';
    $ConfigReqs{"Alien::Base::Wrapper"} = 0;
}

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

my %WriteMakefileArgs = (
  "NAME" => "XML::LibXML",
  "DISTNAME" => "XML-LibXML",
  "LICENSE" => "perl_5",
  "ABSTRACT" => "Interface to Gnome libxml2 xml parsing and DOM library",
  "AUTHOR" => "Petr Pajas <PAJAS\@cpan.org>",
  "MIN_PERL_VERSION" => '5.008001',
  "VERSION_FROM" => "LibXML.pm",
  'META_MERGE' => {
    'dynamic_config' => 1,
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
    %xsbuild_final,
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
