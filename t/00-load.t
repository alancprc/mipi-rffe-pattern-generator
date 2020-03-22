#!perl -T
use 5.010001;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'MipiPatternGenerator' ) || print "Bail out!\n";
}

diag( "Testing MipiPatternGenerator $MipiPatternGenerator::VERSION, Perl $], $^X" );
