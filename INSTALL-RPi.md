
Installing the GPS Tools on a Raspberry Pi
==========================================

Serial Logging Daemon and Utilities
-----------------------------------

These instructions assume you have some basic knowledge of using
a Raspberry Pi and Raspbian / Debian.
Tested March 2016 on a Raspberry Pi 1 Model B with Raspbian 2016-02-26,
but should work on other models too.

1.	Download and install the latest Raspbian image onto an SD card
	according to the installation instructions:
	<https://www.raspberrypi.org/documentation/installation/installing-images/>
	
2.	Boot and configure your RPi
	(<https://www.raspberrypi.org/documentation/configuration/>)
	
	a.	Make sure to correctly configure the network/WiFi, time settings,
		as well as choosing a good password for the `pi` user.
		If you wish you can also disable booting into the GUI.
		
	b.	After expanding the partition and rebooting,
		run an update using `apt-get` or `aptitude`.
		(I also usually install `vim` at this point
		to make the following steps easier.)
		
	c.	Note: In case you get warnings like "perl: warning: Setting locale failed",
		one solution is to edit the file `/etc/default/locale` to look like this
		(of course you're free to use a different locale/language; for lots
		more information Google the term "/etc/default/locale"):
		
			LANG=en_US.UTF-8
			LANGUAGE=en_US:en
			LC_ALL=en_US.UTF-8
		
	d.	Setting up unattended upgrades:
		`sudo apt-get install unattended-upgrades` and
		in `/etc/apt/apt.conf.d/50unattended-upgrades`,
		uncomment one of the lines containing `o=Raspbian`.
		You may also change the `Mail` option if you wish.
		Then add the following lines to the file
		`/etc/apt/apt.conf.d/10periodic`:
		
			APT::Periodic::Update-Package-Lists "1";
			APT::Periodic::Download-Upgradeable-Packages "1";
			APT::Periodic::AutocleanInterval "7";
			APT::Periodic::Unattended-Upgrade "1";
		
	e.	Other configuration files worth taking a look at to see if you need
		to adjust them for your setup: `/etc/ntp.conf`, `/etc/ssh/sshd_config`
	
3.	Install additional packages via `sudo apt-get install ...` or `aptitude`:
	
	a.	Required: Install the following packages: `libio-interface-perl`, `socat`,
		`libdaemon-control-perl`, `libdevice-serialport-perl`;
		for `filter_ts.pl` the additional requirements are:
		`libdatetime-perl`, `libdatetime-format-strptime-perl`
		
	b.	Recommended: Install the package `ufw`, then do `sudo ufw allow OpenSSH`
		and `sudo ufw enable` (status can be checked via
		`sudo ufw status verbose` and `sudo ufw show listening`)
		
	c.	Recommended: Install `alpine` and `postfix`, first configure the
		latter for "Local only", later you can reconfigure it via
		`sudo dpkg-reconfigure postfix`. If you want `root`'s mail to go to
		the `pi` user, add the line `root: pi` to `/etc/aliases` and then
		run `sudo newaliases; sudo service postfix reload`.
		*Note* that when setting a mail domain, it usually works best to use
		a fake subdomain of a domain name you own or can operate underneath.
		
	d.	Optional: `gpsd`, but to avoid conflicts with our logger do
		`sudo update-rc.d -f gpsd remove` and `sudo service gpsd stop`
		
	e.	Optional: Additional useful packages are `screen`, `perl-doc`, `vim`
	
	f.	Packages that are already installed in the latest version of Raspbian
		I used, but may be missing on older versions: `git`
	
3.	In a suitable directory (like `/home/pi`) do:
	`git clone --recursive https://bitbucket.org/haukex/hgpstools.git`
	
4.	Unless you're using a fixed IP address, you can set up a way for the RPi
	to broadcast its IP address as described in `udplisten.pl` and/or `my_ip.pl`.
	(When making entries in `crontab`, don't forget to use the correct pathnames.)
	
5.	The *most current* information to install the NMEA logging daemon is in the files
	referenced below! Here is a short summary of the steps needed at the time of writing:
	
		# the following is from serlog.pl
		$ echo 'ATTRS{idVendor}=="067b", ATTRS{idProduct}=="2303", SYMLINK+="usb_gps"' | sudo tee /etc/udev/rules.d/90-usbgps.rules
		$ sudo service udev restart
		$ sudo adduser pi dialout
		# the following is from serlog_nmea_daemon.pl
		$ ./serlog_nmea_daemon.pl get_init_file | sudo tee /etc/init.d/serlog_nmea
		$ sudo chmod 755 /etc/init.d/serlog_nmea
		$ sudo update-rc.d serlog_nmea defaults
		$ sudo service serlog_nmea start


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
