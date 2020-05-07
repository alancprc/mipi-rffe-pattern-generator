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
    $prog [pseudo-pattern-file] [pseudo-pattern-file...]

DESCRIPTION
    Generate pattern from pseudo pattern file and register table file.
    Multiple devices are Supported.
    The following mipi mode are supported:
        Register Write
        Register Read
        Extended Register Write
        Extended Register Read
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
    Refer to sample.txt, sample.uno and regtable_dut1.csv which should come
    along this tool.

EOF

die $help unless @ARGV;

for my $file (@ARGV) {
    $mipi->gen("$file");
}
