#!/usr/bin/env perl
use warnings;
use strict;
use Test::More tests=>11;

# SEE THE END OF THIS FILE FOR AUTHOR, COPYRIGHT AND LICENSE INFORMATION

BEGIN { use_ok 'NovatelParser', 'parse_novatel' };

ok q{#RAWEPHEMA,COM1,0,35.0,SATTIME,1364,496230.000,00100000,97b7,2310;}
	=~ /\A$NovatelParser::RE_ASCII_HEADER\z/, '$RE_ASCII_HEADER matches';
is_deeply \%+, {
	Sync=>'#', Message=>'RAWEPHEMA', Port=>'COM1', SequenceNr=>0,
	IdleTime=>'35.0', TimeStatus=>'SATTIME', Week=>1364, Seconds=>'496230.000',
	ReceiverStatus=>'00100000', Reserved=>'97b7', ReceiverSWVersion=>2310,
}, '$RE_ASCII_HEADER values' or diag explain \%+;

ok q{#RAWEPHEMA,COM1,0,35.0,SATTIME,1364,496230.000,00100000,97b7,2310;30,1364,496800,8b0550a1892755100275e6a09382232523a9dc04ee6f794a0000090394ee,8b0550a189aa6ff925386228f97eabf9c8047e34a70ec5a10e486e794a7a,8b0550a18a2effc2f80061c2fffc267cd09f1d5034d3537affa28b6ff0eb*7a22f279}
	=~ /\A$NovatelParser::RE_RECORD_GENERIC\z/, '$RE_RECORD_GENERIC matches';
is_deeply NovatelParser::fieldsplit($+{Fields}), [qw/ 30 1364 496800
	8b0550a1892755100275e6a09382232523a9dc04ee6f794a0000090394ee
	8b0550a189aa6ff925386228f97eabf9c8047e34a70ec5a10e486e794a7a
	8b0550a18a2effc2f80061c2fffc267cd09f1d5034d3537affa28b6ff0eb /], 'fieldsplit 1';

ok q{%CORRIMUDATASA,1581,341553.000;1581,341552.997500000,-0.000000690,-0.000001549,0.000001654,0.000061579,-0.000012645,-0.000029988*770c6232}
	=~ /\A$NovatelParser::RE_RECORD_GENERIC\z/, '$RE_RECORD_GENERIC matches short header';
is_deeply NovatelParser::fieldsplit($+{Fields}), [qw/ 1581 341552.997500000
	-0.000000690 -0.000001549 0.000001654 0.000061579 -0.000012645 -0.000029988 /], 'fieldsplit 2';

is_deeply NovatelParser::fieldsplit(q{"foo","bar,quz",baz}), ['foo','bar,quz','baz'], 'fieldsplit 3';

# now some records from the real data files:

is_deeply parse_novatel(q{#VERSIONA,USB2,0,0.0,UNKNOWN,0,3.892,004c0000,3681,13306;1,GPSCARD,"D2QRPRTT0S1","BJYA16010241V","OEM615-2.00","OEM060600RN0000","OEM060201RB0000","2015/Jan/28","15:27:29"*ac0b20bc}),
	{
		Sync=>'#', Message=>'VERSIONA', Port=>'USB2', SequenceNr=>0,
		IdleTime=>'0.0', TimeStatus=>'UNKNOWN', Week=>0, Seconds=>'3.892',
		ReceiverStatus=>'004c0000', Reserved=>'3681', ReceiverSWVersion=>13306,
		_ParsedAs=>'_generic', Fields => [qw{ 1 GPSCARD D2QRPRTT0S1 BJYA16010241V
		OEM615-2.00 OEM060600RN0000 OEM060201RB0000 2015/Jan/28 15:27:29 }],
		Checksum=>'ac0b20bc',
	}, 'parse_novatel VERSIONA';

is_deeply parse_novatel(q{%IMURATECORRIMUSA,2010,298810.100;2010,298810.078576000,0.000105592,-0.000227975,-0.000027416,-0.002454522,-0.000917886,-0.004175763*c5aaf2e6}),
	{
		Sync=>'%', Message=>'IMURATECORRIMUSA', Week=>2010, Seconds=>'298810.100',
		_ParsedAs=>'IMURATECORRIMUSA', Fields => {
			Week=>2010, Seconds=>'298810.078576000', PitchRate=>'0.000105592',
			RollRate=>'-0.000227975', YawRate=>'-0.000027416', LateralAcc=>'-0.002454522',
			LongitudinalAcc=>'-0.000917886', VerticalAcc=>'-0.004175763',
		},
		Checksum=>'c5aaf2e6',
	}, 'parse_novatel IMURATECORRIMUSA';

is_deeply parse_novatel(q{%IMURATEPVASA,2010,298810.100;2010,298810.078576000,52.14386413764,12.66874385849,108.4090,-0.0013,-0.0002,0.0066,-3.667776731,3.789443216,332.930427916,INS_SOLUTION_GOOD*8d42cb89}),
	{
		Sync=>'%', Message=>'IMURATEPVASA', Week=>2010, Seconds=>'298810.100',
		_ParsedAs=>'IMURATEPVASA', Fields => {
			Week=>2010, Seconds=>'298810.078576000', Latitude=>'52.14386413764',
			Longitude=>'12.66874385849', Height=>'108.4090', NorthVelocity=>'-0.0013',
			EastVelocity=>'-0.0002', UpVelocity=>'0.0066', Roll=>'-3.667776731',
			Pitch=>'3.789443216', Azimuth=>'332.930427916', Status=>'INS_SOLUTION_GOOD',
		},
		Checksum=>'8d42cb89',
	}, 'parse_novatel IMURATEPVASA';


__END__

=head1 Author, Copyright, and License

Copyright (c) 2019 Hauke Daempfling (haukex@zero-g.net)
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
