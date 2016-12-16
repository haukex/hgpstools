
Scripts using Daemon::Control
=============================

*by Hauke Daempfling <haukex@zero-g.net>
at the Leibniz Institute of Freshwater Ecology and Inland Fisheries (IGB),
Berlin, Germany, <http://www.igb-berlin.de/>
(legal information below)*

Several scripts in this project use the Perl module `Daemon::Control`, this
is some general information about how to use them.

In the following, `$SCRIPT` refers to the filename of the script (e.g.
`gpsd2file_daemon.pl`) and `$DAEMON` refers to the name of the daemon
which the script provides (e.g. `gpsd2file`). Note that in some cases,
the `$SCRIPT` simply provides a daemon wrapper for the _actual_ code
(in this example, that it `gpsd2file.pl`).

For more information:

	perldoc $SCRIPT
	./$SCRIPT --help   # see available commands
	view $SCRIPT       # view code for details

To get the name of the daemon (`$DAEMON`):

	./$SCRIPT get_init_file | grep Provides:

To install and run the daemon:

	./$SCRIPT get_init_file | sudo tee /etc/init.d/$DAEMON
	sudo chmod -c 755 /etc/init.d/$DAEMON
	sudo update-rc.d $DAEMON defaults       # enable start on boot
	sudo service $DAEMON start              # start the daemon

To stop (and optionally remove) the daemon:

	sudo service $DAEMON stop            # stop the daemon
	sudo update-rc.d -f $DAEMON remove   # disable start on boot
	sudo rm -v /etc/init.d/$DAEMON       # completely disable daemon

Additional useful commands:

	/etc/init.d/$DAEMON status    # current status
	sudo service $DAEMON status   # check the service status
	sudo service $DAEMON reload   # reload the config file (if applicable)

For even more information, see the documentation of `Daemon::Control`
(e.g. <http://search.cpan.org/search?query=Daemon::Control>),
<https://wiki.debian.org/LSBInitScripts> and `man 8 insserv`.


Author, Copyright, and License
------------------------------

Copyright (c) 2016 Hauke Daempfling <haukex@zero-g.net>
at the Leibniz Institute of Freshwater Ecology and Inland Fisheries (IGB),
Berlin, Germany, <http://www.igb-berlin.de/>

This project is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This software is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this software. If not, see <http://www.gnu.org/licenses/>.
