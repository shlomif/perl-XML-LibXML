# -*- cperl -*-
# Test for GitHub issue #71:
# validation succeeds even though the DTD could not be loaded
#
# When validation(1) is set without explicitly setting load_ext_dtd(1),
# the document should still be validated (and fail if the DTD cannot be loaded).
# Previously, the C code in LibXML_init_parser() would strip out the
# XML_PARSE_DTDVALID flag if XML_PARSE_DTDLOAD was not set.

use strict;
use warnings;

use Test::More tests => 8;

use XML::LibXML;

# XML with a reference to a non-existent DTD
my $xml_with_missing_dtd = <<'EOF';
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE root SYSTEM "does-not-exist.dtd">
<root/>
EOF

# Test 1: validation(1) should automatically enable load_ext_dtd
{
    my $parser = XML::LibXML->new();
    $parser->validation(1);

    # TEST
    ok( $parser->validation() == 1,
        'validation should be true after being set to true' );

    # TEST
    ok( $parser->load_ext_dtd() == 1,
        'load_ext_dtd should be automatically enabled when validation is set to true' );
}

# Test 2: validation(1) via method call should cause parse failure on missing DTD
{
    my $parser = XML::LibXML->new();
    $parser->validation(1);

    # TEST
    ok( !eval { $parser->parse_string($xml_with_missing_dtd); 1 },
        'parse_string should die when validation is on and DTD is missing' );

    # TEST
    like( $@, qr/valid|DTD/i,
        'error message should mention validation or DTD' );
}

# Test 3: validation => 1 via constructor should cause parse failure on missing DTD
{
    my $parser = XML::LibXML->new( validation => 1 );

    # TEST
    ok( !eval { $parser->parse_string($xml_with_missing_dtd); 1 },
        'constructor validation => 1 should cause parse failure on missing DTD' );
}

# Test 4: complete_attributes(1) should also enable load_ext_dtd
{
    my $parser = XML::LibXML->new();
    $parser->complete_attributes(1);

    # TEST
    ok( $parser->complete_attributes() == 1,
        'complete_attributes should be true after being set to true' );

    # TEST
    ok( $parser->load_ext_dtd() == 1,
        'load_ext_dtd should be automatically enabled when complete_attributes is set to true' );
}

# Test 5: disabling validation should not disable load_ext_dtd if set independently
{
    my $parser = XML::LibXML->new();
    $parser->load_ext_dtd(1);
    $parser->validation(1);
    $parser->validation(0);

    # TEST
    ok( $parser->load_ext_dtd() == 1,
        'load_ext_dtd should remain true after validation is disabled if it was set independently' );
}
