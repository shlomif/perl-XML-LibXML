package TestHelpers;

use strict;
use warnings;

our @EXPORT = (qw(slurp utf8_slurp));

use base 'Exporter';

sub slurp
{
    my $filename = shift;

    open my $in, "<", $filename
        or die "Cannot open '$filename' for slurping - $!";

    local $/;
    my $contents = <$in>;

    close($in);

    return $contents;
}

sub utf8_slurp
{
    my $filename = shift;

    open my $in, '<', $filename
        or die "Cannot open '$filename' for slurping - $!";

    binmode $in, ':utf8';

    local $/;
    my $contents = <$in>;

    close($in);

    return $contents;
}


1;
