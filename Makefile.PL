# $Id$

use ExtUtils::MakeMaker;
use Config;
use Symbol;
use File::Spec;

$|=0;

my %config;

while($_ = shift) {
    my ($key, $val) = split(/=/, $_, 2);
    $config{$key} = $val;
}

my $DEBUG = delete $config{DEBUG};

# get libs and inc from gnome-config
eval {
    print "running xml2-config... ";
    $config{LIBS} ||= backtick('xml2-config --libs');
    $config{INC} ||= backtick('xml2-config --cflags');
    print "ok\n";
};
if ($@) {
    print "failed\n";
    warn "*** ", $@ if $DEBUG;
    warn "using fallback values for LIBS and INC\n";
    # backtick fails if gnome-config didn't exist...
    $config{LIBS} = '-L/usr/local/lib -L/usr/lib -lxml2 -lz -lm';
    $config{INC} = '-I/usr/local/include -I/usr/include';
    
    print <<OPT;
options:
  LIBS='$config{LIBS}'
  INC='$config{INC}'
If this is wrong, Re-run as:
  \$ $^X Makefile.PL LIBS='-L/path/to/lib' INC='-I/path/to/include'

OPT

}

if ($config{LIBS} !~ /\-lxml2\b/) {
    $config{LIBS} .= ' -lxml2';
}

if ($config{LIBS} !~ /\-lz\b/) {
    $config{LIBS} .= ' -lz';
}

if ($config{LIBS} !~ /\-lm\b/) {
    $config{LIBS} .= ' -lm';
}

if (!have_library("xml2")) {
    die <<DEATH;
libxml2 not found
Try setting LIBS and INC values on the command line
Or get libxml2 from 
  http://www.libxml.org/
If you install via RPMs, make sure you also install the -devel
RPMs, as this is where the headers (.h files) are.
DEATH
}

print <<EOT;
If you are building XML::LibXML from CVS, you may wish to run

  \$ make docs

before doing anything else. This will re-build the documentation
from the XML file in examples/libxml.xml. This is *not* necessary
if you are building from a CPAN distribution.
EOT

WriteMakefile(
    'NAME'	=> 'XML::LibXML',
    'VERSION_FROM' => 'LibXML.pm', # finds $VERSION
    'AUTHOR'    => 'Matt Sergeant',
    'ABSTRACT'  => 'Interface to Gnome libxml2 xml parsing and DOM library',
    'OBJECT'    => '$(O_FILES)', # add the DOM extensions to libxml2
    'dist'      => { PREOP => "$^X -Iblib/arch -Iblib/lib example/xml2pod.pl" },
    %config,
);

sub MY::manifypods {
    package MY;
    my $str = shift->SUPER::manifypods(@_);
#    warn $str;
#    $str =~ s/^manifypods : pure_all (.*)$/manifypods : pure_all docs $1/m;
    $str .= <<EOF;

docs : pure_all
\t\@$^X -Iblib/arch -Iblib/lib example/xml2pod.pl example/libxml.xml lib
\t\@$^X -pi.old -e 's/a/a/' Makefile.PL
\t\@echo "==> YOU MUST NOW RE-RUN $^X Makefile.PL <=="
\t\@false

EOF
    return $str;
}

###################################################################
# Functions
#  - these should really be in MakeMaker... But &shrug;
###################################################################

use Cwd;

use vars qw/$DEVNULL $is_Win32/;

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
    my $command = shift;
    if ($DEBUG) {
        print $command, "\n";
        if (system($command) != 0) {
            die "system call to '$command' failed";
        }
        return 1;
    }
    open(OLDOUT, ">&STDOUT");
    open(OLDERR, ">&STDERR");
    open(STDOUT, ">$DEVNULL");
    open(STDERR, ">$DEVNULL");
    my $retval = system($command);
    open(STDOUT, ">&OLDOUT");
    open(STDERR, ">&OLDERR");
    if ($retval != 0) {
        die "system call to '$command' failed";
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
    my $cfile = gensym();
    mkdir(".testlink", 0777) || die "Cannot create .testlink dir: $!";
    chdir(".testlink");
    open($cfile, ">Conftest.xs") || die "Cannot write to file Conftest.xs: $!";
    print $cfile $src;
    close($cfile);
    open($cfile, ">Conftest.pm") || die "Cannot write to file Conftest.pm: $!";
    print $cfile <<EOT;
package Conftest;
$VERSION = 1.0;
require DynaLoader;
bootstrap Conftest $VERSION;
1;
EOT
    close($cfile);
    open($cfile, ">Makefile.PL") || die "Cannot write to file Makefile.PL: $!";
    print $cfile <<EOT;
use ExtUtils::MakeMaker;
WriteMakefile(NAME => "Conftest", VERSION_FROM => "Conftest.pm");
EOT
    close($cfile);
    xsystem("$^X Makefile.PL " . join(' ', map { "$_=$config{$_}" } keys %config));
    xsystem($Config{make});
}

sub try_link {
    my $start_dir = cwd();
    my $result = eval {
        try_link0(@_);
    };
    warn $@ if $DEBUG && $@;
    chdir($start_dir);
    rm_fr(".testlink");
    return $result;
}

sub have_library {
    my ($lib, $func) = (@_, "main");
    printf("checking for %s() in -l%s... ", $func, $lib);

    my $result;
    if ($func) {
        my $libs = $is_Win32 ? " $lib.lib  " : "-l$lib";
        if ($is_Win32) {
            $result = try_link(<<"SRC", $libs);
#include <windows.h>
#include <winsock.h>
int main() { return 0; }
int t() { ${func}(); return 0; }
SRC
            unless ($result) {
                $result = try_link(<<"SRC", $libs);
#include <windows.h>
#include <winsock.h>
int main() { return 0; }
int t() { void ((*p)()); p = (void ((*)()))${func}; return 0; }
SRC
            }
        }
        else {

            $result = try_link(<<"SRC", $libs);
int main() { return 0; }
int t() { ${func}(); return 0; }
SRC
        }
    }

    unless ($result) {
        print "no\n";
        return 0;
    }

    if ($func ne "main") {
        $config{DEFINE} .= uc(" -Dhave_$func");
    }

    print "yes\n";
    return 1;
}
