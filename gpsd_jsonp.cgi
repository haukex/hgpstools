#!/usr/bin/env perl
use warnings;
use strict;

=head1 SYNOPSIS

Serves a JSON file via JSONP with a jQuery compatible "callback" parameter.

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

use CGI qw/header param/;

# filename set in gpsd2file_daemon.pl
my $JSONFILE = '/var/run/gpsd2file/gpsd.json';

my $cb = param('callback') || "callback";
$cb=~s/[^\w]//g; # sanitize

print header('application/javascript');
print "$cb(";
if (open my $fh, '<', $JSONFILE) {
	print while <$fh>;
	close $fh;
}
print ");";

