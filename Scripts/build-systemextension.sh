#!/usr/bin/env bash
#
# build-systemextension.sh — assemble gg.tame.freshlock.enforce.systemextension
#
# Builds the FreshLockEnforceExtension product and lays out a proper
# .systemextension bundle. Does NOT require Apple's ES entitlement to *assemble*
# the bundle; loading / AUTH_EXEC on SIP-on Macs does.
#
# Usage:
#   Scripts/build-systemextension.sh [output-dir]
#
# Environment:
#   CONFIGURATION   debug|release (default: release)
#   ARCH            arm64|x86_64|universal (default: universal)
#
# Embed into FreshLock.app (optional, not default shipping):
#   EMBED_SYSTEM_EXTENSION=1 Scripts/build-app.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT/dist}"
CONFIGURATION="${CONFIGURATION:-release}"
ARCH="${ARCH:-universal}"

EXT_NAME="FreshLockEnforce"
BUNDLE_ID="gg.tame.freshlock.enforce"
SYSEXT="$OUTPUT_DIR/${BUNDLE_ID}.systemextension"

echo "▶ Building FreshLockEnforceExtension ($CONFIGURATION, $ARCH)…"

BUILD_FLAGS=(--configuration "$CONFIGURATION" --product FreshLockEnforceExtension)
case "$ARCH" in
  universal) BUILD_FLAGS+=(--arch arm64 --arch x86_64) ;;
  arm64|x86_64) BUILD_FLAGS+=(--arch "$ARCH") ;;
  *) echo "Unknown ARCH: $ARCH" >&2; exit 1 ;;
esac

swift build "${BUILD_FLAGS[@]}"
BIN_PATH="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

echo "▶ Assembling system extension at $SYSEXT"
rm -rf "$SYSEXT"
mkdir -p "$SYSEXT/Contents/MacOS" "$SYSEXT/Contents/Resources"

cp "$BIN_PATH/FreshLockEnforceExtension" "$SYSEXT/Contents/MacOS/FreshLockEnforceExtension"
cp "$ROOT/Packaging/EnforceExtension-Info.plist" "$SYSEXT/Contents/Info.plist"
cp "$ROOT/Packaging/EnforceExtension.entitlements" "$SYSEXT/Contents/Resources/EnforceExtension.entitlements"

# Codesign is intentionally left to sign-and-notarize / developer workflow.
# Unsigned sysexts will not activate on SIP-on systems.

cat > "$SYSEXT/Contents/Resources/README.txt" <<EOF
FreshLock Enforce — Endpoint Security system extension (Phase 1 scaffolding)

This is NOT a kernel extension (kext). Apple deprecated third-party kexts;
Endpoint Security system extensions are the supported path for AUTH_EXEC gates.

Entitlement required: com.apple.developer.endpoint-security.client (Apple-managed)
Host install entitlement: com.apple.developer.system-extension.install
Also required: Full Disk Access, user/MDM approval, Developer ID signing.

Without the entitlement the extension exits cleanly and does not enforce.
See docs/ENFORCEMENT.md and docs/THREAT_MODEL.md.
EOF

echo "✅ Built $SYSEXT"
echo "   Next: EMBED_SYSTEM_EXTENSION=1 Scripts/build-app.sh   # optional embed"
echo "   Or copy into FreshLock.app/Contents/Library/SystemExtensions/"
