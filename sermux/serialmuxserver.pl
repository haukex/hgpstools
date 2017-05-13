#!/usr/bin/env perl
use warnings;
use strict;
use 5.010; no feature 'switch';
use Data::Dump 'pp';
use JSON::MaybeXS 'decode_json';
use Fcntl qw/:DEFAULT/;
use IO::Termios ();
use IO::Stty ();

=head1 SYNOPSIS

This is a TCP server that connects to multiple serial ports and serves
them each to their own TCP port number. Multiple clients may connect,
each client will be sent a copy of the data received from the serial port,
and each client may send things to the port, however having multiple
clients send things to the port may end up in confusion, it is left up to
the user to coordinate this.

B<This is an alpha version.> Several things should change for this to
become a beta/release version:

 TODO: Config via Perl files, like ngserlog.pl
 TODO: Automated tests
 TODO Doc: Better doc (e.g. config)
 TODO Later: Use syslog

=head1 Configuration

A few notes: Since not all JSON parsers support comments, these can
currently be implemented using hash entries with the keys beginning
with "__".

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

# Debugging stuff
our $DEBUG = 0; #TODO: standardize: 0=off, 1=start/dis/conn, 2=client events, 3=details, 4=messages, 5=POE traces
sub _debug {
	my ($lvl, $ctx, @out) = @_;
	return if $DEBUG<$lvl || !@out;
	return print STDERR "DEBUG $ctx: ", @out, "\n";
}
$Data::Dump::TRY_BASE64 = 0; # makes debug output kinda hard to read
my @POE_DEBUG_OPTS = ( debug => $DEBUG && $DEBUG>=5, trace => $DEBUG && $DEBUG>=5 );

# ##### Config & Init #####
die "Usage: $0 CONFIGFILE\n"
	unless @ARGV==1;
my $config = decode_json( do { open my $fh, '<', $ARGV[0]
		or die "Failed to open $ARGV[0]: $!\n"; local $/; <$fh> } );
$DEBUG = $config->{debug} if $config->{debug} && $config->{debug}=~/\A\d+\z/;

our @DEFAULT_STTY_MODES = ('raw','-echo');

sub POE::Kernel::ASSERT_DEFAULT () { return 1 }
sub POE::Kernel::TRACE_SIGNALS  () { return $DEBUG && $DEBUG>=5 }
sub POE::Kernel::TRACE_EVENTS   () { return $DEBUG && $DEBUG>=5 }
# Note: don't "use POE" until the "sub POE::Kernel::*" are defined
use POE qw/ Component::Server::TCP Wheel::ReadWrite
	Filter::Line Filter::Stream /;

my $RELOADING_SELF;
my %SESSIONS;

# ##### Signal Handling Session #####
POE::Session->create(
options => { @POE_DEBUG_OPTS },
inline_states => {
	_start => sub {
		$_[KERNEL]->alias_set('signal_handler');
		$_[KERNEL]->sig(INT  => 'shutdown_all');
		$_[KERNEL]->sig(TERM => 'shutdown_all');
		$_[KERNEL]->sig(HUP  => 'sig_hup');
	},
	sig_hup => sub {
		$RELOADING_SELF = 1;
		$_[KERNEL]->yield(shutdown_all => 'HUP');
		$_[KERNEL]->sig_handled;
	},
	shutdown_all => sub {
		my ($kernel,$signal) = @_[KERNEL,ARG0];
		_debug(1,"signal_handler", ($signal ? "Caught $signal, " : '')."Shutting down");
		$kernel->post($_ => 'do_shutdown') for keys %SESSIONS;
		$kernel->sig_handled;
	},
	_stop => sub { _debug(3,"signal_handler","_stop"); },
} );

