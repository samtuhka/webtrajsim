#!/bin/bash
# Hack on hack :(
./build.bash
watchmedo shell-command -p "*.ls;*.jade;*.styl" -R -c 'echo Insanifying because ${watch_src_path} ${watch_event_type} >&2; ./build.bash' --drop --wait
