#!/bin/sh
# Builds GDC Metadata.app (ad-hoc signed for local testing). Build outputs go to the external test volume (STORAGE_POLICY).
set -e
EV="${GDC_BUILD_ROOT:?set GDC_BUILD_ROOT to the external test-storage folder}"
[ -d "$EV" ] && [ -w "$EV" ] || { echo "EXTERNAL TEST STORAGE NOT AVAILABLE"; exit 3; }
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export CARGO_HOME="$EV/cache/cargo" CARGO_TARGET_DIR="$EV/builds/core"
( cd "$HERE/core" && cargo build --release )
( cd "$HERE/app" && swift build -c release --scratch-path "$EV/builds/app" )
APP="$EV/builds/GDC Metadata.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$EV/builds/app/release/GDCMetadata" "$APP/Contents/MacOS/GDCMetadata"
cp "$EV/builds/core/release/gdc-metadata-core" "$APP/Contents/Resources/"
cp "$HERE/LICENSE" "$HERE/NOTICE" "$HERE/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"
cp "$HERE/app/Resources/resolve_bridge.py" "$HERE/app/Resources/demo_clips.ndjson" "$HERE"/app/Resources/thumb_*.png "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.gordas.GDCMetadata</string><key>CFBundleName</key><string>GDC Metadata</string>
<key>CFBundleExecutable</key><string>GDCMetadata</string><key>CFBundleShortVersionString</key><string>${GDC_VERSION:-0.1.0}</string><key>CFBundleVersion</key><string>1</string>
<key>CFBundlePackageType</key><string>APPL</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
P
if [ -n "${SIGN_IDENTITY:-}" ]; then
  # Developer ID, hardened runtime + secure timestamp (required for notarization); helper first, then the bundle
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP/Contents/Resources/gdc-metadata-core"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP/Contents/Resources/gdc-metadata-core" "$APP" 2>&1 | tail -1
fi
echo "$APP"
