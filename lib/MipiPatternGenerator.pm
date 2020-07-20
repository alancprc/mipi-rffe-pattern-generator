package MipiPatternGenerator;

use v5.14;    # minimum version supported by Function::Parameters
use strict;
use warnings;

use Function::Parameters;
use Types::Standard qw(Str Int ArrayRef RegexpRef Ref);
use JSON -convert_blessed_universally;
use File::Basename;
use File::Spec;
use File::Path qw(make_path remove_tree);
use Carp qw(croak carp);
use List::Util qw(max min);
use Config::General qw(ParseConfig);

use Exporter qw(import);
our @EXPORT = qw();

=head1 NAME

MipiPatternGenerator - generate mipi pattern for Unison

=head1 DESCRIPTION

Generate pattern from pattern.txt and registerN.csv file.
Multiple devices are Supported.

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    use MipiPatternGenerator;

    my $mipi = MipiPatternGenerator->new();
    $mipi->gen("pattern.txt");

=head1 SUBROUTINES/METHODS

=cut

=head2 new

 constructor.

=cut

fun new ($var)
{
    my $self = {};
    bless $self, "MipiPatternGenerator";
    return $self;
}

=head2 dutNum

 get/set DUT number.

=cut

method dutNum ($num = undef)
{
    $self->{'dutNum'} = $num if $num;
    return $self->{'dutNum'};
}

=head2 setTimeSet

 set time set for write and read.

=cut

method setTimeSet ($writeTset, $readTset)
{
    $self->{'tsetWrite'} = $writeTset;
    $self->{'tsetRead'}  = $readTset;
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

 open uno file to write.

=cut

method openUnoFile ($file)
{
    my $fn = $file;
    $fn =~ s/(.*)\.\w+/$1.uno/;

    open( my $fh, ">", $fn ) or die "fail to open $fn for write: $!";
    $self->{'fh'} = $fh;
}

=head2 closeUnoFile

 close uno file.

=cut

method closeUnoFile ()
{
    $self->printUno("}");
    close $self->{'fh'};
}

=head2 getPatternName

 return pattern name.

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
}

=head2 printUno

 print str to uno file.

=cut

method printUno (Str $str)
{
    my $fh = $self->{'fh'};
    say $fh $str;
}

=head2 replace01withLH

 replace 0/1 to L/H for read data.

=cut

fun replace01withLH (ArrayRef $dataref, Int $start, Int $len)
{
    for my $idx ( $start .. $start + $len - 1 ) {
        $dataref->[$idx] =~ s/0/L/;
        $dataref->[$idx] =~ s/1/H/;
    }
}

=head2 getTimeSetArray

 return timeset array.

=cut

method getTimeSetArray (@data)
{
    my %tset = (
        "0" => $self->{'tsetWrite'},
        "1" => $self->{'tsetWrite'},
        "H" => $self->{'tsetRead'},
        "L" => $self->{'tsetRead'},
        "X" => $self->{'tsetRead'}
    );
    my @result = map { $tset{$_} } @data;
    return @result;
}

=head2 getClockArray

 return clock array given data array.

=cut

fun getClockArray (@data)
{
    return @data unless $data[1];

    my @result = ("1") x $#data;
    @result[ 0 .. 2 ] = qw(0 0 0);
    push @result, "0";

    return @result;
}

=head2 getNopData

 return data/clock for no-operation.

=cut

fun getNopData ()
{
    return ("0");
}

=head2 getDataArrayReg0

 return data array for register 0 write mode.

=cut

fun getDataArrayReg0 (Str $reg)
{
    my @result;

    # SSC
    @result[ 0 .. 2 ] = qw(0 1 0);

    # SA
    @result[ 3 .. 6 ] = &getBits( 4, &getSlaveAddr($reg) );

    # CMD
    $result[7] = 1;

    # Data
    @result[ 8 .. 14 ] = &getBits( 7, &getRegData($reg) );

    # parity for cmd frame
    $result[15] = &oddParity( @result[ 3 .. 14 ] );

    # add bus park
    push @result, 0;

    # add extra idle after bus park
    push @result, 0;

    return @result;
}

=head2 getDataArrayExtended

 return data array for extended mode.

=cut

