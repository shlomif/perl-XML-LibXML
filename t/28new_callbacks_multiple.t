# $Id$

use strict;
use warnings;

package Collector;

sub new
{
    my $class = shift;

    my $self = bless {}, $class;

    $self->_init(@_);

    return $self;
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

sub _returned_cb
{
    my $self = shift;

    if (@_)
    {
        $self->{_returned_cb} = shift;
    }

    return $self->{_returned_cb};
}

sub _init_returned_cb
{
    my $self = shift;

    $self->_returned_cb(
        sub {
            return $self->_callback()->(@_);
        }
    );

    return;
}

sub cb
{
    return shift->_returned_cb();
}

package Counter;

our @ISA = qw(Collector);

use Test::More;
sub _counter
{
    my $self = shift;

    if (@_)
    {
        $self->{_counter} = shift;
    }

    return $self->{_counter};
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

    $self->_init_returned_cb;

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

1;

package Stacker;

our @ISA = qw(Collector);

use Test::More;

sub _stack
{
    my $self = shift;

    if (@_)
    {
        $self->{_stack} = shift;
    }

    return $self->{_stack};
}

sub _push
{
    my $self = shift;
    my $item = shift;

    push @{$self->_stack()}, $item;

    return;
}

sub _reset
{
    my $self = shift;

    $self->_stack([]);

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
                my $item = shift;

                return $self->_push($item);
            },
        ),
    );

    $self->_init_returned_cb;

    return;
}

sub test
{
    my ($self, $value, $blurb) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    is_deeply ($self->_stack(), $value, $blurb);

    $self->_reset;

    return;
}
1;

package main;

# Should be 68
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
            };
        }
    }
);

my $open_xml_counter = Counter->new(
    {
        gen_cb => sub {
            my $inc_cb = shift;

            return sub {
                my $uri = shift;
                my $dom = XML::LibXML->new->parse_string(q{<?xml version="1.0"?><foo><tmp/>barbar</foo>});

                if ($dom)
                {
                    $inc_cb->();
                }

                return $dom;
            };
        },
    }
);

my $close_hash_counter = Counter->new(
    {
        gen_cb => sub {
            my $inc_cb = shift;
            return sub {
                my $h   = shift;
                undef $h;

                $inc_cb->();

                return 1;
            };
        }
    }
);

my $open_hash_counter = Counter->new(
    {
        gen_cb => sub {
            my $inc_cb = shift;
            return sub {
                my $uri = shift;
                my $hash = { line => 0,
                    lines => [ "<foo>", "bar", "<xsl/>", "..", "</foo>" ],
                };

                $inc_cb->();

                return $hash;
            };
        }
    }
);

my $match_hash_stacker = Stacker->new(
    {
        gen_cb => sub {
            my $push_cb = shift;
            return sub {
                my $uri = shift;

                if ( $uri =~ /^\/libxml\// ){
                    $push_cb->({ verdict => 1, uri => $uri, });
                    return 1;
                }
                else {
                    return;
                }
            };
        },
    }
);

