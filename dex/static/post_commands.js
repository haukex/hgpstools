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

var btn_setdate = $('<button/>',
	{ text: "Set Browser Time on Server", class: "post_cmd",
		click: function() {
			do_post("sys_control", { command:"date", args:["--set="+new Date().toISOString()] } );
		}
	} );
$('#post_commands')
	.append('<div/>')
	.append(btn_setdate);
add_btn_confirm(btn_setdate);

var services =
	["ngserlog_cpt6100_port0","ngserlog_cpt6100_port1","ngserlog_cpt6100_port2","ngserlog_cpt6100_port3",
	"ngserlog_hmt310","ngserlog_novatel1ctrl","ngserlog_novatel2txt","ngserlog_novatel3bin"];
var srv_cmds = ["none", "start", "stop", "status"];
var srv_tbl = $('<table/>');
srv_tbl.append( $('<tr/>')
	.append( $('<th/>', { text: "Service" } ) )
	.append( $('<th/>', { text: "Command" } ) ) );
$.each(services, function(i, srv) {
	var radio_td = $('<td/>');
	$.each(srv_cmds, function(j, cmd) {
		var radio = $('<input/>', { type: "radio", name: "ctrl_"+srv, value: j } );
		if (j==0) radio.prop('checked', true);
		radio_td.append( $('<label/>').append(radio,cmd) );
	});
	srv_tbl.append( $('<tr/>')
		.append( $('<td/>', { text: srv } ) )
		.append( radio_td ) );
});
var btn_services = $('<button/>', {
	text: "Control Services", class: "post_cmd",
	click: function() {
		$.each(services, function(i, srv) {
			var cmd = $('input[name=ctrl_'+srv+']:checked').val();
			if (cmd!=0)
				do_post("sys_control", { command:"service", args:[srv,srv_cmds[cmd]] } );
			$('input[name=ctrl_'+srv+'][value=0]').prop('checked', true);
		});
	}
} );
$('#post_commands')
	.append('<div/>')
	.append(srv_tbl, btn_services);
add_btn_confirm(btn_services);
