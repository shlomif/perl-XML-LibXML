# $Id$

package XML::LibXML::SAX::Generator;

sub new {
    my $class = shift;
    unshift @_, 'Handler' unless @_ != 1;
    my %p = @_;
    return bless \%p, $class;
}

sub generate {
    my $self = shift;
    my ($node) = @_;
    
    
}

1;

__END__

