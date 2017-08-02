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

$('body').append(
  '<div class="widget" id="sens_novatel">'
+ '<div><span id="novatel_value" style="word-wrap:break-word;">?</span></div>'
+ '<div class="small">Data Age: <span id="novatel_txtdata_age">?</span></div>'
+ '<div id="novatel_sendcmd">Command: <input type="text" id="novatel_thecmd" value="LOG VERSIONA ONCE" /></div>'
+ '<div>Command Log:</div>'
+ '<pre id="novatel_cmds"></pre>'
+ '</div>' );

components.push(
	{ componentName: 'sens_novatel',  title: 'Novatel' } );

data_ages.novatel_txtdata_age = { age_s: null };

datahandlers.push(
	function (data) {
		if (data.novatel_txtdata) {
			$('#novatel_value').text(data.novatel_txtdata.record);
			data_ages.novatel_txtdata_age.age_s = data.novatel_txtdata._now;
		}
		if (data.novatel_cmds) {
			$('#novatel_cmds').text(data.novatel_cmds.cmdlog.join("\n"));
		}
	} );

var btn_novatel_sendcmd = $('<button/>',
	{ text: "Send", class: "post_cmd",
		click: function() {
			do_post("novatel_sendcmd", { cmd:$('#novatel_thecmd').val() } );
		}
	} );
$('#novatel_sendcmd')
	.append(btn_novatel_sendcmd);
add_btn_confirm(btn_novatel_sendcmd);

