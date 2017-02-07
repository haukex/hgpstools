#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

Configuration file and daemon wrapper for F<ngserlog.pl> that talks to
a Mensor CPT6100 device connected to a FTDI 4-port RS-485 to USB adapter.
It is assumed that there is only one sensor on each RS-485 port.

You must set the environment variable C<CPT_FTDI_PORT> to either
C<port0>, C<port1>, C<port2>, or C<port3> to indicate which of the
FTDI ports you want to access. You will need to set up one daemon
per port (if desired), they will be named C<cpt6100_portX>.

B<This is an alpha version> that needs more documentation. (TODO)
See F<ngserlog_nmea.pl> for a similar script that has a bit more documentation.

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

use FindBin;
use lib "$FindBin::Bin/..";
use local::lib '/home/pi/perl5';

die "You need to set the CPT_FTDI_PORT environment variable, "
	."acceptable values are port0, port1, port2, port3\n"
	unless length $ENV{CPT_FTDI_PORT} && $ENV{CPT_FTDI_PORT}=~/^port([0-3])$/i;
my $FTDIPORT = $1;

my $DNAME = "cpt6100_port$FTDIPORT";
our $LOGGER_NAME = "ngserlog_$DNAME";
use IdentUsbSerial 'ident_usbser';
our $GET_PORT = sub {
	my @devs = ident_usbser(vend=>'0403', prod=>'6011');
	return unless @devs;
	warn "Multiple devices found, picking the first\n" if @devs>4;
	my $devtty = $devs[$FTDIPORT]{devtty};
	return unless -e $devtty;
	info("Opening port $devtty for CPT6100 Port $FTDIPORT");
	return SerialPort->open($devtty, mode=>'9600,8,n,1',
		timeout_s=>2, flexle=>0, irs=>"\x0D\x0A", chomp=>1 );
};

