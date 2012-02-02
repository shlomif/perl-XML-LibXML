use strict;
use warnings;
use Test::More tests => 1;
use XML::LibXML;

my $is_destroyed;
BEGIN {
	no warnings 'once';
	*XML::LibXML::Element::DESTROY = sub {
		# warn sprintf("DESTROY %s", $_[0]->toString);
		$is_destroyed++;
	};
}

# Create element...
my $root = XML::LibXML->load_xml( IO => \*DATA )->documentElement;

# allow %hash to go out of scope quickly.
{
	my %hash = %$root;
	# assignment to ensure block is not optimized away
	$hash{foo} = 'phooey'; 
} 

# Destroy element...
undef($root);

# Touch the fieldhash...
my %other = %{ XML::LibXML->load_xml( string => '<foo/>' )->documentElement };

# TEST
ok $is_destroyed, "does not leak memory";

__DATA__
<root attr1="foo" xmlns:x="http://localhost/" x:attr2="bar" />
