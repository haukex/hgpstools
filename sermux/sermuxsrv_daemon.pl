#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

This script provides a daemon wrapper for C<serialmuxserver.pl>.
The daemon is named C<sermuxsrv>.
Please see F<Daemon_Control.md> for usage information!

Depends on certain environment variables being set.
See file F<etc_default_sermuxsrv>!

=head1 AUTHOR, COPYRIGHT, AND LICENSE

Copyright (c) 2017 Hauke Daempfling (haukex@zero-g.net)
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
Environment variables SERMUXSRV_USER, SERMUXSRV_GROUP and SERMUXSRV_CONFIG
must be set. See $FindBin::Script and /etc/default/sermuxsrv
ENDMSG
	unless $ENV{SERMUXSRV_USER} && $ENV{SERMUXSRV_GROUP}
	&& $ENV{SERMUXSRV_CONFIG};

exit Daemon::Control->new(
	name         => 'sermuxsrv',
	program      => "$FindBin::Bin/serialmuxserver.pl",
	program_args => [ $ENV{SERMUXSRV_CONFIG} ],
	init_config  => '/etc/default/sermuxsrv',
	user         => $ENV{SERMUXSRV_USER},
	group        => $ENV{SERMUXSRV_GROUP},
	umask        => oct('0022'),
	resource_dir => '/var/run/sermuxsrv/',
	pid_file     => '/var/run/sermuxsrv/pid.pid',
	# the stdout_file and stderr_file should normally remain empty
	# so it's ok that they are in /var/run
	stdout_file  => '/var/run/sermuxsrv/out.txt',
	stderr_file  => '/var/run/sermuxsrv/err.txt',
	fork         => 2, # default = 2 = double-fork
	kill_timeout => 3,
	help         => "Please run `perldoc ".__FILE__."` for help.\n",
	lsb_start    => '$local_fs $time',
	lsb_stop     => '$local_fs',
	map({$_=>"Multiplexing Serial Port Server"} qw/lsb_sdesc lsb_desc/),
	# Note: in Daemon::Control Default-Start is currently fixed at "2 3 4 5" and Default-Stop at "0 1 6"
)->run;

