#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

Configuration file and daemon wrapper for F<ngserlog.pl> that talks to
a Vaisala HMT310 device connected via its USB adapter.

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

our $LOGGER_NAME = 'ngserlog_hmt310';
use IdentUsbSerial 'ident_usbser';
our $GET_PORT = sub {
	my @devs = ident_usbser(vend=>'1843', prod=>'0200');
	return unless @devs;
	warn "Multiple devices found, picking the first\n" if @devs>1;
	my $devtty = $devs[0]{devtty};
	return unless -e $devtty;
	info("Opening port $devtty for HMT310");
	return SerialPort->open($devtty, mode=>'4800,7,e,1',
		stty=>['cs7','parenb','-parodd','raw','-echo'], flexle=>1,
		timeout_s=>3 );
};

our $READ_SIZE = 0;
our $ON_CONNECT = sub {
	my $port = shift;
	# Note: much of this logic is taken from the CPT6100 logger,
	# see its implementation for documentation
	$port->timeout_s(2);
	info('setting HMT310 to streaming mode');
	INITCMD: while (!$port->aborted) {
		$port->write("R\x0D");
		my $in = $port->readline;
		if (defined $in) {
			if ($in eq 'R')
				{ info('streaming mode command executed') }
			else
				{ error("unexpected response from HMT310: \"$in\"") }
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
};
our $ON_TIMEOUT = sub {
	my $port = shift;
	warn "Read timeout, sensor disconnected?\n";
	$ON_CONNECT->($port);
};
our $ON_STOP = sub {
	my $port = shift;
	info('stopping HMT310 streaming mode, may take a little time');
	$port->timeout_s(2);
	my $retries = 0;
	STOPCMD: while (!$port->aborted) {
		$port->write("S\x0D");
		# We don't care about the response, instead just wait until timeout
		my $counter = 0;
		while (defined $port->read(1)) {
			if (++$counter>=256) {
				if (++$retries>=10) {
					error("HMT310 still did not stop streaming, bailing out");
					last STOPCMD;
				}
				warn "HMT310 did not stop streaming yet; retrying...\n";
				next STOPCMD;
			}
		}
		info('stopped HMT310 streaming mode');
		last STOPCMD;
	}
};

use Time::HiRes qw/ gettimeofday /;
use DexProvider ();
my $DEX = DexProvider->new(srcname=>'hmt310', interval_s=>1, dexpath=>'_FROM_CONFIG');
our $HANDLE_LINE = sub {
	return unless length;
	# We currently don't do any further checking of the lines; there is no checksum
	if (my $rec = parse_hmt($_)) {
		$DEX->provide({ data=>
			[ map { [$_,$$rec{val},$$rec{unit}] } sort keys %$rec ] });
	}
	$_ = sprintf("%d.%06d\t%s\n",gettimeofday,$_);
};
our $HANDLE_STATUS = sub {
	$_ = sprintf("%d.%06d\t%s\n",gettimeofday,$_) if length $_;
};

# stuff for parse_hmt
use Carp;
use 5.014; no feature 'switch';
my $HMT_REC_RE =
	qr{ \s* \b
	(?<name> \w+ ) = \s*
	(?<value> -? (?:\d*\.)? \d+ )
	(?: \s*  # unit is optional
		# a unit should not look like a new value
		(?<unit> (?! \w+ = \s* [\-\d\.] ) \S+ )
	)?
	\b \s* }msxaa;
sub parse_hmt {
	my $rec = shift;
	croak "too many arguments to parse_hmt" if @_;
	my %rec;
	pos($rec)=undef;
	while ($rec=~/\G$HMT_REC_RE/gc) {
		carp "HMT310 duplicate value \"$+{name}\"" if $rec{$+{name}};
		$rec{$+{name}} = { val=>$+{value} };
		$rec{$+{name}}{unit} = $+{unit} if defined $+{unit};
	}
	if (length($rec)!=pos($rec)) {
		carp "Not an HMT310 record? \"$rec\"";
		return }
	return \%rec;
}

our $OUTFILE = '/home/pi/data/hmt310_data.txt';
our $NGSERLOG;
if (!$NGSERLOG) {
	require Daemon::Control;
	exit Daemon::Control->new(
	name         => $LOGGER_NAME,
	program      => '/home/pi/hgpstools/ngserlog.pl',
	program_args => [ '/home/pi/hgpstools/serloggers/ngserlog_hmt310.pl' ],
	init_config  => '/etc/default/hgpstools',
	user         => 'pi',
	group        => 'dialout',
	umask        => oct('0022'),
	help         => "Please run `perldoc ".__FILE__."` for help.\n",
	# note that since we use the "outfile" option above, the stdout_file *should* remain empty
	stdout_file  => '/home/pi/logs/hmt310_out.txt',
	# since ngserlog now uses syslog, the stderr_file *should* also remain empty
	stderr_file  => '/home/pi/logs/hmt310_err.txt',
	pid_file     => '/home/pi/pidfiles/hmt310.pid',
	#resource_dir => '/home/pi/ngserlog/', # currently not needed
	fork         => 2, # default = 2 = double-fork
	kill_timeout => 10, # ngserlog.pl needs *at least* one second to shut down, this script needs even longer
	lsb_start   => '$local_fs $time',
	lsb_stop    => '$local_fs',
	lsb_sdesc   => "Serial Logger for HMT310",
	lsb_desc    => "Serial Logger for HMT310",
	# Note: in Daemon::Control Default-Start is currently fixed at "2 3 4 5" and Default-Stop at "0 1 6"
	)->run;
}

1;
