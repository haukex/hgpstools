#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

Filters known timestamp formats added by logger software out of an NMEA
data stream and turns them into fake C<$PCTS> NMEA records (output before
the NMEA line they are found in).

 filter_ts.pl [-t TIMEZONE] INPUT_FILE >OUTPUT_FILE

=head1 DETAILS

Currently handles the timestamps added by C<serlog_conf_nmea.pl>
as well as a Windows logger software which embeds timestamps
in angle brackets in random places in lines.
Also, the status messages added by C<serlog.pl>
with C<serlog_conf_nmea.pl>'s timestamps are removed.

The C<-t> option allows you to specify a timezone other than the current
local time zone for timestamps that need conversion (currently only the
Windows C<< <...> >> timestamps).

The fake C<$PCTS> records have a single field, which is a UNIX timestamp
(seconds since epoch) with an optional fractional part (depending on what
the source timestamp provides).

=head1 AUTHOR, COPYRIGHT, AND LICENSE

Copyright (c) 2016 Hauke Daempfling (haukex@zero-g.net)
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

use Getopt::Std 'getopts';
use Pod::Usage 'pod2usage';
use DateTime::TimeZone ();
use DateTime::Format::Strptime ();

sub HELP_MESSAGE { pod2usage(-output=>shift); return }
sub VERSION_MESSAGE { say {shift} q$filter_ts.pl v1.00$; return }
$Getopt::Std::STANDARD_HELP_VERSION = 1;
getopts('t:', \my %opts) or pod2usage;

my $TIMEZONE = DateTime::TimeZone->new(name=>$opts{t}||'local')->name();
warn "Notice: Assuming time zone $TIMEZONE for <...> timestamps\n" unless $opts{t};
my $fmt_specstamp = DateTime::Format::Strptime->new(on_error=>'croak', pattern => '%Y%m%d%H%M%S.%3N', time_zone=>$TIMEZONE);

my $found_pcts=0;

while(<>) {
	s/\x0D?\x0A$//;
	$found_pcts++ if /\$PCTS/;
	# skip status lines from "serlog.pl" (with "serlog_conf_nmea.pl" timestamp)
	next if /^([0-9]+(\.[0-9]{6})?)[\t ]+(START|STOP|CONNECT|DISCONNECT|RELOAD)$/;
	# timestamp prefixed to each line by "serlog_conf_nmea.pl"
	# should be Time::HiRes::gettimeofday printed as "%d.%06d"
	if (s/^([0-9]+(?:\.[0-9]{6})?)[\t ]+//) {
		nmea_rec_out("PCTS,$1");
	}
	# timestamps embedded into lines (some Windows logger software)
	while (s/<([0-9]{14}\.[0-9]{3})>//) {
		my $dt = $fmt_specstamp->parse_datetime($1);
		$dt->set_time_zone('UTC'); # source TZ set above
		nmea_rec_out("PCTS,".$dt->strftime('%s.%3N'));
	}
	print $_, "\n";
}

warn "Warning: This file already contains $found_pcts PCTS records!\n" if $found_pcts;

sub nmea_rec_out {
	my ($msg) = @_;
	my $xor = 0;
	$xor ^= ord for split //, $msg;
	printf "\$%s*%02X\n", $msg, $xor;
	return;
}

