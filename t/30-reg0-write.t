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
sample,0xE1C,0xE2F,0xE00
LB_GMSK_HPM,0x38,0x14,0x0F
Off,0x38,0x00,0x00
Isolation,0x38,,
EOF
open my $fh, ">", "t/reg_reg0_write.csv";
print $fh $reg;
close $fh;

my $txt = <<EOF;
DUT= 2
ClockPinName= clk1, clk2
DataPinName= data1, data2
TriggerPinName= fx_trigger
ExtraPinName= vramp:0,dummy:1
RegisterTable= t/reg_reg0_write.csv, t/reg_reg0_write.csv
WaveformRefRead= TS13MHz
WaveformRefWrite= TS26MHz

Label: test
0:  0xE0011
0:  0xE00FF
R:  0xE00FF
0:  LB_GMSK_HPM
EOF

open $fh, ">", "t/reg0_write.txt";
print $fh $txt;
close $fh;

is( &MipiPatternGenerator::isExtended("0xE2C38"), 1, "extended mode check" );
is( &MipiPatternGenerator::isExtended("0xE1C38"), 0, "extended mode check" );

# get reg0 write data
{
    my @data = MipiPatternGenerator::getDataArrayReg0("0xE003C");
    my $exp  = "010111010111100100";
    is( join( "", @data ), $exp, "reg0 write data" );
}

# isReg0WriteMode
{
    is( MipiPatternGenerator::isReg0WriteMode("0xE003C"), 1, "is Reg0 Write" );
    is( MipiPatternGenerator::isReg0WriteMode("0xE008C"), 0, "not Reg0 Write" );
    is( MipiPatternGenerator::isReg0WriteMode("0xE0F8C"), 0, "not Reg0 Write" );
}

$mipi->gen("t/reg0_write.txt");

ok( -e "t/reg0_write.uno" );

open $fh, "<", "t/reg0_write.uno";
my @content = <$fh>;
close $fh;

# vector number test
my $vectors = grep /^\*/, @content;
is( $vectors, 18 + 27 + 28 + 27 + 18 + 36, "vector number" );

# pattern end
my $end = grep /^\s*}/, @content;
ok( $end == 1, "pattern end" );

# clean
unlink "t/reg0_write.txt";
unlink "t/reg0_write.uno";
unlink "t/reg_reg0_write.csv";

done_testing();

diag("Testing MipiPatternGenerator $MipiPatternGenerator::VERSION, Perl $], $^X"
);

