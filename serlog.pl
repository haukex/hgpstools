#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

This script reads line-based data (CRLF or LF) from a serial port,
optionally checks and rewrites it, and writes it to C<STDOUT>.
It also handles USB devices being hot-plugged.

 serlog.pl (CONFIGFILE|-C) [-p PORT] [-b BAUD] [-o OUTFILE]

B<Warning:> C<CONFIGFILE> will be executed by this script. Only use files you trust!

C<CONFIGFILE> must be an absolute filename.
If you don't want to specify a config file and use the defaults instead,
you must specify the C<-C> switch. In either case, you can optionally
set or override the settings from the config file with the command line
options shown above.

=head1 DETAILS

This logger writes received data and status messages to C<STDOUT>,
and log messages to C<STDERR>. The data written to C<STDOUT> can be
manipulated by the routines defined in the configuration.
The C<CONFIGFILE> must be a Perl file and can define the following variables.
The config file must return a true value (typically by ending with C<1;>).

=over

=item C<$SERIALPORT> - The filename of the serial port device.
The default is F</dev/ttyUSB0>.
This setting can be overridden with the C<-p> command line option.

=item C<$BAUDRATE> - The baud rate. The default is 9600.
This setting can be overridden with the C<-b> command line option.

=item C<$HANDLE_LINE> - This must be a code reference, it is called for
every line received. The line is passed via C<$_> I<with the end-of-line stripped>,
and the code can check and manipulate C<$_>.
The resulting value of C<$_> is written to C<STDOUT>.
The default code only adds a newline character, everything else received
on the serial port is passed through unchanged.

=item C<$HANDLE_STATUS> - Like C<$HANDLE_LINE>, but for status messages
from this script itself ("CONNECT", "DISCONNECT", etc.). If you don't want
these status messages mixed in with the received data, do C<$_="";>.

=item C<$OUTFILE> - If set, this specifies the filename to which output
should be redirected (append mode).
The default is for this to be unset, meaning data is written to STDOUT.
This setting can be overridden with the C<-o> command line option.

=item C<$MAX_ERRORS> - The maximum number of errors that may be encountered
while reading from the serial port before the script terminates. Once in a
while there may be intermittent errors on a serial port, and this setting
allows the script to continue when they happen, while preventing an infinite
loop of errors if there is a permanent problem with the port.
The default is 100.

=back

You may send a C<SIGHUP> to this process for it to reload the configuration file
and reopen the serial port (note that this can sometimes cause a read error);
for example: C<pkill -HUP -f serlog>.
The process can be stopped cleanly via a C<SIGTERM> or C<SIGINT> (typically C<Ctrl-C>).
If you have set an C<$OUTFILE>, you can send the process a C<SIGUSR1>
for that output file to be reopened (useful for e.g. L<logrotate(8)>).

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

and then your device will always be available as F</dev/usb_gps>
(you may need to do a C<sudo service udev restart>).
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

# ### Default Settings ###
our $SERIALPORT = '/dev/ttyUSB0';
our $BAUDRATE = 9600;
our $HANDLE_LINE = sub { $_.="\n" };
our $HANDLE_STATUS = sub { $_.="\n" };
our $OUTFILE = undef;
our $MAX_ERRORS = 100;

# ### Init Code ###
use Getopt::Std 'getopts';
use Pod::Usage 'pod2usage';
use File::Spec::Functions qw/ file_name_is_absolute /;

sub HELP_MESSAGE { pod2usage(-output=>shift); return }
sub VERSION_MESSAGE { say {shift} q$serlog.pl v1.00$; return }
$Getopt::Std::STANDARD_HELP_VERSION = 1;
getopts('Cp:b:o:', \my %opts) or pod2usage;
our $NO_CONFIGFILE = !!$opts{C};
our $OVRD_SERIALPORT = $opts{p};
our $OVRD_BAUDRATE = $opts{b};
our $OVRD_OUTFILE = $opts{o};
pod2usage('invalid baud rate')
	if defined $OVRD_BAUDRATE && $OVRD_BAUDRATE!~/^\d+$/;
