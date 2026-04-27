#!/usr/bin/env bash
# Creates a distributable DMG containing FLACtastic.app and an /Applications shortcut.
#
# Usage: create-dmg.sh
#
# Inputs:
#   build/FLACtastic.app  (must already exist — run package-macos.sh first)
#   version.txt
#
# Output:
#   dist/FLACtastic-<version>.dmg

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

APP_BUNDLE="$PROJECT_ROOT/build/FLACtastic.app"
DIST_DIR="$PROJECT_ROOT/dist"
VERSION_FILE="$PROJECT_ROOT/version.txt"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "ERROR: $APP_BUNDLE not found. Run package-macos.sh first." >&2
    exit 1
fi

VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
DMG_NAME="FLACtastic-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
VOLUME_NAME="FLACtastic ${VERSION}"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

# Staging directory — what the user sees when they mount the DMG
STAGING="$(mktemp -d)/dmg-staging"
mkdir -p "$STAGING"

echo "▶ Staging DMG contents..."
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Create the DMG using hdiutil. Use UDZO (zlib-compressed) for smaller size.
echo "▶ Creating DMG..."
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG_PATH" >/dev/null

# Code-sign the DMG itself (ad-hoc) — purely cosmetic for development
codesign --force --sign - "$DMG_PATH" 2>/dev/null || true

rm -rf "$(dirname "$STAGING")"

DMG_SIZE="$(du -sh "$DMG_PATH" | cut -f1)"
echo
echo "✅ DMG ready"
echo "   path: $DMG_PATH"
echo "   size: $DMG_SIZE"
