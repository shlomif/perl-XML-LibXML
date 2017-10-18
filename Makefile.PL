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

require 5.008;

use vars qw/$DEVNULL $is_Win32 $extralibdir $skipsaxinstall/;

use ExtUtils::MakeMaker;
use Config;
use Symbol;
use File::Spec;

$|=0;
my %config;

# -------------------------------------------------------------------------- #
# -------------------------------------------------------------------------- #
# common information go to the top, so they are easier to find
# -------------------------------------------------------------------------- #
my %INFOS = (
    'NAME'  => 'XML::LibXML',
    'VERSION_FROM' => 'LibXML.pm', # finds $VERSION
    'AUTHOR'    => 'Petr Pajas',
    'ABSTRACT'  => 'Interface to Gnome libxml2 xml parsing and DOM library',
    'LICENSE' => 'perl',
    (($ExtUtils::MakeMaker::VERSION >= 6.48)
        ? (MIN_PERL_VERSION => '5.008',)
        : ()
    ),
    'PREREQ_PM' => {
        'base' => 0,
        #'Hash::FieldHash' => '0.09',
        'parent' => 0,
        'strict' => 0,
        'Test::More' => 0,
        'vars' => 0,
        'warnings' => 0,
        'XML::NamespaceSupport' => '1.07',
        'XML::SAX' => '0.11',
        'XML::SAX::Base' => '0',
        'XML::SAX::Exception' => '0',
    },
    'OBJECT'    => '$(O_FILES)', # add the DOM extensions to libxml2
    ($ExtUtils::MakeMaker::VERSION >= 6.54)
    ?
    (
        META_MERGE =>
        {
            resources =>
            {
                repository => 'https://github.com/shlomif/perl-XML-LibXML',
                homepage => 'https://github.com/shlomif/perl-XML-LibXML',
            },
            keywords =>
            [
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
    )
    : (),
);
# -------------------------------------------------------------------------- #
# -------------------------------------------------------------------------- #

use lib qw(inc);
use Devel::CheckLib;

# Prompt the user here for any paths and other configuration


# -------------------------------------------------------------------------- #
# libxml2 valid versions

# -------------------------------------------------------------------------- #

# -------------------------------------------------------------------------- #
# read extra configurations from the commandline
my %params;
@params{qw(FORCE DEBUG DEFINE EXTRALIBDIR GDOME INC LIBS SKIP_SAX_INSTALL XMLPREFIX NO_THREADS LDFLAGS)}=();

@ARGV = grep {
  my ($key, $val) = split(/=/, $_, 2);
  if (exists $params{$key}) {
    $config{$key} = $val; 0
  } else { 1 }
} @ARGV;

$extralibdir = $config{EXTRALIBDIR};
delete $config{EXTRALIBDIR};

# -------------------------------------------------------------------------- #

# -------------------------------------------------------------------------- #
# force unsupported version
my $FORCE = delete $config{FORCE};

# switch Debugging messages on
my $DEBUG = delete $config{DEBUG};

if ( $config{DEBUG} and $is_Win32 ) {
    warn "win32 compile\n";
}
# -------------------------------------------------------------------------- #

# -------------------------------------------------------------------------- #
# enable perls UTF8 support if available
if ( $] >= 5.006 ) {
    warn "enable native perl UTF8\n";
    $config{DEFINE} .= " -DHAVE_UTF8";
}
if ( $] < 5.008 or $config{NO_THREADS} ) {
  warn "disabling XML::LibXML support for Perl threads\n";
  $config{DEFINE} .= " -DNO_XML_LIBXML_THREADS";
}
delete $config{NO_THREADS};
# -------------------------------------------------------------------------- #

# -------------------------------------------------------------------------- #
# get the libxml2 configuration
#
# For each release we already know which libxml2 versions work with the given
# module. All we need is to keep track of bad versions.
# If a user wants to build XML::LibXML with a newer version, there will be
# a warning, that errors are possible.
#
# We keep track of the valid versions by keeping a blacklist of intervals
# of working and not working versions where Ma.Mi.Pt <= X.Y.Z is of the same
# state.
#
# NOTE: All versions, the tests pass will be marked as working.
#

