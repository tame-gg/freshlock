#!/usr/bin/env bash
#
# update-cask.sh — bump the Homebrew cask for a new release.
#
# Usage:
#   Scripts/update-cask.sh <version> <path-to-sha256-file>
#
# Behaviour:
#   • Updates version + sha256 in homebrew-tap/Casks/freshlock.rb in this repo.
#   • If GH_TOKEN and HOMEBREW_TAP_REPO are set, clones the real tap repo,
#     applies the same edit, commits and pushes. Otherwise it edits locally only
#     (useful for testing) and exits 0.
#
set -euo pipefail

VERSION="${1:?Usage: update-cask.sh <version> <sha256-file>}"
SHA_FILE="${2:?Usage: update-cask.sh <version> <sha256-file>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SHA256="$(awk '{print $1}' "$SHA_FILE")"
echo "▶ Cask bump: version=$VERSION sha256=$SHA256"

bump() {
  local cask="$1"
  /usr/bin/sed -i.bak -E "s/version \"[^\"]+\"/version \"$VERSION\"/" "$cask"
  /usr/bin/sed -i.bak -E "s/sha256 \"[0-9a-f]+\"/sha256 \"$SHA256\"/" "$cask"
  rm -f "$cask.bak"
}

# Always update the in-repo mirror.
bump "$ROOT/homebrew-tap/Casks/freshlock.rb"

# Push to the real tap repo if credentials are available.
if [[ -n "${GH_TOKEN:-}" ]]; then
  TAP_REPO="${HOMEBREW_TAP_REPO:-tame-gg/homebrew-tap}"
  TMP="$(mktemp -d)"
  git clone "https://x-access-token:${GH_TOKEN}@github.com/${TAP_REPO}.git" "$TMP"
  bump "$TMP/Casks/freshlock.rb"
  git -C "$TMP" add Casks/freshlock.rb
  git -C "$TMP" -c user.name="tame-bot" -c user.email="bot@tame.gg" \
    commit -m "chore: update freshlock to $VERSION"
  git -C "$TMP" push
  echo "✅ Pushed cask update to $TAP_REPO"
else
  echo "ℹ️  GH_TOKEN not set — updated local mirror only."
fi
