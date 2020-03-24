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
$mipi->generate("t/sample.txt");

my $file = 0;
$file = 1 if -e "t/sample.uno";

ok($file, "sample.uno generated");

open my $fh, "<", "t/sample.uno";
my @content = <$fh>;
close $fh;

my @pat = grep /^Pattern\s/, @content;

ok(@pat, "Pattern line");

$pat[0] =~ m/^Pattern\s+(\S+)/;

is( $1, "sample", "pattern name" );

done_testing();

diag("Testing MipiPatternGenerator $MipiPatternGenerator::VERSION, Perl $], $^X"
);

