#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

This script provides a daemon wrapper for C<gpsd2file.pl>
and can also generate an appropriate init script to install in C</etc/init.d/>.

=head1 DETAILS

See also C<gpsd2file_daemon.pl --help> and the code for details on the configuration.

To install and run the daemon:

 ./gpsd2file_daemon.pl get_init_file | sudo tee /etc/init.d/gpsd2file
 sudo chmod -c 755 /etc/init.d/gpsd2file
 sudo update-rc.d gpsd2file defaults
 sudo service gpsd2file start

To stop and remove the daemon:

 sudo service gpsd2file stop
 sudo update-rc.d -f gpsd2file remove
 sudo rm /etc/init.d/gpsd2file

For more information, see C<serlog_nmea_daemon.pl>, which is a similar script.

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
	program      => '/home/pi/hgpstools/gpsd2file.pl',
	program_args => [ '-i5', '-f/var/run/gpsd2file/gpsd.json' ],
	user         => 'pi',
	group        => 'pi',
	umask        => oct('0022'),
	help         => "Please run `perldoc $0` for help.\n",
	resource_dir => '/var/run/gpsd2file/',
	pid_file     => '/var/run/gpsd2file/gpsd2file.pid',
	fork         => 2, # default = 2 = double-fork
	kill_timeout => 3,
	lsb_start   => 'gpsd lighttpd',
	lsb_stop    => 'gpsd lighttpd',
	lsb_sdesc   => "Writes gpsd json data to a file",
	lsb_desc    => "Writes gpsd json data to a file",
	# Note: in Daemon::Control Default-Start is currently fixed at "2 3 4 5" and Default-Stop at "0 1 6"
)->run;