fun getDataArrayExtended (Str $reg, Int $read)
{
    my @addr = &getBits( 8, &getRegAddr($reg) );
    my @result;

    # SSC
    @result[ 0 .. 2 ] = qw(0 1 0);

    # SA
    @result[ 3 .. 6 ] = &getBits( 4, &getSlaveAddr($reg) );

    # CMD
    @result[ 7 .. 10 ] = ( 0, 0, $read, 0 );

    # BC
    my @bytes = &getRegData($reg);
    @result[ 11 .. 14 ] = split //, sprintf( "%04b", $#bytes );

    # parity for cmd
    $result[15] = &oddParity( @result[ 3 .. 14 ] );

    # Addr
    push @result, @addr;
    push @result, &oddParity(@addr);

    # bus park if read
    push @result, "0" if $read;

    # Data
    for my $byte (@bytes) {
        my @bits   = &getBits( 8, $byte );
        my $parity = &oddParity(@bits);
        push @result, @bits, &oddParity(@bits);

        # replace data and parity with expected logic if read
        &replace01withLH( \@result, -9, 9 ) if $read;
    }

    # add bus park
    push @result, $read ? "X" : "0";

    # add extra idle after bus park
    push @result, 0;

    return @result;
}

=head2 getDataArrayLong

 return data array for long mode.

=cut

fun getDataArrayLong (Str $reg, Int $read)
{
    my @addr = &getBits( 16, &getRegAddr($reg) );
    my @result;

    # SSC
    @result[ 0 .. 2 ] = qw(0 1 0);

    # SA
    @result[ 3 .. 6 ] = &getBits( 4, &getSlaveAddr($reg) );

    # CMD
    @result[ 7 .. 11 ] = ( 0, 0, 1, 1, $read );

    # BC
    my @bytes = &getRegData($reg);
    @result[ 12 .. 14 ] = split //, sprintf( "%03b", $#bytes );

    # parity for cmd
    $result[15] = &oddParity( @result[ 3 .. 14 ] );

    # Addr
    push @result, @addr[0..7];
    push @result, &oddParity(@addr[0..7]);
    push @result, @addr[8..15];
    push @result, &oddParity(@addr[8..15]);

    # bus park if read
    push @result, "0" if $read;

    # Data
    for my $byte (@bytes) {
        my @bits   = &getBits( 8, $byte );
        my $parity = &oddParity(@bits);
        push @result, @bits, &oddParity(@bits);

        # replace data and parity with expected logic if read
        &replace01withLH( \@result, -9, 9 ) if $read;
    }

    # add bus park
    push @result, $read ? "X" : "0";

    # add extra idle after bus park
    push @result, 0;

    return @result;
}

=head2 getDataArray

 return data array.

=cut

fun getDataArray (Str $reg, Int $read, Str $mode="")
{
    # for nop
    return &getNopData() if $reg eq "nop";

    # for register 0 write
    return &getDataArrayReg0($reg) if $mode eq "reg0";

    # for extended mode
    return &getDataArrayExtended( $reg, $read ) if $mode eq "extended";

    # for long mode
    return &getDataArrayLong( $reg, $read ) if $mode eq "long";

    # for register read/write mode
    my @result;

    # SSC
    @result[ 0 .. 2 ] = qw(0 1 0);

    # SA
    @result[ 3 .. 6 ] = &getBits( 4, &getSlaveAddr($reg) );

    # CMD
    @result[ 7 .. 9 ] = ( 0, 1, $read );

    # Addr
    @result[ 10 .. 14 ] = &getBits( 5, &getRegAddr($reg) );

    # parity for cmd
    $result[15] = &oddParity( @result[ 3 .. 14 ] );

    # bus park if read
    push @result, "0" if $read;

    # Data
    my @data = &getBits( 8, &getRegData($reg) );
    push @result, @data, &oddParity(@data);

    # replace data and parity with expected logic if read
    &replace01withLH( \@result, -9, 9 ) if $read;

    # add bus park
    push @result, $read ? "X" : "0";

    # add extra idle after bus park
    push @result, 0;

    return @result;
}

=head2 getCommentArray

 return comment array for given mipi mode.
 $bytes:
    byte count of register data, starts from 0.
 $mode:
    see getMipiMode

=cut

