package MipiPatternGenerator;

use 5.010001;
use strict;
use warnings;

use File::Basename;
use File::Spec;

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

    open( my $fh, ">", $fn ) or die "fail to open $fn.";
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

    open( my $fh, "<", $inputfile ) or die "$inputfile doesn't exist.";
    my @data = <$fh>;
    close $fh;

    chomp @data;

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
    say @$dataref;
}

=head2 getTimeSetArray

 return array for timeset

=cut

sub getTimeSetArray
{
    my ( $self, $read ) = @_;

    my $bits = 3 + 23 + $read;
    my @tset = ( $self->{'tsetWrite'} ) x $bits;

    splice @tset, 17, 9, ( $self->{'tsetRead'} ) x 9 if $read;
    return @tset;
}

=head2 getClockArray

 return array for clock pin

=cut

sub getClockArray
{
    my ( $read, $reg ) = @_;
    $reg = "" unless $reg;

    return ("0") x ( 23 + $read ) if $reg eq "nop";

    my $ones  = 23 + $read;
    my $zeros = 3;
    my $str   = "0" x $zeros . '1' x $ones;
    return split //, $str;
}

=head2 getDataArray

 return array for data pin

=cut

sub getDataArray
{
    my ( $reg, $read ) = @_;

    return ("0") x ( 23 + $read ) if $reg eq "nop";

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

sub getCommentArray
{
    my ( $read, $reg ) = @_;
    $reg = "" unless $reg;

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
        } elsif (/wait\s*(\d+)*/i) {
            my $ins = $1 ? "<RPT $1>" : "";
            $self->printDataInsComment( $self->getIdleVectorData, $ins,
                "wait" );
        } elsif (/stop/i) {
            $self->printDataInsComment( $self->getIdleVectorData, "<STOP>",
                "stop" );
        } elsif (/jmp\s+(\w+)/i) {
            $self->printDataInsComment( $self->getIdleVectorData, "<JMP $1>",
                "jump" );
        } elsif (/trig/i) {
            $self->printDataInsComment( $self->getIdleVectorData(1),
                "[TRIG]", "trigger" );
        } elsif (/^(R:)?\s*(\w+\s*(?:,\s*\w+)*)/) {
            my $read = $1 ? 1 : 0;
            $self->getVectorData( $2, $read );    # read/write
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

    #&printUno(join('', '*', $data, '* ', $tset, '; ', $ins, ' "', $cmt, '"'));
    $self->printUno($str);
}

=head2 getVectorData

 write read/write mipi operation segment into pattern file

=cut

sub getVectorData
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

    # lookup registers
    my @vecs;
    my @tsets;
    my @comments;
    for my $dut ( 0 .. $self->dutNum - 1 ) {
        my @regs = $self->lookupRegisters( $ins[$dut], $dut );
        my @clock;
        my @data;
        my @tset;
        my @cmt;
        for my $reg (@regs) {
            push @clock, &getClockArray( $read, $reg );
            push @data, &getDataArray( $reg, $read );
            push @tset, $self->getTimeSetArray($read);
            push @cmt, &getCommentArray( $read, join( ":", $ins[$dut], $reg ) );
        }

        $vecs[ 2 * $dut ]     = \@clock;
        $vecs[ 2 * $dut + 1 ] = \@data;
        $tsets[$dut]          = \@tset;
        $comments[$dut]       = \@cmt;
    }
    &alignVectorData( \@vecs );
    my @tset    = &alignTimeSet( \@tsets );
    my @comment = &mergeComment( \@comments );
    &transposeVectorData( \@vecs );
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

=head2 alignVectorData

=cut

sub alignVectorData
{
    my $ref = shift;

    # get max length
    my $maxlen = 0;
    for (@$ref) {
        my $len = @{$_};
        $maxlen = $len > $maxlen ? $len : $maxlen;
    }
    for (@$ref) {
        while ( @{$_} < $maxlen ) {
            push @{$_}, "0";
        }
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

=head2 mergeComment

=cut

sub mergeComment
{
    my $ref = shift;

    my $maxlen = 0;
    my $maxidx = 0;
    for my $i ( 0 .. $#$ref ) {
        my $len = @{ $ref->[$i] };
        if ( $len > $maxlen ) {
            $maxlen = $len;
            $maxidx = $i;
        }
    }

    my @merge;
    for my $i ( 0 .. $maxlen ) {
        my $str = '';
        for my $d ( 0 .. $#$ref ) {
            if ( $ref->[$d][$i] and $ref->[$d][$i] ne $str ) {
                my $new = $ref->[$d][$i];
                $str = $str ? join( ', ', $str, $new ) : $new;
            }
        }
        $merge[$i] = $str;
    }
    return @merge;
}

=head2 transposeVectorData

 transpose array of columns to array of rows

=cut

sub transposeVectorData
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

    die unless $self->dutNum == @$ref;

    for my $dut ( 0 .. $self->dutNum - 1 ) {
        open my $fh, "<", $ref->[$dut]
          or die $ref->[$dut] . "file doesn't exist";
        my @content = <$fh>;
        close $fh;

        # remove trailing new line
        s/\R// for @content;

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

    open( my $fh, "<", $file ) or die "$file doesn't exist.";
    my @data = <$fh>;
    close $fh;

    chomp @data;
    die "$file is empty!" unless @data;

    # dut number
    my $line = shift @data;
    die unless $line =~ /^DUT:/;
    my $num = () = split /,/, $line, -1;
    $self->dutNum($num);

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
        my ( $pin, $value ) = split /=/;
        $self->addExtraPin( $pin, $value );
    }

    # registerTable
    $line = shift @data;
    die unless $line =~ /^RegisterTable:/;
    $line =~ s/\s//g;
    $line =~ s/.*://g;
    my @regtable = split /,/, $line;
    $self->readRegisterTable( \@regtable );
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

1;    # End of MipiPatternGenerator
