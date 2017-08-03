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
See F<ngserlog_nmea.pl> for a similar script that has a bit more documentation.

=head1 DETAILS

To get the Linux kernel driver C<usbserial> to reliably recognize the Novatel
appears to be a little finicky, as there are different commands that only seem
to work on specific Raspbian versions (perhaps due to differences in the kernel
drivers across versions, but I'm not yet sure).

The following is a combination of two different commands that each worked
separately on two different RPis, and in total it appears to work reliably.

Create the file C</root/novatel.sh> with permissions 755 and the following
contents:

 #!/bin/sh
 date >>/var/log/novatel-init.log
 /sbin/modprobe usbserial vendor=0x09d7 product=0x0100
 echo 09d7 0100 >/sys/bus/usb-serial/drivers/generic/new_id

Then create the file F</etc/udev/rules.d/90-novatel.rules> with the
following contents:

 SUBSYSTEM=="usb", ATTR{idProduct}=="0100", ATTR{idVendor}=="09d7", RUN+="/root/novatel.sh"

Running the above script should set up the Novatel device without requiring a
reboot, and the C<udev> rule should take care of doing so automatically on boot.

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

our $LOGGER_NAME = 'ngserlog_novatel1ctrl';
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
	#{ name=>'INSPOS', type=>'both', rate=>'ONTIME 1' },
	#{ name=>'INSVEL', type=>'both', rate=>'ONTIME 1' },
	#{ name=>'INSATT', type=>'both', rate=>'ONTIME 1' },
	#{ name=>'INSPVA', type=>'both', rate=>'ONTIME 1' },
	
	# Empfohlen für Postprocessing
	#{ name=>'RANGECMP',            type=>'binary', rate=>'ONTIME 1' },
	#{ name=>'RAWEPHEM',            type=>'binary', rate=>'ONTIME 1' },
	#{ name=>'GLOEPHEMERIS',        type=>'binary', rate=>'ONTIME 1' },
	#{ name=>'RAWIMUSX',            type=>'binary', rate=>'ONTIME 1' },
	#{ name=>'IMUTOANTOFFSETS',     type=>'binary', rate=>'ONTIME 1' },
	#{ name=>'VEHICLEBODYROTATION', type=>'binary', rate=>'ONTIME 1' },
	
	# Von Alex
	{ name=>'IMURATECORRIMUS', type=>'ascii', rate=>'ONTIME 0.05' },
	{ name=>'IMURATEPVAS',     type=>'ascii', rate=>'ONTIME 0.05' },
	
); # ##### ##### ##### ##### ##### #####
my @NOVATEL_INITCMDS = (
	# ### Aus Novatel Wizzard ###
	# Set IMU Orientation, Z points up (default)
	#q{SETIMUORIENTATION 5},
	# Set Vehicle to Body Rotation
	#q{VEHICLEBODYROTATION 0.000000 0.000000 0.000000 0.000000 0.000000 0.000000},
	#q{APPLYVEHICLEBODYROTATION disable},
	# Set Lever Arm Offset
	#q{SETIMUTOANTOFFSET 0.000000 0.000000 0.000000 0.000000 0.000000 0.000000},
	#q{SETINSOFFSET 0.000000 0.000000 0.000000},
	# Stationary Alignment
	#q{ALIGNMENTMODE UNAIDED},
	#q{SETINITATTITUDE 0.000000 0.000000 0.000000 1.000000 1.000000 1.000000},
	
	# ### von Alex, aus dem Wizard ###
	q{SETIMUORIENTATION 6},
	# option 6 turns the IMU axis down (around alpha by 180 deg), THEN around the down
	# pointing gamma axis by 90 degrees. Result (old -> new): Z -> -Z, Y -> X, X -> Y
	q{VEHICLEBODYROTATION 0 0 -90 0 0 0}, # beacause X and Y axis between body and IMU
	# frame of reference are interchanged, the IMU has to be turnbed by 90 degrees to the left
	q{APPLYVEHICLEBODYROTATION ENABLE},
	q{SETIMUTOANTOFFSET -0.1 -4 -1 1 1 1}, # antenna offset regarding the
	# TRANSFORMED IMU frame of reference AND VEHICLEBODYROTATION applied.
	#q{SETINSOFFSET 0 0 0},
	q{ALIGNMENTMODE UNAIDED},
	q{SETINITATTITUDE 0 0 0 1 1 1}, # dummy command for manual alignment
	# ### Allgemeines ###
	# Enable asynchronous INS logs (IMURATECORRIMUS and IMURATEPVAS)
	q{ASYNCHINSLOGGING ENABLE},
);
my @NOVATEL_ADDCMDS = (
	# ### Additional Comands after IMU initialisation ###
	# if manual alignment mode has been selected, a SETINITATTITUDE command must be sent
	# to the IMU, however, the IMU does not align correctly if the command is sent for
	# initialisation only. Resending the command eliminates this weird behavior and
	# forces the IMU to a sucessfully alignment.
	q{SETINITATTITUDE 0 0 0 1 1 1},
	# pitch/alhpa, roll/beta, azimuth/gamma in (transformed) IMU frame of reference
	# example regarding the WINGPOD: 'SETINITATTITUDE 5 -5 290 5 5 5' means:
	# IMU frame of reference: alpha=5, beta=-5, azimuth=290
	# WINGPOD frame of reference: beta=-5, alpha=5, azimuth=200
);

