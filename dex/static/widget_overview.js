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
  '<div class="widget overview" id="overview">'
+ '<div class="ovw_msg" style="background:darkgrey"><span id="ovw_temperature">?</span>&nbsp;°C&nbsp;<span style="margin:0 0.5em">&nbsp;</span>&nbsp;<span id="ovw_relhumiditiy">?</span>&nbsp;%RH</div>'
//+ '<div class="ovw_msg ovw_error">Error: Test</div>'
//+ '<div class="ovw_msg ovw_warning">Warn: Test</div>'
//+ '<div class="ovw_msg ovw_ok">All Systems Go</div>'
//+ '<pre id="overview_debug"></pre>' //Debug
+ '</div>' );

components.push(
	{ componentName: 'overview',  title: 'Overview' } );

/*error_listeners.push( function() {
	
} );*/

datahandlers.push(
	function (data) {
		//$('#overview_debug').text( "data_ages="+JSON.stringify(data_ages) ); //Debug
		//TODO
		if (data.hmt310) {
			$.each(data.hmt310.data, function(i, val) {
				var name  = val[0];
				var value = val[1];
				var unit  = val[2];
				if (name=='T' && unit=="'C") {
					$('#ovw_temperature').text(value);
				}
				else if (name=='RH' && unit=='%RH') {
					$('#ovw_relhumiditiy').text(value);
				}
			});
		}
	}
);


