# $Id$
use Test;
BEGIN { plan tests => 70 }
END { ok(0) unless $loaded }
use XML::LibXML;
use IO::File;
$loaded = 1;
ok(1);

# --------------------------------------------------------------------- #
# multiple tests
# --------------------------------------------------------------------- #
{
        my $string = <<EOF;
<x xmlns:xinclude="http://www.w3.org/2001/XInclude">
<xml>test
<xinclude:include href="/example/test2.xml"/>
<xinclude:include href="/libxml/test2.xml"/></xml>
</x>
EOF

        my $icb    = XML::LibXML::InputCallback->new();
        ok($icb);

        $icb->register_callbacks( [ \&match_file, \&open_file, 
                                    \&read_file, \&close_file ] );

        $icb->register_callbacks( [ \&match_hash, \&open_hash, 
                                    \&read_hash, \&close_hash ] );


        my $parser = XML::LibXML->new();
        $parser->expand_xinclude(1);
        $parser->input_callbacks($icb);
        my $doc = $parser->parse_string($string);

        ok($doc);
        ok($doc->string_value(), "\ntest\n..\nbar..\n");
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
        my $doc2 = $parser->parse_string($string);

        ok($doc);
        ok($doc->string_value(), "\ntest\nbar..\nbar..\n");
        ok($doc2);
        ok($doc2->string_value(), "\ntest\nbar..\nbar..\n");
        print $doc->serialize();

        $icb->unregister_callbacks( [ \&match_hash2, \&open_hash, 
                                      \&read_hash, \&close_hash] );
        $doc = $parser->parse_string($string);

        ok($doc);
        ok($doc->string_value(), "\ntest\n..\n\n         \n   \n");
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
                ok(1);
                return 1;
        }
        return 0;        
}

sub open_file {
        my $uri = shift;
        $file = new IO::File;

        if ( $file->open( "< .$uri" ) ){
                ok(1);
        }
        else {
                # warn "cannot open file";
                $file = 0;
        }   
        return $file;
}

sub read_file {
        my $h   = shift;
        my $buflen = shift;
        my $rv   = undef;

        ok(1);
        
        my $n = $h->read( $rv , $buflen );

        return $rv;
}

sub close_file {
        my $h   = shift;
        ok(1);
        $h->close();
        return 1;
}

# --------------------------------------------------------------------- #
# callback set 2 (perl hash reader)
# --------------------------------------------------------------------- #
sub match_hash {
        my $uri = shift;
        if ( $uri =~ /^\/libxml\// ){
                ok(1);
                return 1;
        }
}

sub open_hash {
        my $uri = shift;
        my $hash = { line => 0,
                     lines => [ "<foo>", "bar", "<xsl/>", "..", "</foo>" ],
                   };                
        ok(1);

        return $hash;
}

sub read_hash {
        my $h   = shift;
        my $buflen = shift;

        my $id = $h->{line};
        $h->{line} += 1;
        my $rv= $h->{lines}->[$id];

        $rv = "" unless defined $rv;

        ok(1);
        return $rv;
}

sub close_hash {
        my $h   = shift;
        undef $h;
        ok(1);
}

# --------------------------------------------------------------------- #
# callback set 3 (perl hash reader)
# --------------------------------------------------------------------- #
sub match_hash2 {
        my $uri = shift;
        if ( $uri =~ /^\/example\// ){
                ok(1);
                return 1;
        }
}
