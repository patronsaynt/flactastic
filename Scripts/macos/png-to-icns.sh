#!/usr/bin/env bash
# Converts a 1024x1024 PNG to a multi-resolution .icns file using iconutil.
# Usage: png-to-icns.sh <input_png> <output_icns>

set -euo pipefail

INPUT_PNG="${1:?Input PNG path required}"
OUTPUT_ICNS="${2:?Output ICNS path required}"

if [[ ! -f "$INPUT_PNG" ]]; then
    echo "ERROR: Input PNG not found: $INPUT_PNG" >&2
    exit 1
fi

if ! command -v sips >/dev/null 2>&1; then
    echo "ERROR: 'sips' not found (should be on every macOS install)." >&2
    exit 1
fi

if ! command -v iconutil >/dev/null 2>&1; then
    echo "ERROR: 'iconutil' not found (Xcode Command Line Tools required)." >&2
    exit 1
fi

ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

# Generate all sizes Apple expects in an iconset
sips -z 16 16     "$INPUT_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32     "$INPUT_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$INPUT_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64     "$INPUT_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$INPUT_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256   "$INPUT_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$INPUT_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512   "$INPUT_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$INPUT_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$INPUT_PNG"                "$ICONSET_DIR/icon_512x512@2x.png"

mkdir -p "$(dirname "$OUTPUT_ICNS")"
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"

rm -rf "$(dirname "$ICONSET_DIR")"

echo "Generated ICNS at: $OUTPUT_ICNS"
