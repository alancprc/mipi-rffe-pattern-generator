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

my $reg = <<EOF;
sample,0x1C,0x00,0x02,0x03,0x04,0x05
LB_GMSK_HPM,0x38,0x14,0x0F,0x00,0x08,0x00
LB_HPM_ISO1,0x38,0x00,0x00,0x00,0x00,0x00
LB_HPM_ISO2,0x38,0x00,0x0F,0x00,0x00,0x00
HB_GMSK_HPM,0x38,0x1C,0x00,0x00,0x10,0x0F
HB_HPM_ISO1,0x38,0x00,0x00,0x00,0x00,0x00
HB_HPM_ISO2,0x38,0x00,0x00,0x00,0x00,0x0F
LB_SWout,0x38,0x00,0x00,0x00,0x40,0x00
HB_SWout,0x38,0x00,0x00,0x00,0xC0,0x00
L_TRX1,0x38,0x00,0x01,0x00,0x08,0x00
L_TRX2,0x38,0x00,0x02,0x00,0x08,0x00
Off,0x38,0x00,0x00,0x00,0x00,0x00
Isolation,0x38,,,,,
RESETALL,0x40,,,,,
EOF
open my $fh, ">", "t/reg_sample.csv";
print $fh $reg;
close $fh;

my $txt = <<EOF;
DUT: 1, 2
ClockPinName: clk1, clk2
DataPinName: data1, data2
TriggerPinName: fx_trigger
ExtraPinName: vramp=0,dummy=1
RegisterTable: t/reg_sample.csv, t/reg_sample.csv

Label: test
    LB_GMSK_HPM
    wait 
    trig
    wait 577
    jmp pa_off
    stop
R:  0xE0011
EOF

open $fh, ">", "t/syntax.txt";
print $fh $txt;
close $fh;

$mipi->gen("t/syntax.txt");

ok( -e "t/syntax.uno" );

is( $mipi->getIdleVectorData(1), "0000101", "idle vector data" );

open $fh, "<", "t/syntax.uno";
my @content = <$fh>;
close $fh;

# vector number test
my $vectors = grep /^\*/, @content;
is( $vectors, 161, "vector number" );

# pattern end
my $end = grep /^\s*}/, @content;
ok( $end == 1, "pattern end" );

# clean
unlink "t/syntax.txt";
unlink "t/syntax.uno";
unlink "t/reg_sample.csv";

done_testing();

diag("Testing MipiPatternGenerator $MipiPatternGenerator::VERSION, Perl $], $^X"
);

