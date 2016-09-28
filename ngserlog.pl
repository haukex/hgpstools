#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

This is a logger for serial ports based on L<SerialPort|SerialPort>
with USB-to-serial hot-plugging support.

 ngserlog.pl CONFIGFILE

=head1 DESCRIPTION

Together with a configuration file, this is a logger for a serial port
based on L<SerialPort|SerialPort> which supports hot-plugging of USB
devices. It writes received data and status messages to C<STDOUT> or to an
output file, and log messages to C<syslog>. The data written to the output
can be manipulated by the routines defined in the configuration.

The C<syslog> messages will be logged as program name C<ngserlog>, facility
C<user>, and if you're using C<rsyslog>, you can redirect them to another
log file with the following example configuration file,
F</etc/rsyslog.d/00-ngserlog.conf>:

 $template ngserlogFormat,"%timegenerated% %pri-text% %syslogtag%%msg:::drop-last-lf%\n"
 if $programname == 'ngserlog' then /var/log/ngserlog.log;ngserlogFormat
 & ~

The process can be stopped cleanly via a C<SIGTERM> or C<SIGINT>
(typically C<Ctrl-C>).

You may need to add the user to the group C<dialout> (in Debian, this
normally gives full and direct access to serial ports):

 sudo adduser <username> dialout

If you're connecting multiple USB devices to your system and you don't want
to figure out the device name every time, you can use L<udev(7)>. Create
a file like the following in F</etc/udev/rules.d/> (e.g. F<90-usbgps.rules>):

 ATTRS{idVendor}=="067b", ATTRS{idProduct}=="2303", SYMLINK+="usb_gps"

and then your device will always be available as F</dev/usb_gps>
(you may need to do a C<sudo service udev restart>).
(The above IDs are for a Navilock NL-302U.)
There is also the module L<IdentUsbSerial|IdentUsbSerial>.

Hint: For debugging, you can simply C<cat /dev/ttyUSB0> after setting
the serial port speed via e.g. C<stty -F /dev/ttyUSB0 4800 raw>.
Also, you can use L<minicom(1)>: C<minicom -D/dev/ttyUSB0>
(configure via C<Ctrl-A o>, exit via C<Ctrl-A q>)
or L<screen(1)>: C<screen /dev/ttyUSB0 4800> (exit via C<Ctrl-A \>)

This is Version 0.01 of this script.
B<This is a beta version.>

=head2 CONFIGURATION FILE

The configuration file must be a Perl file which defines the following
global variables.
The config file must return a true value (typically by ending with C<1;>).

B<Warning:> The configuration file will be executed by this script.
Only use files you trust!
It is strongly recommended that you specify the configuration file name
with an absolute pathname.

The variable C<$NGSERLOG> (package C<main>) will be set before the config
file is loaded; if the config file has a second purpose (such as a
L<Daemon::Control|Daemon::Control> script), it should I<not> execute any
code other than setting the configuration variables if C<$NGSERLOG> is set.

Any arguments on the command line after the configuration file name will
be preserved in C<@ARGV> so the configuration file may use them; the
configuration file must leave C<@ARGV> empty when it is done!

The output of the routines defined in the configuration file will be
redirected: Anything C<print>ed will go to the output file if it is
configured, and C<warn>ing and C<die> messages will go to the C<syslog>.
The configuration file can also make use of the C<info> and C<error>
functions provided by this script (package C<main>) to log to C<syslog>
at "info" level or to report recoverable errors, respectively.
The configuration file should I<not> make use of Perl's one-argument
C<select> function, should not install or change C<$SIG{__WARN__}> or
C<$SIG{__DIE__}> handlers, and should not manipluate C<STDOUT> or C<STDERR>
in any other way! Note these redirects are I<not> yet active while the
configuration file is being loaded.

=head3 C<$GET_PORT>

This code reference should return an opened L<SerialPort|SerialPort>
object, C<undef> if the port is temporarily unavailable (e.g. USB
device is unplugged), or throw an exception (C<die>) if there is some
other type of error. Note that if the port is currently unplugged,
this function will be called approximately once per second.

