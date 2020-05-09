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

my $fn = "long";
my $reg = <<EOF;
sample,0XE1C1C,0xE2F,0xE02,0xE03,0xE04,0xE05
LB_GMSK_HPM,0x38,0x14,0x0F,0x00,0x08,0x00
Off,0x38,0x00,0x00,0x00,0x00,0x00
Isolation,0x38,,,,,
EOF
open my $fh, ">", "t/$fn.csv";
print $fh $reg;
close $fh;

my $txt = <<EOF;
DUT= 2
ClockPinName= clk1, clk2
DataPinName= data1, data2
TriggerPinName= 
ExtraPinName= 
RegisterTable= t/$fn.csv, t/$fn.csv
WaveformRefRead= TS13MHz
WaveformRefWrite= TS26MHz


    0xE1F00:00-11-22-33, 0x1FE00:00-11-22-33
R:  0xE1F00:00-11-22-33, 0x1FE00:00-11-22-33
EOF

open $fh, ">", "t/$fn.txt";
print $fh $txt;
close $fh;

# get data
{
    my @data = MipiPatternGenerator::getDataArray( "0xE2C38", 0, "long" );
    my $exp  = "010111000110000000000000100101100000111000000";
    is( join( "", @data ), $exp, "long write data bits" );

    @data = MipiPatternGenerator::getDataArray( "0xE2C47", 1, "long" );
    $exp  = "01011100011100010000000010010110000LHLLLHHHH00";
    is( join( "", @data ), $exp, "long read data bits" );
}

# get comment
{
    my @write = MipiPatternGenerator::getCommentArray( mode => "long" );
    my @exp   = qw(
      Write SSC SSC
      SlaveAddr3 SlaveAddr2 SlaveAddr1 SlaveAddr0
      Command4 Command3 Command2 Command1 Command0
      ByteCount2 ByteCount1 ByteCount0
      ParityCmd
      DataAddr15 DataAddr14 DataAddr13 DataAddr12
      DataAddr11 DataAddr10 DataAddr9 DataAddr8
      ParityAddr
      DataAddr7 DataAddr6 DataAddr5 DataAddr4
      DataAddr3 DataAddr2 DataAddr1 DataAddr0
      ParityAddr
      Data7 Data6 Data5 Data4 Data3 Data2 Data1 Data0
      ParityData BusPark);
    is( join( "", @write ), join( "", @exp ), "long write comment" );

    my @read =
      MipiPatternGenerator::getCommentArray( mode => "long", read => 1 );
    @exp = qw(
      Read SSC SSC
      SlaveAddr3 SlaveAddr2 SlaveAddr1 SlaveAddr0
      Command4 Command3 Command2 Command1 Command0
      ByteCount2 ByteCount1 ByteCount0
      ParityCmd
      DataAddr15 DataAddr14 DataAddr13 DataAddr12
      DataAddr11 DataAddr10 DataAddr9 DataAddr8
      ParityAddr
      DataAddr7 DataAddr6 DataAddr5 DataAddr4
      DataAddr3 DataAddr2 DataAddr1 DataAddr0
      ParityAddr
      BusPark
      Data7 Data6 Data5 Data4 Data3 Data2 Data1 Data0
      ParityData BusPark);
    is( join( "", @read ), join( "", @exp ), "long read comment" );
}

{
    my $slave = MipiPatternGenerator::getSlaveAddr("0xC001122");
    is( $slave, "c", "getSlaveAddr" );

    $slave = MipiPatternGenerator::getSlaveAddr("0xd0000FF");
    is( $slave, "d", "getSlaveAddr" );
}

{
    my $addr = MipiPatternGenerator::getRegAddr("0xC1C0011");
    is( $addr, "1c00", "getRegAddr" );

    $addr = MipiPatternGenerator::getRegAddr("0xd3f00:11");
    is( $addr, "3f00", "getRegAddr" );

    $addr = MipiPatternGenerator::getRegAddr("0xd3e3f:00-11");
    is( $addr, "3e3f", "getRegAddr" );
}

{
    my @data = MipiPatternGenerator::getRegData("0xC1C0011");
    is( $data[0], "11", "getRegData" );

    my $data = MipiPatternGenerator::getRegData("0xd3f5a8d");
    is( $data, "8d", "getRegData" );

    @data = MipiPatternGenerator::getRegData("0xd3e3f:00-11");
    is( join( "", @data ), "0011", "getRegData" );
}

$mipi->gen("t/$fn.txt");

ok( -e "t/$fn.uno" );

open $fh, "<", "t/$fn.uno";
my @content = <$fh>;
close $fh;

# vector number test
my $vectors = grep /^\*/, @content;
is( $vectors, ( 45 + 9 * 3 ) * 2 + 1, "vector number" );

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

