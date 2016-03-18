use warnings;
use strict;

=head1 SYNOPSIS

This is a configuration file for C<serlog.pl> that handles NMEA data.

 serlog.pl /path/to/serlog_conf_nmea.pl

=head1 DETAILS

The subroutine stored in C<$HANDLE_LINE> handles checking input format as
well as manipulating the input lines (such as adding timestamps).
If you want this script to handle something other than NMEA, you can modify
that subroutine. Another simple possibility is to set C<$CHECK_NMEA> to
a false value, and then the current C<$HANDLE_LINE> implementation
simply logs input lines with a timestamp without checking their format.

The subroutine stored in C<$HANDLE_STATUS> handles the manipulation of
status messages from the logger such as "start", "stop", "connect" and "disconnect".
By default it outputs the messages with a timestamp (i.e. they are mixed
in with the NMEA stream).

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

our $SERIALPORT = '/dev/usb_gps';
our $BAUDRATE = 4800;

use Time::HiRes qw/ gettimeofday /;
# the following variables configure the current $HANDLE_LINE implementation
my $STRIP_NULS = 1; # strip NULs at beginning and end of lines (seems to happen sometimes)
my $CHECK_NMEA = 1;
my $ESCAPE_NONPRINTABLE = 1; # escape all nonprintable and non-ASCII chars
our $HANDLE_LINE = sub { # code should edit $_; return value ignored
	$STRIP_NULS and s/^\x00*|\x00*$//g;
	return unless length $_; # nothing needed
	my $err;
	if ($CHECK_NMEA) {
		if (my ($str,$sum) = /^\$(.+?)(?:\*([A-Fa-f0-9]{2}))?$/) {
			if ($sum) {
				my $xor = 0;
				$xor ^= ord for split //, $str;
				my $got = sprintf '%02X', $xor;
				$sum = uc $sum;
				$sum eq $got or $err = "Checksum calc $got, exp $sum";
			}
		}
		else
			{ $err = "Invalid format" }
	}
	if ($err) {
		s/([^\x09\x20-\x7E])/sprintf("\\x%02X", ord $1)/eg;
		warn "Ignoring input ($err): $_\n";
		undef $_;
		return;
	}
	$ESCAPE_NONPRINTABLE and s/([^\x09\x20-\x7E])/sprintf("\\x%02X", ord $1)/eg;
	$_ = sprintf("%d.%06d\t%s\n",gettimeofday,$_) if length $_;
	return;
};
our $HANDLE_STATUS = sub { # code should edit $_; return value ignored
	return unless length $_; # nothing needed
	unless (/^[A-Za-z0-9_]/) {
		warn "Ignoring invalid status \"$_\"\n";
		undef $_;
		return;
	}
	$_ = sprintf("%d.%06d\t%s\n",gettimeofday,$_) if length $_;
	return;
};


1;
