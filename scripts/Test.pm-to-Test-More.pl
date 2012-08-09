#!/usr/bin/perl

=head1 NAME

Test.pm-to-Test-More.pl - semi-automatically and partially convert Test.pm
scripts to Test::More.

=head1 USAGE

    perl Test.pm-to-Test-More.pl -o new.t t/old.t

=head1 VERSION

0.2.0

=cut

use strict;
use warnings;

use Getopt::Long;
use PPI;

my $out_filename;
my $inplace = '';
if (!GetOptions(
    'o|output=s' => \$out_filename,
    'inplace!' => \$inplace,
))
{
    die "Cannot process arguments.";
}

if ($inplace && defined($out_filename))
{
    die 'Inplace is mutually exclusive with specifying an output file!';
}

my $filename = shift(@ARGV);

if ($inplace)
{
    $out_filename = $filename;
}

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

$doc->save($out_filename);

=begin removed

{
    my $out_fh;
    if (defined($out_filename))
    {
        open $out_fh, ">", $out_filename
            or die qq{Cannot open "$out_filename" for writing!};
    }
    else
    {
        open $out_fh, ">&STDOUT";
    }

    print {$out_fh} "$doc";

    close ($out_fh)
}

=end removed

=cut

=head1 COPYRIGHT & LICENSE

Copyright 2011 by Shlomi Fish

This program is distributed under the MIT (X11) License:
L<http://www.opensource.org/licenses/mit-license.php>

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

=cut
