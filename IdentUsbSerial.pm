#!perl
package IdentUsbSerial;
use warnings;
use strict;

our $VERSION = '0.03';

# SEE THE END OF THIS FILE FOR AUTHOR, COPYRIGHT AND LICENSE INFORMATION

=head1 Name

IdentUsbSerial - Perl extension for identifying USB-to-Serial TTYs

=head1 Synopsis

 use IdentUsbSerial 'ident_usbser';
 my @dev = ident_usbser(vend=>'1234', prod=>'abcd', ser=>'XYZ123');

=head1 Description

Looks through the F</sys> filesystem in an attempt to identify all of
the TTYs associated with C<usb-serial> devices.

B<Important Notes:>
This makes a lot of assumptions about the structure of the F</sys> filesystem.
This works fine on my Raspberry Pi with the current Raspbian, but of course
this may not work on other systems because I haven't tested it there yet.

This is Version 0.03 of this module.
B<This is an alpha version.>

=cut

use Exporter 'import';
our @EXPORT_OK = qw/ident_usbser/;

use Path::Class qw/dir file/;
use Carp;

=head2 C<ident_usbser>

Returns a list of hashrefs containing information on all of the C<usb-serial> TTYs.

Accepts a hash with fields C<vend>, C<prod>, and C<ser> to filter the results.
C<vend> and C<prod> are case-insensitively matched against the files F<idVendor> resp. F<idProduct>,
and C<ser> is matched case-sensitively against the file F<serial>.
If any of the files F<idVendor>, F<idProduct>, or F<serial> don't exist, C<undef> is returned.
The returned list is sorted by the C<usbtty> field.

You may also supply an argument of C<< debug=>1 >> and all found devices
will be listed via C<warn>.

=cut

my %IDENT_USBSER_KNOWN_ARGS = map {$_=>1} qw/ vend prod ser debug /;
sub ident_usbser {
	my %args = @_;
	$IDENT_USBSER_KNOWN_ARGS{$_} or croak "ident_usbser unknown argument \"$_\"" for keys %args;
	local $/ = "\n"; # just in case the caller messed with this
	my $usdrv = dir('/sys/bus/usb-serial/drivers/');
	my @usbsers;
	for my $systty ( dir('/sys/class/tty/')->children ) {
		my $devtty = dir('/dev')->file($systty->basename);
		if (!-e $devtty) { carp "unexpected: $systty exists but $devtty doesn't"; next }
		my $drv = _rdlnk( $systty->subdir('device')->subdir('driver') );
		next unless defined $drv && $drv->is_dir && $usdrv->subsumes($drv);
		my $usbtty = _rdlnk( $drv->subdir($systty->basename) );
		next unless defined $usbtty && $usbtty->is_dir;
		my ($vend,$prod,$ser) =
			# I'm not sure if $usbtty->parent->parent is always correct (works for now)
			map { my $f = $usbtty->parent->parent ->file($_);
				-e $f ? scalar $f->slurp(chomp=>1) : undef }
					qw/idVendor idProduct serial/;
		$args{debug} and warn "DEBUG ident_usbser: vend=\"".($vend//'')
			."\", prod=\"".($prod//'')."\", ser=\"".($ser//'')."\"\n";
		next if defined $args{vend} && lc $vend ne lc $args{vend};
		next if defined $args{prod} && lc $prod ne lc $args{prod};
		next if defined $args{ser} && $ser ne $args{ser};
		push @usbsers, { devtty=>"$devtty", usbtty=>"$usbtty",
			vend=>$vend, prod=>$prod, ser=>$ser };
	}
	@usbsers = sort { $$a{usbtty} cmp $$b{usbtty} } @usbsers;
	return @usbsers;
}

sub _rdlnk {
	my ($lnk) = @_;
	defined( my $rl = readlink $lnk ) or return;
	my $o = -d $lnk ? dir($rl) : file($rl);
	return $o->absolute($lnk->parent)->resolve;
}

=head1 Author, Copyright, and License

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

1;
