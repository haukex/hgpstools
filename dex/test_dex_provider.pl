#!/usr/bin/env perl
use warnings;
use strict;

=head1 SYNOPSIS

DataEXchange DexProvider Testing Script

B<Alpha testing version!>

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

use Time::HiRes qw/sleep/;
use DexProvider;

my %dex =
	map { $_=>DexProvider->new( srcname=>$_, dexpath=>'_FROM_CONFIG', interval_s=>1 ) }
	qw/ hmt310 novatel cpt6100_port0 cpt6100_port1 cpt6100_port2 cpt6100_port3 /;

my $fake_hmt310_data = [
		[ RH => '24.3', '%RH'   ],
		[ T  => '19.2', "'C"    ],
		[ Td => '-1.7', "'C"    ],
		[ Tdf=> '-1.5', "'C"    ],
		[ a  => '4.0',  'g/m3'  ],
		[ x  => '3.3',  'g/kg'  ],
		[ Tw => '9.5',  "'C"    ],
		[ ppm=> '5363', undef   ],
		[ pw => '5.40', 'hPa'   ],
		[ pws=> '22.26','hPa'   ],
		[ h  => '27.9', 'kJ/kg' ],
	];

my $run = 1;
local $SIG{INT} = sub { $run=0 };
my $val=0;
while ($run) {
	$dex{hmt310}->provide({data=>$fake_hmt310_data});
	$dex{cpt6100_port0}->provide({pressure=>1234});
	$dex{cpt6100_port1}->provide({pressure=>2345});
	$dex{cpt6100_port2}->provide({pressure=>3456});
	$dex{cpt6100_port3}->provide({pressure=>4567});
	#TODO: Provide some better fake novatel data
	$dex{novatel}->provide({record=>'fake novatel'});
	sleep(0.333333333333333);
}
print "\nDone.\n";
