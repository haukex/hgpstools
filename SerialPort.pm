#!perl
package SerialPort;
use warnings;
use strict;

our $VERSION = '0.11';

# SEE THE END OF THIS FILE FOR AUTHOR, COPYRIGHT AND LICENSE INFORMATION

# WARNING TO SELF: remember that many of the subs defined here have the
# same name as Perl functions, so prefix any calls to the core functions
# with CORE:: !!
## no critic (ProhibitBuiltinHomonyms)

=head1 Name

SerialPort - Perl extension for talking to a serial port in *NIX

=head1 Synopsis

 use SerialPort;
 my $port = SerialPort->open('/dev/ttyS0',
 	mode=>'19200,8,n,1', timeout_s=>2 );
 $port->print("Hello, World!\x0D\x0A");
 print "<< \"".$port->read(5)."\"\n";  # read 5 bytes
 while ( defined($_ = $port->readline) ) {
 	chomp;
 	print "<< \"$_\"\n";
 }
 die "EOF" if $port->eof;
 print "Read timed out\n" if $port->timed_out;
 my $tied = $port->tied_fh;
 print $tied "Hello, World!\x0D\x0A";
 local $/ = "\x0D\x0A";         # input record separator
 chomp( my @lines = <$tied> );  # read until timeout / eof
 print "<< \"$_\"\n" for @lines;
 close $tied or die $!;

=head1 Description

Interfaces a serial port, with timeout support.
Based on L<IO::Termios|IO::Termios>; intended to work on *NIX systems.

In general, all methods throw exceptions in case of errors;
other return values are as documented below.

B<Note:> The port is not automatically closed when the object goes out of
scope, you must explicitly call L</close>.

This is Version 0.11 of this module.
B<This is a beta version,>
and the L</tied_fh> interface should be considered alpha stage.

=head2 Notes

Some USB-to-serial interfaces use a fixed baud rate, and will always
operate at that baud rate, regardless of the baud rate that is set,
and these interfaces may also always report the wrong baud rate back to
the user. They seem to work fine regardless of the incorrectly reported
baud rate.

USB-to-serial converters can be hot-plugged. Testing has so far shown that
in this case, a call to L</read> will return with an EOF condition. If you
want to detect such an unplug event, you can test for the existence of the
device, for example with Perl's C<-e> operator, after the L</read> function
returns with an EOF. Note that some tests on some systems have shown that
the F</dev/> entry may not disappear immediately, so if you want to be sure
of an unplug event, you could implement a brief C<sleep> before testing the
existence of the device.

=head3 Installation

On a clean RPi installation, the following commands are necessary to
install the prerequisites for this module. Note this uses the Perl module
C<local::lib> to install the libraries in the user's home directory
instead of installing them to the system Perl.

 sudo apt-get install liblocal-lib-perl libio-pty-perl libpath-class-perl libio-stty-perl
 cpan
    # When asked if you want automatic config, say yes
    # When asked what appraoch you want, choose local::lib
    # When asked by the local::lib install whether you want to
    #   append the local::lib stuff to .bashrc, say yes
 # log out and back in to make sure local::lib config is in effect
 cpan IO::Termios

=head1 Methods

=cut

use Carp;
use Scalar::Util qw/looks_like_number/;
use Hash::Util qw/lock_ref_keys/;
use IO::Handle ();
use Fcntl qw/:DEFAULT/;
use Time::HiRes qw/gettimeofday tv_interval/;
use IO::Select ();
use IO::Termios ();
use IO::Stty ();
use Data::Dumper (); # for debugging

sub _dump {
	return Data::Dumper->new([shift])->Terse(1)->Indent(0)->Useqq(1)
		->Purity(1)->Quotekeys(0)->Sortkeys(1)->Dump;
}

sub _debug {
	my ($self, $lvl, @out) = @_;
	return if $self->{debug}<$lvl || !@out;
	return CORE::print STDERR __PACKAGE__, " DEBUG: ", @out, "\n";
}

=head2 C<new>

Creates and returns a new serial port object. The port is not yet opened,
see L</open>. This is a class method, e.g. C<< SerialPort->new(...) >>.