You can set whatever options you like on the port; note that
C<eof_fatal> is turned off by this script. The C<flexle> option
is recommended. You can set the C<timeout_s> to as long as you wish,
as signals will still interrupt the wait. 
The configuration file may make use of something like
L<IdentUsbSerial|IdentUsbSerial> to identify the port.

Example:

 our $GET_PORT = sub {
	SerialPort->open('/dev/ttyUSB0',mode=>'9600,8,n,1',flexle=>1) };

=head3 C<$READ_SIZE>

This defaults to zero (0), which tells L<SerialPort|SerialPort> to
read one line at a time. Set this to a positive integer to read that
many bytes at a time. Note that in this case, the L<SerialPort|SerialPort>
setting C<cont> is strongly recommended. Of course, if this option is
set, L</$HANDLE_LINE> won't be passed lines, it will be passed records
of the requested size.

Note that you may change this setting from the L</$HANDLE_LINE> function,
in which case the next read and the corresponding call to L</$HANDLE_LINE>
will read resp. be called with the updated number of bytes.

=head3 C<$HANDLE_LINE>

This function should take the currently received line in the C<$_>
variable, optionally check, filter and/or reformat it, and set C<$_>
either to the string that should be written to the output, or to the empty
string (or C<undef>) for no output to be written. Note that you must
append a newline character to the output if desired.

It is suggested to use the L<SerialPort|SerialPort> options C<flexle>
or C<chomp>. 

=head3 C<$HANDLE_STATUS>

Like L</$HANDLE_LINE>, this function should take a the status message
in C<$_> (currently C<"START">, C<"CONNECT">, C<"DISCONNECT">, or
C<"STOP">) and set C<$_> to either a string to be written to the output,
or the empty string or C<undef> for no output.

=head3 C<$OUTFILE>

Either C<undef> for C<STDOUT>, or a filename for the output to be written
to (append mode).
You can send the process a C<SIGUSR1> and it will reopen this file
(useful for e.g. L<logrotate(8)>).

=head3 C<$ON_START>

This code will be executed once per run of this script, the first time
the serial port has been opened. The serial port object is passed as the
first argument.

=head3 C<$ON_CONNECT>

This code will be executed once every time the serial port is opened.
The serial port object is passed as the first argument.

This is also a good place to set C<$/>, if desired.

=head3 C<$ON_TIMEOUT>

This code will be executed every time a read from the serial port times
out. The serial port object is passed as the first argument.

=head3 C<$ON_STOP>

This code will be executed on a normal exit; B<however>, note that at this
point it is also possible that the port has been disconnected already, or
that this code may not be executed at all in the case of other errors. In
other words, do not rely on this code always being able to talk to the
serial port. Under normal circumstances, it should normally be called on
C<SIGINT> and C<SIGTERM>.
The serial port object is passed as the first argument.

=head3 C<$SYSLOG_TO_STDERR>

Setting this boolean option causes the syslog messages to be printed
to C<STDERR> as well.

=head3 C<$MAX_ERRORS>

The maximum number of errors that may be encountered while reading from
the serial port before the script terminates. Once in a while there may be
intermittent errors on a serial port, and this setting allows the script
to continue when they happen, while preventing an infinite loop of errors
if there is a permanent problem with the port. The default is 100.

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
our $GET_PORT = sub { die "Configuration file does not define \$GET_PORT" };
our $READ_SIZE = 0;
our $HANDLE_LINE = sub { $_.="\n" };
our $HANDLE_STATUS = sub { $_.="\n" };
our $OUTFILE = undef;
our $ON_START = sub {};
our $ON_CONNECT = sub {};
our $ON_TIMEOUT = sub {};
our $ON_STOP = sub {};
our $SYSLOG_TO_STDERR = 0;
our $MAX_ERRORS = 100;
# ###

use Getopt::Std 'getopts';
use Pod::Usage 'pod2usage';
use Sys::Syslog qw/openlog syslog closelog/;
use SerialPort;

