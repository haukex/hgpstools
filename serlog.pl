#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

### BEGIN INIT INFO
# Provides:          serialdaemon_gps
# Required-Start:    $local_fs $time
# Required-Stop:     $local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
### END INIT INFO

=head1 SYNOPSIS

This is a daemon that logs line-based data (CRLF or LF) from a serial port;
the default version stores GPS NMEA data with an added timestamp.
It also handles USB devices being hot-plugged.

 serialdaemon_gps.pl start|stop|status

=head1 DETAILS

Note that although I've had this script running reliably for a while,
it's still a little rough around the edges in that configuration and
customization requires editing the script itself (configuration options
are variables set at the beginning of the script).

The subroutine stored in C<$HANDLE_LINE> handles checking input format as
well as manipulating the input lines (such as adding timestamps).
If you want this script to handle something other than NMEA, you can modify
that subroutine. Another simple possibility is to set C<$CHECK_NMEA> to
a false value, and then the current C<$HANDLE_LINE> implementation
simply logs input lines with a timestamp without checking their format.

The subroutine stored in C<$HANDLE_STATUS> handles the manipulation of
status messages from the daemon such as "start", "stop", "connect" and "disconnect".
By default it outputs the messages with a timestamp (i.e. they are mixed
in with the NMEA stream).

This script contains an init script header, and it can be installed
as a service directly, as follows (adjust paths as necessary).
This script attempts to change its UID and GID as configured, which
is useful when running as root.

 sudo ln -vs /home/user/serialdaemon_gps.pl /etc/init.d/serialdaemon_gps
 sudo update-rc.d serialdaemon_gps defaults
 sudo service serialdaemon_gps start

(It can be removed via C<sudo update-rc.d -f serialdaemon_gps remove>.)
For more information on init scripts see L<https://wiki.debian.org/LSBInitScripts> and L<insserv(8)>.
Note this script does not fully implement the spec, such as the "restart"
command or all of the exit codes.

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

my $DEBUG = 0;

# the following $user just decides between my computer and my RPi,
# you can do this however you like
my $user = -e '/home/haukex' ? 'haukex' : 'pi';
die "I'm not sure what box I'm running on, please check the configuration"
	unless -e "/home/$user";
my $WANT_UID = getpwnam($user) or die "failed to get UID";
my $WANT_GID = getgrnam($user) or die "failed to get GID";
my $WANT_GRP2 = getgrnam('dialout') or die "failed to get GID of dialout";
my $WANT_UMASK = oct('0027');
my $SERIALPORT = '/dev/usb_gps';
my $BAUDRATE = 4800;
my $PIDFILE = "/home/$user/serialdaemon/serialdaemon_gps.pid";
my $OUTFILE = "/home/$user/serialdaemon/gps_out.txt";
my $ERRFILE = "/home/$user/serialdaemon/gps_err.txt";
my $MAX_ERRORS = 100;