fun getCommentArray ( Int :$bytes=0, Int :$read=0, Str :$mode="")
{
    return &commentArrayReadWrite($read) unless $mode;
    return &commentArrayReg0() if $mode eq "reg0";
    return &commentArrayExtended( $read, $bytes ) if $mode eq "extended";
    return &commentArrayLong( $read, $bytes ) if $mode eq "long";
}

=head2 commentArrayReg0

 return comment array for resiter 0 write mode.

=cut

fun commentArrayReg0 ()
{
    my @result = qw(
      Write SSC SSC
      SlaveAddr3 SlaveAddr2 SlaveAddr1 SlaveAddr0
      Command0
      DataAddr6 DataAddr5 DataAddr4
      DataAddr3 DataAddr2 DataAddr1 DataAddr0
      ParityCmd
      BusPark);

    # add comment for stop cycle after bus park
    push @result, "";
    return @result;
}

=head2 commentArrayReadWrite

 return comment array for register read/write mode.

=cut

fun commentArrayReadWrite (Int $read=0)
{
    my @result = qw(
      Write SSC SSC
      SlaveAddr3 SlaveAddr2 SlaveAddr1 SlaveAddr0
      Command2 Command1 Command0
      DataAddr4 DataAddr3 DataAddr2 DataAddr1 DataAddr0
      ParityCmd
      Data7 Data6 Data5 Data4 Data3 Data2 Data1 Data0
      ParityData
      BusPark);

    splice @result, 16, 0, "BusPark" if $read;

    $result[0] = "Read" if $read;

    # add comment for stop cycle after bus park
    push @result, "";

    return @result;
}

=head2 commentArrayExtended

 return comment array for extended mode, $bytes starts from 0.

=cut

fun commentArrayExtended (Int $read=0, Int $bytes=0)
{
    my @result = qw(
      Write SSC SSC
      SlaveAddr3 SlaveAddr2 SlaveAddr1 SlaveAddr0
      Command3 Command2 Command1 Command0
      ByteCount3 ByteCount2 ByteCount1 ByteCount0
      ParityCmd
      DataAddr7 DataAddr6 DataAddr5 DataAddr4
      DataAddr3 DataAddr2 DataAddr1 DataAddr0
      ParityAddr);

    push @result, "BusPark" if $read;

    $result[0] = "Read" if $read;

    for ( 0 .. $bytes ) {
        push @result,
          qw (Data7 Data6 Data5 Data4 Data3 Data2 Data1 Data0 ParityData);
    }

    # add bus park
    push @result, "BusPark";

    # add comment for stop cycle after bus park
    push @result, "";

    return @result;
}

=head2 commentArrayLong

 return comment array for long mode, $bytes starts from 0.

=cut

fun commentArrayLong (Int $read=0, Int $bytes=0)
{
    my @result = qw(
      Write SSC SSC
      SlaveAddr3 SlaveAddr2 SlaveAddr1 SlaveAddr0
      Command4 Command3 Command2 Command1 Command0
      ByteCount2 ByteCount1 ByteCount0
      ParityCmd
      DataAddr15 DataAddr14 DataAddr13 DataAddr12
      DataAddr11 DataAddr10 DataAddr9 DataAddr8
      ParityAddr
      DataAddr7 DataAddr6 DataAddr5 DataAddr4
      DataAddr3 DataAddr2 DataAddr1 DataAddr0
      ParityAddr
      );

    push @result, "BusPark" if $read;

    $result[0] = "Read" if $read;

    for ( 0 .. $bytes ) {
        push @result,
          qw (Data7 Data6 Data5 Data4 Data3 Data2 Data1 Data0 ParityData);
    }

    # add bus park
    push @result, "BusPark";

    # add comment for stop cycle after bus park
    push @result, "";

    return @result;
}

=head2 oddParity

 calculate odd parity bit for given array.

=cut

fun oddParity (@data)
{
    my $num = grep /1/, @data;
    return ( $num + 1 ) % 2;
}

=head2 setPinName

 set clock/data pin name for given dut.
 dut number starts from 1.

=cut

method setPinName (Str $clock, Str $data, $dut = 1)
{
    $self->{'dut'}->[ $dut - 1 ]->{"clock"} = $clock;
    $self->{'dut'}->[ $dut - 1 ]->{"data"}  = $data;
}

=head2 getPinName

 get clock/data pin name for dut.
 dut number starts from 1.

=cut

