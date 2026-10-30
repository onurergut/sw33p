#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="0.0.0"
DIST="$ROOT/dist/sw33p-$VERSION-apple-silicon"

bash "$ROOT/scripts/package.sh" arm64 "$VERSION" 1 > /dev/null
APP="$DIST/sw33p.app"
[[ -x "$APP/Contents/MacOS/sw33p" ]]
codesign --verify --deep --strict "$APP"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" | grep -qx "$VERSION"
rm -rf "$DIST"
printf 'Packaging smoke test passed\n'
