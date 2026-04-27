#!/usr/bin/env bash
# Top-level release builder for FLACtastic. Detects the host platform and
# delegates to the appropriate platform-specific scripts.
#
# Usage: build-release.sh [--skip-tests] [--skip-clean]
#
# Currently supported platforms:
#   - macOS  → produces dist/FLACtastic-<version>.dmg
#
# Future:
#   - Windows → would produce dist/FLACtastic-<version>.exe / .msi
#     (see Scripts/windows/WINDOWS_BUILD_NOTES.md)

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

VERSION_FILE="$PROJECT_ROOT/version.txt"
SKIP_TESTS=0
SKIP_CLEAN=0

for arg in "$@"; do
    case "$arg" in
        --skip-tests) SKIP_TESTS=1 ;;
        --skip-clean) SKIP_CLEAN=1 ;;
        -h|--help)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done

# ── Validate version ────────────────────────────────────────────────────────
if [[ ! -f "$VERSION_FILE" ]]; then
    echo "ERROR: $VERSION_FILE not found." >&2
    exit 1
fi
VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    echo "ERROR: invalid version '$VERSION' in version.txt" >&2
    echo "       expected MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH-PRERELEASE" >&2
    exit 1
fi

echo "═══════════════════════════════════════════════"
echo "  FLACtastic release build — v$VERSION"
echo "═══════════════════════════════════════════════"
echo

# ── Detect platform ─────────────────────────────────────────────────────────
case "$(uname -s)" in
    Darwin)
        PLATFORM="macos"
        ;;
    Linux|MINGW*|MSYS*|CYGWIN*)
        echo "ERROR: Windows/Linux release builds are not yet implemented." >&2
        echo "       See Scripts/windows/WINDOWS_BUILD_NOTES.md for status." >&2
        exit 1
        ;;
    *)
        echo "ERROR: unsupported platform: $(uname -s)" >&2
        exit 1
        ;;
esac

# ── Clean ───────────────────────────────────────────────────────────────────
if [[ $SKIP_CLEAN -eq 0 ]]; then
    echo "▶ Cleaning previous build artifacts..."
    rm -rf "$PROJECT_ROOT/build"
    rm -rf "$PROJECT_ROOT/dist"
fi

# ── Run tests ───────────────────────────────────────────────────────────────
if [[ $SKIP_TESTS -eq 0 ]]; then
    echo
    echo "▶ Running tests..."
    cd "$PROJECT_ROOT"
    if ! swift test; then
        echo
        echo "WARNING: tests failed. Use --skip-tests to bypass." >&2
        echo "         (continuing anyway for beta release)" >&2
    fi
else
    echo "▶ Skipping tests (--skip-tests)"
fi

# ── Platform-specific build ─────────────────────────────────────────────────
echo
echo "▶ Building for platform: $PLATFORM"
case "$PLATFORM" in
    macos)
        bash "$SCRIPT_DIR/macos/package-macos.sh"
        bash "$SCRIPT_DIR/macos/create-dmg.sh"
        ;;
esac

# ── Generate release notes stub ─────────────────────────────────────────────
RELEASE_NOTES="$PROJECT_ROOT/dist/RELEASE_NOTES.md"
if [[ ! -f "$RELEASE_NOTES" ]]; then
    cat > "$RELEASE_NOTES" <<NOTES
# FLACtastic ${VERSION}

**Release date:** $(date +%Y-%m-%d)
**Platforms:** macOS 14+ (Apple Silicon)

## What's new
- _(fill in changes for this beta)_

## Known issues
- _(fill in known issues)_

## Installation
1. Download \`FLACtastic-${VERSION}.dmg\`.
2. Open the DMG and drag **FLACtastic.app** into your **Applications** folder.
3. The first time you launch, right-click the app and choose **Open** to
   bypass macOS Gatekeeper (the build is ad-hoc signed for beta testing).
NOTES
    echo
    echo "▶ Wrote release notes stub: $RELEASE_NOTES"
fi

echo
echo "═══════════════════════════════════════════════"
echo "  ✅ Release build complete: v$VERSION"
echo "═══════════════════════════════════════════════"
ls -la "$PROJECT_ROOT/dist/"
