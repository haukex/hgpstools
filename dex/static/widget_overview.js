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
	}
);


