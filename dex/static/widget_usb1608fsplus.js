"use strict";

/*
Copyright (c) 2017 Hauke Daempfling (haukex@zero-g.net)
at the Leibniz Institute of Freshwater Ecology and Inland Fisheries (IGB),
Berlin, Germany, <http://www.igb-berlin.de/>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <http://www.gnu.org/licenses/>.
*/

/* TODO Later: This widget (and probably also usb1608fsplus_log.pl) should go into hgpstools
 * Notes on patching this stuff in:
 * - copy this file to ~/hgpstools/dex/static/
 * - need to "sudo visudo" and allow "sudo service usb1608fsplus_log"
 *   NOTE that apparently, a sudoers rule like
 *   "... /usr/sbin/service ngserlog_[A-Za-z0-9]*, /usr/sbin/service usb1608fsplus_log"
 *   does not work!? So for now I've just allowed /usr/sbin/service in general.
 *   Not optimal (!) but we're limiting access to the web interface anyway,
 *   so it's "relatively safe" for now. Probably need a better solution later.
 * - need to edit post_commands.js and add "usb1608fsplus_log" to the list
 * - need to edit sys_control.psgi and add "usb1608fsplus_log" to the service regex
 */

$('body').append(
  '<div class="widget" id="sens_usb1608fsplus">'
+ '<div id="usb1608fsplus_data">?</div>'
+ '<div class="small">Data Age: <span id="usb1608fsplus_age">?</span></div>'
+ '</div>' );

components.push(
	{ componentName: 'sens_usb1608fsplus',  title: 'USB-1608FS-Plus' } );

data_ages.usb1608fsplus_age = { age_s: null };

datahandlers.push(
	function (data) {
		if (!data.usb1608fsplus) return;
		$('#usb1608fsplus_data').empty();
		var tbl = $('<table/>');
		for (var i = 0; i < 8; i++) {
			var val = data.usb1608fsplus["chan_"+i];
			if (val) {
				tbl.append( $('<tr/>')
					.append( $('<td/>', { text: "Chan "+i } ) )
					.append( $('<td/>', { text: val.samp } ) )
					.append( $('<td/>', { text: val.volt } ) ) );
			}
		}
		$('#usb1608fsplus_data').append(tbl);
		data_ages.usb1608fsplus_age.age_s = data.usb1608fsplus._now;
	} );

