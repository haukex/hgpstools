
RPi 3 + Adafruit GPS Hat + NTP with `chrony`
============================================

*by Hauke Daempfling <haukex@zero-g.net>
at the Leibniz Institute of Freshwater Ecology and Inland Fisheries (IGB),
Berlin, Germany, <http://www.igb-berlin.de/>
(legal information below)*

Last tested May 2016 on Raspibian jessie 2016-05-10.

1.	**Install Raspbian Jessie** >= 2016-03-18 on the Raspberry Pi 3
as per the instructions in `INSTALL-RPi.md` from:
<https://bitbucket.org/haukex/hgpstools/src>
	
	a.	Make sure to follow the steps closely, including `sudo rpi-update`
	and the Bluetooth UART workaround instructions. Also, during
	initial setup with `raspi-config`, disable the serial console.
	You can skip the final steps for setting up the NMEA logging daemon,
	also you don't need to disable `gpsd` as mentioned there.
	
	b.	We need the latest version of `gpsd` and related packages: in 3.11
	the PPS we use does not yet seem to work correctly, 3.15 works better,
	there is just a small bug that we have a workaround for below.
	At the time of writing, those are only available in Raspbian's
	`testing` repository. At some point in the future those packages
	should migrate into the stable repositories, and this step as well
	as the other references to `testing` in the rest of the instructions
	will no longer be needed.
	At the time of writing (May 2016), the default `gpsd -V` was at
	`3.11 (revision 3.11-3)`, and after using `testing` it was
	`3.16 (revision 3.16-1)`.
	
	Create `/etc/apt/sources.list.d/testing.list` with the content:
	
		deb http://mirrordirector.raspbian.org/raspbian/ testing main contrib
		#deb-src http://archive.raspbian.org/raspbian/ testing main contrib
	
	And `/etc/apt/apt.conf.d/99defaultrelease` with the content
	`APT::Default-Release "jessie";` (this should pin the version and
	prevevent all packages from updating), then `sudo apt-get update`.
	We will install specific packages from `testing` later.
	
2.	Initial **GPS Module** / Serial Port Setup
	
	a.	Make sure the serial console is disabled:
	`sudo vi /boot/cmdline.txt` and make sure there are no `console=`
	or `kgdboc=` parameters referring to `ttyAMA0` or `ttyS0`, also do
	the following and reboot afterwards.
	
		sudo systemctl stop serial-getty@ttyAMA0.service
		sudo systemctl disable serial-getty@ttyAMA0.service
		sudo systemctl stop serial-getty@ttyS0.service
		sudo systemctl disable serial-getty@ttyS0.service
	
	b.	Check that you're getting NMEA data on the serial port:
	
		stty -F /dev/ttyAMA0 raw 9600 cs8 clocal -cstopb
		cat /dev/ttyAMA0
	
3.	**Set Up PPS**
	
	a.	`sudo apt-get install -t testing pps-tools`
	(I don't think `testing` is needed here but it also doesn't hurt)
	
	b.	Add the line `dtoverlay=pps-gpio,gpiopin=4` to `/boot/config.txt`
	(this pin number is specific to the Adafruit GPS Hat)
	
	c.	Add the line `pps-gpio` to `/etc/modules`
	
	d.	Reboot, then `lsmod | grep pps` (look for `pps_gpio` and `pps_core`),
	and check `dmesg | grep pps`. Also try `sudo ppstest /dev/pps0`.
	
	e.	`echo 'SUBSYSTEM=="pps" GROUP="dialout"' | sudo tee /etc/udev/rules.d/87-gpspps.rules`
	
