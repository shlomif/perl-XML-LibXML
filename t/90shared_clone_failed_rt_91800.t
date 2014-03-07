use strict;
use warnings;

use Test::More;
use Config;

BEGIN
{
    my $will_run = 0;
    if ( $Config{useithreads} )
    {
        if ($ENV{THREAD_TEST})
        {
            require threads;
            require threads::shared;
            $will_run = 1;
        }
        else
        {
            plan skip_all => "optional (set THREAD_TEST=1 to run these tests)";
        }
    }
    else
    {
        plan skip_all => "no ithreads in this Perl";
    }

    if ($will_run)
    {
        plan tests => 3;
    }
}

use XML::LibXML qw(:threads_shared);

# TEST
ok(1, 'Loaded');

my $p = XML::LibXML->new();

# TEST
ok($p, 'Parser initted.');

{
    my $doc = $p->parse_string(qq{<root><foo id="1">bar</foo></root>});
    my $cloned = threads::shared::shared_clone($doc);

    # TEST
    ok(1,  "Shared clone");
}
