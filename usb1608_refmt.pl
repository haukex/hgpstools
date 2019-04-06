#!/usr/bin/env perl
use warnings;
use 5.026;
use Data::Dump 'pp';
use File::stat;
use Getopt::Long qw/ HelpMessage :config posix_default gnu_compat
	bundling auto_version auto_help /;
$|++;

# SEE THE END OF THIS FILE FOR AUTHOR, COPYRIGHT AND LICENSE INFORMATION

=head1 SYNOPSIS

 usb1608_refmt.pl [OPTIONS] [FILE(s)]
 OPTIONS:
   -a | --all       - Output all records, not just data
   -q | --quiet     - Be quiet (don't report skipped data)
   -R | --reverse   - Reverse operation

This script takes a block-based file as output by our custom C<read-usb1608fsplus>
program and rewrites it into a line-based format that matches our other loggers,
and also reverses the process with the -R switch.

=head1 Notes

Testing:

 $ ( for FN in `find SEARCHPATH -name usb1608fsplus_out.txt`; do echo "##### $FN #####"; ./usb1608_refmt.pl -a $FN | ./usb1608_refmt.pl -R | diff $FN - ; done ) 2>&1 | less

=cut

our $VERSION = '0.01';

GetOptions(
	'all|a'     => \( my $ALLDATA ),
	'quiet|q'   => \( my $QUIET   ),
	'reverse|R' => \( my $REVERSE ),
	) or HelpMessage(-exitval=>255);

if ($REVERSE) {
	while (<>) {
		my ($rec) = /^\d+\.\d+\t(.+)\z/s or die pp($_);
		print $rec=~s/\\n/\n/gr;
	}
	exit;
}

my $USB1608_LOG_RE = qr{ # for chunking a file into segments
	^ (?: # single-line stuff
		  \QSuccess, found a USB 1608FS-Plus!\E
		| \QFailure, did not find a USB 1608FS-Plus!\E
		| \QResetting device to known state...\E
		| \QSerial number =\E \N+
		| \QwMaxPacketSize =\E \N+
		| \QMFG Calibration date =\E \N+
		| \QStatus =\E \N+
		| \QExiting normally\E \N+
		| \Qusb1608fsplus_log\E \h+ \N+
		| (?i:Error:) \N+
	) (?:\n|\z)
	| ^ (?: # multi-line stuff
		  \QCalibration Table:\E \n (?: \h+ \QRange =\E \N+ (?:\n|\z) )+
		| \QConfigured Ranges:\E \n (?: \h+ \QChannel =\E \N+ (?:\n|\z) )+
	)
	| (?<rec> # what we're actually looking for
		^ time: \h+ (?<tm> \d+\.\d+ ) \h* \n
		\QNumber samples read =\E \h+ \d+ \h* \n
		(?: \h* Scan \h+ \d+ \h+ Chan \h+ \d+ \h+ Sample \h+ = \h+ 0x[a-fA-F0-9]+
			\h+ Corrected \h+ = \h+ -?\d+\.\d+ \h+ V \h* \n )+
	)
}msxn;

for $ARGV (@ARGV) {
	open ARGV, '<', $ARGV or do { warn "$ARGV: $!"; next };
	my $tm = ( stat(*ARGV)->ctime // 0 ).'.000000';
	my $data = do { local $/; <ARGV> } =~ s/\x00+/\n/gr =~ s/[\x0D\x0A]+/\n/gr;
	close ARGV;
	my $plme = 0; # previous "last match end"
	pos($data) = undef;
	while ( $data=~/$USB1608_LOG_RE/gc ) {
		warn "$ARGV: Skipping ".pp(''.substr($data,$plme,$-[0]-$plme))."\n" if !$QUIET && $plme!=$-[0];
		$plme = $+[0];
		chomp( my $rec = $& );
		die pp($rec) if index($rec,"\\n")>=0;
		$tm = $+{tm} if $+{tm};
		say $tm, "\t", $rec=~s/\n/\\n/gr if $+{tm} || $ALLDATA;
	}
	warn "$ARGV: Skipping ".pp(''.substr($data,$plme))."\n" if !$QUIET && $plme!=length($data);
}

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
