#!perl -T
use 5.010001;
use strict;
use warnings;
use Test::More;

#plan tests => 1;

BEGIN {
    use_ok('MipiPatternGenerator') || print "Bail out!\n";
}

use MipiPatternGenerator;

my $mipi = MipiPatternGenerator->new();
isa_ok( $mipi, "MipiPatternGenerator" );

# replace01withLH
{
    my @data = qw ( 0 1 );
    my @exp  = qw ( L H );
    MipiPatternGenerator::replace01withLH( \@data, 0, 2 );
    is( join( "", @data ), join( "", @exp ) );
}

# odd parity
{
    my @data = qw ( 0 1 1 );
    is( MipiPatternGenerator::oddParity(@data), 1 );

    @data = qw ( 1 1 1 0 0 1 0 1 1 1 0 0 );
    is( MipiPatternGenerator::oddParity(@data), 0 );
}

# get slave addr
is( &MipiPatternGenerator::getSlaveAddr("0xE2F1C"),  "e", "slave addr" );
is( &MipiPatternGenerator::getSlaveAddr("0XE2F1C"),  "e", "slave addr" );

# get register addr
is( &MipiPatternGenerator::getRegAddr("0XE2F1C"),  "2f", "reg addr" );
is( &MipiPatternGenerator::getRegAddr("0xE1C1C"),  "1c", "reg addr" );
is( &MipiPatternGenerator::getRegAddr("0xE001C"),  "00", "reg addr" );
is( &MipiPatternGenerator::getRegAddr("0xE1C:11-22"),  "1c", "reg addr" );
is( &MipiPatternGenerator::getRegAddr("0xE1C1C:11-22"), "1c1c", "reg addr" );

# get register data
my @data = &MipiPatternGenerator::getRegData("0XE1C38");
is( join( "", @data ), "38", "reg data" );
@data = &MipiPatternGenerator::getRegData("0xE1C:38");
is( join( "", @data ), "38", "reg data" );
@data = &MipiPatternGenerator::getRegData("0xE1C1C38");
is( join( "", @data ), "38", "reg data" );
@data = &MipiPatternGenerator::getRegData("0xE1C1C:38");
is( join( "", @data ), "38", "reg data" );
@data = &MipiPatternGenerator::getRegData("0xE1C1C:11-22");
is( join( "", @data ), "1122", "reg data" );

# isExtended
is( &MipiPatternGenerator::isExtended("0xE2C38"),  1, "extended mode" );
is( &MipiPatternGenerator::isExtended("0xE1C38"),  0, "extended mode" );
is( &MipiPatternGenerator::isExtended("0xE1C:38"), 0, "extended mode" );

# isLong
is( &MipiPatternGenerator::isLong("0xE2C38"),  0, "long mode" );
is( &MipiPatternGenerator::isLong("0xE1C:38"), 0, "long mode" );
is( &MipiPatternGenerator::isLong("0xE1C1C:38"),  1, "long mode" );
is( &MipiPatternGenerator::isLong("0xE1C1C:11-22-33"),  1, "long mode" );

# get data
{
    my @data = MipiPatternGenerator::getDataArray( "0xE1C38", 0 );
    my $exp = "010111001011100000111000000";
    is( join( "", @data ), $exp, "write data bits");

    @data = MipiPatternGenerator::getDataArray( "0xE1C40", 1 );
    $exp = "01011100111110010LHLLLLLLLX0";
    is( join( "", @data ), $exp, "read data bits" );
}

# get clock
{
    my @data = split //, "010111001011100000111000000";
    my @clock = MipiPatternGenerator::getClockArray(@data);
    my $exp  = "000111111111111111111111110";
    is( join( "", @clock ), $exp, "read/write clock bits" );

    @data = split //, "000000000000000000000000000";
    @clock = MipiPatternGenerator::getClockArray(@data);
    $exp  = "000000000000000000000000000";
    is( join( "", @clock ), $exp, "nop clock bits" );
}

# set/get tset
{
    my @data = MipiPatternGenerator::getDataArray( "0xE1C38", 0 );

    $mipi->setTimeSet("W", "r");
    my @write = $mipi->getTimeSetArray(@data);
    is ( join("", @write), "W" x 27, "write time set");

    @data = MipiPatternGenerator::getDataArray( "0xE1C40", 1 );
    my @read = $mipi->getTimeSetArray(@data);
    is ( join("", @read), "W" x 17 . "r" x 10 . "W", "read time set");
}

# get comment
{
    my @write = MipiPatternGenerator::getCommentArray();
    my @exp   = qw( Write SSC SSC SlaveAddr3 SlaveAddr2 SlaveAddr1 SlaveAddr0
      Command2 Command1 Command0
      DataAddr4 DataAddr3 DataAddr2 DataAddr1 DataAddr0 ParityCmd
      Data7 Data6 Data5 Data4 Data3 Data2 Data1 Data0 ParityData BusPark);
    is( join( "", @write ), join( "", @exp ), "write comment" );

    my @read = MipiPatternGenerator::getCommentArray( read => 1 );
    @exp = qw( Read SSC SSC SlaveAddr3 SlaveAddr2 SlaveAddr1 SlaveAddr0
      Command2 Command1 Command0
      DataAddr4 DataAddr3 DataAddr2 DataAddr1 DataAddr0 ParityCmd BusPark
      Data7 Data6 Data5 Data4 Data3 Data2 Data1 Data0 ParityData BusPark);
    is( join( "", @read ), join( "", @exp ), "read comment" );
}

done_testing();

diag("Testing MipiPatternGenerator $MipiPatternGenerator::VERSION, Perl $], $^X"
);

