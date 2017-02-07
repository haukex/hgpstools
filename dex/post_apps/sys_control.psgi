#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

DataEXchange POST Command "System Control Commands"

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
use Capture::Tiny qw/capture/;

wrap_dex_post_request sub {
	my $in = shift;
	die "no command\n" unless $in->{command};
	die "invalid command\n"
		unless $in->{command} eq 'reboot'
			|| $in->{command} eq 'poweroff';
	my ($stdout,$stderr) = capture {
		#TODO: Take the "safety" off of sys_control
		system('sudo','echo','fake',$in->{command})==0
			or warn "command failed, \$?=$?";
	};
	return {
		text => "Command Executed.\n".$stdout
			.(length $stderr?"\n# STDERR:\n$stderr":'')
	}
}