First argument must be the filename of the device (e.g. F</dev/ttyUSB0>),
followed by options as name/value pairs:

=over

=item *

C<< mode => "19200,8,n,1" >> specifies the mode string
(see C<set_mode> in L<IO::Termios>)

=item *

C<< stty => [...] >> specifies the arguments that L</stty> is called with
upon L</open>. This defaults to C<['raw','-echo']>. If you specify a custom
value here, it will override the default value, so if you need
C<'raw','-echo'>, you'll have to specify those in the list yourself. If you
don't want to do an C<stty> at all, pass an empty arrayref C<[]> here.

=item *

and the additional options are described in their respective sections:
L</timeout_s>, L</flexle>, L</chomp>, L</irs>, L</eof_fatal>, L</cont>, and L</debug>.

=back

The default timeout is currently 2 seconds.

=cut

our $DEFAULT_TIMEOUT_S = 2;
our $DEFAULT_STTY = ['raw','-echo'];

my %KNOWN_OPTS_NEW = map {$_=>1} qw/ mode timeout_s stty flexle chomp irs eof_fatal cont debug /;
sub new {
	my ($class, $dev, %opts) = @_;
	croak "new: no device specified" unless defined $dev;
	$KNOWN_OPTS_NEW{$_} or croak "new: bad option \"$_\"" for keys %opts;
	my $self = bless {
			dev=>$dev,
			open_mode=>$opts{mode},
			open_stty=> defined $opts{stty} ? $opts{stty} : $DEFAULT_STTY,
			hnd=>undef, sel=>undef, # set later
			timeout_s=>$DEFAULT_TIMEOUT_S, # set & validated via setter below
			eof_fatal=>$opts{eof_fatal},
			cont=>$opts{cont},
			debug=>$opts{debug}||0,
			rxdata=>undef,
			timed_out=>0, eof=>0,
			abort=>0,
			flexle=>$opts{flexle}, chomp=>$opts{chomp}, irs=>$opts{irs},
			prev_was_cr=>0, # keeps state for "read"
		}, $class;
	lock_ref_keys $self; # prevent typos
	$self->timeout_s($opts{timeout_s}) if defined $opts{timeout_s};
	return $self;
}

=head2 C<open>

When called as a class method, e.g. C<< SerialPort->open(...) >>, this is a
convenience method that combines L</new> with an immediate C<open>.
The arguments are exactly the same as to L</new>.

When called on an existing object, e.g. C<< $port->open; >>, attempts to open
the port. No arguments are accepted; the parameters used are those supplied
to L</new>. The port must not be already open (see also L</reopen>).

Returns the port object.

=cut

sub open {  ## no critic (RequireArgUnpacking)
	my $self = shift;
	if (ref $self)
		{ croak "too many arguments to open" if @_ }
	else
		{ $self = $self->new(@_) }
	croak "open: port is already open" if $self->is_open;
	sysopen my $fh, $self->{dev}, O_RDWR or croak "open: sysopen failed: $!";
	$self->{hnd} = IO::Termios->new($fh) or croak "open: failed to make new IO::Termios: $!";
	$self->{sel} = IO::Select->new($self->{hnd});
	$self->_debug(2, "Opened ",$self->{dev}," and created new IO::Termios");
	if (defined $self->{open_mode}) {
		$self->_debug(2, "Setting mode ",$self->{open_mode});
		$self->{hnd}->set_mode($self->{open_mode});
	}
	$self->stty(@{$self->{open_stty}}) if defined $self->{open_stty};
	$self->_debug(1, "Port ",$self->{dev}," is ready in mode ",$self->{hnd}->get_mode);
	return $self;
}

=head2 C<reopen>

Like the method call L</open>,
but L</close>s the port first if it is already open.
Unlike L</open>, cannot be used as a class method.

=cut

sub reopen {
	my $self = shift;
	carp "too many arguments to reopen" if @_;
	if ($self->is_open) {
		$self->close or croak "reopen: failed to close: $!" }
	return $self->open;
}

=head2 C<stty>

