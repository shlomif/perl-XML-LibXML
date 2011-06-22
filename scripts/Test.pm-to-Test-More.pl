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

sub is_comma
{
    my $node = shift;
    return  $node->isa('PPI::Token::Operator') && ($node->content() eq ",");
}

foreach my $stmt (@{$statements})
{
    my $call = $stmt->child(0);
    if ($call->isa('PPI::Token::Word')
        && ($call->literal() eq "ok")
    )
    {
        # print "$stmt\n";
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

        my $args = $stmt->find_first('PPI::Structure::List')->find_first('PPI::Statement::Expression');

        my $num_childs = scalar (() = $args->children());

        my $num_args = 1 + scalar (() = grep { is_comma($_) } $args->children());

        my $last_child = $args->child($num_childs - 1);
        if (is_comma($last_child) 
                ||
            (
                $last_child->isa('PPI::Token::Whitespace')
                    && 
                is_comma($args->child($num_childs - 2))
            )
        )
        {
            $num_args--;
        }

        if ( $num_args == 2)
        {
            $call->set_content('is');
        }

        my $test_op = PPI::Token::Operator->new(q{,});
        my $test_ws = PPI::Token::Whitespace->new;
        $test_ws->set_content(' ');
        my $test_name = PPI::Token::Quote::Single->new(q{' TODO : Add test name'});
        # $test_name->string(' TODO : Add test name');
        $args->add_element($test_op);
        $args->add_element($test_ws);
        $args->add_element($test_name);
    }
}

print "$doc";
