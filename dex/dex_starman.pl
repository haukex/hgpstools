#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

Starman Server for DataEXchange

B<Alpha testing version!>

This script uses L<Daemon::Control|Daemon::Control>,
see L<https://bitbucket.org/haukex/hgpstools/src/HEAD/Daemon_Control.md>
for usage information.

Note on Debian-based systems it should be possible to install Starman
via CPAN or C<sudo apt-get install starman>.

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
use lib $FindBin::Bin;
use DexConfig qw/ $DEX_RESOURCE_DIR $STARMAN_LISTEN $STARMAN_STDERR_FILE
	$STARMAN_ACCESS_LOG $SERVER_USER $SERVER_GROUP
	$DEX_PATH $DEX_PATH_USER $DEX_PATH_GROUP /;

use Daemon::Control;
use User::pwent;
use User::grent;
use File::Path qw/make_path/;

exit Daemon::Control->new(
	name         => 'dex_starman',
	program      => \&run_starman,
	# Instead of "user" and "group" here, we'll let Starman handle this below
	# so that Starman can bind to low-numbered ports when run as root.
	# However, see notes on chown below.
	#user         => $SERVER_USER,
	#group        => $SERVER_GROUP,
	umask        => oct('0022'),
	resource_dir => $DEX_RESOURCE_DIR,
	pid_file     => "$DEX_RESOURCE_DIR/dex_starman.pid",
	# starman uses QUIT for graceful shutdown, TERM and INT are hard quits
	stop_signals => [qw/ QUIT TERM INT KILL /],
	# Note access log is set below
	stdout_file  => "$DEX_RESOURCE_DIR/dex_starman_out.txt", # should remain empty
	stderr_file  => $STARMAN_STDERR_FILE, # messages from server and errors
	fork         => 2, # default = 2 = double-fork
	kill_timeout => 5,
	help         => "Please run `perldoc ".__FILE__."` for help.\n",
	map({$_=>'$local_fs $time'} qw/lsb_start lsb_stop/),
	map({$_=>"Serves the DataEXchange via Starman"} qw/lsb_sdesc lsb_desc/),
	# Note: in Daemon::Control Default-Start is currently fixed at "2 3 4 5" and Default-Stop at "0 1 6"
)->run;

use Plack::Runner ();
use Starman (); # "use" not required, but we want to declare this a compile-time dependency
sub run_starman {
	# Because we didn't give Daemon::Control the "user" and "group" options,
	# it won't chown the "resource_dir" for us, so we need to do it manually now.
	my $pwent = getpwnam($SERVER_USER) or die "No such user '$SERVER_USER'?";
	my $grent = getgrnam($SERVER_GROUP) or die "No such group '$SERVER_GROUP'?";
	chown( $pwent->uid, $grent->gid, $DEX_RESOURCE_DIR )==1
		or warn "Warning: Failed to chown $DEX_RESOURCE_DIR: $!\n";
	# Create the $DEX_PATH
	if (!-e $DEX_PATH) {
		make_path( $DEX_PATH, {
				defined $DEX_PATH_USER ? (user=>$DEX_PATH_USER, group=>$DEX_PATH_GROUP) : ()
			} );
	}
	# The following is adapted from the "starman" launcher script.
	# AFAICT, both Plack::Runner->new(@args) and ->parse_options(@argv) set
	# options, and these options are shared between "Starman::Server"
	# (documented in "starman") and "Plack::Runner" (documented in "plackup").
	my @args = (
		server => 'Starman',
		env => 'deployment', # plackup: "Common values are development, deployment, and test."
		version_cb => sub { print "Starman $Starman::VERSION\n" },
		loader => 'Delayed',
	);
	my @argv = (
		'--listen', $STARMAN_LISTEN,
		'--user', $SERVER_USER,
		'--group', $SERVER_GROUP,
		'--access-log', $STARMAN_ACCESS_LOG,
		"$FindBin::Bin/dex.psgi"
	);
	my $runner = Plack::Runner->new(@args);
	$runner->parse_options(@argv);
	die "loader shouldn't be Restarter" if $runner->{loader} eq 'Restarter';
	$runner->set_options(argv => \@argv);
	# Note we could in theory also give a code ref directly to ->run(),
	# but we're passing the filename via @argv above - AFAICT this is
	# important because we're using the "Delayed" loader.
	$runner->run;
}

