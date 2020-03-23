package MipiPatternGenerator;

use 5.010001;
use strict;
use warnings;

use Moose;
use Function::Parameters;
use Types::Standard qw(Str Int ArrayRef RegexpRef Ref);
use JSON -convert_blessed_universally;
use File::Basename;
use File::Spec;
use File::Path qw(make_path remove_tree);
use Carp qw(croak carp);

use Exporter qw(import);
our @EXPORT = qw();

=head1 NAME

MipiPatternGenerator - generate mipi pattern for Unison

=head1 DESCRIPTION

Generate pattern from pattern.txt and registerN.csv file.
Multiple devices are Supported.

pattern.txt if the pseudo pattern file, contains something like following:

   ======================================================
   DUT 1, 2                - required, indicates how many duts
   labelA:                 - optional
       GSM_HB_HPM, nop     - register state in registerN.csv 
       wait 1              - optional, wait 1 cycle
       TRIG                - optional, trigger pin sets to 1
       wait 577
       JMP pa_off          - optional, jump to label pa_off
   ======================================================

registerN.csv should contain the register table for device. One registerN.csv
for each device. typically, N = 1 or 2.

Supported Unison pattern micro-instructions:

   RPT
   STOP
   TRIG
   JMP

Pseudo instructions:

   wait    -   clock/data stays 0 on this vector for all dut
   nop     -   no operation for specific dut, clock/data stays all zero

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

my $tsetWrite = "TS26MHz";
my $tsetRead  = "TS1MHz";
my $WR_TIMES  = 1;           # 256

my $pattern_name;

my @slave_addr;
my @data_addr;
my @parity;
my @data;

my $cycle_count = 0;
my $write_count = 0;
my $read_count  = 0;
my $WR_count    = 0;

my $uno;

=head1 SYNOPSIS

    use MipiPatternGenerator;

    my $mipi = MipiPatternGenerator->new();
    $mipi->setTimeSet($writeTset, $readTset);
    $mipi->generate("pattern.txt");

=head1 SUBROUTINES/METHODS

=cut

has 'debug' => ( is => 'rw', default => 0 );

=head2 generate

 generate unison pattern file from given pseudo pattern file.

=cut

method generate (Str $file)
{
    &validateInputFile($file);
    my @ins = &readPseudoPattern($file);

    open( $uno, ">", "$self->$pattern_name.uno" );

    &printHeader;

    for (@ins) {
        chomp;

        if (/0x(\S+)W$/) {
            &regWrite($1);
        } elsif (/0x(\S+)R$/) {
            &regRead($1);
        } elsif (/0x(\S+)WR256$/) {
            &regWriteRead256Bytes($1);
        } elsif ( !/wait/ and /^\s*(\w+)\s*$/ ) {

            # label
            printUno("\$$1");
        }
    }
    printUno("}");
    close $uno;
}

=head2 setTimeSet

 set time set for write and read.

=cut

method setTimeSet ($writeTset, $readTset)
{
    $tsetWrite = $writeTset;
    $tsetRead  = $readTset;
}

=head2 validateInputFile

 validate input file, die if input file is a .uno file.

=cut

method validateInputFile (Str $file)
{
    die "invalid suffix '.uno', please rename the suffix and try again"
      if $file =~ /.*\.uno$/;

    $pattern_name = $file;
    $pattern_name =~ s/(\S+)\.\S+/$1/;
}

=head2 printHeader()

 print header for unison pattern file.

=cut

fun printHeader ()
{
    print $uno "Unison:SyntaxRevision6.310000;\n";
    print $uno "Pattern  $pattern_name  {\n";
    print $uno "Mode MixedSignal;\n";
    print $uno "AliasMap \"DefaultAliasMap\";\n";
    print $uno "Type Generic;\n\n";

    print $uno "PinList = \"DATA_pin+CLK_pin+FX_TRIGGER_pin\";\n\n";

    #print $uno "CaptureRef MipiCapture = \"DATA_pin\";\n";
    #print $uno "RegSendRef MipiSend = \"DATA_pin+FX_TRIGGER_pin\";\n";
    #print $uno "SyncRef { PatRfTrig }\n\n";

    #print $uno "Default SignalHeader $pattern_name\_SH;\n";
    #print $uno "Default WaveformTable $pattern_name\_WFTRef;\n\n";

    #print $uno "\$start\n";
}

