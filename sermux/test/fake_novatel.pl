#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';
use Term::ReadKey 'ReadMode';

=head1 SYNOPSIS

Fake a Novatel SPAN IGM-S1 for testing our loggers. Run the following in the shell:

 socat pty,raw,echo=0,link=/tmp/fakenova1 exec:'./fake_novatel.pl ctrl' &
 socat pty,raw,echo=0,link=/tmp/fakenova2 exec:'./fake_novatel.pl txt'  &
 socat pty,raw,echo=0,link=/tmp/fakenova3 exec:'./fake_novatel.pl bin'  &

The corresponding config file is F<novatel_muxtest.conf.json>.

=head1 Author, Copyright, and License

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

die "Usage: $0 ctrl|txt|bin\n"
	unless @ARGV==1 && $ARGV[0]=~/\A(?:ctrl|txt|bin)\z/;

my $fakebin = <<'END_FAKE_BIN';
aa 44 12 1c
2a 00 00 be 48 00 00 00  59 b4 9a 07 70 7c 74 17
00 00 00 00 f6 b1 fa 33  00 00 00 00 34 00 00 00
4b f3 a9 8a 94 3a 4a 40  a4 fa 69 b3 0f 9f 2a 40
00 00 f3 83 7e c0 53 40  33 33 1f 42 3d 00 00 00
cc 6e 48 40 2d 9a 00 40  ef e0 02 40 31 32 33 00
00 00 c0 40 00 00 00 00  0f 05 05 05 00 86 00 03
3a 0a 58 ce
END_FAKE_BIN
$fakebin =~ s/\s+//g;
$fakebin = pack('H*',$fakebin);

my $run=1;
local $SIG{INT} = sub { $run = 0 };
$|=1;

binmode STDOUT;
if ($ARGV[0] eq 'ctrl') {
	ReadMode 'noecho';
	while ($run) {
		next unless <STDIN>=~/\S/;
		print "\x0D\x0A<OK\x0D\x0A[USB1]";
	}
	ReadMode 'restore';
}
elsif ($ARGV[0] eq 'txt') {
	while ($run) {
		print "%IMURATECORRIMUSA,1946,393511.650;1946,393511.625911000,0.000005601,-0.000001638,0.000001131,0.000003816,0.000018482,0.000080810*a05f282d\n";
		sleep 2;
		print "%IMURATEPVASA,1946,393511.650;1946,393511.625911000,52.45768750399,13.31071559526,117.5851,0.0027,0.0004,-0.0017,-2.386456514,3.828795332,240.210777669,INS_SOLUTION_GOOD*f9403840\n";
		sleep 2;
	}
}
elsif ($ARGV[0] eq 'bin') {
	while ($run) {
		print $fakebin;
		sleep 2;
	}
}
else { die $ARGV[0] }

