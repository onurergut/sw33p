#!/usr/bin/env bash
# Notarizes and staples a signed bundle, then re-zips it.
# Prerequisite: xcrun notarytool store-credentials sw33p-profile ...
# Usage: scripts/notarize.sh dist/sw33p-<version>-apple-silicon/sw33p.app
set -euo pipefail

APP="${1:?usage: notarize.sh <path/to/sw33p.app>}"
PROFILE="${NOTARY_PROFILE:-sw33p-profile}"
PARENT="$(cd "$(dirname "$APP")" && pwd)"
APP="$PARENT/$(basename "$APP")"
PACKAGE_NAME="$(basename "$PARENT")"
case "$PACKAGE_NAME" in
    sw33p-*-apple-silicon|sw33p-*-intel) ;;
    *) printf 'Use the architecture-named folder created by package.sh.\n' >&2; exit 1 ;;
esac
OUT="$PARENT/$PACKAGE_NAME.zip"

codesign --verify --deep --strict --verbose=2 "$APP"
TMPZIP="$(mktemp -d)/sw33p.zip"
ditto -c -k --keepParent --norsrc "$APP" "$TMPZIP"
xcrun notarytool submit "$TMPZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vvv -t exec "$APP"
ditto -c -k --keepParent --norsrc "$APP" "$OUT"
shasum -a 256 "$OUT" | /usr/bin/awk '{print $1}' > "$OUT.sha256"
printf 'Notarized package: %s\n' "$OUT"
