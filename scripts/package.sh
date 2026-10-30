#!/usr/bin/env bash
# Builds one architecture and assembles a signed .app ZIP.
# Usage: scripts/package.sh [arm64|x86_64] [version] [build-number]
set -euo pipefail

ARCH="${1:-$(uname -m)}"
VERSION="${2:-0.1.0}"
BUILD_NUMBER="${3:-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP_NAME="sw33p"

case "$ARCH" in
    arm64) ARCH_NAME=apple-silicon ;;
    x86_64) ARCH_NAME=intel ;;
    *) printf 'Unsupported architecture: %s\n' "$ARCH" >&2; exit 1 ;;
esac
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Invalid version: %s\n' "$VERSION" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { printf 'Invalid build number: %s\n' "$BUILD_NUMBER" >&2; exit 1; }

OUTROOT="$DIST/$APP_NAME-$VERSION-$ARCH_NAME"
BUNDLE="$DIST/$APP_NAME.app"
ARCHIVE="$OUTROOT/$APP_NAME-$VERSION-$ARCH_NAME.zip"

printf '==> Building %s for %s (release)...\n' "$APP_NAME" "$ARCH"
cd "$ROOT"
swift build --manifest-cache none -c release --arch "$ARCH"
BIN="$(swift build --manifest-cache none -c release --arch "$ARCH" --show-bin-path)/$APP_NAME"
[[ -x "$BIN" ]] || { printf 'Build did not produce %s\n' "$BIN" >&2; exit 1; }

printf '==> Assembling %s...\n' "$BUNDLE"
rm -rf "$BUNDLE" "$OUTROOT"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
cp "$ROOT/Resources/sw33p.icns" "$BUNDLE/Contents/Resources/sw33p.icns"
cp "$ROOT/LICENSE" "$BUNDLE/Contents/Resources/LICENSE.txt"

PLIST="$BUNDLE/Contents/Info.plist"
set_plist() {
    /usr/libexec/PlistBuddy -c "Delete :$1" "$PLIST" > /dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Add :$1 $2 $3" "$PLIST"
}
set_plist CFBundleShortVersionString string "$VERSION"
set_plist CFBundleVersion string "$BUILD_NUMBER"

printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# Drop SwiftPM artifact rpaths from the shipped binary.
LOAD_COMMANDS="$(otool -l "$BUNDLE/Contents/MacOS/$APP_NAME")"
RPATHS="$(printf '%s\n' "$LOAD_COMMANDS" | /usr/bin/awk '
    $1 == "cmd" && $2 == "LC_RPATH" { pending=1; next }
    pending && $1 == "path" { sub(/^[[:space:]]*path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print; pending=0 }
' | sort -u)"
while IFS= read -r rpath; do
    case "$rpath" in
        "$ROOT/.build"|"$ROOT/.build/"*|*/.build/*|/Applications/*/Contents/Developer/*|/Library/Developer/*)
            install_name_tool -delete_rpath "$rpath" "$BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true ;;
    esac
done <<< "$RPATHS"

printf '==> Signing...\n'
SIGN_ARGS=(--force --sign "${CODESIGN_IDENTITY:--}")
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    SIGN_ARGS+=(--options runtime --timestamp)
    SIGN_STATE="signed with '$CODESIGN_IDENTITY' (Hardened Runtime)"
    printf '==> WARNING: Developer ID signature applied; notarization is still required before distribution.\n' >&2
else
    SIGN_STATE='ad-hoc signed (NOT for distribution)'
fi
codesign "${SIGN_ARGS[@]}" --entitlements "$ROOT/Resources/sw33p.entitlements" "$BUNDLE"
codesign --verify --deep --strict --verbose=2 "$BUNDLE"

printf '==> Zipping...\n'
mkdir -p "$OUTROOT"
mv "$BUNDLE" "$OUTROOT/"
ditto -c -k --keepParent --norsrc "$OUTROOT/$APP_NAME.app" "$ARCHIVE"
shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}' > "$ARCHIVE.sha256"
bash "$ROOT/scripts/verify-release.sh" "$OUTROOT/$APP_NAME.app" "$VERSION" "$ARCH"

printf '\n==> %s\n' "$ARCHIVE"
printf '    %s\n' "$(cat "$ARCHIVE.sha256")"
printf '    %s\n' "$SIGN_STATE"
