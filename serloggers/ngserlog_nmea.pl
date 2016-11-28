#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

This is both a configuration file for F<ngserlog.pl> that handles NMEA
data, when used like this:

 ./ngserlog.pl serloggers/ngserlog_nmea.pl

Or, when used like in the following example, it is a daemon wrapper for
the above, providing a daemon named C<ngserlog_nmea>.
Please see F<Daemon_Control.md> for usage information!

 serloggers/ngserlog_nmea.pl get_init_file

=head1 DESCRIPTION

This script uses the variable C<$NGSERLOG> from F<ngserlog.pl> to detect
whether it should function as a configuration file only or also
as a L<Daemon::Control|Daemon::Control> script.

This script requires the paths F< /home/pi/pidfiles/ >, F< /home/pi/logs/ >,
and F< /home/pi/data/ > to exist. You can also make it easier to view all
the log files in one place via the following command. See F<ngserlog.pl>
for information on how to configure C<rsyslog>.

 ln -s /var/log/ngserlog.log ~/logs/

=head2 CONFIGURATION

The subroutine stored in C<$HANDLE_LINE> handles checking input format as
well as manipulating the input lines (such as adding timestamps).

The subroutine stored in C<$HANDLE_STATUS> handles the manipulation of
status messages from the logger such as "start", "stop", "connect" and
"disconnect". By default it outputs the messages with a timestamp (i.e.
they are mixed in with the NMEA stream).

=head2 DAEMON

Please see F<Daemon_Control.md> for usage information!

I<Note:> At the moment, L<Daemon::Control|Daemon::Control> does not
support setting multiple group IDs. As a workaround, in order to access
the serial port, currently the group C<dialout> is used. This means that
files created will be owned by that group.
(See also L<https://github.com/symkat/Daemon-Control/pull/60>.)

=head2 NOTES

You may want to disable L<gpsd(8)> to avoid conflicts:

 sudo update-rc.d -f gpsd remove
 sudo service gpsd stop

If your GPS device is outputting binary data, try L<gpsctl(1)>:

 sudo gpsctl -n /dev/ttyUSB0

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

#TODO Later: Don't hardcode library locations into the scripts
use FindBin;
use lib "$FindBin::Bin/..";
use local::lib '/home/pi/perl5';

use IdentUsbSerial 'ident_usbser';
our $GET_PORT = sub {
	my @devs = ident_usbser(vend=>'067b', prod=>'2303'); # Navilock NL-302U
	return unless @devs;
	warn "Multiple devices found, picking the first\n" if @devs>1;
	my $devtty = $devs[0]{devtty};
	return unless -e $devtty;
	info("Opening port $devtty for NEMA data");
	return SerialPort->open($devtty, mode=>'4800,8,n,1',
		flexle=>1, timeout_s=>3 );
};

use Time::HiRes qw/ gettimeofday /;
our $HANDLE_LINE = sub {
	s/^\x00*|\x00*$//g; # strip NULs at beginning and end of lines (seems to happen sometimes)
	return unless length $_;
	my $err;
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
	# escape all nonprintable and non-ASCII chars
	s/([^\x09\x20-\x7E])/sprintf("\\x%02X", ord $1)/eg;
	if ($err) {
		warn "$err; ignoring input $_\n";
		undef $_;
		return;
	}
	$_ = sprintf("%d.%06d\t%s\n",gettimeofday,$_) if length $_;
};
our $HANDLE_STATUS = sub {
	$_ = sprintf("%d.%06d\t%s\n",gettimeofday,$_) if length $_;
};

our $OUTFILE = '/home/pi/data/nmea_data.txt';

# if this script is run directly instead of being required by ngserlog.pl,
# it functions as a Daemon::Control script for itself
our $NGSERLOG;
if (!$NGSERLOG) {
	require Daemon::Control;
	exit Daemon::Control->new(
	name         => 'ngserlog_nmea',
	program      => '/home/pi/hgpstools/ngserlog.pl',
	program_args => [ '/home/pi/hgpstools/serloggers/ngserlog_nmea.pl' ],
	user         => 'pi',
	group        => 'dialout',
	umask        => oct('0027'),
	help         => "Please run `perldoc ".__FILE__."` for help.\n",
	# note that since we use the "outfile" option above, the stdout_file *should* remain empty
	stdout_file  => '/home/pi/logs/nmea_out.txt',
	# since ngserlog now uses syslog, the stderr_file *should* also remain empty
	stderr_file  => '/home/pi/logs/nmea_err.txt',
	pid_file     => '/home/pi/pidfiles/nmea.pid',
	#resource_dir => '/home/pi/ngserlog/', # currently not needed
	fork         => 2, # default = 2 = double-fork
	kill_timeout => 5, # ngserlog.pl needs *at least* one second to shut down
	lsb_start   => '$local_fs $time',
	lsb_stop    => '$local_fs',
	lsb_sdesc   => "Serial Logger for NMEA Data",
	lsb_desc    => "Serial Logger for NMEA Data",
	# Note: in Daemon::Control Default-Start is currently fixed at "2 3 4 5" and Default-Stop at "0 1 6"
	)->run;
}

1;
