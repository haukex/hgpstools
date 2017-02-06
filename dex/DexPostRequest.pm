#!perl
package DexPostRequest;
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

Wraps DEX Post Requests

B<Alpha testing version!>

=head2 C<wrap_dex_post_request>

This function takes one argument, which must be a code reference,
and returns one value, a code reference which is a PSGI app.
The code reference passed to this function must conform to
these specifications:

It must take exactly one argument, which will be the return value of
C<decode_json> on the POST request content (if this is empty, an empty
hash reference is used).

It must return a hash reference, in which none of the keys may begin
with an underscore.

The function may C<die> in case of errors.

How the returned hash is interpreted is up to the JavaScript calling it.
At the moment, the hash must include either a key C<text> (plain text to
be displayed to the user in C<pre> tags) or a key C<data> (a data structure
which is displayed as JSON), and it may include a key C<alert> (a text
string that will be shown in an alert box I<in addition> to the
aforementioned C<text> or C<data> values.

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

use Exporter 'import';
our @EXPORT_OK = qw/wrap_dex_post_request/;

use Carp;
use JSON::MaybeXS qw/decode_json encode_json/;
use Time::HiRes qw/gettimeofday/;

sub wrap_dex_post_request {
	my $dex_post_app = shift;
	croak "too many arguments to wrap_dex_post_request" if @_;
	return sub {
		my $req = Plack::Request->new(shift);
		croak "user not authenticated" unless length $req->user;
		my $content = $req->content;
		$content = '{}' unless defined $content && length $content;
		my $output = eval {
			$dex_post_app->(decode_json($content)) };
		if (!defined $output)
			{ $output = { _error=>$@//'unknown error' } }
		elsif (ref $output ne 'HASH')
			{ $output = { _error=>"dex app did not return hash" } }
		else
			{ $output->{_ok} = 1 }
		$output->{_servertime} = sprintf("%d.%06d",gettimeofday);
		my $res = $req->new_response(200);
		$res->content_type('application/json');
		$res->body(encode_json($output));
		return $res->finalize;
	}
}