# ### BEGIN INTERFACE HACK STUFF ### (see novatelcmd_hack.pl)
my $INTERFACE_HACK_PATH = '/var/run/novatelctrl'; # created by Daemon::Control (below)
use Fcntl qw/:flock/;
our $ON_SIGUSR2 = sub {
	my $port = shift;
	state %seen_files;
	opendir my $dh, $INTERFACE_HACK_PATH
		or do { warn "$INTERFACE_HACK_PATH: $!"; return };
	my @files = map { $_->[0] }
		sort { $a->[1] <=> $b->[1] }
		map { [$_, (stat)[9] ] } # sort by mtime
		grep { -f && -s && /\.cmd\z/i && !$seen_files{$_} }
		map {"$INTERFACE_HACK_PATH/$_"} readdir $dh;
	close $dh;
	@files or warn "No command files to run?\n";
	FILE: for my $fn (@files) {
		$seen_files{$fn}++;
		open my $fh, '<', $fn or do { warn "$fn: $!"; next FILE };
		flock($fh,LOCK_EX) or die "flock $fn: $!";
		my $cmd = do { local $/; <$fh> };
		close $fh;
		info("Executing command \"$cmd\"");
		$port->write($cmd."\x0D\x0A");
		_logcmd($cmd);
		unlink($fn) and delete $seen_files{$fn};
	}
};
# ### END INTERFACE HACK STUFF ###

use DexProvider ();
my $DEX = DexProvider->new(srcname=>'novatel_cmds', dexpath=>'_FROM_CONFIG');
my $CMDLOG_LIMIT=20;
sub _logcmd {
	my $msg = shift;
	state @cmdlog;
	return unless defined $msg;
	my @msgs = grep {/\S/} split /\x0D\x0A?/, $msg;
	return unless @msgs;
	for (@msgs)
		{ s/\\/\\\\/g; s/([^\x09\x20-\x7E])/sprintf("\\x%02X", ord $1)/eg; }
	push @cmdlog, @msgs;
	@cmdlog>$CMDLOG_LIMIT and splice @cmdlog, 0, @cmdlog-$CMDLOG_LIMIT;
	$DEX->provide({cmdlog=>\@cmdlog});
	return;
}

our $ON_CONNECT = sub {
	my $usb1 = shift;
	# Restore Factory Default Settings
	#_novatel_docmd($usb1,"FRESET"); # NO, this fully resets the device, not just the config
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
	# (note "true" is needed to also disable logs "held" with the "HOLD" parameter)
	_novatel_docmd($usb1,"UNLOGALL TRUE");
	# test the logging of ASCII data to USB2 and binary data to USB3
	_novatel_docmd($usb1,"LOG USB2 VERSIONA ONCE");
	_novatel_docmd($usb1,"LOG USB3 VERSIONB ONCE");
	# Novatel initialization commands
	_novatel_docmd($usb1,$_) for @NOVATEL_INITCMDS;
	sleep(1);
	_novatel_docmd($usb1,$_) for @NOVATEL_ADDCMDS;
	# Configure the logs
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
	_novatel_docmd($usb1, "UNLOGALL USB2 TRUE");
	_novatel_docmd($usb1, "UNLOGALL USB3 TRUE");
};
my %DOCMD_KNOWN_OPTS = map {$_=>1} qw/ empty_ok /;
sub _novatel_docmd {
	my ($port,$cmd,%opts) = @_;
	exists $DOCMD_KNOWN_OPTS{$_} or warn "Bad option '$_'" for keys %opts;
	$port->write($cmd."\x0D\x0A");
	_logcmd($cmd);
	my $in = do { local $/=']'; $port->readline };
	_logcmd($in);
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
	_logcmd($_);
	# escape all nonprintable and non-ASCII chars
	s/\\/\\\\/g; s/([^\x09\x20-\x7E])/sprintf("\\x%02X", ord $1)/eg;
	$_ .= "\n";
};
our $HANDLE_STATUS = sub {
	# don't need to log status messages
	$_ = undef;
};

our $OUTFILE = '/home/pi/data/novatel1ctrl_data.txt';

our $NGSERLOG;
if (!$NGSERLOG) {
	require Daemon::Control;
	exit Daemon::Control->new(
	name         => $LOGGER_NAME,
	program      => '/home/pi/hgpstools/ngserlog.pl',
	program_args => [ '/home/pi/hgpstools/serloggers/ngserlog_novatel1ctrl.pl' ],
	init_config  => '/etc/default/hgpstools',
	user         => 'pi',
	group        => 'dialout',
	umask        => oct('0022'),
	help         => "Please run `perldoc ".__FILE__."` for help.\n",
	# note that since we use the "outfile" option above, the stdout_file *should* remain empty
	stdout_file  => '/home/pi/logs/novatel1ctrl_out.txt',
	# since ngserlog now uses syslog, the stderr_file *should* also remain empty
	stderr_file  => '/home/pi/logs/novatel1ctrl_err.txt',
	pid_file     => '/home/pi/pidfiles/novatel1ctrl.pid',
	#resource_dir => '/home/pi/ngserlog/', # currently not needed
	resource_dir => $INTERFACE_HACK_PATH, # INTERFACE HACK (see novatelcmd_hack.pl)
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
