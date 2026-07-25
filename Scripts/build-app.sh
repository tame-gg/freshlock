#!/usr/bin/env bash
#
# build-app.sh — assemble FreshLock.app from the SwiftPM release build.
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

APP_NAME="FreshLock"
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
mkdir -p "$BUNDLE/Contents/Library/LoginItems" "$BUNDLE/Contents/Library/LaunchAgents"

cp "$BIN_PATH/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Packaging/Info.plist" "$BUNDLE/Contents/Info.plist"

# --- Localizations: copy .lproj catalogs into the main bundle. SwiftUI's
# LocalizedStringKey resolves literals against the main bundle at runtime, so
# no code changes are needed — only these resources. ---
copy_localizations() {
  local resources_dir="$1"
  for lproj in "$ROOT"/Localization/*.lproj; do
    [[ -d "$lproj" ]] || continue
    cp -R "$lproj" "$resources_dir/"
  done
}
copy_localizations "$BUNDLE/Contents/Resources"

# --- Embed the background helper as a nested LoginItems app bundle ---
HELPER="$BUNDLE/Contents/Library/LoginItems/FreshLockHelper.app"
mkdir -p "$HELPER/Contents/MacOS"
cp "$BIN_PATH/FreshLockHelper" "$HELPER/Contents/MacOS/FreshLockHelper"
cp "$ROOT/Packaging/Helper-Info.plist" "$HELPER/Contents/Info.plist"
# The helper renders the lock overlay in production, so it needs the strings too.
mkdir -p "$HELPER/Contents/Resources"
copy_localizations "$HELPER/Contents/Resources"

# launchd agent plist that SMAppService registers to keep the helper alive.
cp "$ROOT/Packaging/gg.tame.freshlock.helper.plist" \
   "$BUNDLE/Contents/Library/LaunchAgents/gg.tame.freshlock.helper.plist"

# Copy an app icon if present (Scripts/generate-icon.sh produces AppIcon.icns).
if [[ -f "$ROOT/Packaging/AppIcon.icns" ]]; then
  cp "$ROOT/Packaging/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" \
    "$BUNDLE/Contents/Info.plist" 2>/dev/null || true
fi

echo "✅ Built $BUNDLE"
