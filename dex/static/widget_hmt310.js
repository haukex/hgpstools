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
  '<div class="widget" id="sens_hmt310">'
+ '<div><span id="hmt310_value" style="font-weight:bold;">?</span></div>'
+ '<div class="small">Data Age: <span id="hmt310_age">?</span></div>'
+ '</div>' );

components.push(
	{ componentName: 'sens_hmt310',  title: 'HMT310' } );

data_ages.hmt310_age = { age_s: null };

datahandlers.push(
	function (data) {
		if (!data.hmt310) return;
		$('#hmt310_value').text(data.hmt310.data);
		data_ages.hmt310_age.age_s = data.hmt310._now;
	} );

