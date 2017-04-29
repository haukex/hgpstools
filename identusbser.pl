#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';
use Getopt::Long qw/HelpMessage :config posix_default gnu_compat bundling auto_help /;
use FindBin;
use lib $FindBin::Bin;
use IdentUsbSerial 'ident_usbser';

# SEE THE END OF THIS FILE FOR AUTHOR, COPYRIGHT AND LICENSE INFORMATION

=head1 SYNOPSIS

 identusbser.pl OPTIONS
 OPTIONS:
   -v | --vend | --vendor  VEND
   -p | --prod | --product PROD
   -s | --ser  | --serial  SER
   -n | --sel  | --select  IDX
   -e | --exp  | --expect  COUNT
   -c | --cnt  | --count
   -l | --long
   -d | --debug

See L<IdentUsbSerial|IdentUsbSerial> for information on the C<vend>, C<prod>, C<ser> and C<debug> parameters.
Use C<--select IDX> to select a specific result, indexed from 0; will die if it doesn't exist.
Use C<--expect COUNT> to die unless the number of results matches the given count.
Use C<--count> to prefix the output with the number of results, regardless of C<--select>.
Use C<--long> to output vendor, product and serial numbers as well.

=cut

my %args;
GetOptions(
	'v|vend|vendor=s'   => \$args{vend},
	'p|prod|product=s'  => \$args{prod},
	's|ser|serial=s'    => \$args{ser},
	'n|sel|select=i'    => \my $SELECT,
	'e|exp|expect=i'    => \my $EXPECT,
	'c|cnt|count!'      => \my $COUNT,
	'l|long!'           => \my $LONG,
	'd|debug!'          => \$args{debug},
	version => sub { say q$identusbser.pl v0.01$; exit },
	) or HelpMessage(-exitval=>255);
HelpMessage(-msg=>'Error: Too many arguments',-exitval=>255) if @ARGV;

my @usbsers = ident_usbser(%args);

say scalar @usbsers if $COUNT;

my $fmt = $LONG
	? sub { join "\t", map {$_[0]->{$_}//''} qw/devtty vend prod ser/ }
	: sub { $_[0]->{devtty} };

if (defined $SELECT) {
	if ($SELECT>$#usbsers || $SELECT<-@usbsers) {
		warn "Error: Can't select index $SELECT as there are only ".@usbsers." results\n";
		exit 2 }
	say $fmt->($usbsers[$SELECT]);
}
else {
	say $fmt->($_) for @usbsers;
}

if (defined $EXPECT && @usbsers!=$EXPECT) {
	warn "Warning: Expected $EXPECT results, but got ".@usbsers." results\n";
	exit 1 }

=head1 Author, Copyright, and License

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

