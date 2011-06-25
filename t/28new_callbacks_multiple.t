# $Id$

use strict;
use warnings;

package Counter;

use Test::More;

sub new
{
    my $class = shift;

    my $self = bless {}, $class;

    $self->_init(@_);

    return $self;
}

sub _counter
{
    my $self = shift;

    if (@_)
    {
        $self->{_counter} = shift;
    }

    return $self->{_counter};
}

sub _callback
{
    my $self = shift;

    if (@_)
    {
        $self->{_callback} = shift;
    }

    return $self->{_callback};
}

sub _increment
{
    my $self = shift;

    $self->_counter($self->_counter + 1);

    return;
}

sub _reset
{
    my $self = shift;

    $self->_counter(0);

    return;
}

sub _init
{
    my $self = shift;
    my $args = shift;

    $self->_reset;

    $self->_callback(
        $args->{gen_cb}->(
            sub {
                return $self->_increment();
            },
        ),
    );

    return;
}

sub test
{
    my ($self, $value, $blurb) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    is ($self->_counter(), $value, $blurb);

    $self->_reset;

    return;
}

sub cb
{
    my ($self) = @_;

    return sub {
        return $self->_callback()->();
    };
}

1;

package main;

# Should be 69
use Test::More tests => 69;

# TEST:$num_parsings=4;

use XML::LibXML;
use IO::File;

my $close_xml_counter = Counter->new(
    {
        gen_cb => sub {
            my $inc_cb = shift;
            return sub {
                my $dom   = shift;
                undef $dom;

                $inc_cb->();

                return 1;
            },
        }
    }
);

my $close_hash_count;
my $open_xml_count;
my (@match_file_urls, @match_xml_urls, @read_xml_rets, @match_hash2_urls);

# --------------------------------------------------------------------- #
# multiple tests
# --------------------------------------------------------------------- #
{
        my $string = <<EOF;
<x xmlns:xinclude="http://www.w3.org/2001/XInclude">
<xml>test
<xinclude:include href="/example/test2.xml"/>
<xinclude:include href="/libxml/test2.xml"/>
<xinclude:include href="/xmldom/test2.xml"/></xml>
</x>
EOF

        my $icb    = XML::LibXML::InputCallback->new();
        # TEST
        ok($icb, 'XML::LibXML::InputCallback was initialized');

        @match_file_urls = ();
        $icb->register_callbacks( [ \&match_file, \&open_file, 
                                    \&read_file, \&close_file ] );

        $icb->register_callbacks( [ \&match_hash, \&open_hash, 
                                    \&read_hash, \&close_hash ] );

        $close_hash_count = 0;
        $open_xml_count = 0;
        @match_xml_urls = ();
        @read_xml_rets = ();
        $icb->register_callbacks( [ \&match_xml, \&open_xml,
                                    \&read_xml, $close_xml_counter->cb] );


        my $parser = XML::LibXML->new();
        $parser->expand_xinclude(1);
        $parser->input_callbacks($icb);
        my $doc = $parser->parse_string($string); # read_xml called here twice

        # TEST
        is_deeply(
            \@read_xml_rets,
            [
                qq{<?xml version="1.0"?>\n<foo><tmp/>barbar</foo>\n},
                '',
            ],
            'read_xml() for multiple callbacks',
        );
        @read_xml_rets = ();
        # TEST
        is_deeply (
            \@match_xml_urls,
            [
                { verdict => 1, uri => '/xmldom/test2.xml', },
            ],
            'match_xml() one.',
        );
        @match_xml_urls = ();

        # TEST
        is_deeply (
            \@match_file_urls, 
            [
                { verdict => 1, uri => '/example/test2.xml',},
            ],
            'match_file() for multiple_tests',
        );
        @match_file_urls = ();

        # TEST
        is ($open_xml_count, 1, 'open_xml() : parse_string() successful.',); 
        $open_xml_count = 0;
        # TEST
        $close_xml_counter->test(1, "close_xml() called once.");
        # TEST
        is ($close_hash_count, 1, "close_hash() called once.");
        $close_hash_count = 0;

        # TEST
        ok ($doc, 'parse_string() returns a doc.');
        # TEST
        is ($doc->string_value(), 
            "\ntest\n..\nbar..\nbarbar\n",
            '->string_value()',
        );
}

