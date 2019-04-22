#!/usr/bin/env perl
use warnings;
use strict;
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
   --py       - Use calculation method used in python file

=cut

GetOptions(
	'py' => \( my $PYTHON ),
	) or HelpMessage(-exitval=>255);

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
sub gps2dt { # this is my interpretation
	my ($gpsweek,$gpssec) = @_;
	my ($gs,$gns) = secsplit($gpssec);
	my $dt = DateTime->new(year=>1980,month=>1,day=>6,hour=>0,minute=>0,second=>0,nanosecond=>0,time_zone=>'UTC');
	$dt->add( weeks=>$gpsweek, seconds=>$gs, nanoseconds=>$gns );
	return $dt->strftime("%s.%N");
}
my $LEAP = 37;
sub gps2sec { # this is how load_data.py does it
	my ($gpsweek,$gpssec) = @_;
	return 315964800 + $gpsweek*604800 + $gpssec - $LEAP + 19;
}

# https://www.novatel.com/support/knowledge-and-learning/published-papers-and-documents/unit-conversions/
# January 28, 2005 13:30 <-> GNSS Week 1307, 480,600 seconds
# January 28, 2005 13:30 <-> UNIX time 1106919000
# Note: Jan 2005 to Jan 2019: five leap seconds added
#dd gps2dt('1307','480600.0');  # ="1106919000" => right?
#dd gps2sec('1307','480600.0'); # ="1106918982" => wrong? (18 secs less)

# http://leapsecond.com/java/gpsclock.htm
# UTC 2019-04-18 21:11:57 (1555621917) <-> GPS week 2049, 421935 s
#dd gps2dt('2049','421935.0');  # ="1555621935" => wrong ?? (18 secs more)
#dd gps2sec('2049','421935.0'); # ="1555621917" => right ??

# ==> This is a ludicrously complex topic.
# https://unix.stackexchange.com/questions/283164/unix-seconds-tai-si-seconds-leap-seconds-and-real-world-code
# https://news.ycombinator.com/item?id=9017761
# https://en.wikipedia.org/wiki/International_Atomic_Time
# https://en.wikipedia.org/wiki/Unix_time#TAI-based_variant
# ... many more
# ==> Luckily, we actually don't need to synchronize our systems to UTC or TAI,
# we need to synchronize our sensors *to*each*other*, and luckily all of our logs,
# including GPS logs, include the UNIX timestamp to do that.
# In the future, we could consider logging something other than the UNIX timestamp (TAI?).

my $code = $PYTHON ? \&gps2sec : \&gps2dt;
local ($\,$,)=($/,",");
while (<>) {
	chomp;
	s/\A(\d+\.\d+)\t// or die pp($_);
	my $syst = $1;
	my $r = parse_novatel($_);
	my $gdt1 = $code->($$r{Week}, $$r{Seconds});
	my $gdt2 = $code->($$r{Fields}{Week}, $$r{Fields}{Seconds});
	print map {s/0+\z//r} $syst,$gdt1,$gdt2;
}
