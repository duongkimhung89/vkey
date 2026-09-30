#!/bin/bash
# Build, test, and replace the running input method with the new build.
# No logout is needed: the built app installs itself into
# ~/Library/Input Methods and restarts the input method that is running.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
./scripts/test.sh
dist/VKey.app/Contents/MacOS/VKey --quiet
echo "Installed: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$HOME/Library/Input Methods/VKey.app/Contents/Info.plist")"
