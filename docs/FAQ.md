# Frequently Asked Questions

### Does FreshLock see or store my password?

No. FreshLock uses Apple's `LocalAuthentication` framework, which shows its own
system authentication sheet. FreshLock only receives a success/failure result — it
never sees, handles, or stores your password.

### Can FreshLock stop an app from *launching*?

**Today (Phase 0): no.** Shipping FreshLock detects the launch after macOS
notifies it, covers the app with an overlay, and requires authentication. That
is a deterrent, not a pre-exec veto.

**Possible later (Phase 1):** Apple's Endpoint Security framework can deny
`AUTH_EXEC` before userland code runs, but only with a **managed entitlement**,
a system extension (or root daemon), Full Disk Access, and Developer ID
distribution - not as a typical Mac App Store feature. Scaffolding lives in
`FreshLockEnforce*`; it is **not shipping**. Even with ES, a local **admin**
can uninstall or disable the product. There is no public API for "admins cannot
bypass" on a personally owned Mac. See [THREAT_MODEL.md](THREAT_MODEL.md).

### Is this as secure as iPhone app lock?

Same *practical* goal - deter casual access on an unlocked device - but FreshLock
is a third-party userland app (Phase 0), not Apple's first-party OS feature. A
determined admin can bypass it. Use FileVault / separate accounts for stronger
guarantees; see [THREAT_MODEL.md](THREAT_MODEL.md).

### Does it need Accessibility permission?

Yes. FreshLock uses Accessibility to observe window creation and geometry so it can
cover a protected app immediately **without** hiding or reactivating it. Hiding
an app while Touch ID is showing cancels Apple's authentication sheet. Grant
Accessibility in System Settings → Privacy & Security → Accessibility (also
prompted during onboarding; Preferences → Advanced shows the current status).

### Why doesn't a locked app disappear when I switch away?

Earlier versions hid locked background apps so Mission Control would not preview
them. That hide raced with LocalAuthentication and broke Touch ID. The lock
pipeline now keeps the app's visibility stable during authentication and relies
on the overlay + Accessibility covering instead. Mission Control may still show
a locked app's own window content — a documented macOS limitation.

### Does it phone home?

No. FreshLock makes no network requests, has no analytics, and no telemetry.

### Can I lock Finder / Terminal / System Settings?

Yes. Any installed app can be added, including system apps.

### Where is my configuration stored?

`~/Library/Application Support/FreshLock/configuration.json`. You can export/import
it from Preferences.

### Does it support Intel Macs?

Yes — `Scripts/build-app.sh` produces a universal binary by default.

### Will there be iCloud sync?

The configuration is a single `Codable` document specifically so sync can be
added cleanly. It's on the [roadmap](ROADMAP.md).
