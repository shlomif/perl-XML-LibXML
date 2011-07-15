# $Id$

use strict;
use warnings;

use lib './t/lib';
use TestHelpers;
use Counter;
use Stacker;

# Should be 37.
use Test::More tests => 37;
use XML::LibXML;

my $using_globals = '';

my $open1_counter = Counter->new(
    {
        gen_cb => sub {
            my $inc_cb = shift;
            return sub {
                my $fn = shift;
                # warn("open: $f\n");

                if (open my $fh, '<', $fn)
                {
                    if (! ($using_globals xor defined($XML::LibXML::open_cb)))
                    {
                        $inc_cb->();
                    }
                    return $fh;
                }
                else
                {
                    return 0;
                }
            };
        },
    }
);

my $open2_counter = Counter->new(
    {
        gen_cb => sub {
            my $inc_cb = shift;
            return sub {
                my ($fn) = @_;
                # warn("open2: $_[0]\n");

                $fn =~ s/([^\d])(\.xml)$/${1}4$2/; # use a different file
                my ($ret, $verdict);
                if ($verdict = open (my $file, '<', $fn))
                {
                    $ret = $file;
                }
                else
                {
                    $ret = 0;
                }

                $inc_cb->();

                return $ret;
            };
        },
    }
);

{
    # first test checks if local callbacks work
    my $parser = XML::LibXML->new();
    # TEST
    ok($parser, 'Parser was initted.');

    $parser->match_callback( \&match1 );
    $parser->read_callback( \&read1 );
    $parser->open_callback( $open1_counter->cb() );
    $parser->close_callback( \&close1 );

    $parser->expand_xinclude( 1 );

    my $dom = $parser->parse_file("example/test.xml");

    # TEST
    $open1_counter->test(2, 'expand_include open1 worked.');

    # TEST
    ok($dom, 'DOM was returned.');
    # warn $dom->toString();

    my $root = $dom->getDocumentElement();

    my @nodes = $root->findnodes( 'xml/xsl' );
    # TEST
    ok( scalar(@nodes), 'Found nodes.' );
}

{
    # test per parser callbacks. These tests must not fail!
    
    my $parser = XML::LibXML->new();
    my $parser2 = XML::LibXML->new();

    # TEST
    ok($parser, '$parser was init.');
    # TEST
    ok($parser2, '$parser2 was init.');

    $parser->match_callback( \&match1 );
    $parser->read_callback( \&read1 );
    $parser->open_callback( $open1_counter->cb() );
    $parser->close_callback( \&close1 );

    $parser->expand_xinclude( 1 );

    $parser2->match_callback( \&match2 );
    $parser2->read_callback( \&read2 );
    $parser2->open_callback( $open2_counter->cb() );
    $parser2->close_callback( \&close2 );

    $parser2->expand_xinclude( 1 );
   
    my $dom1 = $parser->parse_file( "example/test.xml");
    my $dom2 = $parser2->parse_file("example/test.xml");

    # TEST
    $open1_counter->test(2, 'expand_include for $parser out of ($parser,$parser2)');
    # TEST
    $open2_counter->test(2, 'expand_include for $parser2 out of ($parser,$parser2)');
    # TEST
    ok($dom1, '$dom1 was returned');
    # TEST
    ok($dom2, '$dom2 was returned');

    my $val1  = ( $dom1->findnodes( "/x/xml/text()") )[0]->string_value();
    my $val2  = ( $dom2->findnodes( "/x/xml/text()") )[0]->string_value();

    $val1 =~ s/^\s*|\s*$//g;
    $val2 =~ s/^\s*|\s*$//g;

    # TEST

    is( $val1, "test", ' TODO : Add test name' );
    # TEST
    is( $val2, "test 4", ' TODO : Add test name' );
}

chdir("example/complex") || die "chdir: $!";

my $str = slurp('complex.xml');

{
    # tests if callbacks are called correctly within DTDs
    my $parser2 = XML::LibXML->new();
    $parser2->expand_xinclude( 1 );
    my $dom = $parser2->parse_string($str);
    # TEST
    ok($dom, '$dom was init.');
}



$using_globals = 1;
$XML::LibXML::match_cb = \&match1;
$XML::LibXML::open_cb  = $open1_counter->cb();
$XML::LibXML::read_cb  = \&read1;
$XML::LibXML::close_cb = \&close1;

{
    # tests if global callbacks are working
    my $parser = XML::LibXML->new();
    # TEST
    ok($parser, '$parser was init');

    # TEST
    ok($parser->parse_string($str), 'parse_string returns a true value.');

    # TEST
    $open1_counter->test(3, 'open1 for global counter.');
    # warn $dom->toString() , "\n";
}


sub match1 {
    # warn "match: $_[0]\n";
    # TEST*7
    is($using_globals, defined($XML::LibXML::match_cb), 'match1');
    return 1;
}

sub close1 {
    # warn "close $_[0]\n";
    # TEST*7
    is($using_globals, defined($XML::LibXML::close_cb), 'close1');
    if ( $_[0] ) {
        $_[0]->close();
    }
    return 1;
}

sub read1 {
    # warn "read!";
    my $rv = undef;
    my $n = 0;
    if ( $_[0] ) {
        $n = $_[0]->read( $rv , $_[1] );
        # TEST*7
        is($using_globals, defined($XML::LibXML::read_cb), 'read1') if $n > 0
    }
    return $rv;
}

sub match2 {
    # warn "match2: $_[0]\n";
    return 1;
}

sub close2 {
    # warn "close2 $_[0]\n";
    if ( $_[0] ) {
        $_[0]->close();
    }
    return 1;
}

sub read2 {
    # warn "read2!";
    my $rv = undef;
    my $n = 0;
    if ( $_[0] ) {
        $n = $_[0]->read( $rv , $_[1] );
        # warn "read!" if $n > 0;
    }
    return $rv;
}