This calls the C<stty> function from L<IO::Stty|IO::Stty> on this object's
handle with the mode arguments given to this method. If there are no mode
arguments, C<stty> is not called.

=cut

sub stty {
	my ($self,@mode) = @_;
	croak "stty: port is closed" unless $self->{hnd};
	if (!@mode) {
		$self->_debug(2, "Not calling stty b/c mode is empty");
		return }
	$self->_debug(2, "Calling stty ",join ', ', map {"\"$_\""} @mode);
	return IO::Stty::stty($self->{hnd}, @mode);
}

=head2 C<handle>

Returns the underlying L<IO::Termios|IO::Termios> object.
This is provided so you can read/change attributes etc. that are not yet
accessible via this class. See also L</stty>!
B<However,> the interaction of this class with direct read/write operations
on the underlying L<IO::Termios|IO::Termios> object is currently
unspecified.
If the port is closed, this returns C<undef>.

=head2 C<dev>

Returns the device name initially provided to L</open>.

=head2 C<rxdata>

Returns the receive data buffer. Useful if L</read> returned C<undef>
but you're still interested in the partial data.

=head2 C<timed_out>

Returns whether or not the last call to L</read> failed due to a timeout.

=head2 C<eof>

Returns whether or not the last call to L</read> failed due to EOF.
See L</Notes> for some more notes on EOF.

=head2 C<aborted>

Returns the status of the flag set by calling L</abort>.
This flag is I<not> cleared automatically, you must use L</unabort>.
Please see L</abort> and L</read> for details!

=cut

my %getters = ( handle=>'hnd', aborted=>'abort',
	map {$_=>$_} qw/dev rxdata timed_out eof/);
while (my ($func,$field) = each %getters) {
	my $sub = sub {
		my $self = shift;
		carp "too many arguments to $func" if @_;
		return $self->{$field};
	};
	no strict 'refs';  ## no critic (ProhibitNoStrict)
	*{__PACKAGE__."::$func"} = $sub;
}

=head2 C<is_open>

Returns whether or not the port is still open.

=cut

sub is_open { return !!(shift->{hnd}) }

=head2 C<flexle>

This boolean setting, when enabled, causes L</read> in "L</Readline Mode>"
to handle CR, LF, and CRLF line endings.
See L</Readline Mode> for more details.

With no arguments, returns the current C<flexle> setting.
With one argument, sets the C<flexle> setting and returns the new value.

=head2 C<chomp>

This boolean setting, when enabled, causes L</read> in "L</Readline Mode>"
to remove the line ending from the returned string. Note that this
setting is ignored when L</flexle> is enabled.
See L</Readline Mode> for more details.

With no arguments, returns the current C<chomp> setting.
With one argument, sets the C<chomp> setting and returns the new value.

=head2 C<irs>

When set, this option overrides the setting of the input record separator
(IRS) C<$/> when L</read>ing lines in L</Readline Mode>. When this is not
set, i.e. its value is C<undef>, the normal value of C<$/> takes effect.
Note that this setting is ignored when L</flexle> is enabled.
See L</Readline Mode> for more details.

With no arguments, returns the current C<irs> setting.
With one argument, sets the C<irs> setting and returns the new value.

=head2 C<eof_fatal>

This boolean setting, when enabled, causes L</read> to throw an exception
in case of EOF. See also L</read> and L</eof>.

With no arguments, returns the current C<eof_fatal> setting.
With one argument, sets the C<eof_fatal> setting and returns the new value.

=head2 C<cont>

Normally, L</read> clears the read data buffer L</rxdata> before reading
from the port. This boolean setting, when enabled, causes L</read> to
I<not> clear the read data buffer if one of the flags L</timed_out>,
L</aborted>, or L</eof> is set. (This means that the read data buffer is
always cleared if the previous read was successful.)
This setting is useful, for example, if you only received partial data
before a timeout, and want to continue reading the same data.

When this setting is disabled (the default), L</read> clears the read data
buffer L</rxdata> on each call.

With no arguments, returns the current C<cont> setting.
With one argument, sets the C<cont> setting and returns the new value.

=head2 C<debug>