=head2 readPseudoPattern

 read pseudo pattern file

=cut

fun readPseudoPattern ($inputfile)
{
    open( my $fh, "<", $inputfile );
    my @data = <$fh>;
    close $fh;

    return @data;
}

=head2 regWrite

 write data to single register at given address

=cut

fun regWrite ($reg)
{
    my $read = 0;
    return &regRW( $reg, $read );

    my $total20_decimal = hex($reg);
    my $total20_temp    = sprintf( "%016b", $total20_decimal );

    my @total20_bit_temp = split( //, $total20_temp );

    my $length_total20_temp = @total20_bit_temp;
    my $total20;
    if ( $length_total20_temp == 19 ) {
        $total20 = "0" . $total20_temp;
    } elsif ( $length_total20_temp == 18 ) {
        $total20 = "00" . $total20_temp;
    } elsif ( $length_total20_temp == 17 ) {
        $total20 = "000" . $total20_temp;
    } elsif ( $length_total20_temp == 16 ) {
        $total20 = "0000" . $total20_temp;
    } else {
        $total20 = $total20_temp;
    }

    my @total20_bit    = split( //, $total20 );
    my $length_total20 = @total20_bit;

    my @write_read;
    ++$write_count;

    $slave_addr[3] = $total20_bit[0];
    $slave_addr[2] = $total20_bit[1];
    $slave_addr[1] = $total20_bit[2];
    $slave_addr[0] = $total20_bit[3];

    $write_read[2] = 0;
    $write_read[1] = 1;
    $write_read[0] = 0;

    # from LSB to MSB
    for ( my $m = 4 ; $m >= 0 ; $m-- ) {
        my $j = 11 - $m;
        $data_addr[$m] = $total20_bit[$j];
    }

    for ( my $m = 7 ; $m >= 0 ; $m-- ) {
        my $j = 19 - $m;
        $data[$m] = $total20_bit[$j];
    }

    my $sum1 =
      $slave_addr[3] +
      $slave_addr[2] +
      $slave_addr[1] +
      $slave_addr[0] +
      $write_read[2] +
      $write_read[1] +
      $write_read[0] +
      $data_addr[4] +
      $data_addr[3] +
      $data_addr[2] +
      $data_addr[1] +
      $data_addr[0];

    my $sum2 = 0;
    for ( my $m = 7 ; $m >= 0 ; $m-- ) { $sum2 = $sum2 + $data[$m]; }

    if   ( $sum1 % 2 == 0 ) { $parity[0] = 1 }
    else                    { $parity[0] = 0 }

    if   ( $sum2 % 2 == 0 ) { $parity[1] = 1 }
    else                    { $parity[1] = 0 }

    printVector(
"\*000* $tsetWrite;           \"$cycle_count  START Write $data_addr[4]$data_addr[3]$data_addr[2]$data_addr[1]$data_addr[0]\: $data[7]$data[6]$data[5]$data[4]$data[3]$data[2]$data[1]$data[0]\""
    );
    printVector("\*100* $tsetWrite;           \"$cycle_count  \"");
    printVector("\*000* $tsetWrite;           \"$cycle_count  \"");
    printVector(
        "*$slave_addr[3]10* $tsetWrite;           \"$cycle_count  SA3\"");
    printVector(
        "*$slave_addr[2]10* $tsetWrite;           \"$cycle_count  SA2\"");
    printVector(
        "*$slave_addr[1]10* $tsetWrite;           \"$cycle_count  SA1\"");
    printVector(
        "*$slave_addr[0]10* $tsetWrite;           \"$cycle_count  SA0\"");

    printVector(
        "*$write_read[2]10* $tsetWrite;           \"$cycle_count  Write_cmd 2\""
    );
    printVector(
        "*$write_read[1]10* $tsetWrite;           \"$cycle_count  Write_cmd 1\""
    );
    printVector(
        "*$write_read[0]10* $tsetWrite;           \"$cycle_count  Write_cmd 0\""
    );

    for ( my $m = 4 ; $m >= 0 ; $m-- ) {
        printVector(
"*$data_addr[$m]10* $tsetWrite;           \"$cycle_count  data_Addr Bit Num $m  $_\""
        );
    }
    printVector(
        "*$parity[0]10* $tsetWrite;           \"$cycle_count  parity[1]  \"");

    for ( my $m = 7 ; $m >= 0 ; $m-- ) {
        printVector(
"*$data[$m]10* $tsetWrite;           \"$cycle_count  data Bit Num $m  $_\""
        );
    }

    printVector(
        "*$parity[1]10* $tsetWrite;           \"$cycle_count  parity[2]  \"");

    printVector("\*010* $tsetWrite;           \"$cycle_count  BusPark\"");

    printVector("\*010* $tsetWrite;           \"$cycle_count  STOP\"");
    printVector("\*010* $tsetWrite;           \"$cycle_count  \"");
    printVector("\*000* $tsetWrite;           \"$cycle_count  \"");
    printVector("\*000* $tsetWrite;           \"$cycle_count  \"");
}

=head2 regRead

 read single register data at given address

=cut

fun regRead ($reg)
{
    my $read = 1;
    return &regRW( $reg, $read );

    my $total20_decimal = hex($reg);
    my $total20_temp    = sprintf( "%016b", $total20_decimal );

    my @total20_bit_temp = split( //, $total20_temp );

    my $length_total20_temp = @total20_bit_temp;
    my $total20;
    if ( $length_total20_temp == 19 ) {
        $total20 = "0" . $total20_temp;
    } elsif ( $length_total20_temp == 18 ) {
        $total20 = "00" . $total20_temp;
    } elsif ( $length_total20_temp == 17 ) {
        $total20 = "000" . $total20_temp;
    } elsif ( $length_total20_temp == 16 ) {
        $total20 = "0000" . $total20_temp;
    } else {
        $total20 = $total20_temp;
    }

    my @total20_bit    = split( //, $total20 );
    my $length_total20 = @total20_bit;

    my @write_read;
    ++$read_count;

    $slave_addr[3] = $total20_bit[0];
    $slave_addr[2] = $total20_bit[1];
    $slave_addr[1] = $total20_bit[2];
    $slave_addr[0] = $total20_bit[3];

    $write_read[2] = 0;
    $write_read[1] = 1;
    $write_read[0] = 1;

    # from LSB to MSB
    for ( my $m = 4 ; $m >= 0 ; $m-- ) {
        my $j = 11 - $m;
        $data_addr[$m] = $total20_bit[$j];
    }

    for ( my $m = 7 ; $m >= 0 ; $m-- ) {
        my $j = 19 - $m;
        $data[$m] = $total20_bit[$j];
    }

    my $sum1 =
      $slave_addr[3] +
      $slave_addr[2] +
      $slave_addr[1] +
      $slave_addr[0] +
      $write_read[2] +
      $write_read[1] +
      $write_read[0] +
      $data_addr[4] +
      $data_addr[3] +
      $data_addr[2] +
      $data_addr[1] +
      $data_addr[0];

    my $sum2 = 0;
    for ( my $m = 7 ; $m >= 0 ; $m-- ) { $sum2 = $sum2 + $data[$m]; }

    if   ( $sum1 % 2 == 0 ) { $parity[0] = 1 }
    else                    { $parity[0] = 0 }

    if   ( $sum2 % 2 == 0 ) { $parity[1] = 'H' }
    else                    { $parity[1] = 'L' }

    printVector(
"\*000* $tsetRead;           \"$cycle_count  START Read $data_addr[4]$data_addr[3]$data_addr[2]$data_addr[1]$data_addr[0]\: $data[7]$data[6]$data[5]$data[4]$data[3]$data[2]$data[1]$data[0]\""
    );
    printVector("\*100* $tsetRead;           \"$cycle_count  \"");
    printVector("\*000* $tsetRead;           \"$cycle_count  \"");
    printVector(
        "*$slave_addr[3]10* $tsetWrite;           \"$cycle_count  SA3\"");
    printVector(
        "*$slave_addr[2]10* $tsetWrite;           \"$cycle_count  SA2\"");
    printVector(
        "*$slave_addr[1]10* $tsetWrite;           \"$cycle_count  SA1\"");
    printVector(
        "*$slave_addr[0]10* $tsetWrite;           \"$cycle_count  SA0\"");

    printVector(
        "*$write_read[2]10* $tsetWrite;           \"$cycle_count  Read_cmd 2\""
    );
    printVector(
        "*$write_read[1]10* $tsetWrite;           \"$cycle_count  Read_cmd 1\""
    );
    printVector(
        "*$write_read[0]10* $tsetWrite;           \"$cycle_count  Read_cmd 0\""
    );

    for ( my $m = 4 ; $m >= 0 ; $m-- ) {
        printVector(
"*$data_addr[$m]10* $tsetWrite;           \"$cycle_count  data_Addr Bit Num $m  $_\""
        );
    }
    printVector(
        "*$parity[0]10* $tsetRead;           \"$cycle_count  parity[1]  \"");

    printVector("\*010* $tsetRead;           \"$cycle_count  BusPark\"");

    for ( my $m = 7 ; $m >= 0 ; $m-- ) {
        $data[$m] = $data[$m] ? "H" : "L";
        printVector(
"*$data[$m]10\* $tsetRead;           \"$cycle_count  Data Bit Num: $m  $_\""
        );
    }

    printVector(
        "*$parity[1]10* $tsetRead;           \"$cycle_count  parity[2]  \"");

    printVector("\*010* $tsetWrite;           \"$cycle_count  BusPark\"");

    printVector("\*010* $tsetWrite;           \"$cycle_count  STOP\"");
    printVector("\*010* $tsetWrite;           \"$cycle_count  \"");
    printVector("\*000* $tsetWrite;           \"$cycle_count  \"");
    printVector("\*000* $tsetWrite;           \"$cycle_count  \"");
}

=head2 regWriteRead256Bytes

 write data 0x00 to 0xff to a same address and then read back

=cut

fun regWriteRead256Bytes ($reg)
{
    my $total12_decimal = hex($1);
    print "\$1 is $1\n";
    my $total12        = sprintf( "%012b", $total12_decimal );
    my @total12_bit    = split( //, $total12 );
    my $length_total12 = @total12_bit;
    my @write_read;
    $WR_count = $WR_count + 1;
    printUno("\$$1\_WR0_255_T$WR_count");

    $slave_addr[3] = $total12_bit[0];
    $slave_addr[2] = $total12_bit[1];
    $slave_addr[1] = $total12_bit[2];
    $slave_addr[0] = $total12_bit[3];
    $write_read[2] = 0;
    $write_read[1] = 1;
    $write_read[0] = 0;
    my @read_bit;
    $read_bit[0] = 1;
    my @parity_read;

    $data_addr[4] = $total12_bit[7];
    $data_addr[3] = $total12_bit[8];
    $data_addr[2] = $total12_bit[9];
    $data_addr[1] = $total12_bit[10];
    $data_addr[0] = $total12_bit[11];
    my $sum1 =
      $slave_addr[3] +
      $slave_addr[2] +
      $slave_addr[1] +
      $slave_addr[0] +
      $write_read[2] +
      $write_read[1] +
      $write_read[0] +
      $data_addr[4] +
      $data_addr[3] +
      $data_addr[2] +
      $data_addr[1] +
      $data_addr[0];
    if ( $sum1 % 2 == 0 ) { $parity[0] = 1, $parity_read[0] = 0; }
    else                  { $parity[0] = 0; $parity_read[0] = 1; }

    my $loop_data;
    for ( $loop_data = 0 ; $loop_data < $WR_TIMES ; $loop_data++ ) {

        my $data8 = sprintf( "%08b", $loop_data );
        my @data  = split( //, $data8 );
        my $sum2  = 0;
        for ( my $m = 7 ; $m >= 0 ; $m-- ) { $sum2 = $sum2 + $data[$m]; }
        if   ( $sum2 % 2 == 0 ) { $parity[1] = 1 }
        else                    { $parity[1] = 0 }

        printVector(
"\*000* $tsetWrite;           \"$cycle_count  START Write $data_addr[4] $data_addr[3]$data_addr[2]$data_addr[1]$data_addr[0]\: $data[0]$data[1]$data[2]$data[3] $data[4]$data[5]$data[6]$data[7]\""
        );
        printVector("\*100* $tsetWrite;           \"$cycle_count  \"");
        printVector("\*000* $tsetWrite;           \"$cycle_count  \"");
        printVector(
            "*$slave_addr[3]10* $tsetWrite;           \"$cycle_count  SA3\"");
        printVector(
            "*$slave_addr[2]10* $tsetWrite;           \"$cycle_count  SA2\"");
        printVector(
            "*$slave_addr[1]10* $tsetWrite;           \"$cycle_count  SA1\"");
        printVector(
            "*$slave_addr[0]10* $tsetWrite;           \"$cycle_count  SA0\"");
        printVector(
"*$write_read[2]10* $tsetWrite;           \"$cycle_count  Write_cmd 2\""
        );
        printVector(
"*$write_read[1]10* $tsetWrite;           \"$cycle_count  Write_cmd 1\""
        );
        printVector(
"*$write_read[0]10* $tsetWrite;           \"$cycle_count  Write_cmd 0\""
        );

        for ( my $m = 4 ; $m >= 0 ; $m-- ) {
            printVector(
"*$data_addr[$m]10* $tsetWrite;           \"$cycle_count  data_Addr Bit Num $m  $_\""
            );
        }
        printVector(
            "*$parity[0]10* $tsetWrite;           \"$cycle_count  parity[0]  \""
        );

        for ( my $m = 0 ; $m < 8 ; $m++ ) {
            printVector(
"*$data[$m]10* $tsetWrite;           \"$cycle_count  data Bit Num $m  $_\""
            );
        }
        printVector(
            "*$parity[1]10* $tsetWrite;           \"$cycle_count  parity[1]  \""
        );

        printVector("\*010* $tsetWrite;           \"$cycle_count  BusPark\"");

        printVector("\*010* $tsetWrite;           \"$cycle_count  STOP\"");
        printVector("\*010* $tsetWrite;           \"$cycle_count  \"");
        printVector("\*100* $tsetWrite;           \"$cycle_count  \"");
        printVector("\*100* $tsetWrite;           \"$cycle_count  \"");

        ######## end of write #################
        printVector(
"\*000* $tsetRead;           \"$cycle_count  START Read $data_addr[4] $data_addr[3]$data_addr[2]$data_addr[1]$data_addr[0]\: $data[0]$data[1]$data[2]$data[3] $data[4]$data[5]$data[6]$data[7]\""
        );
        printVector("\*100* $tsetRead;           \"$cycle_count  \"");
        printVector("\*000* $tsetRead;           \"$cycle_count  \"");
        printVector(
            "*$slave_addr[3]10* $tsetRead;           \"$cycle_count  SA3\"");
        printVector(
            "*$slave_addr[2]10* $tsetRead;           \"$cycle_count  SA2\"");
        printVector(
            "*$slave_addr[1]10* $tsetRead;           \"$cycle_count  SA1\"");
        printVector(
            "*$slave_addr[0]10* $tsetRead;           \"$cycle_count  SA0\"");
        printVector(
"*$write_read[2]10* $tsetRead;           \"$cycle_count  Read_cmd 2\""
        );
        printVector(
"*$write_read[1]10* $tsetRead;           \"$cycle_count  Read_cmd 1\""
        );
        printVector(
            "*$read_bit[0]10* $tsetRead;           \"$cycle_count  Read_cmd 0\""
        );

        for ( my $m = 4 ; $m >= 0 ; $m-- ) {
            printVector(
"*$data_addr[$m]10* $tsetRead;           \"$cycle_count  data_Addr Bit Num $m  $_\""
            );
        }
        printVector(
"*$parity_read[0]10* $tsetRead;           \"$cycle_count  parity_read  \""
        );
        printVector("\*010* $tsetRead;           \"$cycle_count  BusPark\"");

        for ( my $m = 0 ; $m < 8 ; $m++ ) {

            if ( $data[$m] == 0 ) {
                printVector(
"\*L10\* $tsetRead;           \"$cycle_count  Data Bit Num: $m  $_\""
                );
            } elsif ( $data[$m] == 1 ) {
                printVector(
"\*H10\* $tsetRead;           \"$cycle_count  Data Bit Num: $m  $_\""
                );
            }
        }

        printVector("\*010* $tsetWrite;           \"$cycle_count  STOP\"");
        printVector("\*010* $tsetWrite;           \"$cycle_count  \"");
        printVector("\*100* $tsetWrite;           \"$cycle_count  \"");
        printVector("\*100* $tsetWrite;           \"$cycle_count  \"");

    }
}

=head2 printVector

 printVector and increase cycle number

=cut

fun printVector (Str $vector)
{
    say $uno $vector;
    ++$cycle_count;
}

=head2 printUno

 print str to uno file

=cut

fun printUno (Str $str)
{
    say $uno $str;
}

=head2 replace01withLH

 replace 0/1 to L/H for read data

=cut

fun replace01withLH (ArrayRef $dataref, Int $start, Int $len)
{
    for my $idx ( $start .. $start + $len - 1 ) {
        $dataref->[$idx] =~ s/0/L/;
        $dataref->[$idx] =~ s/1/H/;
    }
    say @$dataref;
}

=head2 getTimeSet

 return array for timeset

=cut

method getTimeSet (Int $read)
{
    my $bits = 3 + 23 + $read;
    my @tset = ($tsetWrite) x $bits;
    splice @tset, 17, 9, ($tsetRead) x 9 if $read;
    return @tset;
}

=head2 getClockArray

 return array for clock pin

=cut

fun getClockArray (Int $read)
{
    my $ones  = 23 + $read;
    my $zeros = 3;
    my $str   = "0" x $zeros . '1' x $ones;
    return split //, $str;
}

=head2 getDataArray

 return array for data pin

=cut

fun getDataArray (Str $reg, Int $read)
{
    my @data = split //, sprintf( "%020b", hex($reg) );

    # set read/write cmd
    splice @data, 4, 3, ( 0, 1, $read );

    # add parity for data
    push @data, oddParity( @data[ 12 .. 19 ] );

    # replace data and parity with expected logic if read
    &replace01withLH( \@data, 12, 9 ) if $read;

    # add bus park
    push @data, 0;

    # bus park if read
    splice @data, 12, 0, 0 if $read;

    # add sequence start condition
    unshift @data, qw(0 1 0);

    # add parity for cmd
    splice @data, 15, 0, oddParity( @data[ 3 .. 14 ] );

    return @data;
}

=head2 oddParity

 calculate odd parity bit for given array

=cut

fun oddParity (@data)
{
    my $num = grep /1/, @data;
    return ( $num + 1 ) % 2;
}

=head2 regRW

 transform register write/read to unison pattern

=cut

fun regRW ( Str $reg, $read)
{
    my @data  = &getDataArray( $reg, $read );
    my @clock = &getClockArray($read);
    my @tset  = &getTimeSet($read);

    my $total20_decimal = hex($reg);
    my $total20_temp    = sprintf( "%016b", $total20_decimal );

    my @total20_bit_temp = split( //, $total20_temp );

    my $length_total20_temp = @total20_bit_temp;
    my $total20;
    if ( $length_total20_temp == 19 ) {
        $total20 = "0" . $total20_temp;
    } elsif ( $length_total20_temp == 18 ) {
        $total20 = "00" . $total20_temp;
    } elsif ( $length_total20_temp == 17 ) {
        $total20 = "000" . $total20_temp;
    } elsif ( $length_total20_temp == 16 ) {
        $total20 = "0000" . $total20_temp;
    } else {
        $total20 = $total20_temp;
    }

    my @total20_bit    = split( //, $total20 );
    my $length_total20 = @total20_bit;

    my @write_read;
    ++$write_count;

    $slave_addr[3] = $total20_bit[0];
    $slave_addr[2] = $total20_bit[1];
    $slave_addr[1] = $total20_bit[2];
    $slave_addr[0] = $total20_bit[3];

    $write_read[2] = 0;
    $write_read[1] = 1;
    $write_read[0] = 0;

    # from LSB to MSB
    for ( my $m = 4 ; $m >= 0 ; $m-- ) {
        my $j = 11 - $m;
        $data_addr[$m] = $total20_bit[$j];
    }

    for ( my $m = 7 ; $m >= 0 ; $m-- ) {
        my $j = 19 - $m;
        $data[$m] = $total20_bit[$j];
    }

    my $sum1 =
      $slave_addr[3] +
      $slave_addr[2] +
      $slave_addr[1] +
      $slave_addr[0] +
      $write_read[2] +
      $write_read[1] +
      $write_read[0] +
      $data_addr[4] +
      $data_addr[3] +
      $data_addr[2] +
      $data_addr[1] +
      $data_addr[0];

    my $sum2 = 0;
    for ( my $m = 7 ; $m >= 0 ; $m-- ) { $sum2 = $sum2 + $data[$m]; }

    if   ( $sum1 % 2 == 0 ) { $parity[0] = 1 }
    else                    { $parity[0] = 0 }

    if   ( $sum2 % 2 == 0 ) { $parity[1] = 1 }
    else                    { $parity[1] = 0 }

    printVector(
"\*000* $tsetWrite;           \"$cycle_count  START Write $data_addr[4]$data_addr[3]$data_addr[2]$data_addr[1]$data_addr[0]\: $data[7]$data[6]$data[5]$data[4]$data[3]$data[2]$data[1]$data[0]\""
    );
    printVector("\*100* $tsetWrite;           \"$cycle_count  \"");
    printVector("\*000* $tsetWrite;           \"$cycle_count  \"");
    printVector(
        "*$slave_addr[3]10* $tsetWrite;           \"$cycle_count  SA3\"");
    printVector(
        "*$slave_addr[2]10* $tsetWrite;           \"$cycle_count  SA2\"");
    printVector(
        "*$slave_addr[1]10* $tsetWrite;           \"$cycle_count  SA1\"");
    printVector(
        "*$slave_addr[0]10* $tsetWrite;           \"$cycle_count  SA0\"");

    printVector(
        "*$write_read[2]10* $tsetWrite;           \"$cycle_count  Write_cmd 2\""
    );
    printVector(
        "*$write_read[1]10* $tsetWrite;           \"$cycle_count  Write_cmd 1\""
    );
    printVector(
        "*$write_read[0]10* $tsetWrite;           \"$cycle_count  Write_cmd 0\""
    );

    for ( my $m = 4 ; $m >= 0 ; $m-- ) {
        printVector(
"*$data_addr[$m]10* $tsetWrite;           \"$cycle_count  data_Addr Bit Num $m  $_\""
        );
    }
    printVector(
        "*$parity[0]10* $tsetWrite;           \"$cycle_count  parity[1]  \"");

    for ( my $m = 7 ; $m >= 0 ; $m-- ) {
        printVector(
"*$data[$m]10* $tsetWrite;           \"$cycle_count  data Bit Num $m  $_\""
        );
    }

    printVector(
        "*$parity[1]10* $tsetWrite;           \"$cycle_count  parity[2]  \"");

    printVector("\*010* $tsetWrite;           \"$cycle_count  BusPark\"");

    printVector("\*010* $tsetWrite;           \"$cycle_count  STOP\"");
    printVector("\*010* $tsetWrite;           \"$cycle_count  \"");
    printVector("\*000* $tsetWrite;           \"$cycle_count  \"");
    printVector("\*000* $tsetWrite;           \"$cycle_count  \"");
}

=head1 AUTHOR

Alan Liang, C<< <alan.cprc at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-mipipatterngenerator at rt.cpan.org>, or through
the web interface at L<https://rt.cpan.org/NoAuth/ReportBug.html?Queue=MipiPatternGenerator>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc MipiPatternGenerator


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<https://rt.cpan.org/NoAuth/Bugs.html?Dist=MipiPatternGenerator>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/MipiPatternGenerator>

=item * CPAN Ratings

L<https://cpanratings.perl.org/d/MipiPatternGenerator>

=item * Search CPAN

L<https://metacpan.org/release/MipiPatternGenerator>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2020 by Alan Liang.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)


=cut

no Moose;
__PACKAGE__->meta->make_immutable;

1;    # End of MipiPatternGenerator
