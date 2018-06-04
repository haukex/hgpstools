#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

This script provides a daemon wrapper for C<dex_relay.pl>.
The daemon is named C<dex_relay>.
Please see F<Daemon_Control.md> for usage information!

=head1 AUTHOR, COPYRIGHT, AND LICENSE

Copyright (c) 2018 Hauke Daempfling (haukex@zero-g.net)
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

use FindBin ();
use Daemon::Control;

die <<"ENDMSG"
Environment variable DEX_RELAY_TARGET must be set.
See $FindBin::Script and /etc/default/dex_relay
ENDMSG
	unless $ENV{DEX_RELAY_TARGET};

exit Daemon::Control->new(
	name         => 'dex_relay',
	program      => "$FindBin::Bin/dex_relay.pl",
	program_args => [ $ENV{DEX_RELAY_TARGET},
		( length($ENV{DEX_RELAY_SOURCE}) ? $ENV{DEX_RELAY_SOURCE} : () ) ],
	init_config  => '/etc/default/dex_relay',
	user         => 'pi',
	group        => 'pi',
	umask        => oct('0022'),
	resource_dir => '/var/run/dex_relay/',
	pid_file     => '/var/run/dex_relay/pid.pid',
	stdout_file  => '/var/run/dex_relay/out.txt', # should remain empty
	# errors may appear in err.txt
	stderr_file  => '/var/run/dex_relay/err.txt',
	fork         => 2, # default = 2 = double-fork
	kill_timeout => 3,
	help         => "Please run `perldoc ".__FILE__."` for help.\n",
	map({$_=>'$network $local_fs'} qw/lsb_start lsb_stop/),
	map({$_=>"DEX Relay"} qw/lsb_sdesc lsb_desc/),
	# Note: in Daemon::Control Default-Start is currently fixed at "2 3 4 5" and Default-Stop at "0 1 6"
)->run;

