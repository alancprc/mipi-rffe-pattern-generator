#!/usr/bin/env perl
use v5.14;
use strict;
use warnings;

# use module under current directory.
use FindBin 1.51 qw( $RealBin );
use lib $RealBin;

use MipiPatternGenerator;

# generate
my $mipi = MipiPatternGenerator->new();

my $prog = $0;

my $help =<<EOF;
NAME
    $prog - generate mipi pattern for Unison

USAGE
    $prog [config-file] [config-file...]

DESCRIPTION
    Generate pattern from config files, with or without register table files.
    Multiple devices are Supported.
    The following mipi mode are supported:
        Register Write
        Register Read
        Extended Register Write
        Extended Register Read
        Extended Long Register Write
        Extended Long Register Read
        Register 0 Write

Supported Unison pattern micro-instructions:
    RPT
    STOP
    TRIG
    JMP
    
Supported Pseudo instructions:
    wait    -   clock/data stays 0 on this vector for all dut
    nop     -   no operation for specific dut, clock/data stays all zero

EXAMPLE
    The following sample files should come along this tool:
        sample.cfg              config file in .cfg format
        sample.csv              config file in .csv file
        regtable_dut1.csv       register table for device 1
        regtable_dut2.csv       register table for device 2
        sample.uno              pattern source generated from sample.cfg/csv

EOF

die $help unless @ARGV;

for my $file (@ARGV) {
    $mipi->gen("$file");
}
