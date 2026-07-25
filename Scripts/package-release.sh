#!/usr/bin/env bash
#
# package-release.sh — produce a distributable FreshLock.zip + SHA256.
#
# Wraps build-app.sh, signs (Developer ID if SIGNING_IDENTITY is set, otherwise
# an ad-hoc signature so the app runs locally), zips and checksums. It assembles
# in a clean staging directory outside any file-provider-backed folder (iCloud
# Documents auto-stamps xattrs that codesign rejects), then copies results back.
#
# Usage: Scripts/package-release.sh [output-dir]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT/dist}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "▶ Building into staging: $STAGE"
CONFIGURATION=release ARCH="${ARCH:-universal}" "$ROOT/Scripts/build-app.sh" "$STAGE" >/dev/null

APP="$STAGE/FreshLock.app"
HELPER="$APP/Contents/Library/LoginItems/FreshLockHelper.app"

# Strip inherited extended attributes so codesign won't refuse.
xattr -cr "$APP"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  echo "▶ Signing with Developer ID and notarizing"
  "$ROOT/Scripts/sign-and-notarize.sh" "$APP"
elif [[ -n "${LOCAL_SIGNING_IDENTITY:-}" ]]; then
  # Persistent, non–Developer-ID identity (free self-signed cert or an Apple
  # Development cert). The point is a *stable* signature: TCC pins an
  # Accessibility grant to the bundle's designated requirement, which for a
  # cert-signed app is anchored to the certificate — not the cdhash — so the
  # grant survives updates as long as the same cert signs every release.
  echo "▶ Signing with persistent identity '$LOCAL_SIGNING_IDENTITY' (cert-anchored, update-stable)"
  codesign --force -s "$LOCAL_SIGNING_IDENTITY" "$HELPER"
  codesign --force --deep -s "$LOCAL_SIGNING_IDENTITY" "$APP"
  echo "   Designated requirement (what TCC pins the grant to):"
  codesign -d --requirements - "$APP" 2>&1 | sed 's/^/   /' || true
else
  echo "ℹ️  No signing identity — applying an ad-hoc signature (runs locally,"
  echo "    Gatekeeper will warn other users, and the Accessibility grant will be"
  echo "    lost on every update). Set LOCAL_SIGNING_IDENTITY or SIGNING_IDENTITY."
  codesign --force --deep -s - "$HELPER"
  codesign --force --deep -s - "$APP"
fi

codesign --verify --deep --strict "$APP"

echo "▶ Zipping + checksum"
mkdir -p "$OUTPUT_DIR"
ditto -c -k --keepParent "$APP" "$STAGE/FreshLock.zip"
( cd "$STAGE" && shasum -a 256 FreshLock.zip > FreshLock.zip.sha256 )

ditto "$APP" "$OUTPUT_DIR/FreshLock.app"
cp "$STAGE/FreshLock.zip" "$OUTPUT_DIR/FreshLock.zip"
cp "$STAGE/FreshLock.zip.sha256" "$OUTPUT_DIR/FreshLock.zip.sha256"

echo "✅ Release artifacts in $OUTPUT_DIR:"
ls -lh "$OUTPUT_DIR"/FreshLock.zip*
cat "$OUTPUT_DIR/FreshLock.zip.sha256"