use Time::HiRes qw/ gettimeofday /;
# the following variables configure the current $HANDLE_LINE implementation
my $STRIP_NULS = 1; # strip NULs at beginning and end of lines (seems to happen sometimes)
my $CHECK_NMEA = 1;
my $ESCAPE_NONPRINTABLE = 1; # escape all nonprintable and non-ASCII chars
my $HANDLE_LINE = sub { # code should edit $_; return value ignored
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
my $HANDLE_STATUS = sub { # code should edit $_; return value ignored
	return unless length $_; # nothing needed
	unless (/^[A-Za-z0-9_]/) {
		warn "Ignoring invalid status \"$_\"\n";
		undef $_;
		return;
	}
	$_ = sprintf("%d.%06d\t%s\n",gettimeofday,$_) if length $_;
	return;
};

# ###

# FIRST, set our PID/GID/umask
set_uid_gid();
umask $WANT_UMASK;
die "Error: umask change failed" unless umask==$WANT_UMASK;

# ### Daemon Stuff ###
use Getopt::Std 'getopts';
use Pod::Usage 'pod2usage';
use FindBin;
# we want to use our patched version of Daemon::Daemonize until a new version gets released
# see also http://github.com/robertkrimen/Daemon-Daemonize/pull/2
use lib "$FindBin::RealBin/Daemon-Daemonize/lib";
use Daemon::Daemonize 0.0052_01 qw/ check_pidfile write_pidfile delete_pidfile daemonize /;

sub HELP_MESSAGE { pod2usage(-output=>shift); return }
sub VERSION_MESSAGE { say {shift} q$serialdaemon.pl v1.00$; return }
$Getopt::Std::STANDARD_HELP_VERSION = 1;
getopts('', \my %opts) or pod2usage;
pod2usage unless @ARGV==1;
my $STARTSTOP = $ARGV[0];

my $oldpid = check_pidfile($PIDFILE);
if ($STARTSTOP eq 'stop') {
	$oldpid or die "Error: Daemon is not running, can't stop\n";
	if ( kill('TERM', $oldpid)==1 )
		{ warn "Sent SIGTERM to PID $oldpid\n"; exit }
	else
		{ die "Error: Failed to signal PID $oldpid" }
}
elsif ($STARTSTOP eq 'start') {
	$oldpid and die "Error: Daemon is already running as PID $oldpid\n";
}
elsif ($STARTSTOP eq 'status') {
	warn $oldpid
		? "Status: Daemon is running as PID $oldpid\n"
		: "Status: Daemon is not running\n" ;
	exit;
}
else { pod2usage }

warn "Daemonizing...\n";
daemonize(stdout=>$OUTFILE, stderr=>$ERRFILE, umask=>$WANT_UMASK);
local $SIG{__WARN__} = sub { warn "[".scalar(gmtime)." UTC] (PID $$) ".shift };
local $SIG{__DIE__} = sub { die "[".scalar(gmtime)." UTC] (PID $$) FATAL ".shift };
my $run=1;
local $SIG{INT} = sub { warn "Caught SIGINT, stopping...\n"; $run=0 };
local $SIG{TERM} = sub { warn "Caught SIGTERM, stopping...\n"; $run=0 };
local $|=1;
write_pidfile($PIDFILE);
my $PID_FILE_WRITTEN = 1;
END { delete_pidfile($PIDFILE) if $PID_FILE_WRITTEN }
die "Error: desired umask not in effect" unless umask==$WANT_UMASK;


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

sub set_uid_gid {
	# reduce permissions by changing user & group
	# (in case this is run by root, which is likely under init)
	warn "Debug: Before: RUID=$<, EUID=$>, RGID=$(, EGID=$), umask=".sprintf("%o",umask)."\n" if $DEBUG;
	if ( $) !~ /^$WANT_GID\b.*\b$WANT_GRP2\b/ ) {
		$) = "$WANT_GID $WANT_GRP2";  ## no critic (RequireLocalizedPunctuationVars)
		die "Error: EGID change failed: $!" if $! || $) ne "$WANT_GID $WANT_GRP2";
	}
	if ( $( != $WANT_GID ) {
		$( = $WANT_GID;  ## no critic (RequireLocalizedPunctuationVars)
		die "Error: RGID change failed: $!" if $! || $( != $WANT_GID;
	}
	if ( $> != $WANT_UID ) {
		$> = $WANT_UID;  ## no critic (RequireLocalizedPunctuationVars)
		die "Error: EUID change failed: $!" if $! || $> != $WANT_UID;
	}
	if ( $< != $WANT_UID ) {
		$< = $WANT_UID;  ## no critic (RequireLocalizedPunctuationVars)
		die "Error: RUID change failed: $!" if $! || $< != $WANT_UID;
	}
	warn "Debug: After: RUID=$<, EUID=$>, RGID=$(, EGID=$), umask=".sprintf("%o",umask)."\n" if $DEBUG;
	return;
}

