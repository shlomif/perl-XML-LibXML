#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 1;

use lib './t/lib';
use TestHelpers;

BEGIN {
    $XML::SAX::ParserPackage = "XML::LibXML::SAX";
}

use XML::SAX::ParserFactory;

my @got_warnings;
local $SIG{__WARN__} = sub {
    my ($warning) = @_;

    if ($warning =~ /\AUse of uninitialized value/)
    {
        push @got_warnings, $warning;
    }
};

my $metadataHandler = innerSAX->new();
my $oaiHandler = outerSAX->new(metadataHandler => $metadataHandler,
    oaiNS => "http://www.openarchives.org/OAI/2.0/");

my $parser = XML::SAX::ParserFactory->parser(Handler => $oaiHandler);

$parser->parse_string(<<'END_OF_XML');
<?xml version="1.0" encoding="UTF-8"?>
<OAI-PMH xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd" xmlns="http://www.openarchives.org/OAI/2.0/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><responseDate>2013-12-16T20:19:20Z</responseDate><request metadataPrefix="RDFxml" verb="GetRecord" identifier="oai:dnb.de/authorities/1045601462">http://services.d-nb.de/oai/repository</request><GetRecord xsi:schemaLocation="http://www.w3.org/1999/02/22-rdf-syntax-ns http://www.w3.org/2000/07/rdf.xsd"><record><header><identifier>oai:dnb.de/authorities/1045601462</identifier><datestamp>2013-12-16T18:47:23Z</datestamp><setSpec>authorities</setSpec></header><metadata><rdf:RDF xmlns:gnd="http://d-nb.info/standards/elementset/gnd#" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:rda="http://rdvocab.info/" xmlns:foaf="http://xmlns.com/foaf/0.1/" xmlns:isbd="http://iflastandards.info/ns/isbd/elements/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:rdfs="http://www.w3.org/2000/01/rdf-schema#" xmlns:marcRole="http://id.loc.gov/vocabulary/relators/" xmlns:lib="http://purl.org/library/" xmlns:umbel="http://umbel.org/umbel#" xmlns:bibo="http://purl.org/ontology/bibo/" xmlns:owl="http://www.w3.org/2002/07/owl#" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:skos="http://www.w3.org/2004/02/skos/core#">

	<rdf:Description rdf:about="http://d-nb.info/gnd/1045601462">
		<rdf:type rdf:resource="http://d-nb.info/standards/elementset/gnd#DifferentiatedPerson"/>
		<gnd:gndIdentifier>1045601462</gnd:gndIdentifier>
		<gnd:preferredNameForThePerson>Kencena, Rain</gnd:preferredNameForThePerson>
		<gnd:preferredNameEntityForThePerson rdf:parseType="Resource">
			<gnd:forename>Rain</gnd:forename>
			<gnd:surname>Kencena</gnd:surname>
		</gnd:preferredNameEntityForThePerson>
		<gnd:professionOrOccupation rdf:resource="http://d-nb.info/gnd/4281949-0"/>
		<gnd:geographicAreaCode rdf:resource="http://d-nb.info/standards/vocab/gnd/geographic-area-code#XB-TR"/>
		<gnd:dateOfBirthAndDeath>ca. 20. / 21. Jh.</gnd:dateOfBirthAndDeath>
		<gnd:gender rdf:resource="http://d-nb.info/standards/vocab/gnd/Gender#notKnown"/>
	</rdf:Description>
</rdf:RDF></metadata></record></GetRecord></OAI-PMH>
END_OF_XML

eq_or_diff(
    \@got_warnings,
    [],
    "No warnings were generated.",
);


package outerSAX;
use parent qw(XML::SAX::Base);

sub new {
    my ($class, %opts) = @_;
    my $self = bless \%opts, ref($class) || $class;
    $self->set_handler( undef );
    return $self;
}

sub start_element {
    my ($self, $element) = @_;

    return $self->SUPER::start_element($element) unless $element->{NamespaceURI} eq $self->{oaiNS};

    if ( $element->{LocalName} eq 'metadata' ) {
        $self->{ OLD_Handler } = $self->get_handler();
        $self->set_handler( $self->{metadataHandler} );
    }
    else {
        return $self->SUPER::start_element($element)};
}

sub end_element {
    my ($self, $element) = @_;

    return $self->SUPER::end_element($element) unless $element->{NamespaceURI} eq $self->{oaiNS};

    if ( $element->{LocalName} eq 'metadata' ) {
        $self->set_handler( $self->{OLD_Handler} );
    }
    else {
        $self->SUPER::end_element($element);
    }
}


package innerSAX;
use parent qw(XML::SAX::Base);
use XML::LibXML::SAX::Builder;

sub new {
    my ($class, %opts) = @_;
    my $self = bless \%opts, ref($class) || $class;
    $self->{'tagStack'} = [];
    return $self;
}

sub start_element {
    my ($self, $element) = @_;

    unless ( $self->{'tagStack'}[0] ) {
        my $builder = XML::LibXML::SAX::Builder->new()
            or die "cannot instantiate SAX builder";
        $self->set_handler($builder);
        $self->SUPER::start_document(); # i.e. $builder->start_document();
        # DEBUG ME: warnings occur here
        $self->SUPER::start_element($element);
    }
    else {
        $self->SUPER::start_element($element)};

    push(@{$self->{'tagStack'}}, $element->{Name});
}

sub end_element {
    my ($self, $element) = @_;
    $self->SUPER::end_element($element);
    pop (@{$self->{'tagStack'}});

    unless ( $self->{'tagStack'}[0] ) {
        my $hdl = $self->get_handler();
        $self->set_handler(undef);

        # Convert fragment to document, do something with it
        # (in real life: XSLT)
        my $fragment = $hdl->done();
        my $child = $fragment->firstChild();
        while ($child && $child->nodeName eq "#text")
        {
            $child = $child->nextSibling;
        }
        my $tempdoc = XML::LibXML::Document->createDocument()
            or die "cannot create new Document";
        $tempdoc->addChild($child)
            or die "cannot addChild";
        # Removing because it was converted into a test script.
        # print $tempdoc->toString;
    }
}

1;

