
Installing the GPS Tools on a Raspberry Pi
==========================================

*by Hauke Daempfling <haukex@zero-g.net>
at the Leibniz Institute of Freshwater Ecology and Inland Fisheries (IGB),
Berlin, Germany, <http://www.igb-berlin.de/>
(legal information below)*

RPi Basic Installation and Serial Logging Daemon and Utilities
--------------------------------------------------------------

These instructions assume you have some basic knowledge of using
a Raspberry Pi and Raspbian / Debian.
Tested March 2016 on a Raspberry Pi 1 Model B with Raspbian 2016-02-26,
May 2016 on a Raspberry Pi 3 with Raspbian jessie 2016-05-10,
and should work on other models too.

1.	Download and install the latest Raspbian image onto an SD card
according to the installation instructions:
<https://www.raspberrypi.org/documentation/installation/installing-images/>

2.	Boot and configure your RPi
(<https://www.raspberrypi.org/documentation/configuration/>)

	a.	Make sure to correctly configure the network/WiFi, time settings,
	as well as choosing **a good password for the `pi` user!**
	If you wish you can also disable booting into the GUI.
	
	b.	After expanding the partition and rebooting,
	run an update using `apt-get` or `aptitude`.
	Also do a run of `sudo rpi-update` to update the firmware.
	(I also usually install `vim` at this point
	to make the following steps easier.)
	
	c.	At one point I had trouble using `raspi-config` to set the keyboard layout,
	you can set it manually by changing the following in `/etc/default/keyboard`
	(example for German):
	
		XKBMODEL="pc105"
		XKBLAYOUT="de"
		XKBVARIANT="nodeadkeys"
		XKBOPTIONS=""
	
	d.	Note: In case you get warnings like "perl: warning: Setting locale failed",
	one solution is to edit the file `/etc/default/locale` to look like the following
	(of course you're free to use a different locale/language; for lots
	more information Google the term "/etc/default/locale").
	
		LANG=en_US.UTF-8
		LANGUAGE=en_US:en
		LC_ALL=en_US.UTF-8
	
	It seems the problem is also avoided by keeping the default `en_GB.UTF-8` locale
	and adding those you want/need (in my case `de_DE.UTF-8` and `en_US.UTF-8`), and
	choosing the default locale to be `None` or `C.UTF-8`.
	
	e.	Setting up unattended upgrades:
	`sudo apt-get install unattended-upgrades` and
	in `/etc/apt/apt.conf.d/50unattended-upgrades`,
	uncomment one of the lines containing `o=Raspbian` (I usually choose the `n=jessie` line).
	You may also change the `Mail` option if you wish (I set it to `"pi"`).
	Then add the following lines to the file
	`/etc/apt/apt.conf.d/10periodic`:
	
		APT::Periodic::Update-Package-Lists "1";
		APT::Periodic::Download-Upgradeable-Packages "1";
		APT::Periodic::AutocleanInterval "7";
		APT::Periodic::Unattended-Upgrade "1";
	
	f.	Other configuration files worth taking a look at to see if you need
	to adjust them for your setup: `/etc/ntp.conf`, `/etc/ssh/sshd_config`
	(in this one I usually change `PermitRootLogin` to `no`).
	
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
	
	d.	Optional: To be able to send out e-mail to the Internet, do
	`sudo dpkg-reconfigure postfix` and select "Internet Site". The rest of
	the configuration can stay the same; now the mail system will attempt
	to send non-local e-mails via the Internet. You can also install the
	package `bsd-mailx` and then send a test mail via:
	`echo "This is a mailx test" | mailx -s "mailx test" recipient@somewhere.com`
	
	e.	Optional: `gpsd`, but to avoid conflicts with our logger do
	`sudo update-rc.d -f gpsd remove` and `sudo service gpsd stop`
	
	f.	Optional: Additional useful packages are `screen`, `perl-doc`, `vim`,
	`lsof`
	
	g.	Packages that are already installed in the latest version of Raspbian
	I used, but may be missing on older versions: `git`
	
4.	In a suitable directory (like `/home/pi`) do:
`git clone --recursive https://bitbucket.org/haukex/hgpstools.git`
	
5.	Unless you're using a fixed IP address, you can set up a way for the RPi
to broadcast its IP address as described in `udplisten.pl` and/or `my_ip.pl`.
(When making entries in `crontab`, don't forget to use the correct pathnames.)
	
	a.	Here's an example `crontab` entry, then you can then listen via
	`socat -u udp-recv:12340 -`
	
		* * * * *  /home/pi/hgpstools/my_ip.pl -sp `hostname` | socat - UDP-DATAGRAM:255.255.255.255:12340,broadcast
	
	b.	You may then want to **adjust your `rsyslog`** configuration
	to prevent your log from filling up with the messages from `cron`
	once a minute caused by the above command. Do this by editing
	`/etc/rsyslog.conf` and finding the line which defines
	`/var/log/syslog` (on some systems it may be in one of the files in
	`/etc/rsyslog.d/`). On my RPi the line initially looked like this:
	`*.*;auth,authpriv.none  -/var/log/syslog`, and I edited it to look
	like this: `*.*;cron,auth,authpriv.none  -/var/log/syslog`
	
	c.	If you find `/var/log/syslog` is filling up with messages like
	"rsyslogd-2007: action 'action 18' suspended", this can be prevented
	by commenting out the entry in the `rsyslog` configuration that
	writes to `/dev/xconsole`.
	
6.	In case you're using a Raspberry Pi 3 with a GPS add-on board
that connects directly to the Raspberry Pi's GPIO UART pins,
you may have to apply the following workaround.
This is because on the Raspberry Pi 3, the Bluetooth Modem uses
the RPi's UART, and the UART pins have been remapped.
The following workaround disables the connection to the Bluetooth
module and applies to Raspbian Jessie >= 2016-03-18.

	a.	In `/boot/config.txt`, add the line `dtoverlay=pi3-disable-bt`
	
	b.	For newer versions of the firmware, approx. after March 2016, see
	<https://github.com/raspberrypi/firmware/issues/553#issuecomment-199486644>,
	set `enable_uart=1` in `/boot/config.txt`. Note it does not seem to
	be neccessary to set `force_turbo` as suggested in that comment
	(run `vcgencmd get_config int` and check that `core_freq=400`).
	
	c.	Run `sudo systemctl disable hciuart`
	
	d.	If necessary, you'll need to disable the serial console as per your
	GPS board's instructions. Also make sure to reboot.
	
7.	The *most current* information to install the NMEA logging daemon is in the files
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

Other Notes
-----------

-	**Static IP** on Raspbian Jessie
	
	-	Add the following lines to `/etc/dhcpcd.conf` and set the values as needed.
	Add an additional set of these lines for the interface `wlan0` if desired.
	
			interface eth0
			static ip_address=192.168.0.10/24
			static routers=192.168.0.1
			static domain_name_servers=192.168.0.1
	
-	I've had the problem on some RPis that WLAN loses connectivity after
	a while. Here's a hack you can place in your crontab to check if
	`wlan0` network / internet connectivity is down and then restart the
	`wlan0` interface. Adjust the target address and the interval as is
	appropriate for your situation.
	
		SHELL=/bin/bash
		  1 */2  *   *   *   if ! ping -c4 -w8 -Iwlan0 www.google.com >/dev/null; then echo "Restarting wlan0"; sudo ifdown wlan0; sudo ifup wlan0; fi
	 


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
