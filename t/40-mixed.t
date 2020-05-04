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

my $fn = "mixed";
my $reg = <<EOF;
sample,0xE1C,0xE2F,0xE02,0xE03,0xE04,0xE05
LB_GMSK_HPM,0x38,0x14,0x0F,0x00,0x08,0x00
Off,0x38,0x00,0x00,0x00,0x00,0x00
Isolation,0x38,,,,,
EOF
open my $fh, ">", "t/$fn.csv";
print $fh $reg;
close $fh;

my $txt = <<EOF;
DUT: 1, 2, 3
ClockPinName: clk1, clk2, clk3
DataPinName: data1, data2, data3
TriggerPinName: 
ExtraPinName: 
RegisterTable: t/$fn.csv, t/$fn.csv, t/$fn.csv
WaveformRefRead: r
WaveformRefWrite: W

0:  0xE0011,0xE1C38
    0xE0011,0xE1C38

0:  0xE0011,0xE1C38,0xE2F0F
    0xE0011,0xE1C38,0xE2F0F
R:  0xE0011,0xE1C38,0xE2F0F

    0xE0011,0xE1C38, 0xE00:00-11-22-33
R:  0xE0011,0xE1C38, 0xE00:00-11-22-33

0:  0xE0011,0xE1C38, 0xE00:00-11-22-33
EOF

open $fh, ">", "t/$fn.txt";
print $fh $txt;
close $fh;

$mipi->gen("t/$fn.txt");

ok( -e "t/$fn.uno" );

open $fh, "<", "t/$fn.uno";
my @content = <$fh>;
close $fh;

# vector number test
my $vectors = grep /^\*/, @content;
is(
    $vectors,
    27 * 2 + ( 36 * 3 + 1 ) + ( 36 + 3 * 9 ) * 3 + 1,
    "vector number"
);

# pattern end
my $end = grep /^\s*}/, @content;
ok( $end == 1, "pattern end" );

# clean
unlink "t/$fn.txt";
unlink "t/$fn.uno";
unlink "t/$fn.csv";

done_testing();

diag("Testing MipiPatternGenerator $MipiPatternGenerator::VERSION, Perl $], $^X"
);