$skipsaxinstall = $ENV{SKIP_SAX_INSTALL} || $config{SKIP_SAX_INSTALL};
delete $config{SKIP_SAX_INSTALL};

unless ( $is_Win32 ) { # cannot get config in W32
    my @blacklist = (
                     # format X,Y,Z,is_ok, X,Y,Z is version,
                     # is_ok applies also to *preceding* versions
                     [2,4,22,0],
                     [2,4,25,0], # broken XPath
                     [2,4,28,0], # unsupported, may work fine with earlier XML::LibXML versions
                     [2,4,29,0], # broken
                     [2,4,30,0], # broken
                     [2,5,0,0], # unsupported
                     [2,5,1,0], # all pre 2.5.4 version have broken attr output
                     [2,5,5,0], # tests pass, but known as broken
                     [2,5,11,0], # will partially work
                     [2,6,0,0], # unsupported
                     [2,6,4,0], # schema error
                     [2,6,5,0], # broken xincludes
                     [2,6,15,0],
                   # [2,6,16,1], # first version to pass all tests
                     [2,6,18,1], # up to 2.6.18 all ok
                     [2,6,19,0], # broken c14n
                     [2,6,20,0], # broken schemas
                     [2,6,24,1], # all tests pass
                     [2,6,25,0], # broken XPath
                     [2,6,32,1], # tested, works ok
                     [2,7,1,0], # broken release, broken utf-16
                     [2,7,6,1], # tested, ok
                     [2,7,8,1], # tested, ok
                     [2,9,3,1], # schema regression
                     [2,9,4,0], # schema regression
                     [2,9,6,1],
                    );
    my $xml2cfg = "xml2-config";
    my $libprefix = $ENV{XMLPREFIX} || $config{XMLPREFIX};

    delete $config{XMLPREFIX}; # delete if exists, otherwise MakeMaker gets confused

    if ( defined $libprefix ) {
        $xml2cfg = $libprefix . '/bin/' . $xml2cfg;
    }

    # if a user defined INC and LIBS on the command line we must not
    # override them
    if ( not defined $config{LIBS} and not defined $config{INC} ) {
        print "running xml2-config...";
        eval {
            try_libconfig( $xml2cfg, \%config, \@blacklist );
        };

        if ( $@ ) {
            if ( $@ =~ /^VERSION|^FORCED/ ) {
                my $libxml2_version;
                print STDERR "The installed version of libxml2 $@ is not compatible with XML::LibXML (and probably buggy)!\n\n".
                    "You may continue at your own risk using 'perl Makefile.PL FORCE=1', but:\n\n".
                    "  - don't expect XML::LibXML to build or work correctly!\n".
                    "  - don't report errors!\n".
                    "  - don't send patches!\n\n".
                    "Check the README file for more information on versions\n".
                    "that are tested with XML::LibXML\n\n";
                if ($@ =~ /^VERSION (\S+)/) {
                    $libxml2_version = $1;
                }
                # 0 recommended by http://cpantest.grango.org (Notes for CPAN Authors)
                exit 0 if !$FORCE and $libxml2_version ne "2.9.4";
            }
            if ( $@ =~ /^UNTESTED (\S*)/ ) {
                warn "Note: libxml2 $1 was not tested with this XML::LibXML version.\n"
#                 warn <<"UNTESTED";
# WARNING!
# The installed version of libxml2 was not tested with this version of XML::LibXML.

#     XML::LibXML may fail building or some tests may not pass.
#     Expect strange errors and unstable scripts.

#     Check the README file for more informations
# END OF WARNING
# UNTESTED
            }

            if ( not defined $config{LIBS} and not defined $config{INC} ) {
                warn "didn't manage to get libxml2 config, guessing\n";
                $config{LIBS} = '-L/usr/local/lib -L/usr/lib -lxml2 -lm';
                $config{INC} = '-I/usr/local/include -I/usr/include';
                print <<"OPT";
options:
  LIBS='$config{LIBS}'
  INC='$config{INC}'
If this is wrong, Re-run as:
  \$ $^X Makefile.PL LIBS='-L/path/to/lib' INC='-I/path/to/include'

OPT
            }
        }
    }
}