{
        my $string = <<EOF;
<x xmlns:xinclude="http://www.w3.org/2001/XInclude">
<xml>test
<xinclude:include href="/example/test2.xml"/>
<xinclude:include href="/example/test3.xml"/></xml>
</x>
EOF

        my $icb    = XML::LibXML::InputCallback->new();

        @match_file_urls = ();
        $icb->register_callbacks( [ \&match_file, \&open_file, 
                                    \&read_file, \&close_file ] );

        @match_hash2_urls = ();
        $close_hash_count = 0;
        $icb->register_callbacks( [ \&match_hash2, \&open_hash, 
                                    \&read_hash, \&close_hash ] );


        my $parser = XML::LibXML->new();
        $parser->expand_xinclude(1);
        $parser->input_callbacks($icb);
        my $doc = $parser->parse_string($string);

        # TEST
        is_deeply (
            \@match_hash2_urls,
            [
                { verdict => 1, uri => '/example/test2.xml',},
                { verdict => 1, uri => '/example/test3.xml',},
            ],
            'match_hash2() input callbacks' ,
        );
        @match_hash2_urls = ();

        # TEST
        is_deeply (
            \@match_file_urls, 
            [
            ],
            'match_file() input callbacks' ,
        );
        @match_file_urls = ();

        # TEST
        is ($doc->string_value(), "\ntest\nbar..\nbar..\n",
            'string_value returns fine',);

        # TEST
        is ($close_hash_count, 2, 
            "close_hash() called twice on two xincludes."
        );
        $close_hash_count = 0;

        @match_hash2_urls = ();
        $icb->unregister_callbacks( [ \&match_hash2, \&open_hash, 
                                      \&read_hash, \&close_hash] );
        $doc = $parser->parse_string($string);

        # TEST
        is_deeply (
            \@match_hash2_urls,
            [
            ],
            'match_hash2() does not match after being unregistered.' ,
        );
        @match_hash2_urls = ();


        # TEST
        is($doc->string_value(), 
           "\ntest\n..\n\n         \n   \n",
           'string_value() after unregister callbacks', 
        );
}

{
        my $string = <<EOF;
<x xmlns:xinclude="http://www.w3.org/2001/XInclude">
<xml>test
<xinclude:include href="/example/test2.xml"/>
<xinclude:include href="/xmldom/test2.xml"/></xml>
</x>
EOF
        my $string2 = <<EOF;
<x xmlns:xinclude="http://www.w3.org/2001/XInclude">
<tmp/><xml>foo..<xinclude:include href="/example/test2.xml"/>bar</xml>
</x>
EOF


        my $icb = XML::LibXML::InputCallback->new();
        # TEST
        ok ($icb, 'XML::LibXML::InputCallback was initialized (No. 2)');

        my $open_xml2 = sub {
                my $uri = shift;
                my $parser = XML::LibXML->new;
                $parser->expand_xinclude(1);
                $parser->input_callbacks($icb);

                my $dom = $parser->parse_string($string2);
                # TEST
                ok ($dom, 'parse_string() inside open_xml2');
        
                return $dom;
        };

        @match_file_urls = ();
        @read_xml_rets = ();
        $icb->register_callbacks( [ \&match_xml, $open_xml2,
                                    \&read_xml, $close_xml_counter->cb ] );

        @match_hash2_urls = ();
        $close_hash_count = 0;
        $icb->register_callbacks( [ \&match_hash2, \&open_hash,
                                    \&read_hash, \&close_hash ] );

        my $parser = XML::LibXML->new();
        $parser->expand_xinclude(1);

        @match_file_urls = ();
        $parser->match_callback( \&match_file );
        $parser->open_callback( \&open_file );
        $parser->read_callback( \&read_file );
        $parser->close_callback( \&close_file );

        $parser->input_callbacks($icb);

        my $doc = $parser->parse_string($string);

        # TEST
        is_deeply (
            \@match_hash2_urls,
            [
                { verdict => 1, uri => '/example/test2.xml',},
            ],
            'match_hash2() input callbacks' ,
        );
        @match_hash2_urls = ();

        # TEST
        is_deeply(
            \@read_xml_rets,
            [
                qq{<?xml version="1.0"?>\n<x xmlns:xinclude="http://www.w3.org/2001/XInclude">\n<tmp/><xml>foo..<foo xml:base="/example/test2.xml">bar<xsl/>..</foo>bar</xml>\n</x>\n},
                '',
            ],
            'read_xml() No. 2',
        );
        @read_xml_rets = ();
        # TEST
        is_deeply (
            \@match_xml_urls,
            [
                { verdict => 1, uri => '/xmldom/test2.xml', },
            ],
            'match_xml() No. 2.',
        );
        @match_xml_urls = ();

        # TEST
        is_deeply (
            \@match_file_urls, 
            [
                { verdict => 1, uri => '/example/test2.xml',},
            ],
            'match_file() for inner callback.',
        );
        @match_file_urls = ();

        # TEST
        $close_xml_counter->test(1, "close_xml() called once.");

        # TEST
        is ($close_hash_count, 1, "close_hash() called once.");
        $close_hash_count = 0;

        # TEST
        is ($doc->string_value(), "\ntest\n..\n\nfoo..bar..bar\n\n",
            'string_value()',);
}


