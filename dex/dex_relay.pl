#!/usr/bin/env perl
use warnings;
use strict;

=head1 SYNOPSIS

 ./dex_relay.pl TARGET_URL [SOURCE_DIR]

=head1 DESCRIPTION

DataEXchange DexProvider Relay Script

B<Alpha testing version!>

 sudo apt-get install inotify-tools

B<Warning:> Do not relay C<$DEX_PATH> to C<localhost>, since that or
any similar configuration will cause an infinite loop! For testing on
the local machine, I<always> set C<SOURCE_DIR> to a different path!

=head1 AUTHOR, COPYRIGHT, AND LICENSE

Copyright (c) 2018 Hauke Daempfling (haukex@zero-g.net)
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
use DexConfig qw/$DEX_PATH/;
use Path::Class qw/file/;
use LWP::UserAgent;
use URI;

my $MAX_ERRORS = 20;
my ($EVENT_RE) = map { qr/$_/i } join '|', map {quotemeta}
	sort { length $b <=> length $a } # list from inotifywait(1):
	qw/ access modify attrib close_write close_nowrite close open moved_to
	moved_from move move_self create delete delete_self unmount /;

sub HELP_MESSAGE { pod2usage(-output=>shift) }
$Getopt::Std::STANDARD_HELP_VERSION = 1;
getopts('', \my %opts) or pod2usage;
pod2usage unless @ARGV==1 || @ARGV==2;
my $TARGET_URL = URI->new(shift(@ARGV));
my $SOURCE_DIR = @ARGV ? shift(@ARGV) : $DEX_PATH;

my @CMD = (qw/ inotifywait -sqm --exclude \.tmp$
	-e moved_to -e close_write /, $SOURCE_DIR);

my $http = LWP::UserAgent->new( env_proxy=>1, timeout=>5, keep_alive=>1 );
# These are set in dex.psgi. Since it's a closed system, it's not
# really meant for security, just to prevent accidental submits.
$http->credentials($TARGET_URL->host_port, 'DEX_PUT', 'dexput', 'DexSending');

my $run = 1;
local $SIG{INT} = sub { $run=0 };

my $errorcount = 0;
sub error {
	warn @_;
	die "Too many errors, bailing out"
		if $errorcount++ >= $MAX_ERRORS;
}

RUNLOOP: while($run) {
	if (not -r -d $SOURCE_DIR) { sleep 1; next RUNLOOP }
	open my $fh, '-|', @CMD or do { error("inotifywait: $!"); next RUNLOOP };
	warn "Now monitoring $SOURCE_DIR...\n";
	LINE: while (<$fh>) {
		chomp;
		my ($watched,$event,$filename) = split /\s+($EVENT_RE(?:,$EVENT_RE)*)\s+/;
		if ( $event=~/\b(?:move_self|delete_self|unmount)\b/i ) {
			# these events mean the file is no longer being watched
			error("$watched $event $filename");
			last LINE;
		}
		next LINE unless $event=~/\b(?:moved_to|close_write)\b/i;
		next LINE unless $filename=~/\A([a-zA-Z][a-zA-Z0-9_]+)\.json\z/;
		my $data = file($watched,$filename)->slurp;
		my $url = $TARGET_URL->clone;
		$url->path_segments($url->path_segments, $filename);
		my $req = HTTP::Request->new('POST', $url);
		$req->content($data);
		my $res = $http->request($req);
		error("$url: ".$res->status_line." / ".$res->content)
			unless $res->is_success;
	}
	close $fh or error($! ? "inotifywait: $!" : "inotifywait \$?=$?");
	sleep 1;
}

