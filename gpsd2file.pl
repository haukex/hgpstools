#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';
use Getopt::Std 'getopts';
use Pod::Usage 'pod2usage';
use JSON::MaybeXS qw/decode_json encode_json/;

=head1 SYNOPSIS

 gpsd2file.pl [-f DATAFILE] [-i INTERVAL]

=head1 DESCRIPTION

Opens L<gpspipe(1)> and regularly overwrites* the data file F<DATAFILE>
with the most recently received JSON packets along with their received time,
organized by the "class" field in the recieved packets.
You can run this tool as a daemon and serve the data file on the web.

The filename can be set via the C<-f> option (default F</tmp/gpsd.json>)
and the write interval in seconds with the C<-i> option (default 10 seconds).
Set the latter to zero to write on every recevied record.
Note writes are currently only triggered when data is received.

* This tool also needs write access to a file named F<DATAFILE.tmp>,
which will then be renamed to F<DATAFILE>. Depending on your OS
and filesystem, the rename operation is hopefully atomic,
which minimizes the risk of F<DATAFILE> being empty or incomplete.

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

sub HELP_MESSAGE { pod2usage(-output=>shift); return }
sub VERSION_MESSAGE { say {shift} q$gpsd2file.pl v1.00$; return }
$Getopt::Std::STANDARD_HELP_VERSION = 1;
getopts('f:i:', \my %opts) or pod2usage;
pod2usage('Too many arguments') if @ARGV;
my $DATAFILE = $opts{f} // '/tmp/gpsd.json';
my $INTERVAL = $opts{i} // 10;
pod2usage('Bad interval')
	unless $INTERVAL=~/^\d+$/ && $INTERVAL>=0;
my $DATAFILE_TMP = "$DATAFILE.tmp";

my $nextwrite = time + $INTERVAL;
my %alldata;

open my $gps, '-|', qw/ gpspipe -wPtu -T %s /
	or die "Failed to open gpspipe: $!";
LINE: while (<$gps>) {
	chomp;
	my ($time,$json) = /^(\d+(?:\.\d+)?):\s*(\{.+\})\s*$/
		or do { warn "Unexpected line format: \"$_\""; next LINE };
	my $data = decode_json($json);
	$alldata{$$data{class}//'UNKNOWN'} = { time=>$time, data=>$data };
	if (time>=$nextwrite) {
		$nextwrite = time + $INTERVAL;
		open my $ofh, '>', $DATAFILE_TMP
			or die "Failed to open $DATAFILE_TMP for write: $!";
		print $ofh encode_json(\%alldata), "\n";
		close $ofh;
		rename $DATAFILE_TMP, $DATAFILE
			or die "Failed to rename $DATAFILE_TMP to $DATAFILE: $!";
	}
}
# Possible To-Do for Later: catch SIGTERM/INT and handle gracefully
close $gps or die $! ? "Error closing pipe: $!" : "Exit status $?";

