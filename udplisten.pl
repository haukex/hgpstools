#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

Waits for a specific message on a UDP port (see variable C<$EXPECT> in the code),
and when the message is received it outputs the IP address from which it was received.

 udplisten.pl [-m]

The C<-m> switch causes this tool to output the entire message it received
in addition to the IP address.

=head1 DETAILS

The message can be transmitted, for example, via the following
L<crontab(5)> entry (note: C<sudo apt-get install socat>):

 * * * * *  echo "HELLO xyZ129" | socat - UDP-DATAGRAM:255.255.255.255:12340,broadcast

The string used can be completely random; the idea is for it to be unique
to your device so you can identify it.

An alternate way to listen is via L<socat(1)> (but this will receive
any message, not just the specific one sent above):

 socat -u udp-recv:12340 -

Don't forget to open the port for incoming UDP traffic on your local firewall,
for example for [UFW](https://wiki.ubuntu.com/UncomplicatedFirewall):

 ufw allow in 12340/udp

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

# The regular expression to be matched against incoming messages;
# can be an exact match (via \A..\z anchors) or a partial match,
# which is useful in combination with the -m switch.
my $EXPECT = qr/\AHELLO xyZ129\n\z/;

use Getopt::Std 'getopts';
use Pod::Usage 'pod2usage';
use IO::Socket::INET ();

sub HELP_MESSAGE { pod2usage(-output=>shift); return }
sub VERSION_MESSAGE { say {shift} q$udplisten.pl v1.10$; return }
$Getopt::Std::STANDARD_HELP_VERSION = 1;
getopts('m', \my %opts) or pod2usage;

my $sock = IO::Socket::INET->new(
		LocalPort => 12340,
		Proto => 'udp',
	) or die "error in socket creation: $!";

RXLOOP: while (1) {
	defined $sock->recv(my $rx,1024)
		or die "error during recv: $!";
	my $peeraddr = $sock->peerhost;
	if ($rx=~$EXPECT) {
		if ($opts{m}) {
			print "FROM $peeraddr:\n$rx";
			print "\n" unless $rx=~/\n\z/;
		}
		else {
			print "$peeraddr\n";
		}
		last RXLOOP;
	}
	else
		{ warn "ignoring unepexted message from $peeraddr: \"$rx\"\n" }
}

$sock->close;