Sets the debug level: 1 is normal debugging, 2 is verbose debugging.
More levels may be added in the future.

With no arguments, returns the current C<debug> setting.
With one argument, sets the C<debug> setting and returns the new value.

=cut

my %setters = map {$_=>$_} qw/flexle chomp irs eof_fatal cont debug/;
while (my ($func,$field) = each %setters) {
	my $sub = sub {
		my $self = shift;
		if (@_) {
			my $newval = shift;
			carp "too many arguments to $func" if @_;
			$self->{$field} = $newval;
		}
		return $self->{$field};
	};
	no strict 'refs';  ## no critic (ProhibitNoStrict)
	*{__PACKAGE__."::$func"} = $sub;
}

=head2 C<timeout_s>

The time in seconds after which a call to L</read> times out.
Fractional seconds may be specified, but whether or not they are respected
depends on the underlying C<select> call.

With no arguments, returns the current timeout setting.
With one argument, sets the timeout setting to that value (in seconds)
and returns the new value.

=cut

sub timeout_s {
	my $self = shift;
	if (@_) {
		my $to = shift;
		carp "too many arguments to timeout_s" if @_;
		croak "bad timeout_s value" if !looks_like_number($to) || $to<=0;
		$self->{timeout_s} = $to;
	}
	return $self->{timeout_s};
}

=head2 C<write>

Accepts one argument, a string of data to be written to the port.
Returns the number of bytes written.

=cut

sub write {
	my $self = shift;
	my $data = shift;
	croak "write: port is closed" unless $self->{hnd};
	croak "write: no data" unless defined $data;
	carp "too many arguments to write (use print instead?)" if @_;
	$self->_debug(1, "TX ",_dump($data));
	my $rv = $self->{hnd}->syswrite($data);
	croak "write failed: $!" unless defined $rv;
	# could handle the writing of less bytes than expected better...
	croak "write only wrote $rv of ".length($data)." bytes"
		unless $rv==length($data);
	return $rv;
}

=head2 C<print>

Simple wrapper for L</write> that acts like Perl's C<print>, i.e.
it adds C<$,> between arguments and C<$\> as the end of line.

=cut

sub print {  ## no critic (RequireArgUnpacking)
	my $self = shift;
	return $self->write( join( (defined $, ? $, : '') , @_ )
		. ( defined $\ ? $\ : '' ) );
}

=head2 C<readline>

Simply calls L</read> in "readline mode" - see L</Readline Mode>.

=cut

sub readline { return shift->read(0) }

=head2 C<read>

Attempts to read and return the specified number of bytes from the port,
timing out when the timeout L</timeout_s> is reached.
The timeout is overall, not per byte, so when receiving large amounts of
data, the timeout must be selected to be long enough to receive the data.

Unlike Perl's C<read> and C<sysread>, this function always returns either
the requested number of bytes, or nothing (C<undef> / the empty list)
on timeout, L</abort>, or at end-of-file (EOF).
Use L</timed_out>, L</aborted>, and L</eof> to find out the cause.
Note that each call to C<read> resets these flags, I<except> L</aborted>,
which must be cleared by the user with a call to L</unabort>.
If the option L</eof_fatal> is set, an EOF is a fatal error.
See L</Notes> for some more notes on EOF.
In any case, the (partial) receive buffer can be accessed with L</rxdata>.

B<Note> that if the L</abort> flag is set, L</read> returns immediately!
See L</abort> for more details.

=head3 Readline Mode

If the number of bytes requested is zero or less, L</read> operates
in "readline mode", meaning that it returns when it has received a full
line. See also the helper L</readline>.
I<Unlike> Perl's C<readline>, this will always return
a single line, even in list context!

If L</flexle> is set, the line ending may be CR, LF, or CRLF (a sequence of
LFCR would be interpreted as two line ending characters). The line ending
will not be returned in the string, regardless of the L</chomp> setting.
B<Note> that when the remote side is sending CRLF line endings and you mix
L</flexle> with non-L</flexle> calls, the latter including L</read>ing
specific numbers of bytes, this will cause leftover LF characters to appear
at the beginning of strings returned from non-L</flexle> calls.

