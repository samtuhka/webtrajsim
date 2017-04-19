#!/bin/bash
# Unix sucks bad.
trap 'kill -HUP 0' EXIT

cd "$( dirname "${BASH_SOURCE[0]}" )"

SESSDIR="/home/samtuhka/sessions/`date +%s`"
mkdir -p $SESSDIR

./wheel/websocketd --port=10101 --address=0.0.0.0 ./wheel/wheel.py&

./wslog --port 10102 --host 0.0.0.0 > "$SESSDIR/simulator.jsons" &

python hmd_calibration_client.py "`date +%s`"&

http-server
