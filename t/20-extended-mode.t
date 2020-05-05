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
sample,0xE1C,0xE2F,0xE02,0xE03,0xE04,0xE05
LB_GMSK_HPM,0x38,0x14,0x0F,0x00,0x08,0x00
Off,0x38,0x00,0x00,0x00,0x00,0x00
Isolation,0x38,,,,,
EOF
open my $fh, ">", "t/reg_extended.csv";
print $fh $reg;
close $fh;

my $txt = <<EOF;
# the number of device. should be successive and start from 1.
DUT: 1, 2

# the name for clock pin for each device.
ClockPinName: clk1, clk2

# the name for data pin for each device.
DataPinName: data1, data2

# the name for trigger pin. leave blank if no trigger pin needed.
TriggerPinName: fx_trigger

# the name for extra pins, separated by ',' for multiple pin.
# leave blank if no extra pins needed.
# the format is: <pin name>=<default logic state>
# e.g.: 'vramp=1' will add pin "vramp" to uno pattern, with logic state '1';
ExtraPinName: vramp=0,dummy=1

# the csv file name for each device.
RegisterTable: t/reg_extended.csv, t/reg_extended.csv

# the waveform reference for read/write cycle
WaveformRefRead: TS13MHz
WaveformRefWrite: TS26MHz

# do NOT delete or change the order of setting lines above.

Label: test
    Isolation, LB_GMSK_HPM
R:  0xE0011
R:  0xE7F11

# extended mode write/read with multiple data
    0xE00:00-11-22-33, 0xE00:00-11-22
R:  0xE00:00-11-22-33, 0xE00:00-11-22
EOF

open $fh, ">", "t/extended.txt";
print $fh $txt;
close $fh;

is( &MipiPatternGenerator::isExtended("0xE2C38"),  1, "extended mode check" );
is( &MipiPatternGenerator::isExtended("0xE1C38"),  0, "extended mode check" );
is( &MipiPatternGenerator::isExtended("0xE1C:38"), 0, "extended mode check" );

# get data
{
    my @data = MipiPatternGenerator::getDataArray( "0xE2C38", 0, "extended" );
    my $exp  = "010111000000000000101100000111000000";
    is( join( "", @data ), $exp, "extended write data bits" );

    @data = MipiPatternGenerator::getDataArray( "0xE2C47", 1, "extended" );
    $exp  = "01011100010000010010110000LHLLLHHHH00";
    is( join( "", @data ), $exp, "extended read data bits" );
}

# get clock
{
    my @data  = split //, "010111000000000000101100000111000000";
    my @clock = MipiPatternGenerator::getClockArray(@data);
    my $exp   = "000111111111111111111111111111111110";
    is( join( "", @clock ), $exp, "extended clock bits" );

    @data  = split //, "0000000000000000000000000000000000000";
    @clock = MipiPatternGenerator::getClockArray(@data);
    $exp   = "0000000000000000000000000000000000000";
    is( join( "", @clock ), $exp, "extended read clock bits" );
}

# set/get tset
{
    $mipi->setTimeSet( "W", "r" );
    my @data  = MipiPatternGenerator::getDataArray( "0xE2C38", 0, "extended" );
    my @write = $mipi->getTimeSetArray(@data);
    is( join( "", @write ), "W" x 36, "extended write time set" );

    @data = MipiPatternGenerator::getDataArray( "0xE2C47", 1, "extended" );
    my @read = $mipi->getTimeSetArray(@data);
    is( join( "", @read ), "W" x 26 . "r" x 9 . "WW",
        "extended read time set" );
}

# get comment
{
    my @write = MipiPatternGenerator::getCommentArray( mode => "extended" );
    my @exp   = qw(
      Write SSC SSC
      SlaveAddr3 SlaveAddr2 SlaveAddr1 SlaveAddr0
      Command3 Command2 Command1 Command0
      ByteCount3 ByteCount2 ByteCount1 ByteCount0
      ParityCmd
      DataAddr7 DataAddr6 DataAddr5 DataAddr4
      DataAddr3 DataAddr2 DataAddr1 DataAddr0
      ParityAddr
      Data7 Data6 Data5 Data4 Data3 Data2 Data1 Data0
      ParityData BusPark);
    is( join( "", @write ), join( "", @exp ), "extended write comment" );

    my @read =
      MipiPatternGenerator::getCommentArray( mode => "extended", read => 1 );
    @exp = qw(
      Read SSC SSC
      SlaveAddr3 SlaveAddr2 SlaveAddr1 SlaveAddr0
      Command3 Command2 Command1 Command0
      ByteCount3 ByteCount2 ByteCount1 ByteCount0
      ParityCmd
      DataAddr7 DataAddr6 DataAddr5 DataAddr4
      DataAddr3 DataAddr2 DataAddr1 DataAddr0
      ParityAddr
      BusPark
      Data7 Data6 Data5 Data4 Data3 Data2 Data1 Data0
      ParityData BusPark);
    is( join( "", @read ), join( "", @exp ), "extended read comment" );
}

{
    my $slave = MipiPatternGenerator::getSlaveAddr("0xC0000");
    is( $slave, "c", "getSlaveAddr" );

    $slave = MipiPatternGenerator::getSlaveAddr("0xd0000");
    is( $slave, "d", "getSlaveAddr" );
}

