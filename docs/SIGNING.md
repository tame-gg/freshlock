# Signing & Accessibility persistence

FreshLock is distributed without a paid Apple Developer ID. To keep the macOS
**Accessibility (TCC) grant from being lost on every update**, releases are
signed with a **stable, self-signed `tame.gg` certificate**.

## Why this matters

macOS pins a TCC grant to the app's *designated requirement* recorded at grant
time. The requirement depends on how the app is signed:

- **Ad-hoc** (`codesign --sign -`): `designated => cdhash H"…"` — a bare code-hash
  pin. The cdhash changes on every build, so the grant is dropped on every update.
- **Cert-signed** (our `tame.gg` cert): `designated => identifier "gg.tame.freshlock"
  and certificate root = H"6c9ddbfe7ec94fb0541298d414acdb1001527eb8"` — anchored to
  the certificate, **independent of the code hash**. Any future release signed with
  the *same* certificate satisfies the stored requirement, so the grant persists.

This requires **no paid Apple Developer Program**. It is *not* notarized, so the
Homebrew cask still clears Gatekeeper quarantine (`xattr -cr`) on install.

## The certificate is critical — do not lose it

The identity lives in the login keychain as **`tame.gg`**, backed up outside the
repo at `~/.freshlock-signing/` (`tamegg.p12` plus the PEM cert/key). The export
password is stored separately in the maintainer's password manager — it is **not**
recorded in this repository.

Cert SHA-1 (the leaf/root hash TCC pins to):
`6C9DDBFE7EC94FB0541298D414ACDB1001527EB8`

**Back up `tamegg.p12` and its password somewhere safe.** If the cert is lost, a
new certificate has a different hash, and every user must re-grant Accessibility
once. Keep signing every release with this same cert.

To reimport on a fresh machine (you will be prompted for the export password):

    security import ~/.freshlock-signing/tamegg.p12 \
      -k ~/Library/Keychains/login.keychain-db \
      -T /usr/bin/codesign -T /usr/bin/security

## Cutting a release

Build and sign locally with the persistent identity, then publish:

    LOCAL_SIGNING_IDENTITY="tame.gg" Scripts/package-release.sh dist
    gh release create vX.Y dist/FreshLock.zip dist/FreshLock.zip.sha256 --title "…"
    Scripts/update-cask.sh X.Y dist/FreshLock.zip.sha256   # or edit the tap cask

Notes:

- The release CI workflow triggers only on **three-part** tags (`v*.*.*`). The
  project's tags are two-part (`v1.70`), so CI does **not** run and cannot
  overwrite the locally signed artifact. If you ever want CI to build, add the
  `tame.gg` cert as a secret and teach the workflow to import it — otherwise CI
  would ship an ad-hoc build and reset everyone's grant.
- The Homebrew cask (`tame-gg/homebrew-tap`) must **preserve** the shipped
  signature. Its postflight only re-signs ad-hoc as a fallback when the bundle
  fails `codesign --verify`; a normal signed release keeps its `tame.gg` identity.

## Upgrading from an ad-hoc build (1.69 and earlier)

The 1.69 and earlier ad-hoc builds have a different (cdhash) requirement, so the
first move to a `tame.gg`-signed build (1.70) needs Accessibility granted **once
more**. From 1.70 onward the grant carries across updates.
