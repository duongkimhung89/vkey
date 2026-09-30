#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
./scripts/test.sh
./scripts/audit.sh
mkdir -p build
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="dist/VKey-$VERSION-arm64.dmg"
# Stage the drag-and-drop installer contents. The Applications symlink is what
# makes Finder show the usual “drag the app to Applications” workflow; the app
# performs the hidden Input Methods registration after its first launch.
DMG_STAGE="$(mktemp -d "$PWD/build/vkey-dmg.XXXXXX")"
trap 'find "$DMG_STAGE" -depth -delete 2>/dev/null || true' EXIT
ditto dist/VKey.app "$DMG_STAGE/VKey.app"
cp HUONG-DAN.txt "$DMG_STAGE/HUONG-DAN.txt"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname VKey -srcfolder "$DMG_STAGE" -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
# Notarize and staple when a notarytool keychain profile is named, e.g.
# VKEY_NOTARY_PROFILE=VKeyNotary (created with `xcrun notarytool store-credentials`).
if [ -n "${VKEY_NOTARY_PROFILE:-}" ]; then
  RESULT="$(xcrun notarytool submit "$DMG" --keychain-profile "$VKEY_NOTARY_PROFILE" --wait --output-format json)"
  echo "$RESULT"
  if ! grep -q '"status" *: *"Accepted"' <<<"$RESULT"; then
    echo "Notarization was not accepted; see: xcrun notarytool log <id> --keychain-profile $VKEY_NOTARY_PROFILE" >&2
    exit 1
  fi
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  # The disk image itself is not a code object; assess the signed app inside it.
  spctl --assess --type execute -vv dist/VKey.app
fi
shasum -a 256 "$DMG" > dist/SHA256SUMS.txt
