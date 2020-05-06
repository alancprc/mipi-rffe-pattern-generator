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
sample,0xE1C,0xE00,0xE02,0xE03,0xE04,0xE05
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
Iso lation,0x38,,,,,
RESETALL,0x40,,,,,
EOF
open my $fh, ">", "t/reg_sample.csv";
print $fh $reg;
close $fh;

my $txt = <<EOF;
# the number of device. should be successive and start from 1.
DUT= 1, 2

# the name for clock pin for each device.
ClockPinName= clk1, clk2

# the name for data pin for each device.
DataPinName= data1, data2

# the name for trigger pin. leave blank if no trigger pin needed.
TriggerPinName= fx_trigger

# the name for extra pins, separated by ',' for multiple pin.
# leave blank if no extra pins needed.
# the format is: <pin name>=<default logic state>
# e.g.: 'vramp=1' will add pin "vramp" to uno pattern, with logic state '1';
ExtraPinName= vramp=0,dummy=1

# the csv file name for each device.
RegisterTable= t/reg_sample.csv, t/reg_sample.csv

# the waveform reference for read/write cycle
WaveformRefRead= TS13MHz
WaveformRefWrite= TS26MHz

# do NOT delete or change the order of setting lines above.

Label: test
    Iso lation, LB_GMSK_HPM
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

# pattern name test
my @name = grep /^Pattern\s/, @content;
ok( @name, "Pattern line" );
like( $name[0], qr/^Pattern\s+syntax/, "pattern name" );

# pin name test
my @pinlist = grep /PinList/, @content;
ok( @pinlist, "PinList line" );
my $pins    = ( split '"', $pinlist[0] )[1];
my $pinsExp = 'clk1+data1+clk2+data2+fx_trigger+vramp+dummy';
is( $pins, $pinsExp, "pinlist test" );

# vector number test
my $vectors = grep /^\*/, @content;
is( $vectors, 195, "vector number" );

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

