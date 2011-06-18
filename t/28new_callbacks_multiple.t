# $Id$

use strict;
use warnings;

# Should be 76
use Test::More tests => 73;

# TEST:$num_parsings=4;

use XML::LibXML;
use IO::File;

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

        $icb->register_callbacks( [ \&match_file, \&open_file, 
                                    \&read_file, \&close_file ] );

        $icb->register_callbacks( [ \&match_hash, \&open_hash, 
                                    \&read_hash, \&close_hash ] );

        $icb->register_callbacks( [ \&match_xml, \&open_xml,
                                    \&read_xml, \&close_xml ] );


        my $parser = XML::LibXML->new();
        $parser->expand_xinclude(1);
        $parser->input_callbacks($icb);
        my $doc = $parser->parse_string($string);

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

        $icb->register_callbacks( [ \&match_file, \&open_file, 
                                    \&read_file, \&close_file ] );

        $icb->register_callbacks( [ \&match_hash2, \&open_hash, 
                                    \&read_hash, \&close_hash ] );


        my $parser = XML::LibXML->new();
        $parser->expand_xinclude(1);
        $parser->input_callbacks($icb);
        my $doc = $parser->parse_string($string);

        # TEST
        is ($doc->string_value(), "\ntest\nbar..\nbar..\n",
            'string_value returns fine',);

        $icb->unregister_callbacks( [ \&match_hash2, \&open_hash, 
                                      \&read_hash, \&close_hash] );
        $doc = $parser->parse_string($string);

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

        $icb->register_callbacks( [ \&match_xml, $open_xml2,
                                    \&read_xml, \&close_xml ] );

        $icb->register_callbacks( [ \&match_hash2, \&open_hash,
                                    \&read_hash, \&close_hash ] );

        my $parser = XML::LibXML->new();
        $parser->expand_xinclude(1);

        $parser->match_callback( \&match_file );
        $parser->open_callback( \&open_file );
        $parser->read_callback( \&read_file );
        $parser->close_callback( \&close_file );

        $parser->input_callbacks($icb);

        my $doc = $parser->parse_string($string);

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
        if ( $uri =~ /^\/example\// ){
            # TEST*$num_parsings
            ok(1, 'match_file()');
            return 1;
        }
        return 0;        
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

        # TEST*$num_parsings
        ok(1, 'close_hash()');
}

# --------------------------------------------------------------------- #
# callback set 3 (perl hash reader)
# --------------------------------------------------------------------- #
sub match_hash2 {
        my $uri = shift;
        if ( $uri =~ /^\/example\// ){

            # TEST*3
            ok(1, 'URI starts with "/example"');
            return 1;
        }
}

# --------------------------------------------------------------------- #
# callback set 4 (perl xml reader)
# --------------------------------------------------------------------- #
sub match_xml {
        my $uri = shift;
        if ( $uri =~ /^\/xmldom\// ){
            # TEST*2
            ok(1, 'URI starts with /xmldom in match_xml');
            return 1;
        }
}

sub open_xml {
        my $uri = shift;
        my $dom = XML::LibXML->new->parse_string(q{<?xml version="1.0"?><foo><tmp/>barbar</foo>});
        # TEST
        ok ($dom, 'open_xml() : parse_string() successful.', );

        return $dom;
}

sub read_xml {
        my $dom   = shift;
        my $buflen = shift;

        my $tmp = $dom->documentElement->findnodes('tmp')->shift;
        my $rv = $tmp ? $dom->toString : "";
        $tmp->unbindNode if($tmp);

        # TEST*$num_parsings
        ok (1, 'read_xml()',);
        return $rv;
}

sub close_xml {
        my $dom   = shift;
        undef $dom;

        # TEST*2
        ok(1, 'close_xml()');

        return 1;
}
