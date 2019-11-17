#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

DataEXchange POST Command "System Control Commands"

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

use DexPostRequest qw/wrap_dex_post_request/;
use Capture::Tiny qw/capture/;

#TODO: Generalize this interface for executing system commands
wrap_dex_post_request sub {
	my $in = shift;
	die "invalid command\n" unless $in->{command}
		&& $in->{command}=~/\A(?:reboot|poweroff|service|date|preflight_checks)\z/;
	my @cmd = ('sudo','-n',$in->{command});
	if ($in->{command} eq 'service') {
		die "invalid service command\n"
			unless $in->{args} && @{$in->{args}}==2;
		my ($srv_name,$srv_cmd) = @{$in->{args}};
		die "invalid service command\n"
			unless $srv_name && $srv_name=~/\A(?:ngserlog_[a-zA-Z0-9_]+|usb1608fsplus_log)\z/;
		die "invalid service command\n"
			unless $srv_cmd && $srv_cmd=~/\A(?:start|stop|status)\z/;
		push @cmd, $srv_name, $srv_cmd;
	}
	elsif ($in->{command} eq 'date') {
		die "invalid date command\n"
			unless $in->{args} && @{$in->{args}}==1
			&& $in->{args}[0]=~/^\s*--set=/;
		push @cmd, $in->{args}[0];
	}
	#TODO: Document that we need to add the following to /etc/sudoers:
	# piweb ALL = (pi:dialout) NOPASSWD: /home/pi/preflight_checks.pl
	# (can also be appended to the novatelcmd_hack.pl line)
	elsif ($in->{command} eq 'preflight_checks') {
		@cmd = qw{ sudo -n -u pi -g dialout /home/pi/preflight_checks.pl };
	}
	my ($stdout, $stderr) = capture {
		system(@cmd);
		if ($? != 0) {
			if ($? == -1)
				{ warn "# Failed to execute: $!\n" }
			elsif ($? & 127)
				{ warn sprintf "# Child died with signal %d, %s coredump\n",
				($? & 127),  ($? & 128) ? 'with' : 'without' }
			else
				{ warn "# Child exited with value ".($?>>8)."\n" }
		}
	};
	return {
		text => "Command \"@cmd\" Executed.\n$stdout"
			.(length $stderr?"\n# WARNING/ERROR:\n$stderr":'')
	}
}
