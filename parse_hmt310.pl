#!/usr/bin/env perl
use warnings;
use strict;
use 5.014; no feature 'switch';

=head1 SYNOPSIS

 perl parse_hmt310.pl INFILEs > OUTFILE

Parser for records from a Vaisala HMT310.
Can handle both raw data and the output of C<ngserlog_hmt310.pl>.

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

# NOTE this regex is almost the same as ngserlog_hmt310.pl
# We don't allow commas so we don't have to worry about escaping them below
my $HMT_REC_RE =
	qr{ \s* \b
	(?<name> \w+ ) = \s*
	(?<value> -? (?:\d*\.)? \d+ )
	(?: \s*  # unit is optional
		# a unit should not look like a new value
		(?<unit> (?! \w+ = \s* [\-\d\.] ) [^\s,]+ )
	)?
	\b \s* }msxaa;

while (<>) {
	chomp;
	next if /\A\S+\s+(?:START|STOP|CONNECT|DISCONNECT|HMT310.*)\s*\z/;
	pos=undef;
	my $cnt=0;
	if (/\G(\d+(?:\.\d+))\s+/gc)
		{ print "$1"; $cnt++ }
	while (/\G$HMT_REC_RE/gc) {
		print "," if $cnt++;
		print "$+{name},$+{value},", $+{unit}//'';
	}
	print "\n";
	die "Not an HMT310 record? \"$_\""
		unless length==pos;
}
