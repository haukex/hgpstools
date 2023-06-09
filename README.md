
GPS Tools
=========

*by Hauke Daempfling <haukex@zero-g.net>
at the Leibniz Institute of Freshwater Ecology and Inland Fisheries (IGB),
Berlin, Germany, <http://www.igb-berlin.de/>
(legal information below)*

This is a collection of various tools for __logging and parsing GPS NMEA data__
as well as (despite the name of the project)
__general and device-specific data logging tools__,
especially for use with a __Raspberry Pi__.
It is by no means a complete application,
but its individual parts do work and can hopefully be useful.
Featuring:

* A general-purpose serial logging daemon with USB hot-plugging support
* Instructions on how to build a standalone NTP server synchronized to GPS
* Miscellaneous tools and information on getting things
  running on a [Raspberry Pi](http://www.raspberrypi.org/)

The scripts are written in [Perl](http://www.perl.org/)
(at least v5.10 but a current version is *strongly* recommended!)
and are intended for use on \*NIX systems
(some scripts may work on Windows but that is untested).

In general, you can get each tool's documentation via `perldoc <filename>`.
In a few places, not every configuration option is documented, and
you may still need to have a look at the code.
The following gives some starting points, but note this list is not complete,
have a look around this repository to discover all the available scripts.

*	**`INSTALL-RPi-2020.md`**
	
	The instructions I use on getting a basic Raspberry Pi setup.
	**Moved to <https://github.com/haukex/raspinotes/blob/main/BaseInstall.md>**!
	
*	**`INSTALL-RPi.md`**
	
	Instructions on how to set up the serial logging daemon (mentioned below) on a Raspberry Pi.
	The general setup instructions in this file have been **superseded by**
	**<https://github.com/haukex/raspinotes/blob/main/BaseInstall.md>**!
	
*	**`RPi3_Adafruit-GPS_NTP-chrony.md`**  
	
	Instructions and tools to build a standalone GPS-synchronized NTP
	server with a Raspberry Pi 3, an Adafruit "GPS Hat", and `chrony`.
	
*	**`ngserlog.pl`** and the `serloggers/*` scripts
	
	A generic serial port logger with support for hot-plugging USB/RS232 adapters.
	In combination with a configuration script such as `ngserlog_nmea.pl`,
	it processes NMEA data, and can be run as a daemon.
	Various other loggers have been added as well, and those
	configurations can be copied and adapted to log other kinds of data.

More information on NMEA:

* <http://www.catb.org/gpsd/NMEA.html>
* <http://home.mira.net/~gnb/gps/nmea.html>
* <http://www.gpsinformation.org/dale/nmea.htm>

Other existing software tools:

* [gpsd](http://www.catb.org/gpsd/)
* [GPSBabel](http://www.gpsbabel.org/)


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

