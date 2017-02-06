#!perl
package DexProvider;
use warnings;
use strict;

=head1 SYNOPSIS

DataEXchange Data Provider Library

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

use Carp;
use JSON::MaybeXS qw/encode_json/;
use File::Spec::Functions qw/catfile file_name_is_absolute/;
use File::Temp qw/tempfile/;
use Scalar::Util qw/looks_like_number/;
use Time::HiRes qw/gettimeofday/;

my %NEW_KNOWN_PARAMS = map {$_=>1} qw/ dexpath srcname interval_s /;
sub new {
	my ($class,%params) = @_;
	$NEW_KNOWN_PARAMS{$_} or croak "new: Bad param '$_'" for keys %params;
	if ($params{dexpath} && $params{dexpath} eq '_FROM_CONFIG') {
		require DexConfig;
		$params{dexpath} = $DexConfig::DEX_PATH;
	}
	croak "new: Bad dexpath '$params{dexpath}'"
		unless $params{dexpath}
			&& file_name_is_absolute($params{dexpath});
	croak "new: Bad srcname '$params{srcname}'"
		unless $params{srcname}
			&& $params{srcname}=~/\A[a-zA-Z][a-zA-Z0-9_]+\z/;
	croak "new: Bad interval_s '$params{interval_s}'"
		if defined $params{interval_s}
			&& ( !looks_like_number($params{interval_s})
				|| $params{interval_s}<0 );
	my $self = {
			dexpath => $params{dexpath},
			srcname => $params{srcname},
			interval_s => $params{interval_s},
			next_upd_time => undef,
			filename => catfile($params{dexpath}, $params{srcname}.'.json'),
		};
	return bless $self, $class;
}

sub provide {
	my $self = shift;
	my $data = shift;
	carp "provide: Too many arguments" if @_;
	croak "provide: data must be hashref" unless ref $data eq 'HASH';
	return unless -d -w $self->{dexpath};
	my $now = sprintf("%d.%06d",gettimeofday);
	if (defined $self->{interval_s}) {
		if (defined $self->{next_upd_time}) {
			if ($now < $self->{next_upd_time}) {
				return -1;
			}
		}
		$self->{next_upd_time} = $now+$self->{interval_s};
	}
	$data->{_now} = $now;
	my ($tfh,$tfn) = tempfile( $self->{srcname}.'_XXXXXXXXXX',
		SUFFIX=>'.tmp', DIR=>$self->{dexpath} );
	print $tfh encode_json($data);
	close $tfh;
	if (!rename($tfn, $self->{filename})) {
		carp "provide: Renaming $tfn to $self->{filename} failed: $!";
		unlink($tfn);
		return;
	}
	return 1;
}

1;

