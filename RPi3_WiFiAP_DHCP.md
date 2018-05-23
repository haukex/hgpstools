
Routing Between Ethernet and WiFi on a Raspberry Pi 3 with Raspbian stretch
===========================================================================

*by Hauke Daempfling <haukex@zero-g.net>
at the Leibniz Institute of Freshwater Ecology and Inland Fisheries (IGB),
Berlin, Germany, <http://www.igb-berlin.de/>
(legal information below)*

Last tested May 2018 on Raspbian stretch 2018-04-18 (*"lite"*).

This guide is intended to document how to set up an RPi 3 based on Raspbian **stretch** in various modes:

*	a WiFi Access Point
*	a NAT gateway between `eth0` and `wlan0` (in either direction)
*	a network bridge between `eth0` and `wlan0`
*	a DHCP server (optional)

It is assumed that the RPi was set up as documented in `INSTALL-RPi.md`,
for example that the `ufw` firewall is being used.

Together with the instructions in `RPi3_Adafruit-GPS_NTP-chrony.md`,
the RPi can also serve as an NTP server (shown in configuration examples below;
if you don't have an NTP server, comment out the lines with `ntp-server`).

**Note** that Raspbian stretch has introduced new network interface names
instead of the old `eth0` names. Note the new name of your network interface
and insert it below **everywhere** you see `eth0`. See also
<https://www.debian.org/releases/stable/armhf/release-notes/ch-whats-new.en.html#new-interface-names>.
(TODO: `enxb827eb38f397`)

Further documentation:

*	`dhcpcd`: `man 5 dhcpcd.conf`
	
*	`dnsmasq`: `man 8 dnsmasq` as well as `/etc/dnsmasq.conf`,
	which below we copy to `/etc/dnsmasq.conf.orig`
	
*	`hostapd`: `zless /usr/share/doc/hostapd/examples/hostapd.conf.gz`
	
*	<https://help.ubuntu.com/lts/serverguide/firewall.html#ip-masquerading>

WARNING
-------

Always have a monitor and keyboard handy in case your network
configuration changes don't work!


General Setup (needed for all of the following)
-----------------------------------------------

	sudo apt-get install bridge-utils hostapd dnsmasq
	sudo systemctl disable dnsmasq
	sudo systemctl disable hostapd
	sudo cp /etc/dnsmasq.conf /etc/dnsmasq.conf.orig

In `/etc/sysctl.conf`, set `net.ipv4.ip_forward=1`.

In `/etc/default/ufw`, set `DEFAULT_FORWARD_POLICY="ACCEPT"`.

In `/etc/ufw/sysctl.conf`, set `net/ipv4/ip_forward=1`.

	sudo ufw status verbose
	# IIF the DNS and DHCP rules don't exist yet:
	sudo ufw allow DNS
	sudo ufw allow from any port 68 to any port 67 proto udp

If you aren't getting DNS servers assigned via DHCP (or have them configured in your
`resolv.conf`), you can configure a specific upstream DNS server in `dnsmasq` by
adding e.g. `server=8.8.8.8` to `dnsmasq.conf`. See the `dnsmasq` documentation.


Optional DHCP Server
--------------------

Most of the following sections show an example `dnsmasq.conf` file
that enables the DHCP server component of `dnsmasq`. If you don't
need or want a DHCP server, you can simply comment out all `dhcp`
related configuration lines in that configuration file to disable it
(see the `dhcp-range` option in `man dnsmasq`).

To assign fixed IPs to certain MAC addresses, add lines like this to `dnsmasq.conf`:

	dhcp-host=11:22:33:44:55:66,192.168.88.20,hostname,infinite


Internet via `eth0`, providing a WiFi Access Point with NAT
-----------------------------------------------------------

In `/etc/ufw/before.rules` at the top, right after the header comments:

	*nat
	:POSTROUTING ACCEPT [0:0]
	-A POSTROUTING -s 192.168.88.0/24 -o eth0 -j MASQUERADE
	COMMIT

In `/etc/dhcpcd.conf`, configure `eth0` as needed for internet access, and:

	interface wlan0
	static ip_address=192.168.88.1/24
	static domain_name_servers=192.168.88.1
	nohook wpa_supplicant

File `/etc/hostapd/hostapd.conf`
(can test via `sudo hostapd /etc/hostapd/hostapd.conf`):

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

File `/etc/dnsmasq.conf`:

	interface=wlan0
	domain-needed
	bogus-priv
	dhcp-range=192.168.88.100,192.168.88.150
	dhcp-option=option:ntp-server,0.0.0.0

Make sure `/etc/network/interfaces` is empty!

In `/etc/default/hostapd`, set `DAEMON_CONF="/etc/hostapd/hostapd.conf"`.

	sudo systemctl enable dhcpcd
	sudo systemctl enable hostapd
	sudo systemctl enable dnsmasq
	sudo reboot


Internet via `wlan0`, providing NAT on `eth0`
---------------------------------------------

In `/etc/ufw/before.rules` at the top, right after the header comments:

	*nat
	:POSTROUTING ACCEPT [0:0]
	-A POSTROUTING -s 192.168.88.0/24 -o wlan0 -j MASQUERADE
	COMMIT

In `/etc/dhcpcd.conf`, configure `wlan0` as needed for internet access, and:

	interface eth0
	static ip_address=192.168.88.1/24
	static domain_name_servers=192.168.88.1

In `/etc/wpa_supplicant/wpa_supplicant.conf`:

	network={
		ssid="SSID"
		psk="Passphrase"
	}

File `/etc/dnsmasq.conf`:

	interface=eth0
	domain-needed
	bogus-priv
	dhcp-range=192.168.88.100,192.168.88.150
	dhcp-option=option:ntp-server,0.0.0.0

Make sure `/etc/network/interfaces` is empty!

In `/etc/default/hostapd`, comment out `DAEMON_CONF`.

	sudo systemctl disable hostapd
	sudo systemctl enable dhcpcd
	sudo systemctl enable dnsmasq
	sudo reboot


Bridged `eth0` and `wlan0`
--------------------------

In `/etc/ufw/before.rules`, remove the `*nat` table entries that may have been added above.

In `/etc/dhcpcd.conf`:

	denyinterfaces wlan0 eth0
	
	interface br0
	# OPTIONAL, if you don't have a DHCP server on the network
	#static ip_address=192.168.88.1/24
	#static domain_name_servers=192.168.88.1

Use the same `/etc/hostapd/hostapd.conf` file as above,
**except** add the line `bridge=br0`.

In `/etc/network/interfaces`:

	auto br0
	iface br0 inet manual
		bridge_ports eth0

File `/etc/dnsmasq.conf`:

	domain-needed
	bogus-priv
	# OPTIONAL - ONLY add in if you DON'T already have a DHCP server!
	#dhcp-range=192.168.88.100,192.168.88.150
	#dhcp-option=option:ntp-server,0.0.0.0

In `/etc/default/hostapd`, set `DAEMON_CONF="/etc/hostapd/hostapd.conf"`

	sudo systemctl enable dhcpcd
	sudo systemctl enable hostapd
	sudo systemctl enable dnsmasq
	sudo reboot


Author, Copyright, and License
------------------------------

Copyright (c) 2018 Hauke Daempfling <haukex@zero-g.net>
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