{
    my $addr = MipiPatternGenerator::getRegAddr("0xC1C00");
    is( $addr, "1c", "getRegAddr" );

    $addr = MipiPatternGenerator::getRegAddr("0xd3f00");
    is( $addr, "3f", "getRegAddr" );

    $addr = MipiPatternGenerator::getRegAddr("0xd3e:00-11");
    is( $addr, "3e", "getRegAddr" );
}

{
    my @data = MipiPatternGenerator::getRegData("0xC1C00");
    is( $data[0], "00", "getRegData" );

    my $data = MipiPatternGenerator::getRegData("0xd3f5a");
    is( $data, "5a", "getRegData" );

    @data = MipiPatternGenerator::getRegData("0xd3e:00-11");
    is( join( "", @data ), "0011", "getRegData" );
}

# get data
{
    my @data =
      MipiPatternGenerator::getDataArray( "0xE2C:38-11", 0, "extended" );
    my $exp = "010111000000001100101100000111000000010001100";
    is( join( "", @data ), $exp, "extended write data bits" );

    @data =
      MipiPatternGenerator::getDataArray( "0xE2C:47-1B-2B-3B", 1, "extended" );
    $exp = "01011100010001110010110000LHLLLHHHHLLLHHLHHHLLHLHLHHHLLHHHLHHL00";
    is( join( "", @data ), $exp, "extended read data bits" );
}

# get clock
{
    my @data =
      MipiPatternGenerator::getDataArray( "0xE2C:38-11", 0, "extended" );
    my @clock = MipiPatternGenerator::getClockArray(@data);
    my $exp   = "000111111111111111111111111111111111111111110";
    is( join( "", @clock ), $exp, "extended write clock bits" );

    @data  = split //, "0000000000000000000000000000000000000";
    @clock = MipiPatternGenerator::getClockArray(@data);
    $exp   = "0000000000000000000000000000000000000";
    is( join( "", @clock ), $exp, "extended read clock bits" );
}

# set/get tset
{
    my @data =
      MipiPatternGenerator::getDataArray( "0xE2C:38-11", 0, "extended" );

    $mipi->setTimeSet( "W", "r" );
    my @write = $mipi->getTimeSetArray(@data);
    is( join( "", @write ), "W" x 45, "extended write time set" );

    @data =
      MipiPatternGenerator::getDataArray( "0xE2C:47-1B-2B-3B", 1, "extended" );
    my @read = $mipi->getTimeSetArray(@data);
    is(
        join( "", @read ),
        "W" x 26 . "r" x 36 . "WW",
        "extended read time set"
    );
}

# get comment
{
    my @write =
      MipiPatternGenerator::getCommentArray( mode => "extended", bytes => 1 );
    my @exp = qw(
      Write SSC SSC
      SlaveAddr3 SlaveAddr2 SlaveAddr1 SlaveAddr0
      Command3 Command2 Command1 Command0
      ByteCount3 ByteCount2 ByteCount1 ByteCount0
      ParityCmd
      DataAddr7 DataAddr6 DataAddr5 DataAddr4
      DataAddr3 DataAddr2 DataAddr1 DataAddr0
      ParityAddr
      Data7 Data6 Data5 Data4 Data3 Data2 Data1 Data0
      ParityData
      Data7 Data6 Data5 Data4 Data3 Data2 Data1 Data0
      ParityData
      BusPark);
    is( join( "", @write ), join( "", @exp ),
        "extended write 2 bytes comment" );

    my @read = MipiPatternGenerator::getCommentArray(
        mode  => "extended",
        read  => 1,
        bytes => 1
    );
    @exp = qw(
      Read SSC SSC
      SlaveAddr3 SlaveAddr2 SlaveAddr1 SlaveAddr0
      Command3 Command2 Command1 Command0
      ByteCount3 ByteCount2 ByteCount1 ByteCount0
      ParityCmd
      DataAddr7 DataAddr6 DataAddr5 DataAddr4
      DataAddr3 DataAddr2 DataAddr1 DataAddr0
      ParityAddr
      BusPark
      Data7 Data6 Data5 Data4 Data3 Data2 Data1 Data0
      ParityData
      Data7 Data6 Data5 Data4 Data3 Data2 Data1 Data0
      ParityData
      BusPark);
    is( join( "", @read ), join( "", @exp ), "extended read 2 bytes comment" );
}

$mipi->gen("t/extended.txt");

ok( -e "t/extended.uno" );

open $fh, "<", "t/extended.uno";
my @content = <$fh>;
close $fh;

# vector number test
my $vectors = grep /^\*/, @content;
is( $vectors, 27 * 5 + 36 + 28 + 37 + 36 + 3 * 9 + 37 + 3 * 9,
    "vector number" );

# pattern end
my $end = grep /^\s*}/, @content;
ok( $end == 1, "pattern end" );

# clean
unlink "t/extended.txt";
unlink "t/extended.uno";
unlink "t/reg_extended.csv";

done_testing();

diag("Testing MipiPatternGenerator $MipiPatternGenerator::VERSION, Perl $], $^X"
);