our $READ_SIZE = 0; # will be changed later
our $ON_CONNECT = sub {
	my $port = shift;
	$port->timeout_s(2);
	info('setting CPT6100 to streaming mode');
	INITCMD: while (!$port->aborted) {
		$port->write("#*M 6\x0D");
		my $in = $port->read(1);
		if (defined $in) {
			if ($in eq 'R')
				{ info('streaming mode command executed') }
			elsif ($in eq '#') {
				# Testing has shown that when our custom RS-485 cable is
				# disconnected from the FTDI adapter, the command we sent
				# is simply echoed back.
				my $in2 = $port->read(5); # read rest of echoed command
				if (defined $in2 && $in2 eq "*M 6\x0D") {
					warn "Recevied echo, RS-485 cable disconnected from FTDI?\n";
					# treat it like a timeout; slow down retries a bit
					sleep 5; # should also be interrupted by signals
					next INITCMD;
				}
				else
					{ error("unexpected response from CPT6100: \"$in".($in2//'').'"') }
			}
			else
				{ error("unexpected response from CPT6100: \"$in\"") }
			# Note we drop out of the INITCMD loop here because either
			# this response is junk, or it might be binary sensor data.
			# If the init command didn't work, the following attempts
			# to read sensor data will time out anyway, which will
			# cause a new attempt at initializing the sensor.
			last INITCMD;
		}
		elsif ($port->timed_out) {
			warn "Read timeout on init, sensor disconnected?\n";
			$port->timeout_s(5); # slow down retries a bit
		}
		else {
			my $prob = $port->eof ? "EOF" : ($port->aborted ? "Aborted" : "Unknown");
			error("read problem on init: $prob");
			return }
	}
	$port->timeout_s(2);
	$READ_SIZE = 5;
};
our $ON_TIMEOUT = sub {
	my $port = shift;
	warn "Read timeout, sensor disconnected?\n";
	# On timeout, we attempt re-initialization, because it's possible
	# the sensor was temporarily disconnected at the RS-485 end, and
	# was therefore powered down and is no longer in streaming mode.
	$ON_CONNECT->($port);
};
our $ON_STOP = sub {
	my $port = shift;
	info('stopping CPT6100 streaming mode, may take a little time');
	$port->timeout_s(2);
	my $retries = 0;
	STOPCMD: while (!$port->aborted) {
		$port->write("#*M 3\x0D");
		# We expect a response of "R" to this command, but the sensor is
		# likely to still be streaming data, so instead of looking for
		# an "R", which could easily be present in the binary data stream,
		# we wait until timeout.
		my $counter = 0;
		while (defined $port->read(1)) {
			if (++$counter>=256) {
				if (++$retries>=10) {
					error("CPT6100 still did not stop streaming, bailing out");
					last STOPCMD;
				}
				warn "CPT6100 did not stop streaming yet; retrying...\n";
				next STOPCMD;
			}
		}
		info('stopped CPT6100 streaming mode');
		last STOPCMD;
	}
	$READ_SIZE = 0;
};

use Time::HiRes qw/ gettimeofday /;
our $HANDLE_LINE = sub {
	state $sumerrors = 0;
	state $resyncing = 0;
	if ($resyncing) {
		$_ = undef;
		$READ_SIZE = 5;
		$resyncing = 0;
		$sumerrors = 0;
		return;
	}
	if ( my ($val,$hex) = press_decode($_) ) {
		$_ = sprintf "%d.%06d\t0x%s\t%f\n", gettimeofday, $hex, $val;
		$sumerrors = 0;
	}
	else {
		$_ = undef;
		# If we get too many consecutive checksum errors, we have to assume
		# that we lost sync with the data stream. In this case, we attempt
		# to resync by reading and discarding a single byte. If we're off
		# by more than one byte, we'll have to repeat this a few times.
		# A different method to reacquire sync would be to read in a buffer
		# of 10-15 bytes and then scan it until we get a checksum match.
		# The current method, which is easier to implement, just takes a
		# bit longer, and since we currently don't get many resync errors
		# it's fine for now.
		if (++$sumerrors>10) {
			warn "Too many checksum errors, attempting resync\n";
			$READ_SIZE = 1;
			$resyncing = 1;
			return;
		}
	}
};
sub press_decode {
	my ($data,$nowarn) = @_;
	my ($val,$got_sum) = unpack 'f>C', $data; # big-endian
	my (@by) = unpack "C4", $data; # bytes
	my $calc_sum = ($by[0]+$by[1]+$by[2]+$by[3])&0xFF;
	if ($calc_sum == $got_sum) {
		return $val, join('', map {sprintf '%02X', $_} @by);
	}
	else {
		warn "Checksum calc $calc_sum, rx $got_sum\n" unless $nowarn;
		return;
	}
}
our $HANDLE_STATUS = sub {
	$_ = sprintf("%d.%06d\t%s\n",gettimeofday,$_) if length $_;
};

our $OUTFILE = "/home/pi/data/${DNAME}_data.txt";
our $NGSERLOG;
if (!$NGSERLOG) {
	require Daemon::Control;
	exit Daemon::Control->new(
	name         => $LOGGER_NAME,
	program      => '/home/pi/hgpstools/ngserlog.pl',
	program_args => [ '/home/pi/hgpstools/serloggers/ngserlog_cpt6100.pl' ],
	init_code    => qq{export CPT_FTDI_PORT="port$FTDIPORT"\n},
	user         => 'pi',
	group        => 'dialout',
	umask        => oct('0027'),
	help         => "Please run `perldoc ".__FILE__."` for help.\n",
	# note that since we use the "outfile" option above, the stdout_file *should* remain empty
	stdout_file  => "/home/pi/logs/${DNAME}_out.txt",
	# since ngserlog now uses syslog, the stderr_file *should* also remain empty
	stderr_file  => "/home/pi/logs/${DNAME}_err.txt",
	pid_file     => "/home/pi/pidfiles/${DNAME}.pid",
	#resource_dir => '/home/pi/ngserlog/', # currently not needed
	fork         => 2, # default = 2 = double-fork
	kill_timeout => 10, # ngserlog.pl needs *at least* one second to shut down, this script needs even longer
	lsb_start   => '$local_fs $time',
	lsb_stop    => '$local_fs',
	lsb_sdesc   => "Serial Logger for CPT6100 (Port $FTDIPORT)",
	lsb_desc    => "Serial Logger for CPT6100 (Port $FTDIPORT)",
	# Note: in Daemon::Control Default-Start is currently fixed at "2 3 4 5" and Default-Stop at "0 1 6"
	)->run;
}

1;
