#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';

=head1 SYNOPSIS

 ssh_ufw_autoblock.pl [-sncqv] [LOGFILES]
 OPTIONS:
   -s - Use sudo for ufw
   -n - Dry-run, don't actually run ufw, just show the command line
   -c - Changes only; don't show ufw output if the rule existed
   -q - Quiet all messages from ufw (overrides -c)
   -v - Verbose (show report of all addresses in log); independent of -q

This script reads log messages like those written to F</var/log/auth.log>,
locates authentication failures and the IP addresses they came from,
and then uses C<ufw> to block recently-seen IPs from which there were too
many attempts.

=head1 DETAILS

The required Perl libraries can be installed on Debian/Ubuntu/Raspbian with:

 sudo apt-get install libdatetime-format-strptime-perl libregexp-common-perl libipc-run3-perl

This program accepts filenames on the commandline (including F<-> for STDIN),
if no filenames are given the program reads from STDIN. Thus you can do
something like:

 zcat -f /var/log/auth.log* | ./ssh_ufw_autoblock.pl

You can see all the current C<ufw> rules with C<sudo ufw status verbose>.
To delete existing rules, use C<sudo ufw status numbered> to see the indexes
of the rules in the list, and then use C<sudo ufw delete INDEX> to delete a rule.
You can also delete them directly using C<sudo ufw delete deny from ADDRESS>.

You can set this script up to be run regularly via C<cron>,
for example to run it every 30 minutes:

 */30 * * * *  /home/pi/hgpstools/ssh_ufw_autoblock.pl -sc /var/log/auth.log

If you have a user that has C<sudo> rights to run C<ufw> without a password,
you may run this script under that username with the C<-s> switch to use C<sudo>;
this should be safer than running this script as C<root>.

Possible To-Do for Later: The code currently contains a few constants
which can only be changed by editing the code.

Possible To-Do for Later: A future version of this script could keep track
of the IPs it previously blocked and unblock them automatically later.

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

use Getopt::Std 'getopts';
use Pod::Usage 'pod2usage';
use DateTime ();
use DateTime::Format::Strptime ();
use Regexp::Common qw/net/;
use IPC::Run3 'run3';

# Constants; feel free to edit
my $MAXATTEMPTS = 5;
# if attempts are seen which are newer than the following date,
# consider them for blocking
my $BLOCKTIME = DateTime->now->add(days=>-1);

sub HELP_MESSAGE { pod2usage(-output=>shift); return }
sub VERSION_MESSAGE { say {shift} q$ssh_ufw_autoblock.pl v0.01$; return }
$Getopt::Std::STANDARD_HELP_VERSION = 1;
getopts('sncqv', \my %opts) or pod2usage;
my $USE_SUDO = !!$opts{s};
my $DRY_RUN  = !!$opts{n};
my $CHANGES  = !!$opts{c};
my $QUIET    = !!$opts{q};
my $VERBOSE  = !!$opts{v};

# ### Parse the Log ###
my %badips;
LINE: while (<>) {
	chomp;
	# you may need to adapt the following regexp if your log looks different
	# in that case you'll also need to update the "Strptime" pattern below
	my ($dt) = /^\s*(\w+\s+\d+\s+[\d\:]+)\s/;
	if (/Failed password for/i) {
		/Failed password for (?:invalid user )?(?<user>.+?) from (?<ip>$RE{net}{IPv4})\s/i
			or do { warn "Failed to parse line \"$_\""; next LINE };
		my $ip = $+{ip};
		$badips{$ip}{attempts}++;
		$badips{$ip}{lastseen} = $dt//'';
	}
	elsif (/POSSIBLE BREAK-IN ATTEMPT/i) {
		/\s\[(?<ip>$RE{net}{IPv4})\] failed\b|\bAddress (?<ip>$RE{net}{IPv4}) maps to\s/i
			or do { warn "Failed to parse line \"$_\""; next LINE };
		my $ip = $+{ip};
		$badips{$ip}{attempts} += $MAXATTEMPTS; # immediately block
		$badips{$ip}{lastseen} = $dt//'';
	}
}
warn "Warning: No input seen\n" unless $.;

# ### Inspect Bad Guys ###
my $strp = DateTime::Format::Strptime->new(
	on_error=>sub { warn "Couldn't parse DT: $_[1]\n" },
	pattern=>'%b %d %H:%M:%S %Y?', time_zone=>'local' );
my $year = DateTime->now->year;
my $approxnow = DateTime->now->add(hours=>1); # allow some leniency in detection of old log entries
my @blocklist;
while (my ($ip,$bad) = each %badips) {
	# add fake year so the parser dosen't complain
	my $dt = $strp->parse_datetime($$bad{lastseen}." $year?");
	# REMINDER $dt may be undef here if the parse failed!
	
	# if now is Jan 2016, but the month on the dt is December, assume year is 2015
	$dt->set( year => $year-1 ) if defined($dt) && $dt > $approxnow;
	
	printf "%15s was last seen %19s with attempts=%-6d - ",
		$ip, $dt//'undef', $$bad{attempts} if $VERBOSE;
	# if we couldn't parse the date/time or if it's a recent attempt,
	# and if the number of attempts is too high, add IP to block list
	if ( (!defined($dt) || $dt>$BLOCKTIME) && $$bad{attempts}>$MAXATTEMPTS ) {
		print "BLOCK\n" if $VERBOSE;
		push @blocklist, $ip;
	}
	else { print "ignore\n" if $VERBOSE }
}
@blocklist = map { $$_[0] }
	sort { $$a[1] cmp $$b[1] }
	map { [$_, pack "C4", split /\./, $_, 4 ] } @blocklist;

# ### Block Bad Guys ###
for my $ip (@blocklist) {
	# this is just a final check to make sure that the command we run looks safe
	die "Internal error: $ip doesn't look like an IP"
		unless $ip=~/^$RE{net}{IPv4}$/;
	my @cmd = (($USE_SUDO?'sudo':()), qw/ ufw insert 1 deny from /, $ip);
	if ($DRY_RUN)
		{ print "\$ @cmd\n"; next }
	run3(\@cmd, \undef, \my $stdout, \my $stderr)
		or die "run3 for \"@cmd\" failed";
	die "command \"@cmd\" exited with \$?=$?, out=\"$stdout\", err=\"$stderr\""
		if $? != 0 || length($stderr);
	print "\$ @cmd\n$stdout"
		if !$QUIET && ( !$CHANGES || $stdout!~/skip.+exist/i );
}
warn "REMINDER: This was a dry-run\n" if $DRY_RUN;

