#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

Waits for message(s) on a UDP port and when a message is received,
prints the IP address from which each message was received.

 udplisten.pl [-m] [-c COUNT] [-a] [-p PORT] [-e EXPR] [-b RXSZ]
 OPTIONS:
   -m       - Output the entire message, not just the IP address
   -c COUNT - Exit after receiving this many messages (default=1)
   -a       - Continuously output all messages (overrides -c)
   -p PORT  - UDP port number (default=12340)
   -e EXPR  - Output only messages which match this Perl expression
   -b RXSZ  - Receive length (default=1024)

=head1 DETAILS

The message can be transmitted, for example, via the following
L<crontab(5)> entry (note: C<sudo apt-get install socat>):

 * * * * *  echo "HELLO xyZ129" | socat - UDP-DATAGRAM:255.255.255.255:12340,broadcast

The string used can be completely random; the idea is for it to be unique
to your device so you can identify it, for example:

 udplisten.pl -e '/HELLO xyZ129/'

Two alternate ways to listen are via L<netcat(1)> or L<socat(1)>
(note these will receive and print I<any> messages on that port):

 netcat -ul 12340           # may need to use -p12340 instead
 socat -u udp-recv:12340 -

Don't forget to open the port for incoming UDP traffic on your local firewall,
for example for L<UFW|https://wiki.ubuntu.com/UncomplicatedFirewall>:

 ufw allow in 12340/udp

B<Note> that the choice of port number above is completely random.
At the time of writing, this port appears to be unused
(L<http://www.iana.org/assignments/port-numbers>),
but if you've got other things on your network that use this port, choose a different one.
You're also free to, for example, use different ports for different devices.

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
use IO::Socket::INET ();
use Data::Dumper;

sub HELP_MESSAGE { pod2usage(-output=>shift); return }
sub VERSION_MESSAGE { say {shift} q$udplisten.pl v2.00$; return }
$Getopt::Std::STANDARD_HELP_VERSION = 1;
getopts('mc:ap:e:b:', \my %opts) or pod2usage;
my $FULLMSG = !!$opts{m};
my $COUNT = $opts{c}//1;
pod2usage("Bad count") unless $COUNT && $COUNT=~/^\d+$/ && $COUNT>0;
my $ALLMSGS = !!$opts{a};
my $PORT = $opts{p}//12340;
pod2usage("Bad port") unless $PORT && $PORT=~/^\d+$/ && $PORT>0;
my $EXPR = $opts{e};
my $RXSZ = $opts{b}//1024;
pod2usage("Bad receive length") unless $RXSZ && $RXSZ=~/^\d+$/ && $RXSZ>0;
pod2usage("Extra arguments") if @ARGV;

my $sock = IO::Socket::INET->new(
		LocalPort => $PORT,
		Proto => 'udp',
	) or die "error in socket creation: $!";

my $count = 0;
RXLOOP: while (1) {
	defined $sock->recv(my $rx,$RXSZ)
		or die "error during recv: $!";
	my $peeraddr = $sock->peerhost;
	my $match = 1;
	if (defined $EXPR) {
		local $_ = $rx;
		eval "\$match = do { package CodeEval; $EXPR }; 1"
			or die "Perl expression failed: ".($@||"Unknown error");
	}
	next RXLOOP unless $match;
	print $FULLMSG ? "From $peeraddr: ".dumpstr($rx)."\n" : "$peeraddr\n";
	last RXLOOP if !$ALLMSGS && ++$count>=$COUNT;
}

$sock->close;


sub dumpstr {
	chomp(my $s = Data::Dumper->new([''.shift])->Terse(1)->Useqq(1)->Dump);
	return $s;
}