If L</flexle> is off, the line ending is either the value of the L</irs>
option if it is set, otherwise it is Perl's input record separator (IRS)
C<$/>. If L</chomp> is enabled, the line ending is removed from the string.
B<Note> that the special IRS functions "paragraph mode", "slurp mode",
and "record mode" are I<not> supported and will currently cause
C<read> to die!

=cut

sub read {  ## no critic (ProhibitExcessComplexity)
	my ($self, $bytes) = @_;
	croak "read: port is closed" unless $self->{hnd};
	$self->{rxdata} = '' unless $self->{cont}
		&& ( $self->{timed_out} || $self->{eof} || $self->{abort} );
	$self->{timed_out} = 0; $self->{eof} = 0;
	if ($self->{abort}) {
		$self->_debug(2, "Not doing read b/c abort flag is still set");
		return }
	# Figure out IRS stuff now, so we don't need to do it on each byte,
	# even if we're not actually going to be using it.
	my $irs = $self->{irs};
	if (!defined $irs) {
		croak "read: IRS slurp mode unsupported" if !defined($/);
		$irs = $/ }
	croak "read: IRS paragraph mode unsupported" if !length($irs);
	croak "read: IRS record mode unsupported (use read(\$bytecount) instead)" if ref($irs);
	my $lirs = length($irs);
	my $remain_s = $self->{timeout_s};
	$self->_debug(2, "Attempting read, timeout ",$remain_s," s");
	my $t0 = [gettimeofday];
	READLOOP: while (1) {
		if ($self->{sel}->can_read($remain_s)) {
			my $was_blocking = $self->{hnd}->blocking(0);
			my $rv = $self->{hnd}->sysread(my $in, 1);
			$self->{hnd}->blocking($was_blocking);
			croak "read failed: $!" unless defined $rv;
			if ($rv==0) {
				$self->_debug(1, "EOF");
				$self->{eof} = 1;
				croak "read: end-of-file" if $self->{eof_fatal};
				return }
			confess "internal error: bad number of bytes: sysread returned $rv, but got ".length($in)." bytes"
				unless $rv==1 && length($in)==$rv; # paranoia
			confess "internal error: byte out of range: ".ord($in)
				if ord($in)<0 || ord($in)>255; # paranoia
			my $done;
			if ($bytes<1) { # readline mode
				if ($self->{flexle}) { # flexible line endings
					if ($self->{prev_was_cr} && $in eq "\x0A")
						{} # ignore LF following a CR
					elsif ($in eq "\x0D" || $in eq "\x0A")
						{ $done=1 } # CR or LF ends the line
					else
						{ $self->{rxdata} .= $in }
				}
				else { # normal line endings (IRS)
					$self->{rxdata} .= $in;
					if (substr($self->{rxdata},-$lirs) eq $irs) {
						substr($self->{rxdata},-$lirs,$lirs,'') if $self->{chomp};
						$done=1 }
				}
			}
			else {
				$self->{rxdata} .= $in;
				$done=1 if length($self->{rxdata})>=$bytes;
			}
			$self->{prev_was_cr} = $in eq "\x0D";
			last READLOOP if $done;
		}
		else {
			my $elapsed_s = tv_interval($t0);
			$remain_s = $self->{timeout_s} - $elapsed_s;
			if ($self->{abort}) {
				$self->_debug(1, "Aborted read after ",$elapsed_s," s");
				return }
			if ($remain_s <= 0) {
				$self->_debug(1, "Timeout read after ",$elapsed_s," s");
				$self->{timed_out} = 1;
				return }
			else
				{ $self->_debug(2, "Continuing read, timeout ",$remain_s," s") }
		}
	}
	$self->_debug(1, "RX ",_dump($self->{rxdata}));
	return $self->{rxdata};
}

=head2 C<abort>