method getPinName ($dut = 1)
{
    return (
        $self->{'dut'}->[ $dut - 1 ]->{"clock"},
        $self->{'dut'}->[ $dut - 1 ]->{"data"}
    );
}

=head2 setTriggerPin

 set trigger pin name.

=cut

method setTriggerPin (Str $name)
{
    $self->{'trigger'} = $name;
}

=head2 getTriggerPin

 get trigger pin name.

=cut

method getTriggerPin ()
{
    return $self->{'trigger'} if $self->{'trigger'};
}

=head2 addExtraPin

 add extra pin name with default state in pattern.

=cut

method addExtraPin (Str $name, Str $data)
{
    push @{ $self->{'pin'} }, { name => $name, data => $data };
}

=head2 getExtraPins

 return extra pins as a list.

=cut

method getExtraPins ()
{
    my @pin;
    for my $ref ( @{ $self->{'pin'} } ) {
        push @pin, $ref->{'name'};
    }
    return @pin;
}

=head2 getPinList

 return pinlist including clock/data for all DUTs, including trigger/extra pins
 if defined.

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

=head2 gen

 generate Unison pattern file from pseudo directive with new syntax.

=cut

method gen (Str $file)
{
    &validateInputFile($file);
    $self->parseConfigFile($file);
    my @ins = &getInstructions($file);

    $self->openUnoFile($file);

    $self->printHeader($file);

    $self->writeVectors( \@ins );

    $self->closeUnoFile();
}

=head2 writeVectors

 generate unison pattern according to pseudo pattern instructions.

=cut

method writeVectors (ArrayRef $ref)
{
    for (@$ref) {
        if (/^Label:\s*(\w+)/) {    # label
            $self->printUno("\$$1");
        } elsif (/^\s*wait\s*(gf)/i) {
            $self->printDataInsComment( $self->getIdleVectorData, "<COND !GF>",
                "wait for GF" );
            $self->printDataInsComment( $self->getIdleVectorData, "<CJMP .>",
                "wait for GF" );
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
        } elsif (/^\s*(R:|0:(?:00)?)?\s*(\w+\s*(?:,\s*\w+)*.*)$/) { # read/write

            # ms excel will turn '0:' to '0:00'
            my ( $read, $reg0, $mode, $ins ) = ( 0, 0, $1, $2 );
            $read = 1 if $mode and $mode =~ /R:/i;
            $reg0 = 1 if $mode and $mode =~ /0:/;
            $self->writeSingleInstruction(
                $ins,
                read => $read,
                reg0 => $reg0
            );
        }
    }
}

=head2 printDataInsComment

 print pattern data, micro-instruction, timeset and comment to uno file.

=cut

method printDataInsComment (Str $data, Str $ins, Str $cmt, Str $tset = $self->{'tsetWrite'})
{
    my $str = join( '', '*', $data, '* ', $tset, '; ', $ins );
    my $num = $self->getPinList() + 30;
    $str = sprintf( "%-${num}s", $str );
    $str .= ' "' . $cmt . '"';

    $self->printUno($str);
}

=head2 writeSingleInstruction

 write vectors for single read/write mipi instruction into pattern file.
 reg0: register 0 write mode shall be used when available.

=cut

method writeSingleInstruction (Str $ins, :$read, :$reg0)
{
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
        $self->writeSingleRegister( $reg, \@ins, read => $read, reg0 => $reg0 );
    }
}

=head2 writeSingleRegister

 write vectors for single read/write mipi register operation into pattern file.
 reg0: register 0 write mode shall be used when available.

=cut

method writeSingleRegister ( ArrayRef $regref, ArrayRef $insref, Int :$read, Int :$reg0 )
{

    my @vecs;
    my @description;
    my @timesets;
    my @comments;
    for my $dut ( 0 .. $self->dutNum - 1 ) {
        my $reg = $regref->[$dut];

        # set mode
        my $mode = &getMipiMode( $regref, $dut, reg0 => $reg0 );

        my @data  = &getDataArray( $reg, $read, $mode );
        my @clock = &getClockArray(@data);

        $vecs[ 2 * $dut ] = \@clock;
        $vecs[ 2 * $dut + 1 ] = \@data;

        my @tset = $self->getTimeSetArray(@data);
        $timesets[$dut] = \@tset;

        my @bytes = &getRegData($reg);
        my @comment;
        if ( $reg ne "nop" ) {
            @comment = &getCommentArray(
                read  => $read,
                mode  => $mode,
                bytes => $#bytes
            );
        }
        $comments[$dut] = \@comment;
    }
    my @timeset     = &mergeTimeSetArray( \@timesets );
    my $description = &getDescription( $insref, $regref );

    my @comment = &mergeComment( \@comments );
    $comment[0] .= " $description";

    &alignVectorData( \@vecs );
    &transposeArrayOfArray( \@vecs );
    $self->addTriggerPinData( \@vecs );
    $self->addExtraPinData( \@vecs );
    $self->printDataTsetComment( \@vecs, \@timeset, \@comment );
}