# -------------------------------------------------------------------------- #

# -------------------------------------------------------------------------- #
# GDOME Support
#
# GDOME Support has to get explicitly activated by setting GDOME=1 as a config param.
#
unless ( $is_Win32 ) { # cannot get config in W32
    if ( $config{GDOME} ) {
        my $ver;
        my $state = undef; # there are three possible states:
                           # 1     : works
                           # 0     : works not
                           # undef : not yet tested
        my @blacklist = (
                         [0,7,2,0],
                         [0,7,3,1],
                        );
        print <<"GDOME";

GDOME Support (experimental):
   XML::LibXML can parse into XML::GDOME DOMs if libgdome is installed.
   This feature is optional and is not required for using XML::LibXML.

GDOME

        print "running gdome-config...";

        eval {
            test_libconfig( "gdome-config", \%config, @blacklist );
            print "NOTE: You will need to install XML::GDOME to use this feature\n";
        };

        if ( $@ ) {
            if ( $@ =~ /^VERSION/ ) {
                warn "The installed libgdome version is not supported\n";
            }
            elsif ( $@ =~ /^UNTESTED/ ) {
                warn "The installed libgdome version was not yet tested with XML::LibXML.\n";
                print "NOTE: You will need to install XML::GDOME to use this feature\n";
            }
        }
    }
}
# -------------------------------------------------------------------------- #


my $config_LIBS_alternatives;
# -------------------------------------------------------------------------- #
# fix the ld flags
# -------------------------------------------------------------------------- #
if (!defined $config{LIBS} || $config{LIBS} !~ /\-l(?:lib)?xml2\b/) {
    # in this case we are not able to run xml2-config. therefore we need to
    # expand the libz as well.
    if ($is_Win32) {
        if( $ENV{ACTIVEPERL_MINGW} ) {
            $config{LIBS} .= ' -llibxml2.lib -lzlib.lib';
        }
        else {
            my $l = $config{LIBS};

            if (!defined($l)) {
                $l = '';
            }

            # Put several options.
            $config_LIBS_alternatives = [
                map { "$l $_" }
                q/ -llibxml2/,
                q/ -lxml2 -lzlib/,
                q/ -llibxml2 -lzlib -llibgettextlib.dll/
            ];
            $config{LIBS} = $config_LIBS_alternatives->[-1];
            $config{INC} .= " -I$Config{incpath}";
        }
    }
    else {
        $config{LIBS} .= ' -lxml2 -lz -lm';
    }
}
elsif ($config{LIBS} !~ /\-lz\b/ and !($is_Win32 && $config{LIBS} !~ /\-lzlib\b/)) {
    # note if libxml2 has not -lz within its cflags, we should not use
    # it! We should trust libxml2 and assume libz is not available on the
    # current system (this is ofcourse not true with win32 systems.
    # $config{LIBS} .= $is_Win32 ? ' -lzlib' :' -lz';
    if ( $config{DEBUG} ) {
        warn "zlib was not configured\n";
        warn "set zlib\n" if $is_Win32;
    }
  if ($is_Win32) {
    if( $ENV{ACTIVEPERL_MINGW} ) {
      $config{LIBS} .= ' -lzlib.lib';
    } else {
      $config{LIBS} .= ' -lzlib';
    }
  } else {
    $config{LIBS} .= ' -lz';
  }
}

# -------------------------------------------------------------------------- #
# MacOS X Compiler switches have to go here
#
# if we run on MacOSX, we should check if 10.2 is running and if so,
# if the Build Target is set correctly. Otherwise we have to set it by
# hand

my $ldflags = delete $config{LDFLAGS};
if ($ldflags) {
    $config{dynamic_lib} = { OTHERLDFLAGS => " $ldflags " };
}

my $incpath = $config{INC} || "";
$incpath =~ s#(\A|\s)\s*-I#$1#g;

