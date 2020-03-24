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

has 'debug'  => ( is => 'rw', default => 0 );
has 'dutNum' => ( is => 'rw', default => 1 );

=head2 generate

 generate unison pattern file from given pseudo pattern file.

=cut

method generate (Str $file)
{
    &validateInputFile($file);
    my @ins = &parsePseudoPatternLegacy($file);

    &openUnoFile($file);

    $self->printHeader($file);

    for (@ins) {
        if (/0x(\S+)W$/) {
            $self->regWrite($1);
        } elsif (/0x(\S+)R$/) {
            $self->regRead($1);
        } elsif (/0x(\S+)WR256$/) {
            $self->regWriteRead256Bytes($1);
        } elsif ( !/wait/ and /^\s*(\w+)\s*$/ ) {

            # label
            printUno("\$$1");
        }
    }

    &closeUnoFile();
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

fun validateInputFile (Str $file)
{
    die "invalid suffix '.uno', please rename the suffix and try again"
      if $file =~ /.*\.uno$/;
}

=head2 openUnoFile

=cut

fun openUnoFile ($file)
{
    my $fn = $file;
    $fn =~ s/(.*)\.\w+/$1.uno/;

    open( $uno, ">", $fn );
}

=head2 closeUnoFile

=cut

fun closeUnoFile ()
{
    printUno("}");
    close $uno;
}

=head2 getPatternName

=cut

fun getPatternName ($file)
{
    my $fn = basename($file);
    $fn =~ s/(.*)\.\w+/$1/;
    return $fn;
}

=head2 printHeader()

 print header for unison pattern file.

=cut

method printHeader ($file)
{
    my $patternName = &getPatternName($file);

    &printUno("Unison:SyntaxRevision6.310000;");
    &printUno("Pattern $patternName {");
    &printUno("Mode MixedSignal;");
    &printUno("AliasMap \"DefaultAliasMap\";");
    &printUno("Type Generic;\n");

    my $pinlist = join( "+", $self->getPinList() );
    &printUno("PinList = \"$pinlist\";\n");

    #print $uno "CaptureRef MipiCapture = \"DATA_pin\";\n";
    #print $uno "RegSendRef MipiSend = \"DATA_pin+FX_TRIGGER_pin\";\n";
    #print $uno "SyncRef { PatRfTrig }\n\n";

    #print $uno "Default SignalHeader $pattern_name\_SH;\n";
    #print $uno "Default WaveformTable $pattern_name\_WFTRef;\n\n";

    #print $uno "\$start\n";
}

=head2 parsePseudoPatternLegacy

 read pseudo pattern file

=cut

fun parsePseudoPatternLegacy ($inputfile)
{
    open( my $fh, "<", $inputfile ) or die "$inputfile doesn't exist.";
    my @data = <$fh>;
    close $fh;

    chomp @data;

    return @data;
}

=head2 regWrite

 write data to single register at given address

=cut

method regWrite ($reg)
{
    my $read = 0;
    return $self->regRW( $reg, $read );
}

=head2 regRead

 read single register data at given address

=cut

method regRead ($reg)
{
    my $read = 1;
    return $self->regRW( $reg, $read );
}

=head2 increaseRegData

 increase register data only

=cut

fun increaseRegData (Ref $ref)
{
    return 0 if $$ref =~ /FF$/i;
    my $dec = hex($$ref);
    ++$dec;
    $$ref = sprintf( "%X", $dec );
}

=head2 regWriteRead256Bytes

 write data 0x00 to 0xff to a same address and then read back

=cut

method regWriteRead256Bytes ($reg)
{
    $self->regWrite($reg);
    $self->regRead($reg);

    while ( &increaseRegData( \$reg ) ) {
        $self->regWrite($reg);
        $self->regRead($reg);
    }
}

=head2 printVectors

=cut

fun printVectors (ArrayRef $ref)
{
    printVector($_) for @$ref;
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

=head2 getTimeSetArray

 return array for timeset

=cut

method getTimeSetArray (Int $read)
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

=head2 getCommentArray

=cut

fun getCommentArray (Int $read, Str $reg="")
{
    my @comment;
    if ($read) {
        @comment = qw( SSC SSC SSC SlaveAddr3 SlaveAddr2 SlaveAddr1 SlaveAddr0
          Command2 Command1 Command0
          DataAddr4 DataAddr3 DataAddr2 DataAddr1 DataAddr0 Parity1 BusPark
          Data7 Data6 Data5 Data4 Data3 Data2 Data1 Data0 Parity2 BusPark);
    } else {
        @comment = qw( SSC SSC SSC SlaveAddr3 SlaveAddr2 SlaveAddr1 SlaveAddr0
          Command2 Command1 Command0
          DataAddr4 DataAddr3 DataAddr2 DataAddr1 DataAddr0 Parity1
          Data7 Data6 Data5 Data4 Data3 Data2 Data1 Data0 Parity2 BusPark);
    }
    $comment[0] .= " $reg" if $reg;

    return @comment;
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

method regRW ( Str $reg, $read)
{
    my @data    = &getDataArray( $reg, $read );
    my @clock   = &getClockArray($read);
    my @tset    = $self->getTimeSetArray($read);
    my @comment = &getCommentArray($read);

    die "size not match" unless $#data == $#clock and $#data == $#tset;

    # add Read/Write register value to comment
    my $cmt = $read ? "read" : "write";
    $comment[0] .= " Start to $cmt $reg";

    my @vec;
    for my $i ( 0 .. $#data ) {
        my $vec = '*';
        $vec .= $data[$i];
        $vec .= $clock[$i];
        $vec .= "0";
        $vec .= '* ';
        $vec .= $tset[$i];
        $vec .= '; ';
        $vec .= "\"$comment[$i]\"";
        push @vec, $vec;
    }
    &printVectors( \@vec );
}

=head2 setPinName

=cut

method setPinName (Str $clock, Str $data, $dut = 1)
{
    $self->{'dut'}->[ $dut - 1 ]->{"clock"} = $clock;
    $self->{'dut'}->[ $dut - 1 ]->{"data"}  = $data;
}

=head2 getPinName

=cut

method getPinName ($dut = 1)
{
    return (
        $self->{'dut'}->[ $dut - 1 ]->{"clock"},
        $self->{'dut'}->[ $dut - 1 ]->{"data"}
    );
}

=head2 addTriggerPin

=cut

method addTriggerPin (Str $name)
{
    $self->{'trigger'} = $name;
}

=head2 getTriggerPin

=cut

method getTriggerPin ()
{
    return $self->{'trigger'} if $self->{'trigger'};
}

=head2 addExtraPin

=cut

method addExtraPin (Str $name, Str $data)
{
    push @{ $self->{'pin'} }, { name => $name, data => $data };
}

=head2 getExtraPins

=cut

method getExtraPins ()
{
    my @pin;
    for my $ref ( @{ $self->{'pin'} } ) {
        push @pin, $ref->{'name'};
    }
    return @pin;
}

=head2 getDutNum

=cut

method getDutNum ()
{
    my $num = @{ $self->{'dut'} };
    return $num;
}

=head2 getPinList

=cut

method getPinList ()
{
    my @pins;
    for my $dut ( @{ $self->{'dut'} } ) {
        push @pins, $dut->{'clock'};
        push @pins, $dut->{'data'};
    }

    push @pins, $self->getTriggerPin() if $self->getTriggerPin();
    push @pins, $self->getExtraPins();
    return @pins;
}

=head2 BUILD

 called after constructor by Moose

=cut

method BUILD ($var)
{
    $self->setPinName( "CLK_pin", "DATA_pin" );
}

=head2 gen

 generate Unison pattern file from pseudo directive with new syntax.

=cut

method gen(Str $file)
{
    &validateInputFile($file);
    my @ins = $self->parsePseudoPattern($file);

    &openUnoFile($file);

    $self->printHeader($file);

    $self->writeVectors(\@ins);

    &closeUnoFile();
}

=head2 writeVectors

=cut

method writeVectors (ArrayRef $ref)
{
    for (@$ref) {
        if (/(\w+):/) {
            &printUno("\$$1");    # label
        } elsif (/wait\s+(\d+)/i) {
            &printUno("wait $1 cycles");    # wait
        } elsif (/stop/i) {
            &printUno("stop");              # stop
        } elsif (/jmp\s+(\w+)/i) {
            &printUno("jmp to $1");         # jmp
        } elsif (/trig/i) {
            &printUno("trigger");           # trigger
        } elsif (/(\w+)/) {
            &printUno("state: $1");     # read/write
            $self->getVectorData($1);
        }
    }
}

=head2 getVectorData

=cut

method getVectorData(Str $reg)
{
    $reg =~ s/\s+//g;
    my @reg = split /,/, $reg;
    while (@reg < $self->dutNum) {
        push @reg, "nop";
    }
    printUno("@reg");
}

=head2 getIdleVectorData

=cut

method getIdleVectorData($trigger)
{
    my $vec;
    $vec .= "00" x $self->dutNum;
    $vec .= $trigger ? "1" : "0" if $self->getTriggerPin();

    for my $ref ( @{ $self->{'pin'} } ) {
        $vec .= $ref->{'data'};
    }

    return $vec;
}

=head2 parsePseudoPattern

 read pseudo pattern file, translate states to register read/write operation by
 lookup the register table

=cut

method parsePseudoPattern($file)
{
    open( my $fh, "<", $file ) or die "$file doesn't exist.";
    my @data = <$fh>;
    close $fh;

    chomp @data;
    die "$file is empty!" unless @data;

    # dut number
    my $line = shift @data;
    die unless $line =~ /^DUT:/;
    $self->dutNum(scalar split /,/, $line);

    # clock
    $line = shift @data;
    die unless $line =~ /^ClockPinName:/;
    $line =~ s/\s//g;
    $line =~ s/.*://g;
    my @clockpins = split /,/, $line;

    # data
    $line = shift @data;
    die unless $line =~ /^DataPinName:/;
    $line =~ s/\s//g;
    $line =~ s/.*://g;
    my @datapins = split /,/, $line;

    die "clock/data pin number not match!" unless @clockpins == @datapins;
    for my $i ( 0 .. @clockpins - 1 ) {
        $self->setPinName( $clockpins[$i], $datapins[$i], $i + 1 );
    }

    # trigger
    $line = shift @data;
    die unless $line =~ /^TriggerPinName:/;
    $line =~ s/\s//g;
    $line =~ s/.*://g;
    my $trigger = $line;
    $self->addTriggerPin($trigger) unless $trigger eq "None";

    # extra
    $line = shift @data;
    die unless $line =~ /^ExtraPinName:/;
    $line =~ s/\s//g;
    $line =~ s/.*://g;
    my @extra = split /,/, $line;
    for (@extra) {
        my ($pin, $value) = split /=/;
        $self->addExtraPin($pin, $value);
    }
    return @data;
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
