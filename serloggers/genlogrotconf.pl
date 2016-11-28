#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

A very simple script that generates L<logrotate(8)> configurations
for the currently known serial loggers.

Use this script to generate a configuration file, then either call it
directly for debugging, or link it into the L<logrotate(8)> config path:

 ./genlogrotconf.pl > ngserloggers.logrotate
 logrotate -d ngserloggers.logrotate
 sudo ln -s /home/pi/hgpstools/serloggers/ngserloggers.logrotate /etc/logrotate.d/ngserloggers

B<Warning:> L<logrotate(8)> will B<delete old log files> in this
configuration, so by itself it is B<not> a solution for long-term
data archival.

B<Warning:> This script assumes that all the loggers follow the convention
that is currently in use for the naming of files:
All files are in F</home/pi/ngserlog/> and the PID, data, STDOUT, and
STDERR files are named, respectively,
F<< <LOGGER>.pid >>, F<< <LOGGER>_data.txt >>,
F<< <LOGGER>_out.txt >>, and F<< <LOGGER>_err.txt >>,
where of course F<< <LOGGER> >> is the name of the logger.
(Exceptions are currently hard-coded in this script!)

B<Note:> Currently, there is no way for the daemons to reopen the STDOUT
and STDERR files, so we don't generate a configuration for them.
Since we've switched the loggers to syslog, they normally shouldn't
generate any output there anyway.

B<This is an alpha version> that needs more documentation. (TODO)

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

my @SERLOGGERS = (qw/ nmea novatel1ctrl novatel2txt novatel3bin hmt310 /,
	map({"cpt6100_port$_"} 0..3) );

my $CONF_TEMPLATE = <<'END_TEMPLATE';
/home/pi/ngserlog/<FILENAME> {
	# It's ok if the log file doesn't exist.
	missingok
	# Don't rotate the log file if it's empty.
	notifempty
	# Rotate the log if the specified size is exceeded.
	size 10M
	# The logs are rotated this many times.
	rotate 100
	# Compress old log files.
	compress
	# Don't compress the most recently rotated log file, since the logger
	# will still be writing to it until we send it the SIGUSR1 signal.
	delaycompress
	# Script to execute after rotation.
	postrotate
		# If it's running, tell the logger to reopen the file.
		test -e /home/pi/ngserlog/<NAME>.pid && kill -USR1 `cat /home/pi/ngserlog/<NAME>.pid`
	endscript
}
END_TEMPLATE

my $once = 0;
for my $l (@SERLOGGERS) {
	my $conf = $CONF_TEMPLATE;
	$conf =~ s/<NAME>/$l/g;
	# customize the filename if needed
	my $fn = $l . '_data.' . ($l eq 'novatel3bin' ? 'dat' : 'txt');
	$conf =~ s/<FILENAME>/$fn/g;
	# don't need the comments repeated a bunch of times
	$conf =~ s/^\s*#[^\n]*(\n|\z)//mg if $once++;
	print $conf;
}

