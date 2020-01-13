# -*- cperl -*-

use strict;
use warnings;

use Test::More tests => 4;

use XML::LibXML;

# Parser with default options should expand predefined entities.
{
    my $XML = <<'EOT';
<?xml version="1.0" encoding="UTF-8"?>
<EXAMPLE>&apos;&quot;&#38;</EXAMPLE>
EOT

    my $sys_line = <<'EOT';
<EXAMPLE>'"&amp;</EXAMPLE>
EOT

    chomp ($sys_line);

    my $parser = XML::LibXML->new();
    my $XML_DOC = $parser->load_xml( string => $XML);
    my $xml_string = $XML_DOC->toString();

    # TEST
    ok (scalar($xml_string =~ m{\Q$sys_line\E}),
        "predefined entities should be expanded by default"
    );
}


# Parser with default options should not expand internal entities
# (Note that billion laughs attack is tested for in t/35huge_mode.t)
{
    my $XML = <<'EOT';
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE EXAMPLE SYSTEM "example.dtd" [
<!ENTITY xml "Extensible Markup Language">
]>
<EXAMPLE>&xml;</EXAMPLE>
EOT

    my $sys_line = <<'EOT';
<EXAMPLE>&xml;</EXAMPLE>
EOT

    chomp ($sys_line);

    my $parser = XML::LibXML->new();
    my $XML_DOC = $parser->load_xml( string => $XML);
    my $xml_string = $XML_DOC->toString();

    # TEST
    ok (scalar($xml_string =~ m{\Q$sys_line\E}),
        "internal entities should not be expanded by default"
    );
}

# Parser with default options should not load external DTD
{
    my $XML = <<'EOT';
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE m PUBLIC "-//B/A/EN" "http://example.com">
<rss version="2.0">
<channel>
    <link>example.com</link>
    <description>DTD</description>
    <item>
        <title>DTD</title>
        <link>example.com</link>
        <description>Remote DTD</description>
    </item>
</channel>
</rss>
EOT

    my $parser = XML::LibXML->new();
    my $xml_string = eval {
        my $XML_DOC = $parser->load_xml( string => $XML );
        return $XML_DOC->toString();
    };

    # TEST
    ok (scalar(!$@ && $xml_string),
        "external DTD should not be loaded by default"
    );
}

# Parser with default options should not load external entities
{
    my $XML = <<'EOT';
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE title [ <!ELEMENT title ANY >
<!ENTITY xxe SYSTEM "file:///etc/nonexistent" >]>
<rss version="2.0">
<channel>
    <link>example.com</link>
    <description>XXE</description>
    <item>
        <title>&xxe;</title>
        <link>example.com</link>
        <description>XXE here</description>
    </item>
</channel>
</rss>
EOT

    my $sys_line = <<'EOT';
<title>&xxe;</title>
EOT

    chomp ($sys_line);

    my $parser = XML::LibXML->new();
    my $xml_string = eval {
        my $XML_DOC = $parser->load_xml( string => $XML );
        return $XML_DOC->toString();
    };

    # TEST
    ok (scalar(!$@ && $xml_string =~ m{\Q$sys_line\E}),
        "external entities should not be expanded by default"
    );
}

1;
