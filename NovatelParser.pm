#!perl
package NovatelParser;
use warnings;
use strict;
use Carp;
use Data::Dump 'pp';
use Regexp::Common qw/number/;

our $VERSION = '0.01';

# SEE THE END OF THIS FILE FOR AUTHOR, COPYRIGHT AND LICENSE INFORMATION

=head1 Synopsis

A parser for a limited subset of Novatel log messages.

Based on the "SPAN on OEM6 Firmware Reference Manual, OM-20000144 / Rev 7 / January 2015"
(page numbers mentioned in code comments refer to this document).

Example: Getting all timestamps from a logger data file:

 $ perl -wMstrict -MData::Dump=pp -MNovatelParser=parse_novatel -nle '
   s/^\x00*(\d+\.\d+)\s+// or do{warn pp($_);next}; my $y=$1;
   my $x=eval{parse_novatel($_)} or do {warn $@;next};
   print $y,"\t",$x->{Week},"/",$x->{Seconds},(ref $x->{Fields} eq "HASH"
   ? ("\t", $x->{Fields}{Week},"/",$x->{Fields}{Seconds}) : ())' novatel2txt_data.txt

=cut

use Exporter 'import';
our @EXPORT_OK = qw/ parse_novatel /;

# --- Data Types (from Page 10) ---
# data type Char and I think String
# (note the spec forbids double-quotes in double-quoted strings)
our $RE_STRING = qr{[^,"]*|"[^"]*"}x;
# data types UChar, Short, UShort, Long, ULong
our $RE_INT = $RE{num}{int};
# data types Double, Float, GPSec
our $RE_REAL = $RE{num}{real};
# data type Hex
our $RE_HEX = qr{(?:[a-fA-F0-9][a-fA-F0-9])*}x;

# --- ASCII Header (from Page 12) ---
our $RE_ASCII_HEADER = qr{
		(?<Sync> \# )
		(?<Message> $RE_STRING ) ,
		(?<Port> $RE_STRING ) , # see listing of port names on Page 16
		(?<SequenceNr> $RE_INT ) ,
		(?<IdleTime> $RE_REAL ) ,
		# from Page 23:
		(?<TimeStatus> UNKNOWN | APPROXIMATE | COARSEADJUSTING | COARSE | COARSESTEERING
			| FREEWHEELING | FINEADJUSTING | FINE | FINEBACKUPSTEERING | FINESTEERING | SATTIME ) ,
		(?<Week> $RE_INT ) ,
		(?<Seconds> $RE_REAL ) ,
		(?<ReceiverStatus> $RE_HEX ) , # bitfield specified on Page 13
		(?<Reserved> $RE_STRING ) ,
		(?<ReceiverSWVersion> $RE_INT ) ;
	}x;

# --- ASCII with Short Headers (Page 19) ---
our $RE_ASCII_SHORT_HEADER = qr{
		(?<Sync> \% )
		(?<Message> $RE_STRING ) ,
		(?<Week> $RE_INT ) ,
		(?<Seconds> $RE_REAL ) ;
	}x;

use Digest::CRC ();
sub novatelcrc {
	my $data = shift;
	return Digest::CRC->new(width=>32, init=>0, xorout=>0,
		refout=>1, refin=>1, cont=>0, poly=>0x04C11DB7)
		->add($data)->digest;
}

our $RE_RECORD_GENERIC = qr{
		(?<ChecksumData>
			(?: $RE_ASCII_HEADER | $RE_ASCII_SHORT_HEADER )
			(?<Fields> (?: $RE_STRING (?: , $RE_STRING )* )? )
		) \*
		(?<Checksum> (?i: (??{
			quotemeta(sprintf('%08X',novatelcrc( substr $+{ChecksumData}, 1 )))
		}) ) )
	}x;

sub fieldsplit {
	my $in = shift;
	pos($in) = undef;
	my @o = $in =~ m{ \G (?:\A|,) (?| ([^,"]*) | "([^"]*)" ) (?=,|\z) }gxc;
	croak "failed to parse fields at pos ".pos($in).": ".pp($in) unless pos($in)==length($in);
	return \@o;
}

our %FIELD_RE = (
	# --- IMURATECORRIMUS / Asynchronous Corrected IMU Data (Page 132) ---
	IMURATECORRIMUSA => qr{
		(?<Week> $RE_INT )             ,  (?<Seconds> $RE_REAL )    ,
		(?<PitchRate> $RE_REAL )       ,  (?<RollRate> $RE_REAL )   ,
		(?<YawRate> $RE_REAL )         ,  (?<LateralAcc> $RE_REAL ) ,
		(?<LongitudinalAcc> $RE_REAL ) ,  (?<VerticalAcc> $RE_REAL )
	}x,
	# --- IMURATEPVAS / Asynchronous INS Position, Velocity and Attitude (Page 134) ---
	IMURATEPVASA => qr{
		(?<Week> $RE_INT )          ,  (?<Seconds> $RE_REAL )       ,
		(?<Latitude> $RE_REAL )     ,  (?<Longitude> $RE_REAL )     ,
		(?<Height> $RE_REAL )       ,  (?<NorthVelocity> $RE_REAL ) ,
		(?<EastVelocity> $RE_REAL ) ,  (?<UpVelocity> $RE_REAL )    ,
		(?<Roll> $RE_REAL )         ,  (?<Pitch> $RE_REAL )         ,
		(?<Azimuth> $RE_REAL )      ,
		(?<Status> INS_INACTIVE       # IMU logs are present, but the alignment routine has not started; INS is inactive.
			| INS_ALIGNING            # INS is in alignment mode.
			| INS_HIGH_VARIANCE       # The INS solution is in navigation mode but the azimuth solution uncertainty has exceeded the threshold. The default threshold is 2 degrees for most IMUs. The solution is still valid but you should monitor the solution uncertainty in the INSCOV log. You may encounter this state during times when the GNSS, used to aid the INS, is absent.
			| INS_SOLUTION_GOOD       # The INS filter is in navigation mode and the INS solution is good.
			| INS_SOLUTION_FREE       # The INS filter is in navigation mode and the GNSS solution is suspected to be in error. This may be due to multipath or limited satellite visibility. The inertial filter has rejected the GNSS position and is waiting for the solution quality to improve.
			| INS_ALIGNMENT_COMPLETE  # The INS filter is in navigation mode, but not enough vehicle dynamics have been experienced for the system to be within specifications.
			| DETERMINING_ORIENTATION # INS is determining the IMU axis aligned with gravity.
			| WAITING_INITIALPOS )    # The INS filter has determined the IMU orientation and is awaiting an initial position estimate to begin the alignment process.
	}x,
);

# VERSIONA not (yet) implemented, is described in: "OEM6 Family Firmware Reference Manual, OM-20000129 / Rev 8 / January 2015"

sub parse_novatel {
	croak "bad number of arguments to parse_novatel" unless @_==1;
	my $in = shift;
	croak "got undef instead of a Novatel record" unless defined $in;
	$in =~ /\A$RE_RECORD_GENERIC\z/ or croak "failed to parse Novatel record: ".pp($in);
	my %rec = %+;
	delete $rec{ChecksumData};
	if (exists $FIELD_RE{$rec{Message}}) {
		$rec{_ParsedAs} = $rec{Message};
		$rec{Fields} =~ /\A$FIELD_RE{$rec{Message}}\z/
			or croak "failed to parse Novatel record: ".pp($in);
		$rec{Fields} = { %+ };
	}
	else {
		$rec{_ParsedAs} = '_generic';
		$rec{Fields} = fieldsplit($rec{Fields});
	}
	return \%rec;
}

1;
__END__

=head1 Author, Copyright, and License

Copyright (c) 2019 Hauke Daempfling (haukex@zero-g.net)
at the Leibniz Institute of Freshwater Ecology and Inland Fisheries (IGB),
Berlin, Germany, L<http://www.igb-berlin.de/>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see L<http://www.gnu.org/licenses/>.

=cut
