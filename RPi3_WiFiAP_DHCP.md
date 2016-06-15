
Raspberry Pi 3 WiFi Access Point and/or DHCP Server
===================================================

*by Hauke Daempfling <haukex@zero-g.net>
at the Leibniz Institute of Freshwater Ecology and Inland Fisheries (IGB),
Berlin, Germany, <http://www.igb-berlin.de/>
(legal information below)*

Last tested May 2016 on Raspbian jessie 2016-05-10.

General
-------

This guide is intended to show you how to make your Raspberry Pi a
standalone access point and/or a DHCP server.
Note this guide currently does not cover how to turn the RPi into a router
or share an Internet connection.

### Status of this Guide ###

The steps below are all tested and they work, with some still-unexplained
things marked with "??", and several places that could use some expansion.

### Making Changes ###

At the moment, the only really reliable way I have found to
switch modes is by rebooting the RPi (??).
Some of the `service ... start/stop/restart` and `systemctl` commands shown
below don't seem to have the desired effect (e.g. switching `wlan0` from
DHCP to static IP) but I reccommend you use them anyway.


DHCP Server
-----------

### Initial Setup ###

	sudo apt-get install dnsmasq

The full configuration is documented in `/etc/dnsmasq.conf` and
`man 8 dnsmasq`. Back this file up via
`sudo cp /etc/dnsmasq.conf /etc/dnsmasq.conf.orig`,
then edit `/etc/dnsmasq.conf` as follows (replace the file if you like).
Repeat the `interface` option for any other interfaces you want to listen
on.

	interface=wlan0
	domain-needed
	bogus-priv
	dhcp-range=192.168.77.100,192.168.77.199

Note that you can specify an NTP server via e.g.
`dhcp-option=option:ntp-server,192.168.77.4`
(use `0.0.0.0` for "this machine").

If you're using the firewall `ufw`:

	sudo ufw allow DNS
	sudo ufw allow from any port 68 to any port 67 proto udp

*Note:* The `ENABLED` parameter in `/etc/default/dnsmasq` does not appear
to have any effect (??).

### Switching On ###

Assign the interface (`eth0` and/or `wlan0`) a static IP by editing
`/etc/dhcpcd.conf` and adding the following:

	interface wlan0
	static ip_address=192.168.77.10/24

Then, to start things up:

	sudo systemctl restart dhcpcd   # currently no effect (??)
	sudo systemctl enable dnsmasq
	sudo systemctl start dnsmasq

### Switching Off ###

Undo the changes made to `/etc/dhcpcd.conf` above (e.g. comment out the
added lines).

	sudo systemctl stop dnsmasq
	sudo systemctl disable dnsmasq

### Alternate On/Off Method ###

Commenting out all `dhcp` related lines in `/etc/dnsmasq.conf` disables
the DHCP component of `dnsmasq` and it will not listen on that port
(don't forget `sudo systemctl restart dnsmasq`). This method is probably
easier and more useful than disabling the service altogether.


Access Point
------------

### Initial Setup ###

	sudo apt-get install hostapd

Create `/etc/hostapd/hostapd.conf` with the following content.
For all details on the configuration parameters see:
`zless /usr/share/doc/hostapd/examples/hostapd.conf.gz`

	interface=wlan0
	driver=nl80211
	ssid=foobarquz
	wpa_passphrase=Hello, World!
	hw_mode=g
	country_code=DE
	channel=5
	ieee80211n=1
	wmm_enabled=1
	ht_capab=[HT40][SHORT-GI-20][DSSS_CCK-40]
	macaddr_acl=0
	auth_algs=1
	wpa=2
	wpa_key_mgmt=WPA-PSK
	rsn_pairwise=CCMP

*Note:* If you have trouble, you can test the config via
`sudo hostapd /etc/hostapd/hostapd.conf`.

### Switching On ###

In `/etc/network/interfaces`, comment out the `wpa-conf` line under the
`iface wlan0 inet manual` line of the interface you want to use.

In `/etc/default/hostapd` change the `DAEMON_CONF=""` line to
point to the configuration file above.

I have not yet found a reliable way to start hostapd
other than rebooting (??).

### Switching Off ###

Undo the changes made to `/etc/network/interfaces` above
(i.e. remove the comment marker that was added).

Undo the changes made to `/etc/default/hostapd` above
(i.e. comment out the `DAEMON_CONF=""` line).

Note `sudo service` doesn't seem to have any effect (??); one way
to kill the daemon is `sudo pkill --pidfile /run/hostapd.pid`,
but as noted above the most reliable way is to reboot.

### Additional Notes ###

**Configuring a second RPi to connect to your wireless network**

Edit `/etc/wpa_supplicant/wpa_supplicant.conf` and add:

	network={
		ssid="SSID"
		psk="Passphrase"
	}


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
