#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
./scripts/test.sh
./scripts/audit.sh
mkdir -p build
# Stage the drag-and-drop installer contents. The Applications symlink is what
# makes Finder show the usual “drag the app to Applications” workflow; the app
# performs the hidden Input Methods registration after its first launch.
DMG_STAGE="$(mktemp -d "$PWD/build/vkey-dmg.XXXXXX")"
trap 'find "$DMG_STAGE" -depth -delete 2>/dev/null || true' EXIT
ditto dist/VKey.app "$DMG_STAGE/VKey.app"
cp HUONG-DAN.txt "$DMG_STAGE/HUONG-DAN.txt"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname VKey -srcfolder "$DMG_STAGE" -format UDZO -ov dist/VKey-0.2.0-arm64.dmg
hdiutil verify dist/VKey-0.2.0-arm64.dmg
shasum -a 256 dist/VKey-0.2.0-arm64.dmg > dist/SHA256SUMS.txt
