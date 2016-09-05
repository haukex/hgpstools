#!perl
package SerialPort;
use warnings;
use strict;

our $VERSION = '0.06';

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
 $/ = "\x0D\x0A";  # input record separator
 while ( defined($_ = $port->readline) ) {
 	chomp;
 	print "<< \"$_\"\n";
 }
 die "EOF" if $port->eof;
 print "Read timed out\n" if $port->timed_out;
 my $tied = $port->tied_fh;
 print $tied "Hello, World!\x0D\x0A";
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

This is Version 0.06 of this module.
B<This is an alpha version,> in particular the L</tied_fh> interface.

=cut

use Carp;
use Scalar::Util qw/looks_like_number/;
use Hash::Util qw/lock_ref_keys/;
use IO::Handle ();
use Fcntl qw/:DEFAULT/;
use Time::HiRes qw/gettimeofday tv_interval/;
use IO::Select ();
use IO::Termios (); # on RPi, can be installed via CPAN + local::lib
use Data::Dumper (); # for debugging

our $DEFAULT_TIMEOUT_S = 2;

=head2 C<open>

Opens a serial port and returns a new object.
First argument must be the filename of the device (e.g. F</dev/ttyUSB0>),
followed by options as name/value pairs:
C<< mode => "19200,8,n,1" >> specifies the mode string
(see C<set_mode> in L<IO::Termios>);
C<< stty => ['raw','-echo'] >> is a simple helper for L</stty>;
and the additional options are described in their respective sections:
L</timeout_s>, L</flexle>, L</chomp>, L</eof_fatal>, and L</debug>.

I<Note> that some USB-to-serial interfaces use a fixed baud rate, and will
always operate at that baud rate, regardless of the baud rate that is set,
and these interfaces may also always report the wrong baud rate back to
the user. They seem to work fine regardless of the incorrectly reported
baud rate.

=cut

my %OPEN_KNOWN_OPTS = map {$_=>1} qw/ mode timeout_s stty flexle chomp eof_fatal debug /;
sub open {
	my ($class, $dev, %opts) = @_;
	croak "open: no device specified" unless defined $dev;
	$OPEN_KNOWN_OPTS{$_} or croak "open: bad option \"$_\"" for keys %opts;
	sysopen my $fh, $dev, O_RDWR or croak "open: sysopen failed: $!";
	my $term = IO::Termios->new($fh) or croak "open: failed to make new IO::Termios: $!";
	my $self = bless {
			dev=>$dev, hnd=>$term,
			sel=>IO::Select->new($term),
			timeout_s=>1, # set correctly below
			eof_fatal=>$opts{eof_fatal},
			debug=>$opts{debug}||0,
			rxdata=>undef, timed_out=>0, eof=>0,
			abort=>0, aborted=>0,
			flexle=>$opts{flexle}, chomp=>$opts{chomp},
			prev_was_cr=>0, # keeps state for "read"
		}, $class;
	lock_ref_keys $self; # prevent typos
	$self->timeout_s( defined $opts{timeout_s} ? $opts{timeout_s} : $DEFAULT_TIMEOUT_S );
	$self->_debug(2, "Opened ",$dev," and created new IO::Termios");
	if (defined $opts{mode}) {
		$self->_debug(2, "Setting mode ",$opts{mode});
		$term->set_mode($opts{mode});
	}
	$self->stty(@{$opts{stty}}) if defined $opts{stty};
	$self->_debug(1, "Port ",$dev," is ready in mode ",$term->get_mode);
	return $self;
}

sub _debug {
	my ($self, $lvl, @out) = @_;
	return if $self->{debug}<$lvl || !@out;
	return CORE::print STDERR __PACKAGE__, " DEBUG: ", @out, "\n";
}

sub _dump {
	return Data::Dumper->new([shift])->Terse(1)->Indent(0)->Useqq(1)
		->Purity(1)->Quotekeys(0)->Sortkeys(1)->Dump;
}

=head2 C<stty>

This attempts to load L<IO::Stty|IO::Stty> and use its C<stty> method
on this object's handle with the mode arguments given to this method.
Note that the modes C<'raw', '-echo'> can be very useful on serial ports.

