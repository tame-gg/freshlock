# Releasing

FreshLock releases are fully automated from an annotated git tag.

## Cut a release

1. Update `CHANGELOG.md` (move items from *Unreleased* to the new version).
2. Bump `CFBundleShortVersionString` in `Packaging/Info.plist`.
3. Commit and tag:
   ```bash
   git commit -am "chore(release): v0.2.0"
   git tag -a v0.2.0 -m "v0.2.0"
   git push origin main --tags
   ```

## Build a release locally

```bash
Scripts/package-release.sh          # → dist/FreshLock.app, FreshLock.zip, .sha256
```

Without `SIGNING_IDENTITY` this applies an **ad-hoc** signature: the app runs on
your own machine, but other users get a Gatekeeper warning (they can right-click
→ Open, or you can distribute a properly signed + notarized build by exporting
the signing variables below first). The script stages in a clean temp directory
so it works even when the repo lives in an iCloud/file-provider folder.

## What the release workflow does

On a `v*.*.*` tag, `.github/workflows/release.yml`:

1. Runs the test suite.
2. Builds, signs (Developer ID + notarize if secrets exist, else ad-hoc), zips
   and checksums via `Scripts/package-release.sh`.
3. Creates a GitHub Release with auto-generated notes and uploads the zip +
   checksum.
4. Bumps the Homebrew cask (`Scripts/update-cask.sh`) and pushes to
   `tame-gg/homebrew-tap` (if `HOMEBREW_TAP_TOKEN` is configured).

## Required repository secrets (all optional)

| Secret               | Purpose                              |
|----------------------|--------------------------------------|
| `SIGNING_IDENTITY`   | Developer ID Application identity     |
| `APPLE_ID`           | Apple ID for notarization             |
| `APPLE_TEAM_ID`      | Developer team id                     |
| `APPLE_APP_PASSWORD` | App-specific password for notarytool  |
| `HOMEBREW_TAP_TOKEN` | PAT with push access to the tap repo  |

Without these, releases still publish an **unsigned** build and skip the cask
bump — nothing fails.
