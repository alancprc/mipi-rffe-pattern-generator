#!perl -T
use 5.010001;
use strict;
use warnings;
use Test::More;

BEGIN {
    use_ok('MipiPatternGenerator') || print "Bail out!\n";
}

use MipiPatternGenerator;

# generate test file
my $pattern = <<EOF;
write
0xE1C38W
0xF1C38W
wait
EOF

open my $fh, ">", "t/pattern.txt";
print $fh $pattern;
close $fh;

# generate
my $mipi = MipiPatternGenerator->new();
$mipi->generate("t/pattern.txt");

ok( -e "t/pattern.uno", "pattern.uno generated" );

# test output file
open $fh, "<", "t/pattern.uno";
my @content = <$fh>;
close $fh;

my @name = grep /^Pattern\s/, @content;

ok( @name, "Pattern line" );

like( $name[0], qr/^Pattern\s+pattern/, "pattern name" );

my $vector = grep /^\s*\*(\s*\w\s*)+\*(\s*\w\s*)+;/, @content;
is( $vector, 54, "vector number" );

my $end = grep /^\s*}/, @content;
ok( $end == 1, "pattern end" );

# clean
unlink "t/pattern.txt";
unlink "t/pattern.uno";

done_testing();

diag("Testing MipiPatternGenerator $MipiPatternGenerator::VERSION, Perl $], $^X"
);

