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
my $pin = <<EOF;
write
0xE1C38W
0xF1C38W
wait
EOF

open my $fh, ">", "t/pin.txt";
print $fh $pin;
close $fh;

# generate
my $mipi = MipiPatternGenerator->new();

$mipi->setPinName( "data", "clk" );
$mipi->addTriggerPin("fx_trigger");
$mipi->addExtraPin( "vramp", "0" );

$mipi->generate("t/pin.txt");

ok( -e "t/pin.uno" );

open $fh, "<", "t/pin.uno";
my @file = <$fh>;
close $fh;

my $re      = qr/^\s*PinList\s*=\s*"\s*(.*)\s*"\s*;/;
my $pinlist = ( grep /$re/, @file )[0];
ok( $pinlist, "PinList test" );

$pinlist =~ m/$re/;
my @pins = split /\s*\+\s*/, $1;

ok( grep /data/,       @pins, "data pin" );
ok( grep /clk/,        @pins, "clodk pin" );
ok( grep /fx_trigger/, @pins, "trigger pin" );
ok( grep /vramp/,      @pins, "trigger pin" );

# clean
unlink "t/pin.txt";
unlink "t/pin.uno";

done_testing();

diag("Testing MipiPatternGenerator $MipiPatternGenerator::VERSION, Perl $], $^X"
);

