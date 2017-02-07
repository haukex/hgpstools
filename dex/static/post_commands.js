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

//TODO: Add commands to start & stop logger services

var btn_reboot = $('<button/>',
	{ text: "System Reboot", class: "post_cmd",
		click: function() {
			do_post("sys_control", { command:"reboot" } );
		}
	} );
$('#post_commands')
	.append('<div/>')
	.append(btn_reboot);
add_btn_confirm(btn_reboot);

var btn_poweroff = $('<button/>',
	{ text: "System Shutdown", class: "post_cmd",
		click: function() {
			if (confirm("WARNING: Are you sure you want to power down?"))
				do_post("sys_control", { command:"poweroff" } );
		}
	} );
$('#post_commands')
	.append('<div/>')
	.append(btn_poweroff);
add_btn_confirm(btn_poweroff);
