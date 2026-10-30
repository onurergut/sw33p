#!/usr/bin/env bash
# Structural checks for a packaged bundle.
# Usage: scripts/verify-release.sh <path/to/sw33p.app> <version> <arm64|x86_64>
set -euo pipefail

APP="${1:?usage: verify-release.sh <app> <version> <arch>}"
VERSION="${2:?missing version}"
ARCH="${3:?missing arch}"
PLIST="$APP/Contents/Info.plist"
EXE="$APP/Contents/MacOS/sw33p"

[[ -d "$APP" ]] || { printf 'Missing bundle: %s\n' "$APP" >&2; exit 1; }
[[ -x "$EXE" ]] || { printf 'Missing executable: %s\n' "$EXE" >&2; exit 1; }
[[ -f "$PLIST" ]] || { printf 'Missing Info.plist\n' >&2; exit 1; }
[[ -f "$APP/Contents/Resources/sw33p.icns" ]] || { printf 'Missing icon\n' >&2; exit 1; }

actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
[[ "$actual_version" == "$VERSION" ]] || { printf 'Version mismatch: %s != %s\n' "$actual_version" "$VERSION" >&2; exit 1; }
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
[[ "$bundle_id" == "com.sw33p.app" ]] || { printf 'Unexpected bundle id: %s\n' "$bundle_id" >&2; exit 1; }
minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")"
[[ "$minimum" == "14.0" ]] || { printf 'Unexpected minimum macOS: %s\n' "$minimum" >&2; exit 1; }

if [[ "$ARCH" == "arm64" ]]; then
    lipo -info "$EXE" | grep -q 'arm64' || { printf 'Expected arm64 binary\n' >&2; exit 1; }
else
    lipo -info "$EXE" | grep -q 'x86_64' || { printf 'Expected x86_64 binary\n' >&2; exit 1; }
fi

if otool -l "$EXE" | grep -q "$(pwd)/.build"; then
    printf 'Binary still has a build-directory rpath\n' >&2
    exit 1
fi

codesign --verify --deep --strict "$APP"
printf 'Verified %s %s (%s)\n' "$(basename "$APP")" "$VERSION" "$ARCH"