4.	**Set Up `gpsd`** (<http://catb.org/gpsd/gpsd-time-service-howto.html>)
	
	a.	`sudo apt-get install -t testing gpsd gpsd-clients`
	
	b.	For testing, `sudo service gpsd stop`, then
	`sudo gpsd -ND3 -n -F /var/run/gpsd.sock /dev/pps0 /dev/ttyAMA0`,
	then in another terminal do `gpsmon`.
	When the module has a fix, there should be lines saying "PPS
	showing up in the messages.
	
	c.	Apparently, at the time of writing, the messages
	`gpsd:ERROR: KPPS:/dev/ttyAMA0 kernel PPS failed Connection timed out`
	are actually not an error:
	<https://lists.gnu.org/archive/html/gpsd-users/2015-08/msg00021.html>
	
	Workaround to prevent the syslog from filling up:
	`sudo vi /etc/rsyslog.d/01-blocklist.conf`
	and add `:msg,contains,"ttyAMA0 kernel PPS failed Connection timed out" ~`,
	then `sudo service rsyslog restart`
	
	d.	`/etc/default/gpsd`:
	
		START_DAEMON="true"
		USBAUTO="false"
		DEVICES="/dev/pps0 /dev/ttyAMA0"
		GPSD_SOCKET=/var/run/gpsd.sock
		GPSD_OPTIONS="-n"
	
	e.	Reboot, and once again test with `gpsmon`.
	
5.	**Set Up `chrony`** (<http://chrony.tuxfamily.org/>)
	
	a.	`sudo apt-get install -t testing chrony`
	This should automatically uninstall `ntp`.
	
	b.	Make your `/etc/chrony/chrony.conf` look like the following,
	which has all the comments stripped (this is not required).
	Many of these values are left at the defaults, but the
	`refclock` lines and the `allow` line(s) are important!
	
		keyfile /etc/chrony/chrony.keys
		commandkey 1
		driftfile /var/lib/chrony/chrony.drift
		log tracking measurements statistics
		logdir /var/log/chrony
		maxupdateskew 100.0
		dumponexit
		dumpdir /var/lib/chrony
		local stratum 10
		allow 192.168.0.0/24
		logchange 0.5
		hwclockfile /etc/adjtime
		rtcsync
		refclock SHM 0 refid GPS precision 1e-1 delay 0.2 noselect
		refclock PPS /dev/pps0 lock GPS
	
	After editing the config, `sudo service chrony restart`
	
	(Possible To-Do for Later: Several of the values above are just
	recommendations gathered from various places,
	and they could probably use some tweaking.)
	
	c.	`chronyc sourcestats`, and `watch chronyc sources`,
	if PPS is working there should be a `*` next to "PPS1" instead of a "?".
	
	d.	Since the RPi might be powered down unexpectedly, we get `chronyd`
	to regularly write data on the clocks by setting up the following
	in `root`'s `crontab`:
	
		*/30 * * * *  chronyc -a dump writertc | grep -v '^200 OK$'
	
	(Note: Since the above `chrony.conf` uses the `rtcsync` option
	and doesn't have an `rtcfile` set, that data won't actually be
	written, but issuing the `writertc` command doesn't hurt, and
	it's better to include it in case the config is changed later.)
	
	e.	`sudo ufw allow ntp/udp`
	
6.	**Serve Clients with NTP**
	
	These instructions describe what you can do on *other* machines
	to synchronize to your newly set up NTP server. In the following
	examples, "`ADDRESS`" is your Raspberry Pi NTP server's address.
	
	a.	The simplest way to query your server is `ntpdate -q ADDRESS`.
	This just queries the time, to set the local clock, do
	`sudo ntpdate -u ADDRESS`.
	
	b.	To configure `ntp`, edit `/etc/ntp.conf` and
	add a line `server ADDRESS`. You should then reload `ntpd` -
	note that if you also have `dhcpcd` running, then apparently
	sometimes the full sequence of commands needed to reload the
	configuration is
	`sudo service ntp stop`, `sudo service dhcpcd restart`, and
	`sudo service ntp start`.
	(Note: The *actual* `ntp.conf` used by the server will be at
	`/var/lib/ntp/ntp.conf.dhcp`.)
	
	c.	If you want your NTP server to be the only one used by the client,
	then you will need to comment out all the `server` and `pool`
	configuration lines in `/etc/ntp.conf`.
	
	Also, it's possible that you are getting NTP servers set via DHCP,
	so check your DHCP client's configuration for corresponding options
	and turn them off. These vary depending on the DHCP client, but one
	example is that in `/etc/dhcpcd.conf`, you can comment out the
	setting `option ntp_servers`.
	
	d.	To check whether `ntp` is functioning correctly, run `ntpq -p`;
	to monitor it, use `watch ntpq -p`. Your NTP server should be listed
	there, and once the NTP client starts using it as a clock source
	(this can take a few minutes), there should be an asterisk (`*`)
	to the left of its name.
	
	e.	You can also use the command `ntpstat` to get a brief report.
	(`sudo apt-get install ntpstat`)
	
7.	**Web Interface**
	
	a.	Setting up `gpsd2file.pl` as daemon:
	`sudo apt-get install lighttpd libjson-maybexs-perl libcapture-tiny-perl`, then
	follow the steps in `gpsd2file_daemon.pl`
	(read via `perldoc gpsd2file_daemon.pl`).
	
	b.	Set up `lighttpd`:
	
		sudo ufw allow 'WWW Secure'
		sudo apt-get install lighttpd lighttpd-doc apache2-utils
		openssl req -new -x509 -keyout server.pem -out server.pem -days 365 -nodes
		# choose some appropriate values for the self-signed certificate
		sudo cp server.pem /etc/lighttpd/server.pem
		rm -v server.pem
		sudo lighty-enable-mod ssl accesslog
		# check which modules are enabled, disable unneccessary ones, e.g.:
		ls -lA /etc/lighttpd/conf-enabled/
		sudo lighty-disable-mod javascript-alias
		sudo rm /var/www/html/index.lighttpd.html
		# /var/www/ and /var/www/html/ should now be empty
		sudo chown -Rc www-data:www-data /var/www
		sudo chmod -Rc 775 /var/www/
		sudo chmod -Rc g+s /var/www/
		sudo adduser pi www-data
		# the above may require logout & login to take effect
		echo "<html>Nothing here yet</html>" > /var/www/html/index.html
	
	Force the server to redirect all HTTP to HTTPS by editing
	`/etc/lighttpd/conf-enabled/10-ssl.conf` and *adding* the following
	(<https://redmine.lighttpd.net/projects/1/wiki/HowToRedirectHttpToHttps>):
	
		$HTTP["scheme"] == "http" {
			$HTTP["host"] =~ ".*" {
				url.redirect = (".*" => "https://%0$0")
			}
		}
	
	Setting up the password-protected area:
	
		mkdir /var/www/html/pi
		echo "<html>Raspberry Pi User Area</html>" > /var/www/html/pi/index.html
		# note: don't add the -c switch if the file already exists
		sudo htdigest -c /etc/lighttpd/htdigest.user pi pi
		# choose a secure password, not the same as the pi user's login password!
	
	Create the file `/etc/lighttpd/conf-enabled/99-myauth.conf` with the content:
	
		server.modules += ( "mod_auth" )
		auth.backend = "htdigest"
		auth.backend.htdigest.userfile = "/etc/lighttpd/htdigest.user"
		auth.require = ( "/pi/" => (
				"method"  => "digest",
				"realm"   => "pi",
				"require" => "user=pi"
			) )
	
	Setting up CGIs (security note: this enables them globally!):
	Create the file `/etc/lighttpd/conf-enabled/99-mycgi.conf` with the content:
	
		server.modules += ( "mod_cgi" )
		cgi.assign = ( ".cgi" => "" )
	
	After making all the config changes, **restart the server**
	via `sudo service lighttpd restart`
	
	Serving `gpsd` data:
	
		ln -s /var/run/gpsd2file/gpsd.json /var/www/html/pi/gpsd.json
		ln -s /home/pi/hgpstools/rpiweb/ /var/www/html/pi/hgps
	
	c.	Now you can use `gpswebmon.html` to monitor the data. Either simply
	open the HTML file in a browser, enter the Raspberry Pi's IP address / hostname,
	and click "Set", or copy `gpswebmon.html` into `/var/www/html/pi/` and
	access it over the web at `https://RPI_ADDRESS/pi/gpswebmon.html`.
	

Further possibly related reading:

- <https://learn.adafruit.com/adafruit-ultimate-gps-hat-for-raspberry-pi?view=all#pi-setup>
- <http://superuser.com/questions/828036/how-can-i-check-whether-my-ntp-daemon-has-pps-support>
- <http://www.catb.org/gpsd/gpsd-time-service-howto.html>


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