sub _libxml_check_lib_with_config_LIBs
{
    my ($lib_name, $conf_LIBS) = @_;

    return
    check_lib(
        debug => $DEBUG,
        LIBS => $conf_LIBS,
        # fill in what you prompted the user for here
        lib => [$lib_name],
        incpath => [split(/\s/,$incpath)],
        header =>
        [
            'libxml/c14n.h',
            'libxml/catalog.h',
            'libxml/entities.h',
            'libxml/globals.h',
            'libxml/HTMLparser.h',
            'libxml/HTMLtree.h',
            'libxml/parser.h',
            'libxml/parserInternals.h',
            'libxml/pattern.h',
            'libxml/relaxng.h',
            'libxml/tree.h',
            'libxml/uri.h',
            'libxml/valid.h',
            'libxml/xinclude.h',
            'libxml/xmlerror.h',
            'libxml/xmlIO.h',
            'libxml/xmlmemory.h',
            'libxml/xmlreader.h',
            'libxml/xmlregexp.h',
            'libxml/xmlschemas.h',
            'libxml/xmlversion.h',
            'libxml/xpath.h',
            'libxml/xpathInternals.h',
        ],
    );
}

sub _libxml_check_lib {
    my ($libname) = @_;

    if (defined($config_LIBS_alternatives)) {
        foreach my $conf_LIBS (@$config_LIBS_alternatives) {
            if (_libxml_check_lib_with_config_LIBs($libname, $conf_LIBS)) {
                $config{LIBS} = $conf_LIBS;
                return 1;
            }
        }
    }
    else {
        return _libxml_check_lib_with_config_LIBs($libname, $config{LIBS});
    }
}

print "Checking for ability to link against xml2...";
if ( _libxml_check_lib('xml2') ) {
    print "yes\n";
}
else {
    print "no\n";
    print "Checking for ability to link against libxml2...";
    if ( _libxml_check_lib('libxml2')) {
        print "yes\n";
    }
    else {
        print STDERR <<"DEATH";
libxml2, zlib, and/or the Math library (-lm) have not been found.
Try setting LIBS and INC values on the command line
Or get libxml2 from
  http://xmlsoft.org/
If you install via RPMs, make sure you also install the -devel
RPMs, as this is where the headers (.h files) are.

Also, you may try to run perl Makefile.PL with the DEBUG=1 parameter
to see the exact reason why the detection of libxml2 installation
failed or why Makefile.PL was not able to compile a test program.
DEATH
        exit 0; # 0 recommended by http://cpantest.grango.org (Notes for CPAN Authors)
    }
}

# -------------------------------------------------------------------------- #
# _NOW_ write the Makefile

WriteMakefile(
              %INFOS,
              %config,
);
# -------------------------------------------------------------------------- #