=head2 printDataTsetComment

 print vector data/time set/comment to uno file.

=cut

method printDataTsetComment (ArrayRef $dataref, ArrayRef $tsetref, ArrayRef $cmtref)
{
    for my $i ( 0 .. $#$dataref ) {
        my $data = join '', @{ $dataref->[$i] };
        my $str  = sprintf( "*%s* %s; %-18s \"%s\"",
            $data, $tsetref->[$i], "", $cmtref->[$i] );
        $self->printUno($str);
    }
}

=head2 addTriggerPinData

 add trigger pin data to vector array.

=cut

method addTriggerPinData ($ref)
{
    if ( $self->getTriggerPin() ) {
        push @$_, "0" for @$ref;
    }
}

=head2 addExtraPinData

 add extra pin data to vector array.

=cut

method addExtraPinData ($ref)
{
    for my $pin ( @{ $self->{'pin'} } ) {
        push @$_, $pin->{'data'} for @$ref;
    }
}

=head2 alignVectorData

 align vector data for all pins by padding "0".

=cut

fun alignVectorData (ArrayRef $ref)
{
    # get max length
    my @length = map { scalar @{$_} } @$ref;
    my $maxlen = max(@length);

    for (@$ref) {
        while ( @{$_} < $maxlen ) {
            push @{$_}, "0";
        }
    }
}

=head2 alignRegWithNop

 if the number of register among devices is not equal, make them equal by
 padding "nop".

=cut

fun alignRegWithNop (ArrayRef $ref)
{
    # get max length
    my @length = map { scalar @{$_} } @$ref;
    my $maxlen = max(@length);

    # pad to max length
    for (@$ref) {
        push @{$_}, ("nop") x ( $maxlen - @{$_} );
    }
}

=head2 mergeTimeSetArray

 return timeset array with max size.

=cut

