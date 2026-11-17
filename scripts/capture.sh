#!/bin/sh
# Headless design-review captures of the app (synthetic demo data only). Output on the external volume.
EV="${GDC_BUILD_ROOT:?set GDC_BUILD_ROOT to the external test-storage folder}"
[ -d "$EV" ] && [ -w "$EV" ] || { echo "EXTERNAL TEST STORAGE NOT AVAILABLE"; exit 3; }
A="$EV/builds/GDC Metadata.app/Contents/MacOS/GDCMetadata"; C="$EV/captures/${1:-review_01}"; mkdir -p "$C"
run() { n="$1"; shift; "$A" "$@" --screen --snapshot "$C/$n.png" >/dev/null 2>&1 & pid=$!; i=0
  while kill -0 $pid 2>/dev/null && [ $i -lt 25 ]; do sleep 1; i=$((i+1)); done; kill $pid 2>/dev/null; wait $pid 2>/dev/null; [ -f "$C/$n.png" ] && echo "ok $n" || echo "MISSING $n"; }
run 01_empty_en --lang en
run 02_default_en --demo --select 0 --lang en --size 1180x700
run 03_search_en --demo --select 0 --lang en --query ColorTemperature --size 1180x700
run 04_search_nomatch_en --demo --select 4 --lang en --query ColorTemperature --size 1180x700
run 05_motion_detected_en --demo --select 1 --lang en --open motion --size 1180x980
run 06_motion_confirmed_en --demo --select 2 --lang en --open motion --size 1180x980
run 07_motion_ready_en --demo --select 0 --lang en --open motion --size 1180x980
run 08_motion_none_en --demo --select 4 --lang en --open motion --size 1180x980
run 09_resolve_en --demo --lang en --resolve
run 10_narrow_es --demo --select 0 --lang es --size 820x560
run 11_narrow_en --demo --select 0 --lang en --size 820x560
run 12_resolve_ro --demo --lang ro --resolve
