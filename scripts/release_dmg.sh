#!/bin/bash
# Builds, signs (Developer ID), notarizes, staples and verifies GDCMetadata-<version>.dmg. Output on the external test volume.
# Needs: GDC_BUILD_ROOT, a Developer ID Application identity, and a notarytool keychain profile (NOTARY_PROFILE, default gdc-notary).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EV="${GDC_BUILD_ROOT:?set GDC_BUILD_ROOT to the external test-storage folder}"
[ -d "$EV" ] && [ -w "$EV" ] || { echo "EXTERNAL TEST STORAGE NOT AVAILABLE"; exit 3; }
VERSION="$(tr -d '[:space:]' < "$HERE/VERSION")"
SIGN_IDENTITY="${SIGN_IDENTITY:?set SIGN_IDENTITY to the Developer ID Application identity}"
PROFILE="${NOTARY_PROFILE:-gdc-notary}"
APP="$EV/builds/GDC Metadata.app"; OUT="$EV/artifacts/$VERSION"; DMG="$OUT/GDCMetadata-$VERSION.dmg"
WORK="$(mktemp -d)"; trap 'hdiutil detach "$WORK/mnt" -quiet 2>/dev/null; rm -rf "${WORK:?}"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
notarize() { local r id st; r="$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait --output-format json)" || fail "notarytool"
  id="$(printf '%s' "$r" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("id",""))')"; st="$(printf '%s' "$r" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("status",""))')"
  [ "$st" = "Accepted" ] || { xcrun notarytool log "$id" --keychain-profile "$PROFILE" | head -40 >&2; fail "notarization $st"; }; echo "notarized $id"; }
GDC_VERSION="$VERSION" SIGN_IDENTITY="$SIGN_IDENTITY" sh "$HERE/scripts/build_app.sh" >/dev/null
codesign --verify --strict --deep "$APP" || fail "app signature"
ditto -c -k --keepParent "$APP" "$WORK/app.zip"; notarize "$WORK/app.zip"
xcrun stapler staple "$APP" >/dev/null; xcrun stapler validate "$APP" >/dev/null
spctl -a -vv -t exec "$APP" 2>&1 | grep -q "Notarized Developer ID" || fail "Gatekeeper rejects app"
mkdir -p "$WORK/stage" "$OUT"; ditto "$APP" "$WORK/stage/GDC Metadata.app"
cp "$HERE/LICENSE" "$HERE/NOTICE" "$HERE/THIRD_PARTY_NOTICES.md" "$WORK/stage/"; ln -s /Applications "$WORK/stage/Applications"
rm -f "$DMG"; hdiutil create -volname "GDC Metadata $VERSION" -srcfolder "$WORK/stage" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"; notarize "$DMG"
xcrun stapler staple "$DMG" >/dev/null; xcrun stapler validate "$DMG" >/dev/null
spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 | grep -q "Notarized Developer ID" || fail "Gatekeeper rejects DMG"
mkdir -p "$WORK/mnt"; hdiutil attach "$DMG" -mountpoint "$WORK/mnt" -nobrowse -readonly >/dev/null
C="$WORK/mnt/GDC Metadata.app"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$C/Contents/Info.plist")" = "$VERSION" ] || fail "version mismatch"
codesign --verify --strict --deep "$C"; xcrun stapler validate "$C" >/dev/null
spctl -a -vv -t exec "$C" 2>&1 | grep -q "Notarized Developer ID" || fail "Gatekeeper rejects app in DMG"
for f in LICENSE NOTICE THIRD_PARTY_NOTICES.md; do [ -f "$WORK/mnt/$f" ] && [ -f "$C/Contents/Resources/$f" ] || fail "missing $f"; done
cp "$DMG" "$OUT/GDCMetadata.dmg"; (cd "$OUT" && shasum -a 256 GDCMetadata-$VERSION.dmg GDCMetadata.dmg > SHA256SUMS)
echo "OK $DMG"; cat "$OUT/SHA256SUMS"
