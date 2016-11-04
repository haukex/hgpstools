#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

Configuration file and daemon wrapper for F<ngserlog.pl> that talks to
a Novatel SPAN-IGM-S1 device.

This script talks to the USB1 channel, which we are using as a control
channel.

B<This is an alpha version> that needs more documentation. (TODO)

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

use IdentUsbSerial 'ident_usbser';
our $GET_PORT = sub {
	my @devs = ident_usbser(vend=>'09d7', prod=>'0100');
	return unless @devs;
	warn "Multiple devices found, picking the first\n" if @devs>3;
	my $devtty = $devs[0]{devtty};
	return unless -e $devtty;
	info("Opening port $devtty for Novatel USB1");
	return SerialPort->open($devtty, mode=>'115200,8,n,1',
		timeout_s=>3, flexle=>0, chomp=>0 );
};

my @LOGS = ( # ##### ##### ##### Novatel Logs ##### ##### #####
	# Parameter:
	# - name: Name des Logs, *ohne* "B" (Binaer) oder "A" (ASCII) am Ende
	# - type: Entweder "binary", "ascii" oder "both"
	# - rate: Angabe der Logging-Rate, siehe Novatel Firmware Handbuch
	#         (Beispiele: "ONCHANGED", "ONNEW", "ONTIME 1", "ONTIME 0.1")
	
	# Beispiel zum Loggen der IMU Daten
	{ name=>'INSPOS', type=>'both', rate=>'ONTIME 1' },
	{ name=>'INSVEL', type=>'both', rate=>'ONTIME 1' },
	{ name=>'INSATT', type=>'both', rate=>'ONTIME 1' },
	{ name=>'INSPVA', type=>'both', rate=>'ONTIME 1' },
	
	# Empfohlen für Postprocessing
	#{ name=>'RANGECMP',            type=>'binary', rate=>'ONTIME 1' },
	#{ name=>'RAWEPHEM',            type=>'binary', rate=>'ONTIME 1' },
	#{ name=>'GLOEPHEMERIS',        type=>'binary', rate=>'ONTIME 1' },
	#{ name=>'RAWIMUSX',            type=>'binary', rate=>'ONTIME 1' },
	#{ name=>'IMUTOANTOFFSETS',     type=>'binary', rate=>'ONTIME 1' },
	#{ name=>'VEHICLEBODYROTATION', type=>'binary', rate=>'ONTIME 1' },
	
	# Von Alex
	#{ name=>'CORRIMUDATAS', type=>'binary', rate=>'ONTIME 1' },
	#{ name=>'INSPVAS',      type=>'binary', rate=>'ONTIME 1' },
	
); # ##### ##### ##### ##### ##### #####

our $ON_CONNECT = sub {
	my $usb1 = shift;
	# Turn on the "[USBx]" prompt and "<OK" response for the control port.
	# If the response+prompt was previously turned off, we won't get a response.
	# Since in that case we can't determine if the device is functioning or not,
	# send the command a second time and we should always get a response then.
	_novatel_docmd($usb1,"INTERFACEMODE USB1 NOVATEL NOVATEL ON", empty_ok=>1);
	_novatel_docmd($usb1,"INTERFACEMODE USB1 NOVATEL NOVATEL ON");
	# Disable the prompt and response on USB2 and USB3 (logging only)
	_novatel_docmd($usb1,"INTERFACEMODE USB2 NOVATEL NOVATEL OFF");
	_novatel_docmd($usb1,"INTERFACEMODE USB3 NOVATEL NOVATEL OFF");
	# Disable all logs (in case there were some running)
	_novatel_docmd($usb1,"UNLOGALL");
	# test the logging of ASCII data to USB2 and binary data to USB3
	_novatel_docmd($usb1,"LOG USB2 VERSIONA ONCE");
	_novatel_docmd($usb1,"LOG USB3 VERSIONB ONCE");
	for my $log (@LOGS) {
		if (lc $log->{type} eq 'ascii' || lc $log->{type} eq 'both') {
			_novatel_docmd($usb1,"LOG USB2 ".$log->{name}."A ".$log->{rate});
		}
		if (lc $log->{type} eq 'binary' || lc $log->{type} eq 'both') {
			_novatel_docmd($usb1,"LOG USB3 ".$log->{name}."B ".$log->{rate});
		}
	}
	info('Novatel initialized');
};
our $ON_STOP = sub {
	my $usb1 = shift;
	info('Stopping Novatel logging');
	_novatel_docmd($usb1, "UNLOGALL USB2");
	_novatel_docmd($usb1, "UNLOGALL USB3");
};
my %DOCMD_KNOWN_OPTS = map {$_=>1} qw/ empty_ok /;
sub _novatel_docmd {
	my ($port,$cmd,%opts) = @_;
	exists $DOCMD_KNOWN_OPTS{$_} or warn "Bad option '$_'" for keys %opts;
	$port->write($cmd."\x0D\x0A");
	my $in = do { local $/=']'; $port->readline };
	if (!defined $in && $opts{empty_ok})
		{ info("Command Sent: \"$cmd\"\n") }
	elsif (defined $in && $in=~/^\x0D\x0A<OK\x0D\x0A\[(?:USB|COM)\d\]$/)
		{ info("Command Successful: \"$cmd\"\n") }
	else
		{ error("Unexpected response to command \"$cmd\": \"$in\"") }
}

# note we don't expect to receive any data on this port since
# it's only used for control commands
our $HANDLE_LINE = sub {
	# escape all nonprintable and non-ASCII chars
	s/\\/\\\\/g; s/([^\x09\x20-\x7E])/sprintf("\\x%02X", ord $1)/eg;
	$_ .= "\n";
};
our $HANDLE_STATUS = sub {
	# don't need to log status messages
	$_ = undef;
};

our $OUTFILE = '/home/pi/ngserlog/novatel1ctrl_data.txt';

our $NGSERLOG;
if (!$NGSERLOG) {
	require Daemon::Control;
	exit Daemon::Control->new(
	name         => 'ngserlog_novatel1ctrl',
	program      => '/home/pi/hgpstools/ngserlog.pl',
	program_args => [ '/home/pi/hgpstools/serloggers/ngserlog_novatel1ctrl.pl' ],
	user         => 'pi',
	group        => 'dialout',
	umask        => oct('0027'),
	help         => "Please run `perldoc ".__FILE__."` for help.\n",
	# note that since we use the "outfile" option above, the stdout_file *should* remain empty
	stdout_file  => '/home/pi/ngserlog/novatel1ctrl_out.txt',
	# since ngserlog now uses syslog, the stderr_file *should* also remain empty
	stderr_file  => '/home/pi/ngserlog/novatel1ctrl_err.txt',
	pid_file     => '/home/pi/ngserlog/novatel1ctrl.pid',
	resource_dir => '/home/pi/ngserlog/',
	fork         => 2, # default = 2 = double-fork
	kill_timeout => 5, # ngserlog.pl needs *at least* one second to shut down
	lsb_start   => '$local_fs $time ngserlog_novatel2txt ngserlog_novatel3bin',
	lsb_stop    => '$local_fs ngserlog_novatel2txt ngserlog_novatel3bin',
	lsb_sdesc   => "Serial Logger for Novatel (USB1 Control)",
	lsb_desc    => "Serial Logger for Novatel (USB1 Control)",
	# Note: in Daemon::Control Default-Start is currently fixed at "2 3 4 5" and Default-Stop at "0 1 6"
	)->run;
}

1;
