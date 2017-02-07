#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

This script provides a daemon named C<gpsd2file> which regularly
writes the most recently received data from L<gpspipe(1)> into a file.
Please see F<Daemon_Control.md> for usage information!

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
	name         => 'gpsd2file',
	program      => \&gpsd2file,
	init_config  => '/etc/default/hgpstools',
	user         => 'pi',
	group        => 'pi',
	umask        => oct('0022'),
	resource_dir => '/var/run/gpsd2file/',
	pid_file     => '/var/run/gpsd2file/gpsd2file.pid',
	# the stdout_file and stderr_file should normally remain empty
	stdout_file  => '/var/run/gpsd2file/gpsd2file_out.txt',
	stderr_file  => '/var/run/gpsd2file/gpsd2file_err.txt',
	fork         => 2, # default = 2 = double-fork
	kill_timeout => 3,
	help         => "Please run `perldoc ".__FILE__."` for help.\n",
	map({$_=>'gpsd lighttpd'} qw/lsb_start lsb_stop/),
	map({$_=>"Writes gpsd json data to a file"} qw/lsb_sdesc lsb_desc/),
	# Note: in Daemon::Control Default-Start is currently fixed at "2 3 4 5" and Default-Stop at "0 1 6"
)->run;

use JSON::MaybeXS qw/decode_json/;
use DexProvider ();

sub gpsd2file {
	#TODO: A widget to display data from gpsd2file
	my $DEX = DexProvider->new(srcname=>'gpsd2file', dexpath=>'_FROM_CONFIG',
		interval_s=>5);
	my $MAX_ERRORS = 100;
	
	my ($run,$errors) = (1,0);
	local $SIG{INT}  = sub { $run=0 };
	local $SIG{TERM} = sub { $run=0 };
	open my $gps, '-|', qw/ gpspipe -wPtu -T %s /
		or die "Failed to open gpspipe: $!";
	my %alldata;
	LINE: while (<$gps>) {
		last unless $run;
		chomp;
		my ($time,$json) = /^(\d+(?:\.\d+)?):\s*(\{.+\})\s*$/;
		if (!defined $json) {
			warn "Unexpected line format: \"$_\"";
			if (++$errors>$MAX_ERRORS)
				{ last LINE } else { next LINE }
		}
		my $data = decode_json($json);
		$alldata{$$data{class}//'UNKNOWN'} = { time=>$time, data=>$data };
		$DEX->provide(\%alldata);
	}
	close $gps or die $! ? "Error closing pipe: $!" : "Exit status $?";
}
