#!/usr/bin/env bash
# Verifies the latest DMG installs cleanly and the app launches.
#
# Usage: test-install.sh [--launch]
#
#   Without --launch: mounts the DMG, validates the bundle, copies the app
#                     to a temp location, runs codesign + spctl checks, and
#                     unmounts. Does NOT install into /Applications.
#   With --launch:    additionally runs the app from the temp location to
#                     confirm it starts. You'll need to quit it manually.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
DIST_DIR="$PROJECT_ROOT/dist"

LAUNCH=0
for arg in "$@"; do
    case "$arg" in
        --launch) LAUNCH=1 ;;
    esac
done

# Pick the most recent DMG
DMG="$(ls -t "$DIST_DIR"/FLACtastic-*.dmg 2>/dev/null | head -n1 || true)"
if [[ -z "$DMG" ]]; then
    echo "ERROR: no DMG found in $DIST_DIR. Run build-release.sh first." >&2
    exit 1
fi

echo "▶ Testing DMG: $DMG"
echo

# ── Mount ───────────────────────────────────────────────────────────────────
echo "▶ Mounting DMG..."
# hdiutil emits tab-separated columns: device, content-hint, mount-point.
# Volume names can contain spaces, so split on tabs and grab the third field.
MOUNT_OUTPUT="$(hdiutil attach -nobrowse -readonly "$DMG")"
MOUNT_POINT="$(printf '%s\n' "$MOUNT_OUTPUT" | awk -F '\t' '/\/Volumes\// {print $NF; exit}' | sed -E 's/^ +//; s/ +$//')"
if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
    echo "ERROR: failed to determine mount point" >&2
    echo "hdiutil output:" >&2
    echo "$MOUNT_OUTPUT" >&2
    exit 1
fi
echo "  mounted at: $MOUNT_POINT"

cleanup() {
    if [[ -n "${MOUNT_POINT:-}" ]] && [[ -d "$MOUNT_POINT" ]]; then
        echo "▶ Unmounting..."
        hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

# ── Validate bundle ─────────────────────────────────────────────────────────
APP_IN_DMG="$MOUNT_POINT/FLACtastic.app"
if [[ ! -d "$APP_IN_DMG" ]]; then
    echo "ERROR: FLACtastic.app not found in DMG" >&2
    exit 1
fi

echo
echo "▶ Bundle inspection..."
echo "  Info.plist:"
plutil -p "$APP_IN_DMG/Contents/Info.plist" | sed 's/^/    /' \
    | grep -E "(CFBundleIdentifier|CFBundleVersion|CFBundleShortVersionString|CFBundleExecutable)"
echo
echo "  Bundle contents:"
ls "$APP_IN_DMG/Contents/" | sed 's/^/    /'
echo
if [[ -d "$APP_IN_DMG/Contents/Frameworks" ]]; then
    echo "  Embedded frameworks:"
    ls "$APP_IN_DMG/Contents/Frameworks/" | sed 's/^/    /'
fi

# ── Copy to temp install location ───────────────────────────────────────────
TEMP_INSTALL="$(mktemp -d)/FLACtastic.app"
echo
echo "▶ Copying app to temp location: $TEMP_INSTALL"
cp -R "$APP_IN_DMG" "$TEMP_INSTALL"

# ── Code-sign verification ──────────────────────────────────────────────────
echo
echo "▶ codesign verification..."
codesign --verify --deep --verbose=2 "$TEMP_INSTALL" 2>&1 | sed 's/^/    /'

echo
echo "▶ codesign details..."
codesign -dvv "$TEMP_INSTALL" 2>&1 | sed 's/^/    /' || true

# ── Gatekeeper check (informational; ad-hoc signed apps will be rejected) ───
echo
echo "▶ Gatekeeper assessment (expected to be rejected for ad-hoc signing)..."
spctl --assess --verbose=4 "$TEMP_INSTALL" 2>&1 | sed 's/^/    /' || true

# ── Library dependency check ────────────────────────────────────────────────
echo
echo "▶ Dynamic library dependencies..."
otool -L "$TEMP_INSTALL/Contents/MacOS/flactastic" | sed 's/^/    /'

# ── Optional launch ─────────────────────────────────────────────────────────
if [[ $LAUNCH -eq 1 ]]; then
    echo
    echo "▶ Launching app (quit manually when done testing)..."
    open -W "$TEMP_INSTALL"
fi

echo
echo "✅ Install test complete"
echo "   To install for real: drag FLACtastic.app from the DMG into /Applications"
