
use strict;
use warnings;

use lib './t/lib';

use Counter;
# $Id$

# Should be 20.
use Test::More tests => 20;

use XML::LibXML;
use IO::File;

# --------------------------------------------------------------------- #
# simple test
# --------------------------------------------------------------------- #
my $string = <<EOF;
<x xmlns:xinclude="http://www.w3.org/2001/XInclude"><xml>test<xinclude:include href="/example/test2.xml"/></xml></x>
EOF

my $icb    = XML::LibXML::InputCallback->new();
# TEST
ok($icb, ' TODO : Add test name');

my $match_file_counter = Counter->new(
    {
        gen_cb => sub {
            my $inc_cb = shift;

            sub {
                my $uri = shift;
                if ( $uri =~ /^\/example\// ){
                    $inc_cb->();
                    return 1;
                }
                return 0;     
            }
        }
    }
);

my $open_file_counter = Counter->new(
    {
        gen_cb => sub {
            my $inc_cb = shift;

            sub {
                my $uri = shift;
                open my $file, '<', ".$uri"
                    or die "Cannot open '.$uri'";
                $inc_cb->();
                return $file;
            }
        }
    }
);

$icb->register_callbacks( [ $match_file_counter->cb(), $open_file_counter->cb(),
                            \&read_file, \&close_file ] );

my $parser = XML::LibXML->new();
$parser->expand_xinclude(1);
$parser->input_callbacks($icb);
my $doc = $parser->parse_string($string);

# TEST
$match_file_counter->test(1, 'match_file matched once.');

# TEST
$open_file_counter->test(1, 'open_file called once.');

# TEST

ok($doc, ' TODO : Add test name');
# TEST

is($doc->string_value(),"test..", ' TODO : Add test name');

my $icb2    = XML::LibXML::InputCallback->new();
# TEST

ok($icb2, ' TODO : Add test name');

$icb2->register_callbacks( [ \&match_hash, \&open_hash, 
                             \&read_hash, \&close_hash ] );

$parser->input_callbacks($icb2);
$doc = $parser->parse_string($string);

# TEST

ok($doc, ' TODO : Add test name');
# TEST

is($doc->string_value(),"testbar..", ' TODO : Add test name');

# --------------------------------------------------------------------- #
# CALLBACKS
# --------------------------------------------------------------------- #
# --------------------------------------------------------------------- #
# callback set 1 (perl file reader)
# --------------------------------------------------------------------- #

sub open_file {
}

sub read_file {
        my $h   = shift;
        my $buflen = shift;
        my $rv   = undef;

        # TEST*2
        ok(1, 'read_file');
        
        my $n = $h->read( $rv , $buflen );

        return $rv;
}

sub close_file {
        my $h   = shift;
        # TEST
        ok(1, 'close_file');
        $h->close();
        return 1;
}

# --------------------------------------------------------------------- #
# callback set 2 (perl hash reader)
# --------------------------------------------------------------------- #
sub match_hash {
        my $uri = shift;
        if ( $uri =~ /^\/example\// ){
                # TEST
                ok(1, 'match_hash');
                return 1;
        }
}

sub open_hash {
        my $uri = shift;
        my $hash = { line => 0,
                     lines => [ "<foo>", "bar", "<xsl/>", "..", "</foo>" ],
                   };                
        # TEST
        ok(1, 'open_hash');

        return $hash;
}

sub read_hash {
        my $h   = shift;
        my $buflen = shift;

        my $id = $h->{line};
        $h->{line} += 1;
        my $rv= $h->{lines}->[$id];

        $rv = "" unless defined $rv;

        # TEST*6
        ok(1, 'read_hash');
        return $rv;
}

sub close_hash {
        my $h   = shift;
        undef $h;
        # TEST
        ok(1, 'close_hash');
}
