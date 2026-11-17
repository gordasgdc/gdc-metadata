#!/bin/sh
# Captures for the manual (synthetic data only), per language, from the built app. Output on the external volume.
EV="${GDC_BUILD_ROOT:?set GDC_BUILD_ROOT to the external test-storage folder}"
[ -d "$EV" ] && [ -w "$EV" ] || { echo "EXTERNAL TEST STORAGE NOT AVAILABLE"; exit 3; }
A="${GDC_APP:-$EV/builds/GDC Metadata.app}/Contents/MacOS/GDCMetadata"; C="$EV/captures/manual/raw"; F="/Volumes/DemoClips"; mkdir -p "$C"
# neutral volume name so no personal path shows in the screenshots
if [ ! -d "$F" ]; then IMG="$EV/temp/DemoClips.dmg"; rm -f "$IMG"; hdiutil create -size 8m -fs HFS+ -volname DemoClips "$IMG" >/dev/null; hdiutil attach "$IMG" -nobrowse >/dev/null; for n in 1 2 3; do cp "$EV/fixtures/pkgprobe/PKG_A00$n.mov" "$F/A00$n.mov"; done; fi
echo synthetic > "$F/notes.txt"
run() { n="$1"; shift; rm -f "$C/$n.png"; "$A" "$@" --no-update --screen --snapshot "$C/$n.png" >/dev/null 2>&1 & pid=$!; i=0
  while kill -0 $pid 2>/dev/null && [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done; kill $pid 2>/dev/null; wait $pid 2>/dev/null; [ -f "$C/$n.png" ] && echo "ok $n" || echo "MISSING $n"; }
for L in ro en es; do
  run import_three_$L --lang $L --scan "$F/A001.mov|$F/A002.mov|$F/A003.mov|$F/notes.txt" --select 0 --size 1180x700
  run inspector_$L --demo --select 0 --lang $L --size 1180x700
  run search_$L --demo --select 0 --lang $L --query ColorTemperature --size 1180x700
  run resolve_sheet_$L --demo --lang $L --resolve
done
python3 "$(dirname "$0")/crop_manual.py" "$(dirname "$C")"
