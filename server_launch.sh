#!/bin/bash
# Unix sucks bad.
trap 'kill -HUP 0' EXIT

cd "$( dirname "${BASH_SOURCE[0]}" )"

SESSDIR="/home/tru/host/sessions/`date +%s`"
PUPILPORT=64559

mkdir -p $SESSDIR
mkdir -p "$SESSDIR/verifications/"
mkdir -p "$SESSDIR/calibrations/"

./wheel/websocketd --port=10101 --address=0.0.0.0 ./wheel/wheel.py&

./wslog --port 10102 --host 0.0.0.0 > "$SESSDIR/simulator.jsons" &

python hmd_calibration_client.py "`date +%s`" "$SESSDIR/calibrations/", $PUPILPORT &
python3 hmd_verification_client.py  "$SESSDIR/verifications/", $PUPILPORT &

http-server
