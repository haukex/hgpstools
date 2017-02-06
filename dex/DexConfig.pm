#!perl
package DexConfig;
use warnings;
use strict;

=head1 SYNOPSIS

DataEXchange Configuration File

=head1 DETAILS

B<Note> that all file and path names should be absolute!

=head2 Changing the Password

Use one of the following two commands to generate a new value for the
C<$POST_AUTH_HASH> variable. The values to insert for C<USER> and C<REALM>
can be found in the code as C<$POST_AUTH_USER> and C<$POST_AUTH_REALM>,
respectively. (You are welcome to change these also if you like.)

 perl -wMstrict -MDigest::MD5=md5_hex -le 'print md5_hex("USER:REALM:PASS")'
 echo -n "USER:REALM:PASS" | md5sum

=head2 User-Customizable Files

The user-customizable files in DEX are the following. Note that it is
recommended to not change the config variables C<$STATICFILES_PATH> or
C<$POST_APPS_PATH>, instead keeping the defaults and placing your custom
files in those directories (this will help keep things organized).
C<$STATICFILES_PATH> defaults to the directory F<static> beneath the
location of the F<dex.psgi> script. C<$POST_APPS_PATH> defaults to the
directory F<post_apps> beneath the location of the F<dex.psgi> script.

=over

=item This File

The central configuration file.

=item POST Commands (Browser-Side)

In the file F<$STATICFILES_PATH/post_commands.js>.

=item POST Commands (Server-Side)

Each POST command should be a F<.psgi> app placed in the directory
F<$POST_APPS_PATH>. These scripts should normally use the helper module
L<DexPostRequest|DexPostRequest>. (See also the variable C<%post_apps>
in F<dex.psgi>.)

=item Widgets (Browser-Side)

These are files named F<$STATICFILES_PATH/widget_*.js> that should set up
custom widgets for the browser side.

=back

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
our @EXPORT_OK = qw/
	$DEX_RESOURCE_DIR
	$STARMAN_LISTEN
	$STARMAN_STDERR_FILE	$STARMAN_ACCESS_LOG
	$SERVER_USER	$SERVER_GROUP
	$DEX_PATH	$DEX_PATH_USER	$DEX_PATH_GROUP
	$RAWDATA_PATH
	$POST_AUTH_USER	$POST_AUTH_REALM	$POST_AUTH_HASH
	$STATICFILES_PATH
	$POST_APPS_PATH
/;

# Resource dir will be automatically created by dex_starman.pl
our $DEX_RESOURCE_DIR = '/var/run/dex';
our $STARMAN_LISTEN = ':5000'; # see doc of "starman" command
#TODO: Logs would normally not be in /var/run, this is just for testing.
our $STARMAN_STDERR_FILE = "$DEX_RESOURCE_DIR/dex_starman_err.txt";
our $STARMAN_ACCESS_LOG = "$DEX_RESOURCE_DIR/dex_starman_accesslog.txt";
our $SERVER_USER = 'nobody';
our $SERVER_GROUP = 'nogroup';

# The path in which the .json files are placed by DexProvider.
# Will be automatically created by dex_starman.pl
our $DEX_PATH = "$DEX_RESOURCE_DIR/dex";
# Chown the $DEX_PATH to this user/group (set $DEX_PATH_USER to undef to disable)
our $DEX_PATH_USER = undef;
our $DEX_PATH_GROUP = undef;
# The path where the raw log files are kept so the user can download them.
our $RAWDATA_PATH = "/home/pi/data";

our $POST_AUTH_USER = 'dex';
our $POST_AUTH_REALM = 'DEX';
# See "Changing the Password" in the documentation above.
our $POST_AUTH_HASH = '832805de62b8929edd6945e9b63a2f64'; # FooBar

# WARNING: Regarding the following two variables,
# read the above documentation "User-Customizable Files" above!
our $STATICFILES_PATH = undef; # undef = default
our $POST_APPS_PATH = undef;   # undef = default

1;
