#!/usr/bin/env bash
#
# sign-and-notarize.sh — code-sign, notarize and staple AppLock.app.
#
# Designed to degrade gracefully in CI: if the signing secrets are absent the
# script prints a notice and exits 0, so unsigned builds still publish.
#
# Required environment for signing (all optional — missing any skips signing):
#   SIGNING_IDENTITY        "Developer ID Application: … (TEAMID)"
#   APPLE_ID                Apple ID email for notarization
#   APPLE_TEAM_ID           Developer team id
#   APPLE_APP_PASSWORD      app-specific password
#
set -euo pipefail

APP="${1:?Usage: sign-and-notarize.sh <path-to.app>}"
ENTITLEMENTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Packaging/AppLock.entitlements"

if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
  echo "ℹ️  SIGNING_IDENTITY not set — skipping code signing and notarization."
  echo "   The app will run but Gatekeeper will warn users on first launch."
  exit 0
fi

echo "▶ Code signing $APP"
codesign --force --deep --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGNING_IDENTITY" \
  --timestamp "$APP"

codesign --verify --strict --verbose=2 "$APP"

if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_APP_PASSWORD:-}" ]]; then
  echo "ℹ️  Notarization credentials incomplete — signed but not notarized."
  exit 0
fi

ZIP="$(dirname "$APP")/AppLock-notarize.zip"
echo "▶ Notarizing…"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait

echo "▶ Stapling ticket"
xcrun stapler staple "$APP"
rm -f "$ZIP"
echo "✅ Signed, notarized and stapled."
