# $Id$

use ExtUtils::MakeMaker;
use Config;
use Symbol;

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

my $LINK = "$Config{ld} -o conftest $Config{ccflags} -I$Config{incpath} %s $Config{lddlflags} $Config{ldflags} conftest.c $Config{libs} %s %s";

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

# have_library("xml2", "ghttp_get_header_names");

WriteMakefile(
    'NAME'	=> 'XML::LibXML',
    'VERSION_FROM' => 'LibXML.pm', # finds $VERSION
    'AUTHOR'    => 'Matt Sergeant',
    'ABSTRACT'  => 'Interface to Gnome libxml2 xml parsing and DOM library',
    'OBJECT'    => '$(O_FILES)', # add the DOM extensions to libxml2
    %config,
);

###################################################################
# Functions
#  - these should really be in MakeMaker... But &shrug;
###################################################################

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
    open(STDOUT, ">/dev/null");
    open(STDERR, ">/dev/null");
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
    open(STDOUT, ">/dev/null");
    open(STDERR, ">/dev/null");
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
    open($cfile, ">conftest.c") || die "Cannot write to file conftest.c";
    print $cfile $src;
    close($cfile);
    xsystem(sprintf($LINK, $config{INC}, $config{LIBS}, $opt));
}

sub try_link {
    my $result = eval {
        try_link0(@_);
    };
    my $err = $@;
    rm_f("conftest*");
    if ($err) {
        die $err;
    }
    return $result;
}

sub have_library {
    my ($lib, $func) = (@_, "main");
    printf("checking for %s() in -l%s... ", $func, $lib);
    
    my $result;
    if ($func) {
        my $libs = "-l$lib";
        eval {
        $result = try_link(<<"SRC", $libs);
int main() { return 0; }
int t() { ${func}(); return 0; }
SRC
        };
        if ($@) {
            warn $@ if $DEBUG;
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
