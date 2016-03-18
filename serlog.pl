#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

B<This is a work in progress.> Please use C<serialdaemon_gps.pl> for now.

This is a logger that logs line-based data (CRLF or LF) from a serial port.
It also handles USB devices being hot-plugged.

 serlog.pl CONFIGFILE.pl

B<Warning:> C<CONFIGFILE.pl> will be executed by this script.
For security, only use absolute pathnames and scripts you trust.

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

You may need to add the user to the group C<dialout> (in Debian, this
normally gives full and direct access to serial ports):

 sudo adduser <username> dialout

You may want to disable L<gpsd(8)> to avoid conflicts:

 sudo update-rc.d -f gpsd remove
 sudo service gpsd stop

If your GPS device is outputting binary data, try L<gpsctl(1)>:

 sudo gpsctl -n /dev/ttyUSB0

If you're connecting multiple USB devices to your system and you don't want
to figure out the device name every time, you can use L<udev(7)>. Create
a file like the following in F</etc/udev/rules.d/> (e.g. F<90-usbgps.rules>):

 ATTRS{idVendor}=="067b", ATTRS{idProduct}=="2303", SYMLINK+="usb_gps"

and then your device will always be available as F</dev/usb_gps>.
(The above IDs are for a Navilock NL-302U.)

Hint: For debugging, you can simply C<cat /dev/ttyUSB0> after setting
the serial port speed via C<stty -F /dev/ttyUSB0 4800 raw>.
Also, you can use L<minicom(1)>: C<minicom -D/dev/ttyUSB0>
(configure via C<Ctrl-A o>, exit via C<Ctrl-A q>)
or L<screen(1)>: C<screen /dev/ttyUSB0 4800> (exit via C<Ctrl-A \>)

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

# ### Application-Specific User Settings ###

#TODO: move this to CONFIGFILE.pl (and into a hash)
our $SERIALPORT = '/dev/usb_gps';
our $BAUDRATE = 4800;
our $MAX_ERRORS = 100;

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


use Getopt::Std 'getopts';
use Pod::Usage 'pod2usage';

sub HELP_MESSAGE { pod2usage(-output=>shift); return }
sub VERSION_MESSAGE { say {shift} q$serlog.pl v1.00$; return }
$Getopt::Std::STANDARD_HELP_VERSION = 1;
getopts('', \my %opts) or pod2usage;
pod2usage unless @ARGV==1;
my $CONFIGFILE = $ARGV[0];
#TODO: execute $CONFIGFILE

local $SIG{__WARN__} = sub { warn "[".scalar(gmtime)." UTC] (PID $$) ".shift };
local $SIG{__DIE__} = sub { die "[".scalar(gmtime)." UTC] (PID $$) FATAL ".shift };
my $run=1;
local $SIG{INT} = sub { warn "Caught SIGINT, stopping...\n"; $run=0 };
local $SIG{TERM} = sub { warn "Caught SIGTERM, stopping...\n"; $run=0 };
local $|=1;

# ### Main Loop ###
use Device::SerialPort 1.04 ();

my $do_status = sub {
		local $_ = shift;
		$HANDLE_STATUS->();
		print $_ if length $_;
	};

warn "Entering main loop...\n";
$do_status->("START");
MAINLOOP: while($run) {
	if (!-e $SERIALPORT) {
		$do_status->("DISCONNECT");
		warn "Warning: $SERIALPORT doesn't exist - unplugged? Waiting...\n";
		while ($run && !-e $SERIALPORT) { sleep 1 } # wait for it to reappear
		last MAINLOOP unless $run;
		warn "Notice: $SERIALPORT has (re-)appeared, continuing\n";
		sleep 1; # wait for any init the OS might have to do
	}
	my $port = Device::SerialPort->new($SERIALPORT);
	last MAINLOOP unless $run;
	unless ($port) {
		error("Can't open $SERIALPORT: $!");
		sleep 1; # slow down error rate and retries
		next MAINLOOP;
	}
	$port->handshake('none');
	$port->baudrate($BAUDRATE);
	$port->parity('none');
	$port->databits(8);
	$port->stopbits(1);
	$port->read_char_time(0); # don't wait for each character
	$port->read_const_time(10000); # timeout for unfulfilled "read" call
	$do_status->("CONNECT");
	my $buf='';
	READLOOP: while($run) {
		my ($incnt, $in) = $port->read(1);
		last MAINLOOP unless $run;
		# handle read failures
		unless ($incnt && $incnt==1) {
			sleep 1; # wait for possible unplugging to register in filesystem; also slow down error rate
			if (!-e $SERIALPORT) { # it's probably been unplugged
				undef $port;
				next MAINLOOP;
			}
			else { error("Read failed (timeout?)") }
			next READLOOP;
		}
		warn "Warning: Byte outside of valid range: ".ord($in)
			if ord($in)<0 || ord($in)>255;
		# handle a line
		if ($in eq "\x0A") {
			local $_ = $buf;
			s/\x0D$//; # CRLF -> LF (that means we handle LF and CRLF, but not pure CR)
			$HANDLE_LINE->(); # feed chomped line through user code
			print $_ if length $_;
			$buf = '';
		}
		# just a regular byte of input
		else { $buf .= $in }
	}
}

$do_status->("STOP");
warn "Normal exit\n";
exit;


# ### Subs ###

sub error {
	my ($msg) = @_;
	state $errs = 0;
	if (++$errs>=$MAX_ERRORS)
		{ die "Error: $msg; too many errors ($errs), aborting\n" }
	else
		{ warn "Error: $msg; continuing ($errs errors)\n" }
	return;
}
