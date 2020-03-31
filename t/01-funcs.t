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

# get data
{
    my @data = MipiPatternGenerator::getDataArray( "0xE1C38", 0 );
    my $exp = "010111001011100000111000000";
    is( join( "", @data ), $exp, "write data bits");

    @data = MipiPatternGenerator::getDataArray( "0xE1C40", 1 );
    $exp = "01011100111110010LHLLLLLLL00";
    is( join( "", @data ), $exp, "read data bits" );
}

# get clock
{
    my @data = MipiPatternGenerator::getClockArray(0);
    my $exp  = "000111111111111111111111110";
    is( join( "", @data ), $exp, "write clock bits" );

    @data = MipiPatternGenerator::getClockArray(1);
    $exp  = "0001111111111111111111111110";
    is( join( "", @data ), $exp, "read clock bits" );
}

# set/get tset
{
    $mipi->setTimeSet("W", "r");
    my @write = $mipi->getTimeSetArray(0);
    is ( join("", @write), "W" x 27, "write time set");

    my @read = $mipi->getTimeSetArray(1);
    is ( join("", @read), "W" x 17 . "r" x 9 . "WW", "read time set");
}

# get comment
{
    my @write = MipiPatternGenerator::getCommentArray(0);
    my @exp   = qw( SSC SSC SSC SlaveAddr3 SlaveAddr2 SlaveAddr1 SlaveAddr0
      Command2 Command1 Command0
      DataAddr4 DataAddr3 DataAddr2 DataAddr1 DataAddr0 Parity1
      Data7 Data6 Data5 Data4 Data3 Data2 Data1 Data0 Parity2 BusPark);
    is( join( "", @write ), join( "", @exp ), "write comment" );

    my @read = MipiPatternGenerator::getCommentArray(1);
    @exp = qw( SSC SSC SSC SlaveAddr3 SlaveAddr2 SlaveAddr1 SlaveAddr0
      Command2 Command1 Command0
      DataAddr4 DataAddr3 DataAddr2 DataAddr1 DataAddr0 Parity1 BusPark
      Data7 Data6 Data5 Data4 Data3 Data2 Data1 Data0 Parity2 BusPark);
    is( join( "", @read ), join( "", @exp ), "read comment" );
}

# increase data
{
    my $reg = "E0089";
    MipiPatternGenerator::increaseRegData( \$reg );
    is( $reg, "E008A", "increase hex data" );

    $reg = "E00FF";
    MipiPatternGenerator::increaseRegData( \$reg );
    is( $reg, "E00FF", "increase hex data 0xff" );
}

done_testing();

diag("Testing MipiPatternGenerator $MipiPatternGenerator::VERSION, Perl $], $^X"
);

