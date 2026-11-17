#!/bin/sh
# Regenerates the three manual PDFs from the single source docs/manual/source.py (+ captures from the built app) and verifies them.
# Captures (synthetic only): GDC_BUILD_ROOT=... sh scripts/capture_manual.sh   |  Source of the text: docs/manual/source.py
set -e
EV="${GDC_BUILD_ROOT:?set GDC_BUILD_ROOT to the external test-storage folder}"
[ -d "$EV" ] && [ -w "$EV" ] || { echo "EXTERNAL TEST STORAGE NOT AVAILABLE"; exit 3; }
HERE="$(cd "$(dirname "$0")/.." && pwd)"; VER="$(tr -d '[:space:]' < "$HERE/VERSION")"; C="$EV/captures/manual"; T="$EV/temp/manual"; mkdir -p "$T" "$C"
for L in ro en es; do [ -f "$C/inspector_$L.png" ] && sips -c 90 2360 --cropOffset 1310 0 "$C/inspector_$L.png" --out "$C/version_bar_$L.png" >/dev/null; done
python3 "$HERE/docs/manual/source.py" "$VER" > "$T/source.json"
swiftc -O "$HERE/tools/make_manual.swift" -o "$T/make_manual"; swiftc -O "$HERE/tools/verify_manual.swift" -o "$T/verify_manual"
for L in ro en es; do "$T/make_manual" "$T/source.json" $L "$C" "$HERE/docs/manual/pdf/manual-$L.pdf"; "$T/verify_manual" $L "$HERE/docs/manual/pdf/manual-$L.pdf" "$VER"; done