If this function is not used, L<IO::Stty|IO::Stty> is not required to
be installed.

=cut

our $IO_STTY_LOADED;
sub stty {
	my ($self,@mode) = @_;
	croak "stty: port is closed" unless $self->{hnd};
	if (!$IO_STTY_LOADED) {
		eval "use IO::Stty; 1"  ## no critic (ProhibitStringyEval)
			or croak "Failed to load IO::Stty: $@";
		$IO_STTY_LOADED = 1;
		$self->_debug(2, "Successfully loaded IO::Stty");
	}
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

Note that USB-to-serial converters can be unplugged. Testing has so far
shown that in this case, a call to L</read> will return with an EOF
condition. If you want to detect such an unplug event, you can test
for the existence of the device, for example with Perl's C<-e> operator,
after the L</read> function returns with an EOF. Note that some tests
on some systems have shown that the F</dev/> entry may not disappear
immediately, so if you want to be sure of an unplug event, you could
implement a brief C<sleep> before testing the existence of the device.

=head2 C<aborted>

Returns whether or not the last call to L</read> returned due to a
call to L</abort>.

=cut

my %getters = ( handle=>'hnd',
	map {$_=>$_} qw/dev rxdata timed_out eof aborted/);
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

=head2 C<eof_fatal>

This boolean setting, when enabled, causes L</read> to throw an exception
in case of EOF. See L</read>.

With no arguments, returns the current C<eof_fatal> setting.
With one argument, sets the C<eof_fatal> setting and returns the new value.

=head2 C<debug>

Sets the debug level: 1 is normal debugging, 2 is verbose debugging.
More levels may be added in the future.

With no arguments, returns the current C<debug> setting.
With one argument, sets the C<debug> setting and returns the new value.

=cut

my %setters = map {$_=>$_} qw/flexle chomp eof_fatal debug/;
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
Note that each call to C<read> resets these flags.
If the option L</eof_fatal> is set, an EOF is a fatal error.
In any case, the (partial) receive buffer can be accessed with L</rxdata>.

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

If L</flexle> is off, the line ending is the input record separator C<$/>,
and if L</chomp> is enabled, the line ending is removed from the string.
B<Note> that the special C<$/> functions "paragraph mode", "slurp mode",
and "record mode" are I<not> supported and will currently cause
C<read> to die!

=cut

sub read {  ## no critic (ProhibitExcessComplexity)
	my ($self, $bytes) = @_;
	croak "read: port is closed" unless $self->{hnd};
	$self->{rxdata} = ''; $self->{timed_out} = 0; $self->{eof} = 0;
	$self->{abort} = 0; $self->{aborted} = 0;
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
				else { # normal line endings (IRS $/)
					$self->{rxdata} .= $in;
					croak "read: \$/ slurp mode unsupported" if !defined($/);
					croak "read: \$/ paragraph mode unsupported" if !length($/);
					croak "read: \$/ record mode unsupported (use read(\$bytecount) instead)" if ref($/);
					if (substr($self->{rxdata},-length($/)) eq $/) {
						CORE::chomp($self->{rxdata}) if $self->{chomp};
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
				$self->{aborted} = 1;
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

Because a signal usually causes Perl's C<select> to return immediately,
you can call this function from a signal handler, in which case the
L</read> call will return immediately.
Note that Perl's C<select> documentation says: "whether select gets
restarted after signals (say, SIGALRM) is implementation-dependent".
For example, you can use this to implement a graceful exit, as shown below.
See also L</aborted>.

 local $SIG{INT} = sub { $port->abort };
 my $rd = $port->readline;
 if ($port->aborted) {
     $port->close;
     # ...other cleanup activities...
     exit;
 }

=cut

sub abort { shift->{abort}=1; return }

=head2 C<close>

Closes the port.

=cut

sub close {  ## no critic (ProhibitAmbiguousNames)
	my ($self) = @_;
	$self->_debug(1, "Closing port");
	my $hnd = $self->{hnd};
	$self->{sel} = undef;
	$self->{hnd} = undef;
	$self->{rxdata} = undef; $self->{timed_out} = 0; $self->{eof} = 0;
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
