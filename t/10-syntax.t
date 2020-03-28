#!perl -T
use 5.010001;
use strict;
use warnings;
use Test::More;

BEGIN {
    use_ok('MipiPatternGenerator') || print "Bail out!\n";
}

use MipiPatternGenerator;

# generate
my $mipi = MipiPatternGenerator->new();

$mipi->gen("t/syntax.txt");

ok( -e "t/syntax.uno" );

is( $mipi->getIdleVectorData(1), "0000101", "idle vector data");

open my $fh, "<", "t/syntax.uno";
my @content = <$fh>;
close $fh;

# vector number test
my $vectors = grep /^\*/, @content;
is( $vectors, 161, "vector number");

# pattern end
my $end = grep /^\s*}/, @content;
ok( $end == 1, "pattern end" );

done_testing();

diag("Testing MipiPatternGenerator $MipiPatternGenerator::VERSION, Perl $], $^X"
);

