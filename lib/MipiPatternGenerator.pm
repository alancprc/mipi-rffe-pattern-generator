package MipiPatternGenerator;

use 5.010001;
use strict;
use warnings;

use File::Basename;
use File::Spec;
use List::Util qw(max min);

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
   Label: labelA           - optional
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

=head1 SYNOPSIS

    use MipiPatternGenerator;

    my $mipi = MipiPatternGenerator->new();
    $mipi->setTimeSet($writeTset, $readTset);
    $mipi->generate("pattern.txt");

=head1 SUBROUTINES/METHODS

=cut

=head2 new

 constructor

=cut

sub new
{
    my $self = {};
    bless $self, "MipiPatternGenerator";
    $self->setPinName( "CLK_pin", "DATA_pin" );
    $self->setTimeSet( "tsetWrite", "tsetRead" );
    return $self;
}

=head2 dutNum

=cut

sub dutNum
{
    my ( $self, $num ) = @_;
    $self->{'dutNum'} = $num if $num;
    return $self->{'dutNum'};
}

=head2 generate

 generate unison pattern file from given pseudo pattern file.

=cut

sub generate
{
    my ( $self, $file ) = @_;

    &validateInputFile($file);
    my @ins = &parsePseudoPatternLegacy($file);

    $self->openUnoFile($file);

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
            $self->printUno("\$$1");
        }
    }

    $self->closeUnoFile();
}

=head2 setTimeSet

 set time set for write and read.

=cut

sub setTimeSet
{
    my ( $self, $writeTset, $readTset ) = @_;

    $self->{'tsetWrite'} = $writeTset;
    $self->{'tsetRead'}  = $readTset;
}

=head2 validateInputFile

 validate input file, die if input file is a .uno file.

=cut

sub validateInputFile
{
    my ($file) = @_;
    die "invalid suffix '.uno', please rename the suffix and try again"
      if $file =~ /.*\.uno$/;
}

=head2 openUnoFile

=cut

sub openUnoFile
{
    my ( $self, $file ) = @_;
    my $fn = $file;
    $fn =~ s/(.*)\.\w+/$1.uno/;

    open( my $fh, ">", $fn ) or die "$!";
    $self->{'fh'} = $fh;
}

=head2 closeUnoFile

=cut

sub closeUnoFile
{
    my $self = shift;

    $self->printUno("}");
    close $self->{'fh'};
}

=head2 getPatternName

=cut

sub getPatternName
{
    my $file = shift;

    my $fn = basename($file);
    $fn =~ s/(.*)\.\w+/$1/;
    return $fn;
}

=head2 printHeader()

 print header for unison pattern file.

=cut

