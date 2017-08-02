#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

Configuration file and daemon wrapper for F<ngserlog.pl> that talks to
a Novatel SPAN-IGM-S1 device.

This script talks to the USB2 channel, on which we are only logging
ASCII-format records.

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

our $LOGGER_NAME = 'ngserlog_novatel2txt';
use IdentUsbSerial 'ident_usbser';
our $GET_PORT = sub {
	my @devs = ident_usbser(vend=>'09d7', prod=>'0100');
	return unless @devs;
	warn "Multiple devices found, picking the first\n" if @devs>3;
	my $devtty = $devs[1]{devtty};
	return unless -e $devtty;
	info("Opening port $devtty for Novatel USB2");
	return SerialPort->open($devtty, mode=>'115200,8,n,1',
		timeout_s=>3, flexle=>1 );
};

use Digest::CRC ();
sub novatelcrc {
	my $data = shift;
	return Digest::CRC->new(width=>32, init=>0, xorout=>0,
		refout=>1, refin=>1, cont=>0, poly=>0x04C11DB7)
		->add($data)->digest;
}

use DexProvider ();
my $DEX = DexProvider->new(srcname=>'novatel', interval_s=>1, dexpath=>'_FROM_CONFIG');
our $HANDLE_LINE = sub {
	my $err;
	if (my ($msg,$got) = /\A[#%](.*)\*([0-9a-fA-F]{8})\z/) {
		my $exp = sprintf '%08X', novatelcrc($msg);
		$exp eq uc $got or $err = "Checksum calc $got, exp $exp";
	}
	else
		{ $err = "Invalid format" }
	if ($err) {
		s/\\/\\\\/g; s/([^\x09\x20-\x7E])/sprintf("\\x%02X", ord $1)/eg;
		warn "$err; ignoring input \"$_\"\n";
		$_ = undef;
	}
	else {
		# This is a real data value.
		#TODO: Only provide certain parsed records.
		$DEX->provide({record=>$_});
		$_ .= "\n";
	}
};
our $HANDLE_STATUS = sub {
	# don't log status messages into data stream
	$_ = undef;
};

our $OUTFILE = '/home/pi/data/novatel2txt_data.txt';

our $NGSERLOG;
if (!$NGSERLOG) {
	require Daemon::Control;
	exit Daemon::Control->new(
	name         => $LOGGER_NAME,
	program      => '/home/pi/hgpstools/ngserlog.pl',
	program_args => [ '/home/pi/hgpstools/serloggers/ngserlog_novatel2txt.pl' ],
	init_config  => '/etc/default/hgpstools',
	user         => 'pi',
	group        => 'dialout',
	umask        => oct('0022'),
	help         => "Please run `perldoc ".__FILE__."` for help.\n",
	# note that since we use the "outfile" option above, the stdout_file *should* remain empty
	stdout_file  => '/home/pi/logs/novatel2txt_out.txt',
	# since ngserlog now uses syslog, the stderr_file *should* also remain empty
	stderr_file  => '/home/pi/logs/novatel2txt_err.txt',
	pid_file     => '/home/pi/pidfiles/novatel2txt.pid',
	#resource_dir => '/home/pi/ngserlog/', # currently not needed
	fork         => 2, # default = 2 = double-fork
	kill_timeout => 5, # ngserlog.pl needs *at least* one second to shut down
	lsb_start   => '$local_fs $time',
	lsb_stop    => '$local_fs',
	lsb_sdesc   => "Serial Logger for Novatel (USB2 ASCII)",
	lsb_desc    => "Serial Logger for Novatel (USB2 ASCII)",
	# Note: in Daemon::Control Default-Start is currently fixed at "2 3 4 5" and Default-Stop at "0 1 6"
	)->run;
}

1;