fun mergeTimeSetArray ( ArrayRef $ref )
{
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

=head2 mergeComment

 merge comment for multiple device.

=cut

fun mergeComment (ArrayRef $ref)
{
    # get max length
    my @length = map { scalar @{$_} } @$ref;
    my $maxlen = max(@length);

    my @result = @{ $ref->[0] };
    for my $d ( 1 .. $#$ref ) {
        for my $i ( 0 .. $maxlen ) {
            $ref->[$d][$i] = "" unless $ref->[$d][$i];
            $result[$i] = "" unless $result[$i];
            if ( $ref->[$d][$i] ne $result[$i] ) {
                $result[$i] .= ", " . $ref->[$d][$i];
            }
        }
    }

    # remove extra ", " in first element when there's a nop, since comment for
    # nop is empty.
    $result[0] =~ s/, //;

    return @result;
}

=head2 transposeArrayOfArray

 transpose array of columns to array of rows.

=cut

fun transposeArrayOfArray ( ArrayRef $ref )
{
    my @new;
    for my $i ( 0 .. $#$ref ) {
        for my $j ( 0 .. $#{ $ref->[0] } ) {
            $new[$j][$i] = $ref->[$i]->[$j];
        }
    }
    @$ref = @new;
}

=head2 translateInsToRegs

 translate instruction to array of registers of all devices.

=cut

method translateInsToRegs (@ins)
{
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

method lookupRegisters (Str $ins, $dutNum)
{
    return $ins if $ins eq "nop";
    return $ins if $ins =~ /0x\w+/i;

    die
"there's no entry for $ins in register table. check register table and line starts with 'RegisterTable:' in input file.\n"
      unless $self->{'table'}->[$dutNum]->{$ins};

    return @{ $self->{'table'}->[$dutNum]->{$ins} };
}

=head2 readRegisterTable

 read register table for each dut and save them.

=cut

method readRegisterTable (ArrayRef $ref)
{
    return unless @$ref;

    die "RegisterTable file number is not equal to dut number."
      unless $self->dutNum == @$ref;

    for my $dut ( 0 .. $self->dutNum - 1 ) {
        my $fn = $ref->[$dut];
        open my $fh, "<", $fn or warn "fail to open $fn for read: $!" and next;
        my @content = <$fh>;
        close $fh;

        # remove trailing new line
        chomp @content;
        s/\s+//g for @content;
        s/\R//g  for @content;

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

 return idle vector data for stop/wait/jmp/trig.

=cut

method getIdleVectorData ($trigger=0)
{
    my $vec;
    $vec .= "00" x $self->dutNum;
    $vec .= $trigger ? "1" : "0" if $self->getTriggerPin();

    for my $ref ( @{ $self->{'pin'} } ) {
        $vec .= $ref->{'data'};
    }

    return $vec;
}

=head2 parseConfigFile

 the pseudo pattern file contains two parts, config and instructions.  this
 function will read file and setup with config part, then return instructions.

=cut

method parseConfigFile ($file)
{
    my %conf = ParseConfig( -ConfigFile => $file, -LowerCaseNames => 1 );

    # remove trailing commas or spaces
    while ( my ( $key, $val ) = each %conf ) {
        next unless $val;
        next if ref $val;
        $val =~ s/\s*,\s*/,/g;
        $val =~ s/(\s|,)+$//g;
        $val =~ s/^\s*,//;
        $conf{$key} = $val;
    }

    # dut number
    die "missing 'DUT' line in $file." unless $conf{'dut'};
    die "DUT number shall >= 1" unless $conf{'dut'} > 0;
    $self->dutNum( $conf{'dut'} );

    # clock
    die "missing 'ClockPinName' line in $file." unless $conf{clockpinname};
    my @clockpins = split /\s*,\s*/, $conf{clockpinname};
    die "clock pin number shall match with DUT number"
      unless @clockpins == $self->dutNum();

    # data
    die "missing 'DataPinName' line in $file." unless $conf{datapinname};
    my @datapins = split /\s*,\s*/, $conf{datapinname};
    die "data pin number shall match with DUT number"
      unless @datapins == $self->dutNum();

    for my $i ( 0 .. @clockpins - 1 ) {
        $self->setPinName( $clockpins[$i], $datapins[$i], $i + 1 );
    }

    # trigger, optional
    die "missing 'TriggerPinName' line in $file." unless exists $conf{triggerpinname};
    my $trigger = $conf{triggerpinname};
    $self->setTriggerPin($trigger);

    # extra, optional
    die "missing 'ExtraPinName' line in $file." unless exists $conf{extrapinname};
    my @extra = split /\s*,\s*/, $conf{extrapinname};
    for (@extra) {
        my ( $pin, $value ) = split /\s*:\s*/;
        $self->addExtraPin( $pin, $value );
    }

    # registerTable, optional for mipi function
    die "missing 'RegisterTable:' line in $file." unless exists $conf{registertable};
    my @regtable = split /\s*,\s*/,  $conf{registertable};
    $self->readRegisterTable( \@regtable );

    # waveform ref
    die "missing 'WaveformRefRead' line in $file."
      unless $conf{waveformrefread};
    my $read = $conf{waveformrefread};

    die "missing 'WaveformRefWrite' line in $file."
      unless $conf{waveformrefwrite};
    my $write = $conf{waveformrefwrite};

    $self->setTimeSet( $write, $read );
}

=head2 getInstructions

 get instructions from config file.

=cut

fun getInstructions(Str $file)
{
    open( my $fh, "<", $file ) or die "fail to open $file for read: $!";
    my @data = <$fh>;
    close $fh;

    chomp @data;
    s/\R//g for @data;

    @data = grep !/^\s*#|^\s*$|=/, @data;
    die "$file is empty!" unless @data;

    my @result;
    for my $line ( @data ) {
        next unless $line;
        next if $line =~ /^#/;
        $line =~ s/\s*,\s*/,/g;
        $line =~ s/(\s|,)+$//g;
        push @result, $line if $line;
    }

    # remove the first comma for csv file config file
    if ( $file =~ /\.csv$/ ) {
        s/,// for @result;
    }
    return @result;
}

=head2 isExtended

 return true if register requires extended mode.

=cut

fun isExtended ( Str $reg )
{
    return 0 if $reg eq "nop";

    my $addr = hex( &getRegAddr($reg) );
    return 1 if $addr > 0x1F and $addr <= 0xff;
    my @data = &getRegData($reg);
    return 1 if @data > 1;

    return 0;
}

=head2 isLong

 return true if register requires long mode.

=cut

fun isLong ( Str $reg )
{
    return 0 if $reg eq "nop";

    my $addr = hex( &getRegAddr($reg) );
    return 1 if $addr > 0xFF and $addr <= 0xffff;

    return 0;
}

=head2 isReg0WriteMode

 return true if register can be written with register 0 write mode.

=cut

fun isReg0WriteMode (Str $reg)
{
    my $addr = &getRegAddr($reg);
    my @data = &getRegData($reg);
    if ( $addr eq "00" and @data == 1 and hex( $data[0] ) <= 0x7f ) {
        return 1;
    }
    return 0;
}

=head2 getMipiMode

 return MIPI mode for current register of current dut.
 "reg0"     : register 0 write mode
 "extended" : extended mode
 "long"     : long mode
 ""         : register read/write mode

=cut

fun getMipiMode (ArrayRef $regref, Int $dut, Int :$reg0)
{
    return "reg0" if $reg0 and isReg0WriteMode( $regref->[$dut] );

    my $long = grep &isLong($_), @$regref;
    return "long" if $long;

    my $extended = grep &isExtended($_), @$regref;
    return "extended" if $extended;

    return "";
}

=head2 printTriggerVector

 print a vector with trigger.  when trigger pin is defined, it's set to 1.
 otherwise, pattern trigger will be assumed and a '[TRIG]' will be added as
 micro-instruction.

=cut

method printTriggerVector ()
{
    my $ins = "";

    $ins = "[TRIG]" unless $self->getTriggerPin();
    $self->printDataInsComment( $self->getIdleVectorData(1), $ins, "trigger" );
}

=head2 getSlaveAddr

 return slave address for given register.

=cut

fun getSlaveAddr (Str $reg)
{
    return "" if $reg eq "nop";

    if ( $reg =~ /0x([[:xdigit:]])/i ) {
        return lc $1;
    } else {
        die "invalid slave address for $reg";
    }
}

=head2 getRegAddr

 return register address for given register.

=cut

fun getRegAddr (Str $reg)
{
    return "" if $reg eq "nop";

    if ( $reg =~
        /0x[[:xdigit:]] ( [[:xdigit:]]{4,4} ) :? (:? [[:xdigit:]]{2,2})/xi )
    {
        return lc $1;
    } elsif ( $reg =~
        /0x[[:xdigit:]] ( [[:xdigit:]]{2,2} ) :? (:?[[:xdigit:]]{2,2})/xi )
    {
        return lc $1;
    } else {
        die "invalid register address for $reg";
    }
}

=head2 getRegData

 return register data as a LIST for given register.

=cut

fun getRegData (Str $reg)
{
    return "" if $reg eq "nop";

    if ( $reg =~ /:/ ) {
        my @tmp = split /:/, $reg;
        $reg = $tmp[-1];
        return split /-/, $reg;
    } elsif ( $reg =~ /[[:xdigit:]]{5,5} (:? [[:xdigit:]]{2,2} )?/x ) {
        return substr $reg, -2;
    }

    die "invalid register data for $reg";
}

=head2 getBits

 return list of bits(MSB first) for given hex string.

=cut

fun getBits (Int $bitNum, Str $reg)
{
    return split "", sprintf( "%0${bitNum}b", hex($reg) );
}

=head2 getDescription

 return description for instruction/register for all DUTs.
 if instruction is the same with register, starting with '0x', only instruction
 will be kept.

=cut

fun getDescription (ArrayRef $insref,ArrayRef $regref)
{
    my @result;
    for my $dut ( 0 .. $#$regref ) {
        if ( $insref->[$dut] eq $regref->[$dut] ) {
            $result[$dut] =
              sprintf( "%d:%s", $dut + 1, $insref->[$dut] );
        } else {
            $result[$dut] =
              sprintf( "%d:%s:%s", $dut + 1, $insref->[$dut], $regref->[$dut] );
        }
    }

    return "@result";
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
