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

my $run = 1;
local $SIG{INT} = sub { $run=0 };
my $val=0;
while ($run) {
	#TODO: Provide some better fake data
	$dex{hmt310}->provide({data=>'fake hmt310'});
	$dex{novatel}->provide({record=>'fake novatel'});
	$dex{cpt6100_port0}->provide({pressure=>111});
	$dex{cpt6100_port1}->provide({pressure=>222});
	$dex{cpt6100_port2}->provide({pressure=>333});
	$dex{cpt6100_port3}->provide({pressure=>444});
	sleep(0.333333333333333);
}
print "\nDone.\n";