This function is intended to be called from a signal handler and should
cause L</read> to return immediately (the only exception is the case if
your Perl's C<select> is not interrupted by signals*). Whether or not you
use L</read>, the status of this flag can be checked via L</aborted>.

B<Note> that this flag is B<not> cleared automatically. If you wish to
continue L</read>ing from the port, you B<must> clear the flag with a call
to L</unabort>, otherwise, the next call(s) to read L</read> will return
immediately!

You can use this to implement a graceful exit, for example:

 $port->write("start sending me data\x0D");
 local $SIG{INT} = sub { $port->abort };  # catch Ctrl-C
 while (1) {
     my $line = $port->readline;
     if (!defined($line)) {
         last if $port->aborted;
         ...; # handle other error cases here (timeout etc.)
     }
     else { ... } # read was successful
 }
 $port->unabort;  # necessary in case you want to continue reading
 $port->write("stop sending me data\x0D");
 ...; # other cleanup activities (e.g. read response to stop command)
 $port->close;

* Note that Perl's C<select> documentation says: "whether select gets
restarted after signals (say, SIGALRM) is implementation-dependent".
See also L<perlport>.

=cut

sub abort { shift->{abort}=1; return }

=head2 C<unabort>

Clears the L</aborted> flag which is set by L</abort>.
Please see L</abort> and L</read> for details.

=cut

sub unabort { shift->{abort}=0; return }

=head2 C<close>

Closes the port and resets the internal state.

=cut

sub close {  ## no critic (ProhibitAmbiguousNames)
	my ($self) = @_;
	$self->_debug(1, "Closing port");
	my $hnd = $self->{hnd};
	$self->{sel} = undef;
	$self->{hnd} = undef;
	$self->{rxdata} = undef;
	$self->{timed_out} = 0; $self->{eof} = 0;
	$self->{abort} = 0;
	return $hnd->close;
}

=head2 C<tied_fh>

Returns a new filehandle tied to this port object (lexical filehandles
are generally recommended instead of global filehandles).
The tied handle is a simple wrapper around this module's methods.

B<Warning:> Unlike Perl's lexical file handles, the port is not
automatically closed when the handle goes out of scope,
you B<must> instead explicitly call L</close>.

The tied C<readline> (C<< <$handle> >>) in list context is emulated
by calling L</readline> in a loop until it returns C<undef> (due to
timeout, abort, or EOF, as described in L</read>). This means the
timeout value applies on a per-line basis.

C<sysread>, C<read> and C<write>'s offset and length arguments are
emulated using C<substr>.

C<read>/C<sysread> require a minimum read length of 1, and on timeout
will return any data received, even if it does not match the requested
amount of data. Use L</timed_out> to determine if a read timed out.

=cut

sub tied_fh {
	my ($self) = @_;
	my $fh = IO::Handle->new;
	tie *$fh, 'SerialPort', $self;
	return $fh;
}
sub TIEHANDLE {
	my ($class, $self) = @_;
	croak "first and only argument to \"tie\" must be a $class object"
		unless ref($self) eq $class;
	return $self;
}
sub WRITE {
	my ($self,$buf,$len,$offset) = @_;
	$len = length($buf) unless defined $len;
	croak "bad write length" if $len<0;
	$offset = 0 unless defined $offset;
	return $self->write(substr $buf, $offset, $len);
}
*PRINT = \&print;
sub PRINTF {  ## no critic (RequireArgUnpacking)
	my $self = shift;
	return $self->print( sprintf(shift, @_) );
}
sub READ {  ## no critic (RequireArgUnpacking)
	my ($self,undef,$len,$offset) = @_;
	croak "bad read length" if $len<1;
	$offset = 0 unless defined $offset;
	my $rv = $self->read($len);
	return 0 if !defined $rv && $self->eof;
	my $data = $self->rxdata;
	substr $_[1], $offset, length($data), $data;
	return length($data);
}
sub READLINE {
	my ($self) = @_;
	if (wantarray) {
		my @lines;
		while (defined(my $l = $self->readline))
			{ push @lines, $l }
		return @lines;
	}
	else
		{ return $self->readline }
}
sub GETC {
	my ($self) = @_;
	return $self->read(1);
}
*EOF = \&eof;
*CLOSE = \&close;
#sub UNTIE {}
#sub DESTROY {}

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
