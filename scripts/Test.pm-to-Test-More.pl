#!/usr/bin/perl

use strict;
use warnings;

use PPI;

my $filename = shift(@ARGV);

my $doc = PPI::Document->new($filename);

my $statements = $doc->find('PPI::Statement');

if (! $statements)
{
    die "Could not find any statements.";
}

foreach my $stmt (@{$statements})
{
    if ($stmt->child(0)->isa('PPI::Token::Word')
        && ($stmt->child(0)->literal() eq "ok")
    )
    {
        print "$stmt\n";
        my $comment = PPI::Token::Comment->new;
        $comment->line(1);
        $comment->set_content ("# TEST\n");
        
        my $which_to_prepend = $stmt;
        my $prev = $stmt->previous_sibling;
        if ($prev->isa('PPI::Token::Whitespace'))
        {
            my $space = PPI::Token::Whitespace->new;
            $space->set_content($prev->content());
            $prev->insert_before($space);
            $prev->insert_before($comment);
        }
        else
        {
            $stmt->insert_before( $comment );
        }
    }
}

print "$doc";
