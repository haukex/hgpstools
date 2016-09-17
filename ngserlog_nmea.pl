#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

TODO: Document

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

use lib '/home/pi/hgpstools';

use IO::Stty (); # because we use "stty" option below
use IdentUsbSerial 'ident_usbser';
our $GET_PORT = sub {
	my @devs = ident_usbser(vend=>'067b', prod=>'2303'); # Navilock NL-302U
	return unless @devs;
	my $devtty = $devs[0]{devtty};
	return unless -e $devtty;
	info "Opening port $devtty for NEMA data";
	return SerialPort->open($devtty, mode=>'4800,8,n,1',
		stty=>['raw','-echo'], flexle=>1, timeout_s=>3 );
};

use Time::HiRes qw/ gettimeofday /;
our $HANDLE_LINE = sub {
	s/^\x00*|\x00*$//g;
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
	if ($err) {
		s/([^\x09\x20-\x7E])/sprintf("\\x%02X", ord $1)/eg;
		warn "Ignoring input ($err): $_\n";
		undef $_;
		return;
	}
	# escape all nonprintable and non-ASCII chars
	s/([^\x09\x20-\x7E])/sprintf("\\x%02X", ord $1)/eg;
	$_ = sprintf("%d.%06d\t%s\n",gettimeofday,$_) if length $_;
};
our $HANDLE_STATUS = sub {
	$_ = sprintf("%d.%06d\t%s\n",gettimeofday,$_) if length $_;
};

our $OUTFILE = '/home/pi/ngserlog/nmea_data.txt';

our $NGSERLOG;
if (!$NGSERLOG) {
	require Daemon::Control;
	exit Daemon::Control->new(
	name         => 'ngserlog_nmea',
	program      => '/home/pi/hgpstools/ngserlog.pl',
	program_args => [ '/home/pi/hgpstools/ngserlog_nmea.pl' ],
	user         => 'pi',
	group        => 'dialout',
	umask        => oct('0027'),
	help         => "Please run `perldoc ".__FILE__."` for help.\n",
	# note that since we use the "outfile" option above, the stdout_file *should* remain empty
	stdout_file  => '/home/pi/ngserlog/nmea_out.txt',
	stderr_file  => '/home/pi/ngserlog/nmea_err.txt',
	pid_file     => '/home/pi/ngserlog/nmea.pid',
	resource_dir => '/home/pi/ngserlog/',
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
