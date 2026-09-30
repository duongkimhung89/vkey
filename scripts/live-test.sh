#!/bin/bash
# Type through the installed VKey into real AppKit and WebKit text views.
# Install the build under test first (scripts/dev-install.sh).  A test window
# takes keyboard focus for a few minutes; do not type or click elsewhere while
# it is open.  It switches VKey between Telex and VNI and puts your setting
# back when it ends.  The first run asks for the Accessibility permission that
# pressing keys requires.
# LIVE_ONLY="WebKit textarea" limits the run to one kind of text view;
# LIVE_KEYS="tieengs " types just those keys in the current mode.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/VKeyLiveTest.app
LOG="$PWD/build/live-test.log"
mkdir -p build/module-cache "$APP/Contents/MacOS"
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" \
  -framework AppKit -framework Carbon -framework WebKit Tests/Live/main.swift \
  -o "$APP/Contents/MacOS/VKeyLiveTest"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>VKeyLiveTest</string>
	<key>CFBundleIdentifier</key>
	<string>local.vkey.livetest</string>
	<key>CFBundleName</key>
	<string>VKeyLiveTest</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
</dict>
</plist>
PLIST
# Sign with the build identity so the permission survives rebuilds.
IDENTITY="${VKEY_CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application:/ { print $2; exit }')}"
codesign --force --sign "${IDENTITY:--}" "$APP" >/dev/null 2>&1
: > "$LOG"
# LaunchServices must start the app: only then may it become the active
# application, and an inactive one is not served by the input method.
open -W -n "$APP" --stdout "$LOG" --stderr "$LOG" ${LIVE_ONLY:+--env "LIVE_ONLY=$LIVE_ONLY"} ${LIVE_KEYS:+--env "LIVE_KEYS=$LIVE_KEYS"}
cat "$LOG"
tail -1 "$LOG" | grep -q "^\([0-9]*\)/\1 live checks passed$"
