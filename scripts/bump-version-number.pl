#!/usr/bin/perl

use strict;
use warnings;

use File::Find::Object;
use IO::All;

my $tree = File::Find::Object->new({}, 'lib/');

my $version_n = shift(@ARGV);

if (!defined($version_n))
{
    die "Specify version number as an argument! bump-version-number.pl '0.0.1'";
}

sub process_file
{
    # The filename.
    my ($r) = @_;

    my @lines = io->file($r)->getlines();
    foreach (@lines)
    {
        s#(\$VERSION = "|^Version )\d+\.\d+(?:\.\d+)?("|)#$1 . $version_n . $2#e;
    }
    io->file($r)->print(
        @lines
    );
}

process_file('LibXML.pm');

while (my $r = $tree->next()) {
    if ($r =~ m{/\.(?:svn|hg|git)\z})
    {
        $tree->prune();
    }
    elsif ($r =~ m{\.pm\z})
    {
        process_file($r);
    }
}

