#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Prefer an explicitly selected Developer ID identity, otherwise select the
# first Developer ID Application certificate available in the login keychain.
# Set VKEY_CODESIGN_IDENTITY to a certificate name or SHA-1 hash in CI.
SIGNING_IDENTITY="${VKEY_CODESIGN_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application:/ { print $2; exit }')"
fi
if [ -z "$SIGNING_IDENTITY" ]; then
  echo "No Developer ID Application certificate found." >&2
  echo "Set VKEY_CODESIGN_IDENTITY or install a Developer ID Application certificate." >&2
  exit 1
fi
echo "Signing with: $SIGNING_IDENTITY"

# Resources are rebuilt from scratch so that nothing from an earlier build lingers.
rm -rf dist/VKey.app/Contents/Resources
mkdir -p build/module-cache dist/VKey.app/Contents/{MacOS,Resources}
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
xcrun swiftc -O -swift-version 5 -module-cache-path "$CLANG_MODULE_CACHE_PATH" -target arm64-apple-macosx13.0 -framework AppKit -framework InputMethodKit -framework Carbon Sources/XKeyEngine/*.swift Sources/*.swift -o dist/VKey.app/Contents/MacOS/VKey
cp Resources/Info.plist dist/VKey.app/Contents/Info.plist
cp Resources/VKeyIcon.pdf dist/VKey.app/Contents/Resources/VKeyIcon.pdf
cp Resources/VKey.icns dist/VKey.app/Contents/Resources/VKey.icns
ditto Resources/Licenses dist/VKey.app/Contents/Resources/Licenses
cp THIRD_PARTY.md dist/VKey.app/Contents/Resources/THIRD_PARTY.md
cp THIRD_PARTY_NOTICES.md dist/VKey.app/Contents/Resources/THIRD_PARTY_NOTICES.md
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" dist/VKey.app
codesign --verify --deep --strict dist/VKey.app