# -------------------------------------------------------------------------- #
# helper functions to build the Makefile
sub MY::manifypods {
    package MY;
    my $str = shift->SUPER::manifypods(@_);
#    warn $str;
#    $str =~ s/^manifypods : pure_all (.*)$/manifypods : pure_all docs $1/m;
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

sub MY::install {
   package MY;
   my $script = shift->SUPER::install(@_);
   unless ( $::skipsaxinstall ) {
     $script =~ s/install :: (.*)$/install :: $1 install_sax_driver/m;
     $script .= <<"INSTALL";

install_sax_driver :
\t-\@\$(PERL) -I\$(INSTALLSITELIB) -I\$(INSTALLSITEARCH) -MXML::SAX -e "XML::SAX->add_parser(q(XML::LibXML::SAX::Parser))->save_parsers()"
\t-\@\$(PERL) -I\$(INSTALLSITELIB) -I\$(INSTALLSITEARCH) -MXML::SAX -e "XML::SAX->add_parser(q(XML::LibXML::SAX))->save_parsers()"

INSTALL
   } else {
     warn "Note: 'make install' will skip XML::LibXML::SAX registration with XML::SAX!\n";
   }
   return $script;
}

sub MY::test {
   package MY;
   my $script = shift->SUPER::test(@_);
   if ( $::extralibdir ) {
      $script =~ s/(\$\(TEST_VERBOSE\),)/$1 \'$::extralibdir\',/m;
   }
   return $script;
}

# echo perl -pi~ -e '$$_=q($(version))."\n" if /#\ VERSION TEMPLATE/ ' $(TO_INST_PM)
sub MY::postamble {
    my $mpl_args = join " ", map qq["$_"], @ARGV;

    my $CC =
    (
        exists($ENV{CC})
            ? "CC = $ENV{CC}"
            : ''
    );

  my $ret = "$CC\n\n" . <<'MAKE_FRAG';

# used to update version numbers in all modules
version:
	@version=`grep '\# VERSION TEMPLATE' $(VERSION_FROM)`; \
	echo "New version line: $$version"; \
	perl -pi~ -e '$$_=q('"$$version"')."\n" if /#\ VERSION TEMPLATE/ ' $(TO_INST_PM);

runtest: pure_all
	perl -MFile::Spec -MTest::Run::CmdLine::Iface -e \
        "local @INC = @INC;	unshift @INC, map { File::Spec->rel2abs(\$$_) } ('$(INST_LIB)', '$(INST_ARCHLIB)'); Test::Run::CmdLine::Iface->new({test_files => [glob(q{t/*.t})]})->run();"

distruntest: distdir
	cd $(DISTVNAME) && $(ABSPERLRUN) Makefile.PL {#mpl_args#}
	cd $(DISTVNAME) && $(MAKE) $(PASTHRU)
	cd $(DISTVNAME) && $(MAKE) runtest $(PASTHRU)

MAKE_FRAG

    $ret =~ s/{#mpl_args#}/$mpl_args/;

    return $ret;
}


# -------------------------------------------------------------------------- #

# -------------------------------------------------------------------------- #
# Functions
#  - these should really be in MakeMaker... But &shrug;
# -------------------------------------------------------------------------- #

use Config;
use Cwd;
use Symbol;
use File::Spec;


BEGIN {
    $is_Win32 = ($^O =~ /Win32/);
    if ($is_Win32) {
        $DEVNULL = 'DEVNULL';
    }
    else {
        $DEVNULL = eval { File::Spec->devnull };
        if ($@) { $DEVNULL = '/dev/null' }
    }
}

sub rm_f {
    my @files = @_;
    my @realfiles;
    foreach (@files) {
        push @realfiles, glob($_);
    }
    if (@realfiles) {
        chmod(0777, @realfiles);
        unlink(@realfiles);
    }
}

sub rm_fr {
    my @files = @_;
    my @realfiles;
    foreach (@files) {
        push @realfiles, glob($_);
    }
    foreach my $file (@realfiles) {
        if (-d $file) {
            # warn("$file is a directory\n");
            rm_fr("$file/*");
            rm_fr("$file/.exists");
            rmdir($file) || die "Couldn't remove $file: $!";
        }
        else {
            # warn("removing $file\n");
            chmod(0777, $file);
            unlink($file);
        }
    }
}

sub xsystem {
    my $command_aref = shift;
    if ($DEBUG) {
        print "@$command_aref\n";
        if ((system { $command_aref->[0] } @$command_aref) != 0) {
            die "system call to '@$command_aref' failed";
        }
        return 1;
    }
    open(OLDOUT, ">&STDOUT");
    open(OLDERR, ">&STDERR");
    open(STDOUT, ">$DEVNULL");
    open(STDERR, ">$DEVNULL");
    my $retval = (system { $command_aref->[0] } @$command_aref);
    open(STDOUT, ">&OLDOUT");
    open(STDERR, ">&OLDERR");
    if ($retval != 0) {
        die "system call to '@$command_aref' failed";
    }
    return 1;
}

sub backtick {
    my $command = shift;
    if ($DEBUG) {
        print $command, "\n";
        my $results = `$command`;
        chomp $results;
        if ($? != 0) {
            die "backticks call to '$command' failed";
        }
        return $results;
    }
    open(OLDOUT, ">&STDOUT");
    open(OLDERR, ">&STDERR");
    open(STDOUT, ">$DEVNULL");
    open(STDERR, ">$DEVNULL");
    my $results = `$command`;
    my $retval = $?;
    open(STDOUT, ">&OLDOUT");
    open(STDERR, ">&OLDERR");
    if ($retval != 0) {
        die "backticks call to '$command' failed";
    }
    chomp $results;
    return $results;
}

sub try_link0 {
    my ($src, $opt) = @_;
    # local $config{LIBS};
    # $config{LIBS} .= $opt;
    unless (mkdir(".testlink", 0777)) {
        rm_fr(".testlink");
        mkdir(".testlink", 0777) || die "Cannot create .testlink dir: $!";
    }
    chdir(".testlink");
    {
        open(my $cfile, '>', 'Conftest.xs')
            or die "Cannot write to file Conftest.xs: $!";
        print {$cfile} <<"EOT";
#ifdef __cplusplus
extern "C" {
#endif
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>
#ifdef __cplusplus
}
#endif

EOT
        print {$cfile} $src;
        print {$cfile} <<"EOT";

MODULE = Conftest          PACKAGE = Conftest

PROTOTYPES: DISABLE

EOT
        close($cfile);
    }
    {
        open(my $cfile, '>', 'Conftest.pm')
            or die "Cannot write to file Conftest.pm: $!";
        print {$cfile} <<'EOT';
package Conftest;
$VERSION = 1.0;
require DynaLoader;
@ISA = ('DynaLoader');
bootstrap Conftest $VERSION;
1;
EOT
        close($cfile);
    }
    {
        open (my $cfile, '>', 'Makefile.PL')
            or die "Cannot write to file Makefile.PL: $!";
        print {$cfile} <<'EOT';
use ExtUtils::MakeMaker;
my %config;
while($_ = shift @ARGV) {
    my ($k, $v) = split /=/, $_, 2;
    warn("$k = $v\n");
    $config{$k} = $v;
}
WriteMakefile(NAME => "Conftest", VERSION_FROM => "Conftest.pm", %config);
EOT
        close($cfile);
    }
    {
        open(my $cfile, ">test.pl")
            or die "Cannot write to file test.pl: $!";
        print {$cfile} <<"EOT";
use Test; BEGIN { plan tests => 1; } END { ok(\$loaded) }
use Conftest; \$loaded++;
EOT
        close($cfile);
    }
    my $quote = $is_Win32 ? '"' : "'";
    xsystem([$^X, 'Makefile.PL',
        (map { "$_=$config{$_}" } keys %config),
        ]
    );

    my $def_opt = defined($opt) ? $opt : '';
    # I am not sure if OTHERLDFLAGS is really required - at least the
    # libraries to include do not belong here!
    # I would assume a user to set OTHERLDFLAGS in the %config if they are
    # really required. if done so, we don't have to pass them here ...
    xsystem([$Config{make}, 'test', "OTHERLDFLAGS=${def_opt}"]);
} # end try_link0

sub try_link {
    my $start_dir = cwd();
    my $result = eval {
        try_link0(@_);
    };
    warn $@ if $@;
    chdir($start_dir);
    rm_fr(".testlink");
    return $result;
}

# -------------------------------------------------------------------------- #
# try_libconfig class a generic config file and requests --version, --libs and
# --cflags
sub try_libconfig {
    my $cfgscript = shift;
    my $config = shift;
    my $bl = shift;

    my $state = undef; # there are three possible states:
                       # 1     : works
                       # 0     : works not
                       # undef : not yet tested

    my $ver = backtick("$cfgscript --version");
    if ( defined $ver ) {
        my ( $major, $minor, $point) = $ver =~ /([0-9]+).([0-9]+)\.([0-9]+)/g;
        foreach my $i ( @$bl ) {
            $state = $i->[3];
            last if $major <  $i->[0];
            next if $major >  $i->[0];
            last if $minor <  $i->[1];
            next if $minor >  $i->[1];
            last if $point <= $i->[2];
            $state = undef;
        }

        $config->{LIBS} = backtick("$cfgscript --libs");
        $config->{INC}  = backtick("$cfgscript --cflags");

        if ( defined $state and $state == 0 ) {
            print "failed\n";
            if ($FORCE) {
                die "FORCED $ver\n";
            }
            else {
              die "VERSION $ver\n";
            }
        }

        unless ( defined $state ) {
            print "untested\n";
            die "UNTESTED $ver\n";
        }

        print "ok ($ver)\n";
    }
    else {
        print "failed\n";
        die "FAILED\n"; # strange error
    }
}
# -------------------------------------------------------------------------- #
