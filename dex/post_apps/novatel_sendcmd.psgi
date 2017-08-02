#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

DataEXchange POST Command "Novatel Send Command"

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

use DexPostRequest qw/wrap_dex_post_request/;
#use Capture::Tiny qw/capture/;
use Data::Dump qw/pp/; #DB

wrap_dex_post_request sub {
	my $in = shift;
	my $cmd = $in->{cmd};
	#TODO NEXT: novatel_sendcmd
	return {
		text => "unimplemented, you said: ".pp($cmd),
		alert => "novatel_sendcmd.psgi unimplemented",
	}
}

