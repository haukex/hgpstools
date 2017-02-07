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
  '<div class="widget" id="sens_cpt6100">'
+ '<table id="cpt6100">'
+ '<tr><th>Port</th><th>Pressure</th><th class="small">Age</th></tr>'
+ '<tr><td>0</td><td><span id="cpt6100_port0_val">?</span></td><td><span id="cpt6100_port0_age" class="small">?</span></td></tr>'
+ '<tr><td>1</td><td><span id="cpt6100_port1_val">?</span></td><td><span id="cpt6100_port1_age" class="small">?</span></td></tr>'
+ '<tr><td>2</td><td><span id="cpt6100_port2_val">?</span></td><td><span id="cpt6100_port2_age" class="small">?</span></td></tr>'
+ '<tr><td>3</td><td><span id="cpt6100_port3_val">?</span></td><td><span id="cpt6100_port3_age" class="small">?</span></td></tr>'
+ '</table>'
+ '</div>' );

components.push(
	{ componentName: 'sens_cpt6100',  title: 'CPT6100' } );

for (var i=0; i<4; i++)
	data_ages["cpt6100_port"+i+"_age"] = { age_s: null };

datahandlers.push(
	function (data) {
		for (var i=0; i<4; i++) {
			if (data["cpt6100_port"+i]) {
				$('#cpt6100_port'+i+'_val').text(data["cpt6100_port"+i].pressure);
				data_ages["cpt6100_port"+i+"_age"].age_s = data["cpt6100_port"+i]._now;
			}
		}
	} );