my $match_file_stacker = Stacker->new(
    {
        gen_cb => sub {
            my $push_cb = shift;
            return sub {
                my $uri = shift;

                my $verdict = (( $uri =~ /^\/example\// ) ? 1 : 0);
                if ($verdict)
                {
                    $push_cb->({ verdict => $verdict, uri => $uri, });
                }

                return $verdict;
            };
        },
    }
);

my $match_hash2_stacker = Stacker->new(
    {
        gen_cb => sub {
            my $push_cb = shift;
            return sub {        
                my $uri = shift;
                if ( $uri =~ /^\/example\// ){
                    $push_cb->({ verdict => 1, uri => $uri, });
                    return 1;
                }
                else {
                    return 0;
                }
            };
        },
    }
);

my $match_xml_stacker = Stacker->new(
    {
        gen_cb => sub {
            my $push_cb = shift;
            return sub {        
                my $uri = shift;
                if ( $uri =~ /^\/xmldom\// ){
                    $push_cb->({ verdict => 1, uri => $uri, });
                    return 1;
                }
                else {
                    return 0;
                }
            };
        },
    }
);

my $read_xml_stacker = Stacker->new(
    {
        gen_cb => sub {
            my $push_cb = shift;
            return sub {        
                my $dom   = shift;
                my $buflen = shift;

                my $tmp = $dom->documentElement->findnodes('tmp')->shift;
                my $rv = $tmp ? $dom->toString : "";
                $tmp->unbindNode if($tmp);

                $push_cb->($rv);

                return $rv;
            };
        },
    }
);

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

        $icb->register_callbacks( [ $match_file_stacker->cb, \&open_file, 
                                    \&read_file, \&close_file ] );

        $icb->register_callbacks( [ $match_hash_stacker->cb, $open_hash_counter->cb,
                                    \&read_hash, $close_hash_counter->cb ] );

        $icb->register_callbacks( [ $match_xml_stacker->cb, $open_xml_counter->cb,
                                    $read_xml_stacker->cb, $close_xml_counter->cb] );


        my $parser = XML::LibXML->new();
        $parser->expand_xinclude(1);
        $parser->input_callbacks($icb);
        my $doc = $parser->parse_string($string); # read_xml called here twice

        # TEST
        $match_hash_stacker->test(
            [
                { verdict => 1, uri => '/libxml/test2.xml',},
            ],
            'match_hash() for URLs.',
        );

        # TEST
        $read_xml_stacker->test(
            [
                qq{<?xml version="1.0"?>\n<foo><tmp/>barbar</foo>\n},
                '',
            ],
            'read_xml() for multiple callbacks',
        );
        # TEST
        $match_xml_stacker->test(
            [
                { verdict => 1, uri => '/xmldom/test2.xml', },
            ],
            'match_xml() one.',
        );

        # TEST
        $match_file_stacker->test(
            [
                { verdict => 1, uri => '/example/test2.xml',},
            ],
            'match_file() for multiple_tests',
        );

        # TEST
        $open_hash_counter->test(1, 'open_hash() : called 1 times');
        # TEST
        $open_xml_counter->test(1, 'open_xml() : parse_string() successful.',); 
        # TEST
        $close_xml_counter->test(1, "close_xml() called once.");
        # TEST
        $close_hash_counter->test(1, "close_hash() called once.");

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

        $icb->register_callbacks( [ $match_file_stacker->cb, \&open_file, 
                                    \&read_file, \&close_file ] );

        $icb->register_callbacks( [ $match_hash2_stacker->cb, $open_hash_counter->cb,
                                    \&read_hash, $close_hash_counter->cb() ] );


        my $parser = XML::LibXML->new();
        $parser->expand_xinclude(1);
        $parser->input_callbacks($icb);
        my $doc = $parser->parse_string($string);

        # TEST
        $match_hash2_stacker->test(
            [
                { verdict => 1, uri => '/example/test2.xml',},
                { verdict => 1, uri => '/example/test3.xml',},
            ],
            'match_hash2() input callbacks' ,
        );

        # TEST
        $match_file_stacker->test(
            [
            ],
            'match_file() input callbacks' ,
        );

        # TEST
        is ($doc->string_value(), "\ntest\nbar..\nbar..\n",
            'string_value returns fine',);

        # TEST
        $open_hash_counter->test(2, 'open_hash() : called 2 times');
        # TEST
        $close_hash_counter->test(
            2, "close_hash() called twice on two xincludes."
        );

        $icb->unregister_callbacks( [ $match_hash2_stacker->cb, \&open_hash, 
                                      \&read_hash, $close_hash_counter->cb] );
        $doc = $parser->parse_string($string);

        # TEST
        $match_hash2_stacker->test(
            [
            ],
            'match_hash2() does not match after being unregistered.' ,
        );

        # TEST
        $match_file_stacker->test(
            [
                { verdict => 1, uri => '/example/test2.xml',},
                { verdict => 1, uri => '/example/test3.xml',},
            ],
            'match_file() input callbacks' ,
        );


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

        $icb->register_callbacks( [ $match_xml_stacker->cb, $open_xml2,
                                    $read_xml_stacker->cb, $close_xml_counter->cb ] );

        $icb->register_callbacks( [ $match_hash2_stacker->cb, $open_hash_counter->cb,
                                    \&read_hash, $close_hash_counter->cb ] );

        my $parser = XML::LibXML->new();
        $parser->expand_xinclude(1);

        $parser->match_callback( $match_file_stacker->cb );
        $parser->open_callback( \&open_file );
        $parser->read_callback( \&read_file );
        $parser->close_callback( \&close_file );

        $parser->input_callbacks($icb);

        my $doc = $parser->parse_string($string);

        # TEST
        $match_hash2_stacker->test(
            [
                { verdict => 1, uri => '/example/test2.xml',},
            ],
            'match_hash2() input callbacks' ,
        );

        # TEST
        $read_xml_stacker->test(
            [
                qq{<?xml version="1.0"?>\n<x xmlns:xinclude="http://www.w3.org/2001/XInclude">\n<tmp/><xml>foo..<foo xml:base="/example/test2.xml">bar<xsl/>..</foo>bar</xml>\n</x>\n},
                '',
            ],
            'read_xml() No. 2',
        );
        # TEST
        $match_xml_stacker->test(
            [
                { verdict => 1, uri => '/xmldom/test2.xml', },
            ],
            'match_xml() No. 2.',
        );

        # TEST
        $match_file_stacker->test(
            [
                { verdict => 1, uri => '/example/test2.xml',},
            ],
            'match_file() for inner callback.',
        );

        # TEST
        $open_hash_counter->test(1, 'open_hash() : called 1 times');

        # TEST
        $close_xml_counter->test(1, "close_xml() called once.");

        # TEST
        $close_hash_counter->test(1, "close_hash() called once.");

        # TEST
        is ($doc->string_value(), "\ntest\n..\n\nfoo..bar..bar\n\n",
            'string_value()',);
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

