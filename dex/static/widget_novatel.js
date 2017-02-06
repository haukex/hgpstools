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
+ '<div><span id="novatel_value" style="font-weight:bold;">?</span></div>'
+ '<div class="small">Data Age: <span id="novatel_age">?</span></div>'
+ '</div>' );

components.push(
	{ componentName: 'sens_novatel',  title: 'Novatel' } );

data_ages.novatel_age = { age_s: null };

datahandlers.push(
	function (data) {
		if (!data.novatel) return;
		$('#novatel_value').text(data.novatel.record);
		data_ages.novatel_age.age_s = data.novatel._now;
	} );

