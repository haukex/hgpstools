#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 DESCRIPTION

This file documents and implements part of the B<Novatel / DataEXchange
Interface Hack>. The other two parts of this hack are in
F<novatel_sendcmd.psgi> and F<ngserlog_novatel1ctrl.pl>, marked with
code comments.

We needed a way to get commands sent to the Novatel device from the web
interface (DEX). The proper way to do this would be to exchange the
F<ngserlog_novatel*.pl> loggers with the new F<serialmuxserver.pl> script,
then all the web interface would have to do is connect to the TCP port
and send the command, but F<serialmuxserver.pl> does not yet support
the automatic sending of initialization commands (e.g. the C<$ON_CONNECT>
function of F<ngserlog.pl>). So for now, this is the hacked solution:

=over

=item 1

the web interface (F<novatel_sendcmd.psgi>) calls this script via C<sudo>,
because we need the same file access permissions as
F<ngserlog_novatel1ctrl.pl>

=item 2

this script drops the command as a file in a known location, and then
sends a SIGUSR2 to the logger (F<ngserlog_novatel1ctrl.pl>)

=item 3

the logger gets the SIGUSR2, reads the files in the known location, sends
those commands to the Novatel, and deletes the files

=item 4

the response from the Novatel is shown in the web interface via the
command logging mechanism.

=back

=head2 SETUP

Using C<sudo visudo> (C</etc/sudoers>), add the line:

 piweb ALL = (pi:dialout) NOPASSWD: /home/pi/hgpstools/serloggers/novatelcmd_hack.pl

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

use File::Temp qw/tempfile/;
use Fcntl qw/:flock/;

my $TARGET_DIR = '/var/run/novatelctrl'; # see ngserlog_novatel1ctrl.pl
my $PID_FILE = '/home/pi/pidfiles/novatel1ctrl.pid'; # see ngserlog_novatel1ctrl.pl

my $cmd = "@ARGV";

die "command is empty" unless $cmd=~/\S/;

die "is the logger running? not a writable dir: $TARGET_DIR"
	unless -w -d $TARGET_DIR;

open my $pidfh, '<', $PID_FILE
	or die "is the logger running? $PID_FILE: $!";
chomp( my $pid = <$pidfh> );
close $pidfh;

my ($tfh,$tfn) = tempfile(DIR=>$TARGET_DIR, SUFFIX=>'.cmd');
flock($tfh,LOCK_EX) or die "flock $tfn: $!";
print $tfh $cmd;
close $tfh;

kill 'USR2', $pid or die "Failed to send SIGUSR2 to $pid: $!";

