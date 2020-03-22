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
    my $exp = "01011100101110000011100000";
    is( join( "", @data ), $exp );

    @data = MipiPatternGenerator::getDataArray( "0xE1C40", 1 );
    $exp = "01011100111110010LHLLLLLLL0";
    is( join( "", @data ), $exp );
}

# get clock
{
    my @data = MipiPatternGenerator::getClockArray(0);
    my $exp  = "00011111111111111111111111";
    is( join( "", @data ), $exp );
}

done_testing();

diag("Testing MipiPatternGenerator $MipiPatternGenerator::VERSION, Perl $], $^X"
);
