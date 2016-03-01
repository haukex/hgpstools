#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

Prints a list of this system's IP address(es) with timestamps
(only active interfaces and excluding loopback).
If no IP address can be determined, reports the IP 0.0.0.0.

=head1 DETAILS

One usage example is to put something like the following in your L<crontab(5)>
(every 5 minutes, store the IP addresses in a file on a remote machine):

 */5 * * * *  /home/pi/my_ip.pl | ssh user@hostname "cat >/home/user/pi_ip.txt"

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

use Getopt::Std 'getopts';
use Pod::Usage 'pod2usage';
use IO::Interface::Simple ();

sub HELP_MESSAGE { pod2usage(-output=>shift); return }
sub VERSION_MESSAGE { say {shift} q$my_ip.pl v1.00$; return }
$Getopt::Std::STANDARD_HELP_VERSION = 1;
getopts('', \my %opts) or pod2usage;

my $cnt = 0;
for my $if (IO::Interface::Simple->interfaces) {
	next if !$if->is_running || $if->is_loopback;
	say $if->address, "\t", scalar time, "\t", scalar gmtime, " UTC";
	$cnt++;
}

say "0.0.0.0", "\t", scalar time, "\t", scalar gmtime, " UTC"
	unless $cnt;

