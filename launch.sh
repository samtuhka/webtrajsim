#!/bin/bash
# Unix sucks bad.
trap 'kill -HUP 0' EXIT

#BROWSER="chromium --user-data-dir=chromium-data --allow-file-access-from-files"
#BROWSER="primusrun ./firefox/firefox/firefox"
BROWSER="./firefox/full-build-linux/chrome --disable-setuid-sandbox --disable-gpu-sandbox --user-data-dir=chromium-data --allow-file-access-from-files"


SHOST=localhost
SPORT=8000
WHOST=localhost
WPORT=10101
./wheel/websocketd --port=$WPORT --address=$WHOST ./wheel/wheel.py&
python3 -m http.server --bind $SHOST $PORT &
#export __GL_FSAA_MODE=11
#$BROWSER "http://$SHOST:$SPORT/index.html?controller=ws://$WHOST:$WPORT/"
#$BROWSER "file://$PWD/index.html?controller=ws://$WHOST:$WPORT/"
$BROWSER "file://$PWD/index.html"
