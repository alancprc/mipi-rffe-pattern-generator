package MipiPatternGenerator;

use 5.010001;
use strict;
use warnings;

use Moose;
use Function::Parameters;
use Types::Standard qw(Str Int ArrayRef RegexpRef);
use JSON -convert_blessed_universally;
use Image::ExifTool qw(:Public);
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


=head1 SYNOPSIS

    use MipiPatternGenerator;

    my $mipi = MipiPatternGenerator->new();
    $mipi->setTimeSet($writeTset, $readTset);
    $mipi->generate("pattern.txt");

=head1 SUBROUTINES/METHODS

=head2 function1

=cut

sub function1 {
}

=head2 function2

=cut

sub function2 {
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

1; # End of MipiPatternGenerator
