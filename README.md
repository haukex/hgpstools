
GPS Tools
=========

This is a collection of various tools for __logging and parsing GPS NMEA data__.
It is by no means a complete application,
but its individual parts do work and can hopefully be useful.
Featuring:

* A general-purpose serial logging daemon with USB hot-plugging support
* Work is in Progress on an NMEA parser
* Miscellaneous tools and information on getting things
  running on a [Raspberry Pi](http://www.raspberrypi.org/)

The scripts are written in [Perl](http://www.perl.org/)
(at least v5.10 but a current version is *strongly* recommended!)
and are intended for use on \*NIX systems
(some scripts may work on Windows but that is untested).

These tools currently live at
<https://bitbucket.org/haukex/hgpstools/>.
There is also an issue tracker there.

More information on NMEA:

* <http://www.catb.org/gpsd/NMEA.html>
* <http://home.mira.net/~gnb/gps/nmea.html>
* <http://www.gpsinformation.org/dale/nmea.htm>

Other existing software tools:

* [gpsd](http://www.catb.org/gpsd/)
* [GPSBabel](http://www.gpsbabel.org/)

In general, you can get each tool's documentation via `perldoc <filename>`.
In a few places, not every configuration option is documented, and
you may still need to have a look at the code.
A brief overview of the tools:

*	**`my_ip.pl`**

	Report the computer's IP address(es).

*	**`udplisten.pl`**

	Listen for a specific UDP message and report the sender's IP address.

*	**`serialdaemon_gps.pl`**

	A daemon that logs NMEA messages from a serial port
	(can be adapted for logging other serial data)

*	**`filter_ts.pl`**

	Converts timestamps embedded in NMEA log files into fake NMEA records.


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

