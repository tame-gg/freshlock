#!/usr/bin/env bash
#
# build-app.sh - assemble FreshLock.app from the SwiftPM release build.
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
#   CONFIGURATION            debug|release (default: release)
#   ARCH                     arm64|x86_64|universal (default: universal)
#   EMBED_SYSTEM_EXTENSION   0|1 (default: 0) - embed Phase 1 .systemextension
#                            Requires Apple ES entitlement to *activate* on SIP-on.
#                            Off by default so Phase 0 shipping stays entitlement-free.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT/dist}"
CONFIGURATION="${CONFIGURATION:-release}"
ARCH="${ARCH:-universal}"
EMBED_SYSTEM_EXTENSION="${EMBED_SYSTEM_EXTENSION:-0}"

APP_NAME="FreshLock"
BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
ENTITLEMENTS="$ROOT/Packaging/FreshLock.entitlements"

echo "▶ Building $APP_NAME ($CONFIGURATION, $ARCH)…"

BUILD_FLAGS=(--configuration "$CONFIGURATION")
case "$ARCH" in
  universal) BUILD_FLAGS+=(--arch arm64 --arch x86_64) ;;
  arm64|x86_64) BUILD_FLAGS+=(--arch "$ARCH") ;;
  *) echo "Unknown ARCH: $ARCH" >&2; exit 1 ;;
esac

# Phase 0 default: only GUI + helper. Endpoint Security is built separately
# (Scripts/build-systemextension.sh) or when EMBED_SYSTEM_EXTENSION=1.
echo "   Products: FreshLock, FreshLockHelper"
swift build "${BUILD_FLAGS[@]}" --product FreshLock
swift build "${BUILD_FLAGS[@]}" --product FreshLockHelper
BIN_PATH="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

echo "▶ Assembling bundle at $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
mkdir -p "$BUNDLE/Contents/Library/LoginItems" "$BUNDLE/Contents/Library/LaunchAgents"

cp "$BIN_PATH/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Packaging/Info.plist" "$BUNDLE/Contents/Info.plist"

# --- Localizations: copy .lproj catalogs into the main bundle. SwiftUI's
# LocalizedStringKey resolves literals against the main bundle at runtime, so
# no code changes are needed - only these resources. ---
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

# --- Optional Phase 1 Endpoint Security system extension (off by default) ---
if [[ "$EMBED_SYSTEM_EXTENSION" == "1" ]]; then
  echo "▶ Embedding system extension (EMBED_SYSTEM_EXTENSION=1)…"
  CONFIGURATION="$CONFIGURATION" ARCH="$ARCH" \
    "$ROOT/Scripts/build-systemextension.sh" "$OUTPUT_DIR"
  SYSEXT_SRC="$OUTPUT_DIR/gg.tame.freshlock.enforce.systemextension"
  SYSEXT_DST="$BUNDLE/Contents/Library/SystemExtensions/gg.tame.freshlock.enforce.systemextension"
  mkdir -p "$BUNDLE/Contents/Library/SystemExtensions"
  rm -rf "$SYSEXT_DST"
  cp -R "$SYSEXT_SRC" "$SYSEXT_DST"
  echo "   Embedded $SYSEXT_DST"
  echo "   Note: host entitlements in Packaging/FreshLock-SystemExtension-Host.entitlements"
  echo "   are required to activate; default Phase 0 signing does not merge them."
else
  echo "▶ Skipping system extension embed (set EMBED_SYSTEM_EXTENSION=1 to include)"
fi

# Copy an app icon if present (Scripts/generate-icon.swift produces AppIcon.icns).
if [[ -f "$ROOT/Packaging/AppIcon.icns" ]]; then
  cp "$ROOT/Packaging/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

# --- Signing.
#
# Three tiers, in order of how well macOS remembers an Accessibility grant across
# updates:
#
#   1. SIGNING_IDENTITY  → Developer ID (paid). sign-and-notarize.sh handles it.
#   2. LOCAL_SIGNING_IDENTITY → a persistent signing identity that is NOT
#      Developer ID: a free self-signed code-signing certificate, or an "Apple
#      Development" cert from a free Apple ID. Both give the bundle a stable
#      *designated requirement* anchored to the certificate, so a rebuilt release
#      still satisfies the requirement TCC stored at grant time.
#   3. Ad-hoc (`--sign -`) → fallback. WARNING: an ad-hoc signature has no
#      certificate, so its designated requirement is a bare `cdhash` pin. The
#      cdhash changes on every build, so TCC drops the Accessibility grant on
#      every update. This is the least-sticky option; prefer (1) or (2) for
#      anything users install.
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  echo "▶ SIGNING_IDENTITY set - leaving signing to Scripts/sign-and-notarize.sh"
elif [[ -n "${LOCAL_SIGNING_IDENTITY:-}" ]]; then
  echo "▶ Signing bundle with persistent identity '$LOCAL_SIGNING_IDENTITY' (cert-anchored, update-stable)…"
  # Innermost first, then host. --deep covers nested LoginItems helper.
  codesign --force --sign "$LOCAL_SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    "$HELPER" 2>/dev/null || codesign --force --sign "$LOCAL_SIGNING_IDENTITY" "$HELPER"
  codesign --force --deep --sign "$LOCAL_SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    "$BUNDLE"
  codesign --verify --verbose=1 "$BUNDLE" 2>&1 | sed 's/^/   /' || true
  echo "   Designated requirement (what TCC pins the grant to):"
  codesign -d --requirements - "$BUNDLE" 2>&1 | sed 's/^/   /' || true
else
  echo "▶ Ad-hoc signing bundle (cdhash-pinned; Accessibility grant will NOT survive updates)…"
  # Innermost first, then host. --deep covers nested LoginItems helper.
  codesign --force --sign - \
    --entitlements "$ENTITLEMENTS" \
    "$HELPER" 2>/dev/null || codesign --force --sign - "$HELPER"
  codesign --force --deep --sign - \
    --entitlements "$ENTITLEMENTS" \
    "$BUNDLE"
  codesign --verify --verbose=1 "$BUNDLE" 2>&1 | sed 's/^/   /' || true
fi

echo "✅ Built $BUNDLE"
echo "   Run: open \"$BUNDLE\""
