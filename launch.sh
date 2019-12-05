#!/bin/bash
# Unix sucks bad.
trap 'kill -HUP 0' EXIT

cd "$( dirname "${BASH_SOURCE[0]}" )"
DISPLAY=":1.1"

SESSDIR="/home/tru/beech19/sessions/`date +%s`"
mkdir -p $SESSDIR

BROWSER="chromium --test-type --ignore-gpu-blacklist --no-sandbox --disable-gpu-sandbox --user-data-dir=chromium-data --allow-file-access-from-files --start-fullscreen"
#BROWSER="firefox -no-remote -new-instance -profile firefox-data"
#BROWSER="primusrun ./firefox/firefox/firefox"
#BROWSER="primusrun ./chrome/full-build-linux/chrome \
#	--test-type \
#	--ignore-gpu-blacklist \
#	--disable-setuid-sandbox \
#	--disable-gpu-sandbox --user-data-dir=chromium-data \
#	--allow-file-access-from-files \
#	--start-fullscreen
#	--js-flags=--expose-gc \
#	--enable-precise-memory-info"
#BROWSER="primusrun chromium --test-type --ignore-gpu-blacklist --disable-setuid-sandbox --disable-gpu-sandbox --user-data-dir=chromium-data --allow-file-access-from-files"

#SHOST=localhost
SHOST=0.0.0.0
SPORT=8000
WHOST=localhost
WPORT=10101

./wslog --port 10102 --host 0.0.0.0 > "$SESSDIR/simulator.jsons" &

./wheel/websocketd --port=$WPORT --address=$WHOST ./wheel/wheel.py&
#python3 -m http.server --bind $SHOST $PORT &
#export vblank_mode=0
#export __GL_FSAA_MODE=11
#$BROWSER "http://$SHOST:$SPORT/index.html?controller=ws://$WHOST:$WPORT/"
$BROWSER "file://$PWD/index.html?experiment=singleScenario&singleScenario=fixSwitch&controller=ws://$WHOST:$WPORT/&disableDefaultLogger=true&wsLogger=ws://localhost:10102/"
#$BROWSER "file://$PWD/index.html"
#$BROWSER "http://$SHOST:$SPORT/index.html"