sub printHeader
{
    my ( $self, $file ) = @_;

    my $patternName = &getPatternName($file);

    $self->printUno("Unison:SyntaxRevision6.310000;");
    $self->printUno("Pattern $patternName {");
    $self->printUno("Mode MixedSignal;");
    $self->printUno("AliasMap \"DefaultAliasMap\";");
    $self->printUno("Type Generic;\n");

    my $pinlist = join( "+", $self->getPinList() );
    $self->printUno("PinList = \"$pinlist\";\n");

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

sub parsePseudoPatternLegacy
{
    my $inputfile = shift;

    open( my $fh, "<", $inputfile ) or die "$!";
    my @data = <$fh>;
    close $fh;

    chomp @data;
    s/\R//g for @data;

    return @data;
}

=head2 regWrite

 write data to single register at given address

=cut

sub regWrite
{
    my ( $self, $reg ) = @_;

    my $read = 0;
    return $self->regRW( $reg, $read );
}

=head2 regRead

 read single register data at given address

=cut

sub regRead
{
    my ( $self, $reg ) = @_;
    my $read = 1;
    return $self->regRW( $reg, $read );
}

=head2 increaseRegData

 increase register data only

=cut

sub increaseRegData
{
    my $ref = shift;

    return 0 if $$ref =~ /FF$/i;
    my $dec = hex($$ref);
    ++$dec;
    $$ref = sprintf( "%X", $dec );
}

=head2 regWriteRead256Bytes

 write data 0x00 to 0xff to a same address and then read back

=cut

sub regWriteRead256Bytes
{
    my ( $self, $reg ) = @_;

    $self->regWrite($reg);
    $self->regRead($reg);

    while ( &increaseRegData( \$reg ) ) {
        $self->regWrite($reg);
        $self->regRead($reg);
    }
}

=head2 printVectors

=cut

sub printVectors
{
    my ( $self, $ref ) = @_;

    $self->printVector($_) for @$ref;
}

=head2 printVector

 printVector and increase cycle number

=cut

sub printVector
{
    my ( $self, $vector ) = @_;

    my $fh = $self->{'fh'};
    say $fh $vector;
}

=head2 printUno

 print str to uno file

=cut

sub printUno
{
    my ( $self, $str ) = @_;

    my $fh = $self->{'fh'};
    say $fh $str;
}

=head2 replace01withLH

 replace 0/1 to L/H for read data

=cut

sub replace01withLH
{
    my ( $dataref, $start, $len ) = @_;

    for my $idx ( $start .. $start + $len - 1 ) {
        $dataref->[$idx] =~ s/0/L/;
        $dataref->[$idx] =~ s/1/H/;
    }
}

=head2 getTimeSetArray

 return array for timeset

=cut

sub getTimeSetArray
{
    my ( $self, $read, $ext ) = @_;

    if ( $ext ) {

        # 3 ssc, 23/24 cmd, 1 stop cycle after bus park
        my $bits = 35 + $read + 1;
        my @tset = ( $self->{'tsetWrite'} ) x $bits;

        splice @tset, 25, 10, ( $self->{'tsetRead'} ) x 10 if $read;
        return @tset;
    }

    # 3 ssc, 23/24 cmd, 1 stop cycle after bus park
    my $bits = 3 + 23 + $read + 1;
    my @tset = ( $self->{'tsetWrite'} ) x $bits;

    splice @tset, 17, 9, ( $self->{'tsetRead'} ) x 9 if $read;
    return @tset;
}

=head2 getClockArray

 return array for clock pin

=cut

sub getClockArray
{
    my ( $read, $reg, $ext ) = @_;
    $reg = "" unless $reg;
    my $numZero = 3;
    my $numOne = 23;
    my $numIdle = 1;

    $numOne = 32 if $ext;

    return ("0") x ( $numZero + $numOne + $read + $numIdle ) if $reg eq "nop";

    my $str = "0" x $numZero . '1' x ( $numOne + $read ) . '0';
    return split //, $str;
}

=head2 getDataArray

 return array for data pin

=cut

sub getDataArray
{
    my ( $reg, $read, $ext ) = @_;

    return &getClockArray( $read, $reg, $ext ) if $reg eq "nop";

    my @bits = split //, sprintf( "%020b", hex($reg) );
    my @sa   = @bits[ 0 .. 3 ];
    my @addr = @bits[ 4 .. 11 ];
    my @data = @bits[ 12 .. 19 ];
    my @result;

    # SSC
    @result[ 0 .. 2 ] = qw(0 1 0);

    # SA
    @result[ 3 .. 6 ] = @sa;

    if ($ext) {

        # CMD
        @result[ 7 .. 10 ] = ( 0, 0, $read, 0 );

        # BC
        @result[11 .. 14] = ( 0, 0, 0, 0);

        # parity for cmd
        $result[15] = oddParity( @result[ 3 .. 14 ] );

        # Addr
        @result[16..23] = @addr;
        $result[24] =  oddParity( @addr );

        # Data
        @result[25.. 32] = @data;
        $result[33] =  oddParity( @data );

        # replace data and parity with expected logic if read
        &replace01withLH( \@result, 25, 9 ) if $read;

        # add bus park
        push @result, 0;

        # add extra idle after bus park
        push @result, 0;

        # bus park if read
        splice @result, 25, 0, 0 if $read;

        return @result;
    }

    # CMD
    @result[ 7 .. 9 ] = ( 0, 1, $read );

    # Addr
    @result[ 10 .. 14 ] = @addr[ 3 .. 7 ];

    # parity for cmd
    $result[15] = oddParity( @result[ 3 .. 14 ] );

    # Data
    @result[16.. 23] = @data;
    $result[24] =  oddParity( @data );

    # replace data and parity with expected logic if read
    &replace01withLH( \@result, 16, 9 ) if $read;

    # add bus park
    push @result, 0;

    # add extra idle after bus park
    push @result, 0;

    # bus park if read
    splice @result, 16, 0, 0 if $read;

    return @result;
}

=head2 getCommentArray

=cut

sub getCommentArray
{
    my ( $read, $reg, $ext ) = @_;
    $reg = "" unless $reg;

    my @comment;
    if ($ext) {
        @comment = qw(
          SSC SSC SSC
          SlaveAddr3 SlaveAddr2 SlaveAddr1 SlaveAddr0
          Command3 Command2 Command1 Command0
          ByteCount3 ByteCount2 ByteCount1 ByteCount0
          ParityCmd
          DataAddr7 DataAddr6 DataAddr5 DataAddr4
          DataAddr3 DataAddr2 DataAddr1 DataAddr0
          ParityAddr
          Data7 Data6 Data5 Data4 Data3 Data2 Data1 Data0
          ParityData BusPark);
        splice @comment, 25, 0, "BusPark" if $read;
    } else {
        @comment = qw(
          SSC SSC SSC SlaveAddr3 SlaveAddr2 SlaveAddr1 SlaveAddr0
          Command2 Command1 Command0
          DataAddr4 DataAddr3 DataAddr2 DataAddr1 DataAddr0 Parity1
          Data7 Data6 Data5 Data4 Data3 Data2 Data1 Data0 Parity2 BusPark);
        splice @comment, 16, 0, "BusPark" if $read;
    }
    $comment[0] .= " $reg" if $reg;

    # add comment for stop cycle after bus park
    push @comment, "";

    return @comment;
}

=head2 oddParity

 calculate odd parity bit for given array

=cut

sub oddParity
{
    my @data = @_;

    my $num = grep /1/, @data;
    return ( $num + 1 ) % 2;
}

=head2 regRW

 transform register write/read to unison pattern

=cut

sub regRW
{
    my ( $self, $reg, $read ) = @_;

    my @data    = &getDataArray( $reg, $read );
    my @clock   = &getClockArray($read);
    my @tset    = $self->getTimeSetArray($read);
    my @comment = &getCommentArray($read);

    die "clock/data/tset size not match."
      unless $#data == $#clock and $#data == $#tset;

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
    $self->printVectors( \@vec );
}

=head2 setPinName

 set clock/data pin name for dut.
 the dut number starts from 1.

=cut

sub setPinName
{
    my ( $self, $clock, $data, $dut ) = @_;
    $dut = 1 unless $dut;

    $self->{'dut'}->[ $dut - 1 ]->{"clock"} = $clock;
    $self->{'dut'}->[ $dut - 1 ]->{"data"}  = $data;
}

=head2 getPinName

 get clock/data pin name for dut.
 the dut number starts from 1.

=cut

sub getPinName
{
    my ( $self, $dut ) = @_;
    $dut = 1 unless $dut;

    return (
        $self->{'dut'}->[ $dut - 1 ]->{"clock"},
        $self->{'dut'}->[ $dut - 1 ]->{"data"}
    );
}

=head2 addTriggerPin

=cut

sub addTriggerPin
{
    my ( $self, $name ) = @_;

    $self->{'trigger'} = $name;
}

=head2 getTriggerPin

=cut

sub getTriggerPin
{
    my $self = shift;

    return $self->{'trigger'} if $self->{'trigger'};
}

=head2 addExtraPin

=cut

sub addExtraPin
{
    my ( $self, $name, $data ) = @_;

    push @{ $self->{'pin'} }, { name => $name, data => $data };
}

=head2 getExtraPins

=cut

sub getExtraPins
{
    my $self = shift;

    my @pin;
    for my $ref ( @{ $self->{'pin'} } ) {
        push @pin, $ref->{'name'};
    }
    return @pin;
}

=head2 getDutNum

=cut

sub getDutNum
{
    my $self = shift;

    my $num = @{ $self->{'dut'} };
    return $num;
}

=head2 getPinList

=cut

sub getPinList
{
    my $self = shift;

    my @pins;
    for my $dut ( @{ $self->{'dut'} } ) {
        push @pins, $dut->{'clock'};
        push @pins, $dut->{'data'};
    }

    push @pins, $self->getTriggerPin() if $self->getTriggerPin();
    push @pins, $self->getExtraPins();
    return @pins;
}

=head2 gen

 generate Unison pattern file from pseudo directive with new syntax.

=cut

sub gen
{
    my ( $self, $file ) = @_;

    &validateInputFile($file);
    my @ins = $self->parsePseudoPattern($file);

    $self->openUnoFile($file);

    $self->printHeader($file);

    $self->writeVectors( \@ins );

    $self->closeUnoFile();
}

=head2 writeVectors

=cut

sub writeVectors
{
    my ( $self, $ref ) = @_;

    for (@$ref) {
        if (/^Label:\s*(\w+)/) {    # label
            $self->printUno("\$$1");
        } elsif (/^\s*wait\s*(\d+)*/i) {
            my $ins = $1 ? "<RPT $1>" : "";
            $self->printDataInsComment( $self->getIdleVectorData, $ins,
                "wait" );
        } elsif (/^\s*stop/i) {
            $self->printDataInsComment( $self->getIdleVectorData, "<STOP>",
                "stop" );
        } elsif (/^\s*jmp\s+(\w+)/i) {
            $self->printDataInsComment( $self->getIdleVectorData, "<JMP $1>",
                "jump" );
        } elsif (/^\s*trig/i) {
            $self->printTriggerVector();
        } elsif (/^(R:)?\s*(\w+\s*(?:,\s*\w+)*)/) {
            my $read = $1 ? 1 : 0;
            $self->writeSingleInstruction( $2, $read );    # read/write
        }
    }
}

=head2 printDataInsComment

=cut

sub printDataInsComment
{
    my ( $self, $data, $ins, $cmt, $tset ) = @_;
    $tset = $self->{'tsetWrite'} unless $tset;

    my $str = join( '', '*', $data, '* ', $tset, '; ', $ins );
    my $num = $self->getPinList() + 30;
    $str = sprintf( "%-${num}s", $str );
    $str .= ' "' . $cmt . '"';

    $self->printUno($str);
}

=head2 writeSingleInstruction

 write read/write mipi operation segment into pattern file

=cut

sub writeSingleInstruction
{
    my ( $self, $ins, $read ) = @_;

    # pading with nop if regs is less than dut number
    $ins =~ s/\s+//g;
    my @ins = split /,/, $ins;
    die "column number '@ins' more than dut number " . $self->dutNum . "."
      if @ins > $self->dutNum;
    while ( @ins < $self->dutNum ) {
        push @ins, "nop";
    }

    my @registers = $self->translateInsToRegs(@ins);

    &alignRegWithNop( \@registers );

    &transposeArrayOfArray( \@registers );

    for my $reg (@registers) {
        $self->writeSingleRegister( $reg, \@ins, $read );
    }
}

=head2 writeSingleRegister

=cut

sub writeSingleRegister
{
    my ( $self, $regref, $insref, $read ) = @_;

    my @vecs;
    my @cmt;
    my $extended = grep { &isExtended($_) } @$regref;
    for my $dut ( 0 .. $self->dutNum - 1 ) {
        my $reg = $regref->[$dut];

        my @clock = &getClockArray( $read, $reg, $extended );
        my @data  = &getDataArray( $reg, $read, $extended );

        $vecs[ 2 * $dut ] = \@clock;
        $vecs[ 2 * $dut + 1 ] = \@data;

        $cmt[$dut] =
          sprintf( "%d:%s:%s", $dut + 1, $insref->[$dut], $regref->[$dut] );
    }
    my @tset    = $self->getTimeSetArray($read, $extended);
    my @comment = &getCommentArray( $read, "@cmt", $extended );

    &transposeArrayOfArray( \@vecs );
    $self->addTriggerPinData( \@vecs );
    $self->addExtraPinData( \@vecs );
    $self->printVectorData( \@vecs, \@tset, \@comment );
}

=head2 printVectorData

 print vector data to uno file

  0101          "comment"
 *0101* tset;   "comment"

=cut

sub printVectorData
{
    my ( $self, $dataref, $tsetref, $cmtref ) = @_;

    for my $i ( 0 .. $#$dataref ) {
        my $data = join '', @{ $dataref->[$i] };
        my $str  = sprintf( "*%s* %s; %-18s \"%s\"",
            $data, $tsetref->[$i], "", $cmtref->[$i] );
        $self->printUno($str);
    }
}

=head2 print

=head2 addTriggerPinData

=cut

sub addTriggerPinData
{
    my ( $self, $ref ) = @_;

    if ( $self->getTriggerPin() ) {
        push @$_, "0" for @$ref;
    }
}

=head2 addExtraPinData

=cut

sub addExtraPinData
{
    my ( $self, $ref ) = @_;

    for my $pin ( @{ $self->{'pin'} } ) {
        push @$_, $pin->{'data'} for @$ref;
    }
}

=head2 alignRegWithNop

 if the number of register among devices is not equal, make them equal by
 padding "nop".

=cut

sub alignRegWithNop
{
    my $ref = shift;

    # get max length
    my @length = map { scalar @{$_} } @$ref;
    my $maxlen = max(@length);

    # pad to max length
    for (@$ref) {
        push @{$_}, ("nop") x ( $maxlen - @{$_} );
    }
}

=head2 alignTimeSet

=cut

sub alignTimeSet
{
    my $ref = shift;

    my $maxlen = 0;
    my $maxidx = 0;
    my $i      = 0;
    for (@$ref) {
        my $len = @{$_};
        if ( $len > $maxlen ) {
            $maxlen = $len;
            $maxidx = $i;
        }
        ++$i;
    }
    return @{ $ref->[$maxidx] };
}

=head2 transposeArrayOfArray

 transpose array of columns to array of rows

=cut

sub transposeArrayOfArray
{
    my $ref = shift;

    my @new;
    for my $i ( 0 .. $#$ref ) {
        for my $j ( 0 .. $#{ $ref->[0] } ) {
            $new[$j][$i] = $ref->[$i]->[$j];
        }
    }
    @$ref = @new;
}

=head2 translateInsToRegs

 translate instruction to array of registers of all devices

=cut

sub translateInsToRegs
{
    my $self = shift;
    my @ins  = @_;
    my @registers;
    for my $dut ( 0 .. $self->dutNum - 1 ) {
        my @tmp = $self->lookupRegisters( $ins[$dut], $dut );
        $registers[$dut] = \@tmp;
    }
    return @registers;
}

=head2 lookupRegisters

 lookup register adress/data in register table.
 if the $ins matches '0xADDD', it's returned unchanged.
 $dutNum starts from 0.

 e.g.: GSM_HB_HPM => (0xE1C38, 0xE0001)

=cut

sub lookupRegisters
{
    my ( $self, $ins, $dutNum ) = @_;

    return $ins if $ins eq "nop";
    return $ins if $ins =~ /0x\w+/i;

    die "there's no $ins in registerTable."
      unless $self->{'table'}->[$dutNum]->{$ins};
    return @{ $self->{'table'}->[$dutNum]->{$ins} };
}

=head2 readRegisterTable

=cut

sub readRegisterTable
{
    my ( $self, $ref ) = @_;

    die "RegisterTable file number is not equal to dut number."
      unless $self->dutNum == @$ref;

    for my $dut ( 0 .. $self->dutNum - 1 ) {
        open my $fh, "<", $ref->[$dut] or die "$!";
        my @content = <$fh>;
        close $fh;

        # remove trailing new line
        chomp @content;
        s/\R//g for @content;

        my @addr = split /,/, shift @content;
        shift @addr;

        for (@content) {
            my @data = split /,/;
            my $name = shift @data;

            # concate address and data;
            for my $i ( 0 .. $#data ) {
                my $data = $data[$i];
                $data =~ s/0x//i;
                $data[$i] = $addr[$i] . $data;
            }
            $self->{'table'}->[$dut]->{$name} = \@data;
        }
    }
}

=head2 getIdleVectorData

=cut

sub getIdleVectorData
{
    my ( $self, $trigger ) = @_;
    $trigger = 0 unless $trigger;

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

sub parsePseudoPattern
{
    my ( $self, $file ) = @_;

    open( my $fh, "<", $file ) or die "$!";
    my @data = <$fh>;
    close $fh;

    chomp @data;
    s/\R//g for @data;

    @data = grep !/^\s*#|^\s*$/, @data;
    die "$file is empty!" unless @data;

    # dut number
    my $line = shift @data;
    die "missing 'DUT:' line in $file." unless $line =~ /^DUT:/;
    my $num = () = split /,/, $line, -1;
    $self->dutNum($num);

    # clock
    $line = shift @data;
    die "missing 'ClockPinName:' line in $file."
      unless $line =~ /^ClockPinName:/;
    $line =~ s/\s//g;
    $line =~ s/.*://g;
    my @clockpins = split /,/, $line;

    # data
    $line = shift @data;
    die "missing 'DataPinName:' line in $file." unless $line =~ /^DataPinName:/;
    $line =~ s/\s//g;
    $line =~ s/.*://g;
    my @datapins = split /,/, $line;

    die "clock/data pin number does not match!" unless @clockpins == @datapins;
    for my $i ( 0 .. @clockpins - 1 ) {
        $self->setPinName( $clockpins[$i], $datapins[$i], $i + 1 );
    }

    # trigger
    $line = shift @data;
    die "missing 'TriggerPinName:' line in $file."
      unless $line =~ /^TriggerPinName:/;
    $line =~ s/\s//g;
    $line =~ s/.*://g;
    my $trigger = $line;
    $self->addTriggerPin($trigger) unless $trigger eq "None";

    # extra
    $line = shift @data;
    die "missing 'ExtraPinName:' line in $file."
      unless $line =~ /^ExtraPinName:/;
    $line =~ s/\s//g;
    $line =~ s/.*://g;
    my @extra = split /,/, $line;
    for (@extra) {
        my ( $pin, $value ) = split /=/;
        $self->addExtraPin( $pin, $value );
    }

    # registerTable
    $line = shift @data;
    die "missing 'RegisterTable:' line in $file."
      unless $line =~ /^RegisterTable:/;
    $line =~ s/\s//g;
    $line =~ s/.*://g;
    my @regtable = split /,/, $line;
    $self->readRegisterTable( \@regtable );

    # waveform ref
    $line = shift @data;
    die "missing 'WaveformRefRead:' line in $file."
      unless $line =~ /^WaveformRefRead:/;
    $line =~ s/\s//g;
    $line =~ s/.*://g;
    my $read = $line;

    $line = shift @data;
    die "missing 'WaveformRefWrite' line in $file."
      unless $line =~ /^WaveformRefWrite:/;
    $line =~ s/\s//g;
    $line =~ s/.*://g;
    my $write = $line;

    $self->setTimeSet( $write, $read );

    return @data;
}

=head2 isExtended

=cut

sub isExtended
{
    my $reg = shift;
    return 1 if $reg =~ /0x\w[A-F2-9]\w{3,3}/i;
    return 0;
}

=head2 printTriggerVector

=cut

sub printTriggerVector
{
    my $self = shift;
    my $ins  = "";

    $ins = "[TRIG]" unless $self->getTriggerPin();
    $self->printDataInsComment( $self->getIdleVectorData(1), $ins, "trigger" );
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

1;    # End of MipiPatternGenerator