our $CONFIGFILE;
if ($NO_CONFIGFILE)
	{ pod2usage if @ARGV }
else {
	pod2usage unless @ARGV==1;
	$CONFIGFILE = $ARGV[0];
	pod2usage('configuration filename must be absolute')
		unless file_name_is_absolute($CONFIGFILE);
}

local $SIG{__WARN__} = sub { warn "[".scalar(gmtime)." UTC] (PID $$) ".shift };
local $SIG{__DIE__} = sub { die "[".scalar(gmtime)." UTC] (PID $$) FATAL ".shift };

load_config() unless $NO_CONFIGFILE;
open_output();

# ### Main Loop ###
use Device::SerialPort 1.04 ();

my $do_status = sub {
		local $_ = shift;
		$HANDLE_STATUS->();
		print $_ if length $_;
	};

my $run=1;
my $reload=0;
my $signaled=0;
local $SIG{INT}  = sub { warn "Caught SIGINT, stopping...\n"; $run=0 };
local $SIG{TERM} = sub { warn "Caught SIGTERM, stopping...\n"; $run=0 };
local $SIG{HUP}  = sub { warn "Caught SIGHUP, reloading...\n"; $reload=1 };
local $SIG{USR1} = sub { warn "Caught SIGUSR1, reopening output...\n"; $signaled=1; open_output() };

warn "Entering main loop...\n";
$do_status->("START");
MAINLOOP: while($run) {
	if ($reload) {
		$do_status->("RELOAD");
		if ($NO_CONFIGFILE) { warn "Note: No config file to reload\n" }
		else { load_config() }
		open_output();
		$reload=0;
	}
	if (!-e $SERIALPORT) {
		$do_status->("DISCONNECT");
		warn "Warning: $SERIALPORT doesn't exist - unplugged? Waiting...\n";
		while ($run && !$reload && !-e $SERIALPORT) { sleep 1 } # wait for it to reappear
		last MAINLOOP unless $run;
		next MAINLOOP if $reload;
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
	READLOOP: while($run && !$reload) {
		$signaled=0;
		my ($incnt, $in) = $port->read(1);
		last MAINLOOP unless $run;
		next MAINLOOP if $reload;
		# handle read failures
		unless ($incnt && $incnt==1) {
			sleep 1; # wait for possible unplugging to register in filesystem; also slow down error rate
			if (!-e $SERIALPORT) { # it's probably been unplugged
				undef $port;
				next MAINLOOP;
			}
			elsif($signaled) {} # read() returned due to a signal that we handled, not an error
			else { error("Read failed (timeout?)") }
			next READLOOP;
		}
		warn "Warning: Byte outside of valid range: ".ord($in)
			if ord($in)<0 || ord($in)>255;
		# handle a line
		if ($in eq "\x0A") {
			local $_ = $buf;
			#TODO Later: Handle CR as well?
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

sub load_config {
	warn "Loading configuration from $CONFIGFILE...\n";
	unless (my $rv = do $CONFIGFILE) {
		die "Error: couldn't parse $CONFIGFILE: $@" if $@;
		die "Error: couldn't do $CONFIGFILE: $!\n" unless defined $rv;
		die "Error: couldn't run $CONFIGFILE\n" unless $rv;
	}
	$SERIALPORT = $OVRD_SERIALPORT if defined $OVRD_SERIALPORT;
	$BAUDRATE = $OVRD_BAUDRATE if defined $OVRD_BAUDRATE;
	$OUTFILE = $OVRD_OUTFILE if defined $OVRD_OUTFILE;
	return;
}

sub open_output {
	if (defined $OUTFILE) {
		open my $fh, '>>', $OUTFILE or die "Error: Failed to open $OUTFILE for append: $!\n";
		close or error("Failed to close output filehandle: $!");
		select($fh);
	}
	$|=1; ## no critic (RequireLocalizedPunctuationVars)
}

sub error {
	my ($msg) = @_;
	state $errs = 0;
	if (++$errs>=$MAX_ERRORS)
		{ die "Error: $msg; too many errors ($errs), aborting\n" }
	else
		{ warn "Error: $msg; continuing ($errs errors)\n" }
	return;
}
