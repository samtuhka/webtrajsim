#!/bin/bash
# Unix sucks bad.
trap 'kill -HUP 0' EXIT

cd "$( dirname "${BASH_SOURCE[0]}" )"

BROWSER="chromium --user-data-dir=chromium-data --allow-file-access-from-files"
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
LOGHOST=localhost
LOGPORT=10102

SESSDIR="./sessions/`date --utc --iso-8601=ns`"
mkdir -p $SESSDIR

./wheel/websocketd --port=$WPORT --address=$WHOST ./wheel/wheel.py&

./wslog --port $LOGPORT --host $LOGHOST > "$SESSDIR/simulator.jsons" &
#python3 -m http.server --bind $SHOST $PORT &
#export vblank_mode=0
#export __GL_FSAA_MODE=11
#$BROWSER "http://$SHOST:$SPORT/index.html?controller=ws://$WHOST:$WPORT/"
ARGS="?experiment=blindFollow17"
#ARGS+="&controller=ws://$WHOST:$WPORT/"
ARGS+="&wsLogger=ws://$LOGHOST:$LOGPORT&disableDefaultLogger=true"
$BROWSER "file://$PWD/index.html$ARGS"
#$BROWSER "file://$PWD/index.html"
#$BROWSER "http://$SHOST:$SPORT/index.html"
