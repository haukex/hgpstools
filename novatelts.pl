#!/usr/bin/env perl
use warnings;
use strict;
use feature 'state';
use Data::Dump qw/dd pp/;
use Getopt::Long qw/ HelpMessage :config posix_default gnu_compat bundling auto_help /;
use DateTime;
use FindBin;
use lib $FindBin::Bin;
use NovatelParser 'parse_novatel';
$|++;

=head1 SYNOPSIS

A simple script to convert GPS timestamps.

 novatelts.pl [OPTIONS] FILE(s)
 OPTIONS:
   --head     - Use the GPS timestamp from the header instead of body
   --delta    - Output the delta between the UNIX and GPS times
   --state    - Instead of timestamps, track State in IMURATEPVASA
   --dt       - Output Date/Time values instead of UNIX timestamps
   --height=N - With --state, report height changes of N meters

=head1 NOTES

 # Testing:
 $ grep INS_SOLUTION_GOOD /path/to/novatel2txt_data.txt | ./novatelts.pl --delta | perl -F, -ane 'print if abs($F[2])>=1'

=cut

GetOptions(
	'head'     => \( my $HEADTIME ),
	'delta'    => \( my $DELTA ),
	'state'    => \( my $TRACKSTATE ),
	'dt'       => \( my $DTOUT ),
	'height=i' => \( my $HEIGHT_M ),
	) or HelpMessage(-exitval=>255);
HelpMessage(-msg=>'--height requires --state',-exitval=>255)
	if defined($HEIGHT_M) && !$TRACKSTATE;

sub secsplit { # turn "seconds.decimal" into seconds and nanoseconds
	my $in = shift;
	my ($s,$ss) = $in =~ /\A(\d+)\.(\d{1,9})\z/ or die pp($in);
	my $ns = "0"x9;
	substr($ns,0,length($ss),$ss);
	#die pp($in,$s,$ss,$ns) unless $in=="$s.$ns";
	return ($s,$ns);
}

# SPAN on OEM6 Firmware Reference Manual
# OM-20000144 / Rev 7 / January 2015
# "GPS reference time is referenced to UTC with zero point defined as midnight on the night of
# January 5, 1980. The time stamp consists of the number of weeks since that zero point and the number of
# seconds since the last week number change (0 to 604,799). GPS reference time differs from UTC time since
# leap seconds are occasionally inserted into UTC and GPS reference time is continuous."
sub gps2dt {
	my ($gpsweek,$gpssec) = @_;
	# Alternative that produces the same output for 2019, *however*, the "37" would need to be calculated.
	# Our load_data.py basically does exactly the same and relies on a config value for the "37".
	#return DateTime->from_epoch( epoch => 315964800 + $gpsweek*604800 + $gpssec - 37 + 19 );
	my ($gs,$gns) = secsplit($gpssec);
	# DateTime does the leap second handling for us:
	state $odt = DateTime->new(year=>1980,month=>1,day=>6,hour=>0,minute=>0,second=>0,nanosecond=>0,time_zone=>'UTC');
	my $dt = $odt->clone;
	# Note GPS weeks have a fixed number of seconds, so this calculation is ok:
	$dt->add( seconds => $gpsweek*60*60*24*7 + $gs, nanoseconds=>$gns );
	return $dt;
}

# https://en.wikipedia.org/wiki/Leap_second
# "In 1972, the leap-second system was introduced so that the broadcast UTC seconds could be made exactly equal to
# the standard SI second ... After 1972, both clocks have been ticking in SI seconds, so the difference between their
# readouts at any time is 10 seconds plus the total number of leap seconds that have been applied to UTC"
# Leap Seconds 1972 to 2019: 27, so plus the 10 extra is 37 as of 2019. Current TAI - UTC is therefore 37.
# "... so in 2018, UTC lags behind TAI by an offset of 37 seconds."
# "It is also easy to convert GPS time to TAI, as TAI is always exactly 19 seconds ahead of GPS time."
# DateTime->new(year=>2019,time_zone=>"UTC")->leap_seconds is 27.

# https://www.novatel.com/support/knowledge-and-learning/published-papers-and-documents/unit-conversions/
# January 28, 2005, 13:30 hours <=> GPS Week 1307, 480,600 seconds
#print STDERR gps2dt('1307','480600.0')->strftime('%Y-%m-%dT%H:%M:%S.%3N%z'),"\n"; #TODO: why is this "2005-01-28T13:29:47.000+0000" ?
# it works again if I change time_zone=>'UTC' to time_zone=>'floating', but then testing it against real data fails

# https://gssc.esa.int/navipedia/index.php/Transformations_between_Time_Systems
# "TAI = GPST + 19.000 seconds"

local ($\,$,)=($/,",");
my $conv = $DTOUT
	? sub { (ref $_[0] ? $_[0] : DateTime->from_epoch(epoch=>$_[0]))->strftime('%Y-%m-%d %H:%M:%S.%3N %Z') }
	: sub {  ref $_[0] ? $_[0]->strftime("%s.%6N") : sprintf('%.6f', $_[0]) };
my $state='(none)';
my $prevheight_m=0;
while (<>) {
	chomp;
	s/\A\x00+//;
	s/\A(\d+\.\d+)\t// or do { warn "skipping: ".pp($_); next };
	my $syst = $1;
	my $r = parse_novatel($_);
	next if $$r{_ParsedAs} eq '_generic';
	my $gdt = gps2dt(
			$HEADTIME ? ($$r{Week}, $$r{Seconds})
			: ($$r{Fields}{Week}, $$r{Fields}{Seconds}) );
	if ( $TRACKSTATE ) {
		if ( $$r{Message} eq 'IMURATEPVASA' ) {
			if ( $$r{Fields}{Status} ne $state || defined $HEIGHT_M && abs($prevheight_m-$$r{Fields}{Height})>$HEIGHT_M ) {
				print $conv->($syst), $conv->($gdt), $state, $$r{Fields}{Status}, defined($HEIGHT_M)?$$r{Fields}{Height}:();
				$state = $$r{Fields}{Status};
				$prevheight_m = $$r{Fields}{Height};
			}
		}
	}
	else {
		print $conv->($syst), $conv->($gdt), $DELTA ? $gdt->epoch-$syst : ();
	}
}