sub HELP_MESSAGE { pod2usage(-output=>shift); return }
sub VERSION_MESSAGE { say {shift} q$ngserlog.pl v0.01$; return }
$Getopt::Std::STANDARD_HELP_VERSION = 1;
getopts('', \my %opts) or pod2usage;
pod2usage unless @ARGV;
my $CONFIGFILE = shift @ARGV;
die "Bad configuration file name $CONFIGFILE" unless -f -r $CONFIGFILE;
our $NGSERLOG=1; # inform the config file that it is being loaded by us
require $CONFIGFILE;
pod2usage if @ARGV;

my $syslogopts = $SYSLOG_TO_STDERR ? 'ndelay,pid,perror' : 'ndelay,pid';
openlog('ngserlog',$syslogopts,'user');
sub info {
	chomp(my $msg = shift);
	warn "Too many arguments to info()\n" if @_;
	syslog('info','Info: %s',$msg);
	return;
}
local $SIG{__WARN__} = sub { chomp(my $m = shift); syslog('warning','Warn: %s',$m) };
local $SIG{__DIE__}  = sub { chomp(my $m = shift); syslog('err','Error: %s',$m) };

# ### Main Loop ###

sub open_output {
	if (defined $OUTFILE) {
		open my $fh, '>>', $OUTFILE  ## no critic (RequireBriefOpen)
			or die "Error: Failed to open $OUTFILE for append: $!\n";
		close or error("Failed to close output filehandle: $!");
		select($fh);  ## no critic (ProhibitOneArgSelect)
	}
	$|=1; ## no critic (RequireLocalizedPunctuationVars)
	return;
}
open_output();
local $SIG{USR1} = sub { info "Caught SIGUSR1, reopening output...\n"; open_output() };

my $run=1;
local $SIG{INT}  = sub { info "Caught SIGINT, stopping...\n";  $run=0 };
local $SIG{TERM} = sub { info "Caught SIGTERM, stopping...\n"; $run=0 };

my $do_status = sub {
		local $_ = shift;
		$HANDLE_STATUS->();
		print $_ if length $_;
	};

my $discon_informed = 0; # only inform once per disconnect event
my $on_start_run = 0;
info "Entering main loop...\n";
$do_status->("START");
MAINLOOP: while($run) {
	my $port;
	eval {
		$port = $GET_PORT->();
	1 } or do {
		error("Couldn't open port: ".($@//'unknown error'));
		sleep 1;
		next MAINLOOP;
	};
	if (!defined $port) {
		if (!$discon_informed) {
			info "Device not connected (unplugged?) Waiting...\n";
			$do_status->("DISCONNECT");
			$discon_informed = 1;
		}
		sleep 1;
		next MAINLOOP;
	}
	$discon_informed = 0;
	info "Device available, conntected to serial port\n";
	$do_status->("CONNECT");
	if (!$on_start_run) {
		$ON_START->($port);
		$on_start_run = 1;
	}
	$ON_CONNECT->($port);
	$port->eof_fatal(0);
	local $SIG{INT}  = sub { info "Caught SIGINT, stopping...\n";  $port->abort; $run=0 };
	local $SIG{TERM} = sub { info "Caught SIGTERM, stopping...\n"; $port->abort; $run=0 };
	READLOOP: while($run) {
		my $line = $port->read($READ_SIZE);
		if (!defined $line) {
			if ($port->eof) { sleep 1; last READLOOP }; # likely unplug
			if ($port->aborted) { $run=0; last READLOOP; }
			if ($port->timed_out) { $ON_TIMEOUT->($port); next READLOOP; }
			# The above statements should handle all the cases in which
			# read/readline returns undef, so this should be unreachable.
			die "Unexpected read of undef";
		}
		local $_ = $line;
		$HANDLE_LINE->();
		print $_ if length $_;
	}
	$ON_STOP->($port) unless $run;
	$port->close or error("Couldn't close the port: $!");
}
info "Normal exit\n";
$do_status->("STOP");
closelog;
exit;

# ### Subs ###

sub error {
	chomp(my $msg = shift);
	warn "Too many arguments to error()\n" if @_;
	state $errs = 0;
	if (++$errs>=$MAX_ERRORS)
		{ die "$msg; too many errors ($errs), aborting\n" }
	else
		{ warn "$msg; continuing ($errs errors)\n" }
	return;
}
