#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

DataEXchange Server Script

B<Alpha testing version!>

=head1 DETAILS

See F<dex_starman.pl> for how to run this as a service.

Or, run me in any PSGI server, like

 plackup dex.psgi

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

use FindBin ();
use DexConfig qw/ $DEX_PATH $RAWDATA_PATH $POST_AUTH_USER $POST_AUTH_REALM
	$POST_AUTH_HASH $STATICFILES_PATH $POST_APPS_PATH /;
use List::Util qw/max/;
use Path::Class qw/dir/;
use Time::HiRes qw/gettimeofday/;
use Sys::Hostname qw/hostname/;
use JSON::MaybeXS qw/decode_json encode_json/;
use Plack::Builder qw/builder enable mount/;
use Plack::Request ();
use Plack::App::Directory ();
use Plack::Util ();
use File::Replace qw/replace2/;
# the following is not needed, but catch missing module at compile time
use Plack::Middleware::Auth::Digest ();

$STATICFILES_PATH //= "$FindBin::Bin/static";
$POST_APPS_PATH //= "$FindBin::Bin/post_apps";
my $HOSTNAME = hostname;

# Not really meant for security, just to prevent accidental submits.
# See "Changing the Password" in DexConfig.pm.
my $PUT_AUTH_USER = 'dexput';
my $PUT_AUTH_REALM = 'DEX_PUT';
my $PUT_AUTH_HASH = '418c9f04ff3373fe2a037d88a46d4659'; # DexSending

my %post_apps =
	map { (my $x=$_->basename)=~s/\.psgi$//; $x => $_ }
	grep { -f && $_->basename=~/\A([a-zA-Z][a-zA-Z0-9_]+)\.psgi\z/ }
	dir($POST_APPS_PATH)->absolute->children;

my $app_get = sub {
	my $req = Plack::Request->new(shift);
	my %the_data = (
			_servertime => sprintf("%d.%06d",gettimeofday),
			_hostname => $HOSTNAME,
		);
	if (-d $DEX_PATH) {
		for my $file (dir($DEX_PATH)->children) {
			next unless -f $file;
			my ($name) = $file->basename =~
				/\A([a-zA-Z][a-zA-Z0-9_]+)\.json\z/ or next;
			my $data = eval { decode_json(scalar $file->slurp) };
			if (ref $data eq 'HASH') {
				$data->{_mtime} = $file->stat->mtime;
				$the_data{$name} = $data;
			}
		}
	}
	else { $the_data{_error} = 'DEX Path not found' }
	my $res = $req->new_response(200);
	$res->content_type('application/json');
	$res->body(encode_json(\%the_data));
	return $res->finalize;
};
my $app_put = sub {
	my $req = Plack::Request->new(shift);
	die "auth" unless length $req->user; # shouldn't happen, just double-check
	my $ok = eval {
		my $content = decode_json($req->content);
		my ($file) = $req->path=~m{\A/([a-zA-Z][a-zA-Z0-9_]+\.json)\z}
			or die "bad path";
		$content->{_remote} = $req->remote_host || $req->address;
		$content->{_rx_time} = sprintf("%d.%06d",gettimeofday);
		my $ofh = replace2( dir($DEX_PATH)->file($file) );
		print $ofh encode_json($content);
		close $ofh;
	1 }; my $e = $@||'unknown error';
	my $res = $req->new_response($ok ? 200 : 500);
	$res->content_type('text/plain');
	$res->body($ok ? 'OK' : $e);
	return $res->finalize;
};
my $app_post = sub {
	my $req = Plack::Request->new(shift);
	die "auth" unless length $req->user; # shouldn't happen, just double-check
	my $out = [ reverse sort keys %post_apps ];
	my $res = $req->new_response(200);
	$res->content_type('application/json');
	$res->body(encode_json($out));
	return $res->finalize;
};
my $app_listwidgets = sub {
	my @widgets =
		grep { -f && $_->basename=~/\Awidget_.+\.js\z/ }
		dir($STATICFILES_PATH)->absolute->children;
	my %out = (
			widgets => [ sort map { $_->basename } @widgets ],
			lastmod => max( map {$_->stat->mtime} @widgets ),
		);
	return [ '200',
		['Content-Type'=>'application/json'],
		[ encode_json(\%out) ],
	]
};

builder {
	enable 'SimpleLogger';
	enable 'Static',
		path => sub { s#\A/\z#/dex.html#; /\.(?:html|js|css)\z/ },
		root => $STATICFILES_PATH;
	builder {
		mount '/listwidgets' => $app_listwidgets;
		mount '/rawdata' =>
			Plack::App::Directory->new({root=>$RAWDATA_PATH})->to_app;
		# TODO: Can we disable logging of /get requests?
		mount '/get' => builder {
			# commented out JSONP because we're serving the main page ourselves
			#enable 'JSONP';
			$app_get };
		mount '/put' => builder {
			enable 'Auth::Digest',
				realm => $PUT_AUTH_REALM, secret => 'seeecrettt',
				password_hashed => 1,
				authenticator => sub {
					my ($username, $env) = @_;
					return $username eq $PUT_AUTH_USER ? $PUT_AUTH_HASH : undef;
				};
			$app_put };
		mount '/post' => builder {
			enable 'Auth::Digest',
				realm => $POST_AUTH_REALM, secret => 'seeecrettt',
				password_hashed => 1,
				authenticator => sub {
					my ($username, $env) = @_;
					return $username eq $POST_AUTH_USER ? $POST_AUTH_HASH : undef;
				};
			mount "/$_" => Plack::Util::load_psgi($post_apps{$_})
				for reverse sort keys %post_apps;
			mount '/' => $app_post };
	}
}
