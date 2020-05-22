
My Notes on Setting up Raspbian
===============================

*by Hauke Dämpfling <haukex@zero-g.net>
at the Leibniz Institute of Freshwater Ecology and Inland Fisheries (IGB),
Berlin, Germany, <http://www.igb-berlin.de/>
(legal information below)*

Introduction
------------

These instructions assume you have some basic knowledge of using
a Raspberry Pi and Raspbian / Debian.

Last tested:

- May 2020 on a Raspberry Pi Zero W with Raspbian Buster Lite 2020-02-13


Basic Setup
-----------

1. Flash the Raspbian image onto an SD card. See also:
<https://www.raspberrypi.org/documentation/installation/installing-images/>
	
	1. <https://www.raspberrypi.org/documentation/remote-access/ssh/> -
	   On the `boot` partition, touch a file `ssh`
	
	2. <https://www.raspberrypi.org/documentation/configuration/wireless/headless.md> -
	   On the `rootfs` partition, edit `/etc/wpa_supplicant/wpa_supplicant.conf`:
		
		network={
			ssid="ssid"
			psk="pass"
		}
	
	3. Log in with `pi` / `raspberry`
	
	4. `sudo raspi-config`
	
		1. Password, Hostname
		
		3. Locales: Add needed locales, don't delete existing locales, set C.UTF-8 as default
		
		4. If setting the keyboard layout setting fails, edit `/etc/default/keyboard`
		   and e.g. set `XKBLAYOUT="de"` and `XKBVARIANT="nodeadkeys"`
		
		4. All other options as appropriate
	
	5. `sudo apt-get update && sudo apt-get upgrade && sudo apt-get dist-upgrade` (reboot afterwards if necessary)
	
	6. `sudo apt-get install --no-install-recommends ufw fail2ban vim git screen ntpdate socat lsof dnsutils elinks lftp proxychains4 build-essential cpanminus liblocal-lib-perl perl-doc`
	
	7. `perl -Mlocal::lib >>~/.profile`
	
	8. Set up any files like `.bash_aliases`, `.vimrc`, etc.

2. **UFW**: `sudo ufw allow OpenSSH && sudo ufw enable`

3. **SSH**:
	
	1. Set up SSH keys
	
	2. `sudo vi /etc/ssh/sshd_config`
		
		PermitRootLogin no
		# Careful with the next one, it depends!
		PasswordAuthentication no

4. **fail2ban**

	1. `sudo cp -v /etc/fail2ban/jail.conf /etc/fail2ban/jail.local`
	
	2. File `/etc/fail2ban/action.d/ufw.conf` should exist
	
	3. File `/etc/fail2ban/jail.d/defaults-debian.conf`
	
		- Should contain `enabled = true` in section `[sshd]`
		- Add additional enables here if needed, for example,
		  create a section `[pure-ftpd]` and add `enabled = true`
	
	4. Edit `/etc/fail2ban/jail.local` to set the following values:
	
		- **Note:** search from the top of the file to set the global values in the `[DEFAULT]` section
		- `bantime   = 1day`
		- `findtime  = 6hours`
		- `maxretry  = 3`
		- `banaction = ufw`
		- In section `[sshd]`, set `mode = aggressive`
		
	5. In `/etc/fail2ban/fail2ban.conf`, set `dbpurgeage = 7d`
	
	6. `sudo systemctl restart fail2ban`, then check status:
	
		- `sudo fail2ban-client status`
		- `sudo fail2ban-client status sshd`
		- `sudo zgrep 'Ban' /var/log/fail2ban.log*`
	
	8. Note: Manual banning of repeat offenders:
		- `sudo zgrep Ban /var/log/fail2ban.log* | perl -wMstrict -Mvars=%x -nale '$x{$F[7]}++}{print "$_\t$x{$_}" for grep {$x{$_}>1} sort { $x{$b}<=>$x{$a} } keys %x'`
		- `sudo ufw deny from ADDRESS comment 'too many failed login attempts'`

5. **Crontab** to broadcast RPi's address and name

	1. `crontab -e`
		
		@reboot    hostname | socat -s - UDP-DATAGRAM:255.255.255.255:12340,broadcast 2>/dev/null
		* * * * *  hostname | socat -s - UDP-DATAGRAM:255.255.255.255:12340,broadcast 2>/dev/null
	
	2. In `/etc/rsyslog.conf`, apply this patch:
	
		-*.*;auth,authpriv.none          -/var/log/syslog
		+*.*;cron,auth,authpriv.none     -/var/log/syslog
	
	3. `sudo systemctl restart rsyslog`
	
	4. Can use `udplisten.pl` from this repository to listen for the broadcasts.

6. **Mail**: Configure Postfix either as "Local only" or "Internet Site" as appropriate in the following steps:

	sudo apt-get install alpine postfix bsd-mailx
	sudo vi /etc/postfix/main.cf
	#=> add the line "smtp_tls_security_level = may"
	#=> add the line "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"
	sudo dpkg-reconfigure postfix
	echo "root: pi" | sudo tee -a /etc/aliases
	sudo newaliases && sudo systemctl restart postfix
	echo "This is a mailx test" | mailx -s "mailx test" root
	alpine
	# Configure "User Domain" and anything else as needed

7. **Unattended Upgrades**

	1. `sudo apt-get install unattended-upgrades`
	
	2. `sudo vi /etc/apt/apt.conf.d/50unattended-upgrades`
		- Change the two `origin=Debian` to `origin=${distro_id}`
		  and change `label=Debian` to `label=Raspbian`
		- Set `Unattended-Upgrade::Mail` to `pi@localhost`
	
	3. `sudo vi /etc/apt/apt.conf.d/20auto-upgrades`
	
		APT::Periodic::Update-Package-Lists "1";
		APT::Periodic::Unattended-Upgrade "1";
		APT::Periodic::Download-Upgradeable-Packages "1";
		//APT::Periodic::Verbose "1";
		APT::Periodic::AutocleanInterval "7";
	
	4. Test with `sudo unattended-upgrade -d -v --dry-run`
	5. Enable with `sudo dpkg-reconfigure --priority=low unattended-upgrades`

8. **Miscellaneous**

	- For network time, `sudo apt-get install --no-install-recommends ntp` and edit `/etc/ntp.conf` as appropriate.
	
	- If the Raspberry Pi doesn't have direct internet access after installation:
		
		1. In `/etc/proxychains4.conf`, replace the default `socks4` line in the `[ProxyList]` section
		   with `socks5	127.0.0.1	12333`
		
		2. When you connect to the RPi via SSH, use `ssh -R12333 pi@...`
		
		3. Then, commands that support it, you can use e.g. `ALL_PROXY=socks5h://localhost:12333 curl http://example.com`,
		   for other commands use e.g. `sudo proxychains4 apt-get update`
	
	- Sometimes, on some WiFi nets, WiFi will stop working unless I reboot the Pi once in a while.
	  This can be done via `sudo -i crontab -e`: `0 5 * * *  /sbin/shutdown --reboot +5; /usr/bin/wall 'Reboot in 5 minutes!'`
	
	- Serial port: `sudo adduser pi dialout`, `stty -F /dev/ttyS0 19200 cs8 -parenb raw -crtscts -echo`, `cat /dev/ttyS0`


Author, Copyright, and License
------------------------------

Copyright (c) 2016-2020 Hauke Dämpfling <haukex@zero-g.net>
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
