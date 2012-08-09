#!/usr/bin/perl

use strict;
use warnings;

use File::Slurp qw(:edit);

if (system("$^X", "Makefile.PL"))
{
    die "Cannot run 'Makefile.PL' - $!";
}

edit_file_lines(
    sub { $_ = '' if m/\$\(OBJECT\).*:.*\$\(FIRST_MAKEFILE\)/ },
'Makefile'
);
