#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

This script provides a daemon wrapper for C<serlog.pl> with C<serlog_conf_nmea.pl>
and can also generate an appropriate init script to install in C</etc/init.d/>.

See also C<serlog_nmea_daemon.pl --help> and the code for details on the configuration.
This file can be copied and adapted to create other C<serlog.pl>-based daemons.

=head1 DETAILS

To install and run the daemon:

 serlog_nmea_daemon.pl get_init_file | sudo tee /etc/init.d/serlog_nmea
 sudo chmod 755 /etc/init.d/serlog_nmea
 sudo update-rc.d serlog_nmea defaults
 sudo service serlog_nmea start

To stop and remove the daemon:

 sudo service serlog_nmea stop
 sudo update-rc.d -f serlog_nmea remove
 sudo rm /etc/init.d/serlog_nmea

Additional useful commands:

 /etc/init.d/serlog_nmea status    # current status
 sudo service serlog_nmea status   # check the service status
 sudo service serlog_nmea reload   # reload the config file

For even more information, see L<Daemon::Control>,
L<https://wiki.debian.org/LSBInitScripts> and L<insserv(8)>.

I<Note:> At the moment, L<Daemon::Control> does not support setting
multiple group IDs. As a workaround, in order to access the serial port,
currently the group C<dialout> is used. This means that files created
will be in that group.
See also L<https://github.com/symkat/Daemon-Control/pull/60>.

There is an example L<logrotate(8)> configuration in the file
F<serlog_nmea.logrotate> that you can either call directly via
C<logrotate serlog_nmea.logrotate> or set up for daily exection via

 sudo ln -s /home/pi/hgpstools/serlog_nmea.logrotate /etc/logrotate.d/serlog_nmea

B<Note> that L<logrotate(8)> will B<delete old log files> in this configuration,
so by itself it is B<not> a solution for long-term data archival.

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
	name         => 'serlog_nmea',
	program      => '/home/pi/hgpstools/serlog.pl',
	program_args => [
		'-o', '/home/pi/serlog/nmea_data.txt',
		'/home/pi/hgpstools/serlog_conf_nmea.pl' ],
	user         => 'pi',
	group        => 'dialout',
	umask        => oct('0027'),
	help         => "Please run `perldoc $0` for help.\n",
	# note that since we use the -o option above, the stdout_file *should* remain empty
	stdout_file  => '/home/pi/serlog/nmea_out.txt',
	stderr_file  => '/home/pi/serlog/nmea_err.txt',
	pid_file     => '/home/pi/serlog/nmea.pid',
	resource_dir => '/home/pi/serlog/',
	fork         => 2, # default = 2 = double-fork
	kill_timeout => 5, # serlog.pl needs *at least* one second to shut down
	lsb_start   => '$local_fs $time',
	lsb_stop    => '$local_fs',
	lsb_sdesc   => "Serial Logger for NMEA Data",
	lsb_desc    => "Serial Logger for NMEA Data",
	# Note: in Daemon::Control Default-Start is currently fixed at "2 3 4 5" and Default-Stop at "0 1 6"
)->run;

