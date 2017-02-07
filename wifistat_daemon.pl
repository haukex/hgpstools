#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

This script provides a daemon named C<wifistat> which regularly
writes WiFi and other network status info to a file.
Please see F<Daemon_Control.md> for usage information!

=head1 DETAILS

Some of the commands this daemon calls need to be run as C<root>.
This tool simply writes the unparsed STDOUT and STDERR of the various
commands to the file and does not parse them.

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

use Daemon::Control;

exit Daemon::Control->new(
	name         => 'wifistat',
	program      => \&wifistat,
	init_config  => '/etc/default/hgpstools',
	# note we want to run as root so we don't set user & group
	umask        => oct('0022'),
	resource_dir => '/var/run/wifistat/',
	pid_file     => '/var/run/wifistat/wifistat.pid',
	# the stdout_file and stderr_file should normally remain empty
	# so it's ok that they are in /var/run
	stdout_file  => '/var/run/wifistat/wifistat_out.txt',
	stderr_file  => '/var/run/wifistat/wifistat_err.txt',
	fork         => 2, # default = 2 = double-fork
	kill_timeout => 3,
	help         => "Please run `perldoc ".__FILE__."` for help.\n",
	map({$_=>'$local_fs'} qw/lsb_start lsb_stop/),
	map({$_=>"Writes WiFi and other network status info to a file"} qw/lsb_sdesc lsb_desc/),
	# Note: in Daemon::Control Default-Start is currently fixed at "2 3 4 5" and Default-Stop at "0 1 6"
)->run;

use FindBin;
use Capture::Tiny 'capture';
use DexProvider ();

sub wifistat {
	#TODO: A widget to display data from wifistat
	my $DEX = DexProvider->new(srcname=>'wifistat', dexpath=>'_FROM_CONFIG');
	my $MAX_ERRORS = 100;
	my @COMMANDS = (
			[qw/ ifconfig -a /],
			[qw/ iwconfig /],
			[qw/ iwlist scan /], # this requires root access to work
			[qw/ wpa_cli list_networks /],
			[qw/ wpa_cli status /],
		);
	my $DHCP_CMD = ["$FindBin::Bin/dhcpcd_leases.sh"];
	push @COMMANDS, $DHCP_CMD if -e -f -x $$DHCP_CMD[0];
	
	my ($run,$errors) = (1,0);
	local $SIG{INT}  = sub { $run=0 };
	local $SIG{TERM} = sub { $run=0 };
	while($run) {
		my %data = ( _last_update => time );
		for my $cmd (@COMMANDS) {
			my ($stdout, $stderr, $exit) = capture { system(@$cmd) };
			if ($exit!=0) {
				my $msg = "child exited with value ".($?>>8);
				if ($? == -1)
					{ $msg = "failed to execute: $!" }
				elsif ($? & 127)
					{ $msg = sprintf "child died with signal %d, %s ",
					($? & 127),  ($? & 128) ? 'with' : 'without' }
				if (++$errors>$MAX_ERRORS)
					{ die $msg }
				else
					{ warn $msg }
			}
			#TODO Later: We might want to parse the output of the commands further.
			$data{"@$cmd"} = {stdout=>$stdout, stderr=>$stderr, exit=>$exit};
		}
		$DEX->provide(\%data);
		sleep(60*2);
	}
}