# --------------------------------------------------------------------- #
# CALLBACKS
# --------------------------------------------------------------------- #
# --------------------------------------------------------------------- #
# callback set 1 (perl file reader)
# --------------------------------------------------------------------- #
sub match_file {
    my $uri = shift;

    my $verdict = (( $uri =~ /^\/example\// ) ? 1 : 0);

    if ($verdict)
    {
        push @match_file_urls, { verdict => $verdict, uri => $uri };
    }

    return $verdict;
}

sub open_file {
        my $uri = shift;

        # TEST*$num_parsings
        ok( open (my $file, '<', ".$uri"), 'open file');

        return $file;
}

sub read_file {
        my $h   = shift;
        my $buflen = shift;
        my $rv   = undef;

        # TEST*8
        ok(1, 'read_file()');
        
        my $n = $h->read( $rv , $buflen );

        return $rv;
}


sub close_file {
        my $h   = shift;
        # TEST*$num_parsings
        ok(1, 'close_file()');
        $h->close();
        return 1;
}

# --------------------------------------------------------------------- #
# callback set 2 (perl hash reader)
# --------------------------------------------------------------------- #
sub match_hash {
        my $uri = shift;

        if ( $uri =~ /^\/libxml\// ){
            # TEST
            ok(1, 'URI starts with "/libxml"');
            return 1;
        }
        return;
}

sub open_hash {
        my $uri = shift;
        my $hash = { line => 0,
                     lines => [ "<foo>", "bar", "<xsl/>", "..", "</foo>" ],
                   };

        # TEST*$num_parsings
        ok (1, 'open_hash()');

        return $hash;
}

sub read_hash {
        my $h   = shift;
        my $buflen = shift;

        my $id = $h->{line};
        $h->{line} += 1;
        my $rv= $h->{lines}->[$id];

        $rv = "" unless defined $rv;

        # TEST*24
        ok(1, 'read_hash()',);
        return $rv;
}

sub close_hash {
        my $h   = shift;
        undef $h;

        $close_hash_count++;

        return 1;
}

# --------------------------------------------------------------------- #
# callback set 3 (perl hash reader)
# --------------------------------------------------------------------- #
sub match_hash2 {
    my $uri = shift;
    if ( $uri =~ /^\/example\// ){
        push @match_hash2_urls, { verdict => 1, uri => $uri, };
        return 1;
    }
    else {
        return 0;
    }
}

# --------------------------------------------------------------------- #
# callback set 4 (perl xml reader)
# --------------------------------------------------------------------- #
sub match_xml {
    my $uri = shift;
    if ( $uri =~ /^\/xmldom\// ){
        push @match_xml_urls, { verdict => 1, uri => $uri, };
        return 1;
    }
    else {
        return 0;
    }
}

sub open_xml {
        my $uri = shift;
        my $dom = XML::LibXML->new->parse_string(q{<?xml version="1.0"?><foo><tmp/>barbar</foo>});

        if ($dom)
        {
            $open_xml_count++;
        }

        return $dom;
}

sub read_xml {
        my $dom   = shift;
        my $buflen = shift;

        my $tmp = $dom->documentElement->findnodes('tmp')->shift;
        my $rv = $tmp ? $dom->toString : "";
        $tmp->unbindNode if($tmp);

        push @read_xml_rets, $rv;
        return $rv;
}

