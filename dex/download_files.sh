#!/bin/bash
set -e
# Helper script to download the required files. Uses wget; must be run
# from the "dex" main directory. Deletes existing files before download!
cd static
rm -fv normalize* jquery* goldenlayout*
# The normal download sources would be:
# - https://necolas.github.io/normalize.css/
# - https://jquery.com/download/
# - https://www.golden-layout.com/download/
# But I'm using the GitHub repos directly:
# - https://github.com/necolas/normalize.css
# - https://github.com/jquery/jquery
# - https://github.com/deepstreamIO/golden-layout
# Because it makes picking specific fixed versions easier.
NORMALIZE_VERSION="8.0.0"
JQUERY_VERSION="3.3.1"
GOLDLAY_VERSION="v1.5.9"
wget -nv -i- <<ENDURLLIST
https://raw.githubusercontent.com/necolas/normalize.css/$NORMALIZE_VERSION/LICENSE.md
https://raw.githubusercontent.com/necolas/normalize.css/$NORMALIZE_VERSION/normalize.css
https://raw.githubusercontent.com/jquery/jquery/$JQUERY_VERSION/dist/jquery.min.js
https://raw.githubusercontent.com/deepstreamIO/golden-layout/$GOLDLAY_VERSION/LICENSE
https://raw.githubusercontent.com/deepstreamIO/golden-layout/$GOLDLAY_VERSION/dist/goldenlayout.min.js
https://raw.githubusercontent.com/deepstreamIO/golden-layout/$GOLDLAY_VERSION/src/css/goldenlayout-base.css
https://raw.githubusercontent.com/deepstreamIO/golden-layout/$GOLDLAY_VERSION/src/css/goldenlayout-light-theme.css
https://raw.githubusercontent.com/deepstreamIO/golden-layout/$GOLDLAY_VERSION/src/css/goldenlayout-dark-theme.css
ENDURLLIST
mv LICENSE.md normalize-LICENSE.txt
mv LICENSE goldenlayout-LICENSE.txt
