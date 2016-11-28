#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

Configuration file and daemon wrapper for F<ngserlog.pl> that talks to
a Novatel SPAN-IGM-S1 device.

This script talks to the USB3 channel, on which we are only logging
Binary-format records.

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

use IdentUsbSerial 'ident_usbser';
our $GET_PORT = sub {
	my @devs = ident_usbser(vend=>'09d7', prod=>'0100');
	return unless @devs;
	warn "Multiple devices found, picking the first\n" if @devs>3;
	my $devtty = $devs[2]{devtty};
	return unless -e $devtty;
	info("Opening port $devtty for Novatel USB3");
	return SerialPort->open($devtty, mode=>'115200,8,n,1',
		timeout_s=>3, flexle=>0, chomp=>0, cont=>1 );
};

use Digest::CRC ();
sub novatelcrc {
	my $data = shift;
	return Digest::CRC->new(width=>32, init=>0, xorout=>0,
		refout=>1, refin=>1, cont=>0, poly=>0x04C11DB7)
		->add($data)->digest;
}

use constant {
	STATE_FIND_SYNC_1 => 0,
	STATE_FIND_SYNC_2 => 1,
	STATE_FIND_SYNC_3 => 2,
	STATE_HDR_LEN     => 3,
	STATE_HEADER      => 4,
	STATE_MESSAGE     => 5,
	STATE_CRC         => 6,
};
our $READ_SIZE = 1;
our $HANDLE_LINE = sub {
	state $state = STATE_FIND_SYNC_1;
	state $curbuf = '';
	state $calc_crc;
	my $data = $_;
	# don't output by default; instead accumulate in $curbuf until checksum
	$_ = undef;
	$curbuf .= $data;
	if ($state == STATE_FIND_SYNC_1) {
		$curbuf = $data; # reset buffer
		if ($data eq "\xAA")
			{ $state = STATE_FIND_SYNC_2 }
		else { lostsync() }
	}
	elsif ($state == STATE_FIND_SYNC_2) {
		if ($data eq "\x44")
			{ $state = STATE_FIND_SYNC_3 }
		else
			{ lostsync(); $state = STATE_FIND_SYNC_1 }
	}
	elsif ($state == STATE_FIND_SYNC_3) {
		if ($data eq "\x12")
			{ $state = STATE_HDR_LEN }
		else
			{ lostsync(); $state = STATE_FIND_SYNC_1 }
	}
	elsif ($state == STATE_HDR_LEN) {
		my ($hdrlen) = unpack 'C', $data;
		$READ_SIZE = $hdrlen - 4; # already read the sync bytes & length
		$state = STATE_HEADER;
	}
	elsif ($state == STATE_HEADER) {
		my ($mid,$mtype,$port,$msglen) = unpack 'vcCv', $data;
		$READ_SIZE = $msglen;
		$state = STATE_MESSAGE;
	}
	elsif ($state == STATE_MESSAGE) {
		$calc_crc = novatelcrc($curbuf);
		$READ_SIZE = 4;
		$state = STATE_CRC;
	}
	elsif ($state == STATE_CRC) {
		my ($got_crc) = unpack 'V', $data;
		if ($got_crc == $calc_crc)
			{ $_ = $curbuf } # ok, now output whole buffer
		else
			{ warn "Checksum calc $calc_crc, rx $got_crc" }
		$calc_crc = undef;
		$READ_SIZE = 1;
		$state = STATE_FIND_SYNC_1;
	}
};
sub lostsync {
	state $counter = 0;
	# don't flood the logs too much, just every X times this happens
	if (++$counter>=10) {
		warn "Lost sync 10 times since last reported";
		$counter = 0;
	}
}
our $HANDLE_STATUS = sub {
	# don't log status messages into data stream
	$_ = undef;
};

our $OUTFILE = '/home/pi/data/novatel3bin_data.dat';

our $NGSERLOG;
if (!$NGSERLOG) {
	require Daemon::Control;
	exit Daemon::Control->new(
	name         => 'ngserlog_novatel3bin',
	program      => '/home/pi/hgpstools/ngserlog.pl',
	program_args => [ '/home/pi/hgpstools/serloggers/ngserlog_novatel3bin.pl' ],
	user         => 'pi',
	group        => 'dialout',
	umask        => oct('0027'),
	help         => "Please run `perldoc ".__FILE__."` for help.\n",
	# note that since we use the "outfile" option above, the stdout_file *should* remain empty
	stdout_file  => '/home/pi/logs/novatel3bin_out.txt',
	# since ngserlog now uses syslog, the stderr_file *should* also remain empty
	stderr_file  => '/home/pi/logs/novatel3bin_err.txt',
	pid_file     => '/home/pi/pidfiles/novatel3bin.pid',
	#resource_dir => '/home/pi/ngserlog/', # currently not needed
	fork         => 2, # default = 2 = double-fork
	kill_timeout => 5, # ngserlog.pl needs *at least* one second to shut down
	lsb_start   => '$local_fs $time',
	lsb_stop    => '$local_fs',
	lsb_sdesc   => "Serial Logger for Novatel (USB3 Binary)",
	lsb_desc    => "Serial Logger for Novatel (USB3 Binary)",
	# Note: in Daemon::Control Default-Start is currently fixed at "2 3 4 5" and Default-Stop at "0 1 6"
	)->run;
}

1;
