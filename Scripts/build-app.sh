#!/usr/bin/env bash
#
# build-app.sh — assemble AppLock.app from the SwiftPM release build.
#
# SwiftPM produces a bare executable; macOS needs a bundle. This script builds
# in release configuration and lays out a proper .app directory with Info.plist
# so the binary can run as a menu-bar app, register a login item, and be
# code-signed / notarized.
#
# Usage:
#   Scripts/build-app.sh [output-dir]
#
# Environment:
#   CONFIGURATION   debug|release (default: release)
#   ARCH            arm64|x86_64|universal (default: universal)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT/dist}"
CONFIGURATION="${CONFIGURATION:-release}"
ARCH="${ARCH:-universal}"

APP_NAME="AppLock"
BUNDLE="$OUTPUT_DIR/$APP_NAME.app"

echo "▶ Building $APP_NAME ($CONFIGURATION, $ARCH)…"

BUILD_FLAGS=(--configuration "$CONFIGURATION")
case "$ARCH" in
  universal) BUILD_FLAGS+=(--arch arm64 --arch x86_64) ;;
  arm64|x86_64) BUILD_FLAGS+=(--arch "$ARCH") ;;
  *) echo "Unknown ARCH: $ARCH" >&2; exit 1 ;;
esac

swift build "${BUILD_FLAGS[@]}"
BIN_PATH="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

echo "▶ Assembling bundle at $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cp "$BIN_PATH/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Packaging/Info.plist" "$BUNDLE/Contents/Info.plist"

# Copy an app icon if present (Scripts/generate-icon.sh produces AppIcon.icns).
if [[ -f "$ROOT/Packaging/AppIcon.icns" ]]; then
  cp "$ROOT/Packaging/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" \
    "$BUNDLE/Contents/Info.plist" 2>/dev/null || true
fi

echo "✅ Built $BUNDLE"
