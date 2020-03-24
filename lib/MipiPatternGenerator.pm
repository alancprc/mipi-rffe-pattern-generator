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

has 'debug' => ( is => 'rw', default => 0 );

=head2 generate

 generate unison pattern file from given pseudo pattern file.

=cut

method generate (Str $file)
{
    $self->validateInputFile($file);
    my @ins = &readPseudoPattern($file);

    open( $uno, ">", "$pattern_name.uno" );

    &printHeader();

    for (@ins) {
        chomp;

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
    open( my $fh, "<", $inputfile ) or die "$inputfile doesn't exist.";
    my @data = <$fh>;
    close $fh;

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

fun increaseRegData(Ref $ref)
{
    return 0 if $$ref =~ /FF$/i;
    my $dec = hex($$ref);
    ++$dec;
    $$ref = sprintf("%X", $dec);
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
    my $cmt = $read ? "Read" : "Write";
    $comment[0] .= " $cmt $reg";

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