for my $service ( sort keys %{ $config->{services} } ) {
	next if $service =~ /^__/; # "comments"
	my $conf = $config->{services}{$service};
	my $servername = "server_$service";
	my $serialname = "serial_$service";
	
	# ##### TCP Server #####
	my %clients;
	$SESSIONS{$servername} = { clients=>\%clients };
	POE::Component::Server::TCP->new(
		Alias         => $servername,
		Port          => $conf->{srvport},
		$config->{bindaddr} ? ( Address=>$config->{bindaddr} ) : (),
		ClientFilter  => ( $conf->{binary} ? POE::Filter::Stream->new() : POE::Filter::Line->new() ),
		SessionParams => [ options => { @POE_DEBUG_OPTS } ],
		Started => sub {
			_debug(1,$servername,"Started");
			$_[KERNEL]->state('do_shutdown' => sub {
					_debug(1,$servername,"do_shutdown");
					$_[KERNEL]->call($servername => set_concurrency => 0); # stop accepting connections
					for my $cli_id (keys %clients)
						{ $_[KERNEL]->post($cli_id => 'shutdown') }
					$_[KERNEL]->yield('shutdown');
				});
			$_[KERNEL]->state('broadcast' => sub {
					my ($msg) = @_[ARG0,];
					my @clients = keys %clients;
					return unless @clients;
					_debug(3,$servername,"Broadcasting to ".@clients." clients: ".pp($msg));
					for my $cli_id (@clients)
						{ $_[KERNEL]->post($cli_id => transmit => $msg) }
				});
		},
		Stopped => sub {
			_debug(3,$servername,"_stop");
			delete $SESSIONS{$servername};
		},
		Error => sub {
			my ($op,$errnum,$errstr) = @_[ARG0,ARG1,ARG2];
			warn "$servername error: op $op error $errnum: $errstr\n";
			$_[KERNEL]->post(signal_handler => 'shutdown_all', 'server error');
		},
		# remember the following are all in the client sessions
		ClientConnected => sub {
			my ($kernel,$sess,$heap) = @_[KERNEL,SESSION,HEAP];
			$kernel->alias_set($servername."_client_".$sess->ID);
			$clients{$sess->ID} = {};
			_debug(2,$servername,"Client ".$sess->ID." connected from ".$heap->{remote_ip});
		},
		ClientDisconnected => sub {
			my ($sess) = @_[SESSION,];
			_debug(2,$servername,"Client ".$sess->ID." disconnected");
			delete $clients{$sess->ID};
		},
		ClientInput => sub {
			my ($kernel,$sess,$input) = @_[KERNEL,SESSION,ARG0];
			_debug(4,$servername,"Client ".$sess->ID." Rx: ".pp($input));
			$kernel->post($serialname => serial_output => $input);
		},
		ClientError => sub {
			my ($sess,$op,$errnum,$errstr) = @_[SESSION,ARG0,ARG1,ARG2];
			if ($op eq 'read' && $errnum==0) { return } # just EOF, nothing needed
			warn "$servername client ".$sess->ID." error: op $op error $errnum: $errstr\n";
		},  ClientShutdownOnError => 1, # connection will be shut down after ClientError handler
		InlineStates => {
			transmit => sub {
				my ($sess,$heap,$msg) = @_[SESSION,HEAP,ARG0];
				if (defined $heap->{client}) {
					_debug(4,$servername,"Client ".$sess->ID." Tx: ".pp($msg));
					$heap->{client}->put($msg) }
			},
		},
	);
	
	# ##### Serial Port Handler #####
	$SESSIONS{$serialname} = {};
	my $logfh;
	if (defined $conf->{logfile}) {
		open $logfh, '>>', $conf->{logfile}
			or die "Failed to open ".$conf->{logfile}." for append: $!\n";
		binmode $logfh if $conf->{binary};
	}
	POE::Session->create(
	options => { @POE_DEBUG_OPTS },
	inline_states => {
		_start => sub {
			$_[KERNEL]->alias_set($serialname);
			$_[HEAP]{usr_msg_open_attempts} = 0;
			$_[KERNEL]->yield('serial_try_open');
		},
		serial_try_open => sub {
			my $theport = $conf->{serport}//"";
			my $redo = sub {
				# adjust debug level based on whether the message has been shown or not
				_debug( $_[HEAP]{usr_msg_open_attempts}++ ? 3 : 1 ,
					$serialname,"Port $theport doesn't exist, waiting");
				$_[KERNEL]->delay(serial_try_open => 1) };
			if ($conf->{identusbser}) {
				$theport = "";
				eval "use IdentUsbSerial qw/ident_usbser/; 1" or die "Failed to load IdentUsbSerial: $@";
				my @devs = ident_usbser( map { $_ => $conf->{identusbser}{$_} } qw/ vend prod ser / );
				if ( $conf->{identusbser}{idx} > $#devs ) { $redo->(@_); return }
				$theport = $devs[ $conf->{identusbser}{idx} ]{devtty};
				_debug(1,$serialname, "IdentUsbSerial: $theport");
			}
			if (!length($theport) || !-e $theport) { $redo->(@_); return }
			$_[HEAP]{usr_msg_open_attempts} = 0;
			my $fh;
			if (not sysopen $fh, $theport, O_RDWR) {
				# This tries to take care of the race condition where the
				# port disappears between the -e test and the sysopen.
				if ($!{ENOENT}) { $redo->(@_); return }
				else { die "Failed to sysopen $theport: $!\n" }
			}
			my $handle = IO::Termios->new($fh) or die "IO::Termios->new: $!";
			$handle->set_mode($conf->{sermode});
			IO::Stty::stty($handle, @DEFAULT_STTY_MODES);
			_debug(1,$serialname,"Connected to $theport");
			$_[HEAP]{serial_wheel} = POE::Wheel::ReadWrite->new(
					Handle => $handle,
					InputEvent => 'serial_input',
					ErrorEvent => 'serial_error',
					Filter => ($conf->{binary} ? POE::Filter::Stream->new() : POE::Filter::Line->new()),
				);
		},
		serial_input => sub {
			my ($kernel,$input) = @_[KERNEL,ARG0];
			_debug(3,$serialname,"Rx: ".pp($input));
			if (defined $logfh) {
				print {$logfh} $input;
				print {$logfh} "\n" unless $conf->{binary};
			}
			$kernel->post($servername => broadcast => $input);
		},
		do_shutdown => sub {
			_debug(2,$serialname,"do_shutdown");
			$_[KERNEL]->delay('serial_try_open'); # stops the timer
			delete $_[HEAP]{serial_wheel};
		},
		serial_output => sub {
			my ($heap,$output) = @_[HEAP,ARG0];
			if (defined $heap->{serial_wheel}) {
				_debug(3,$serialname,"Tx: ".pp($output));
				$heap->{serial_wheel}->put($output) }
		},
		serial_error => sub {
			my ($op,$errnum,$errstr) = @_[ARG0,ARG1,ARG2];
			if ($op eq 'read' && $errnum==0) {
				_debug(1,$serialname,"EOF (unplugged?), waiting");
				$_[KERNEL]->delay(serial_try_open => 1);
			}
			else {
				warn "$serialname error: op $op error $errnum: $errstr\n";
				$_[KERNEL]->post(signal_handler => 'shutdown_all', 'serial error');
			}
		},
		_stop => sub {
			delete $SESSIONS{$serialname};
			close $logfh if defined $logfh;
			_debug(3,$serialname,"_stop");
		},
	} );
}

POE::Kernel->run();

if ($RELOADING_SELF) {
	_debug(1,"main","Reloading");
	exec($^X,$0,@ARGV)
		or die "Can't re-exec myself ($^X $0): $!\n";
}
