# Frequently Asked Questions

### Does FreshLock see or store my password?

No. FreshLock uses Apple's `LocalAuthentication` framework, which shows its own
system authentication sheet. FreshLock only receives a success/failure result — it
never sees, handles, or stores your password.

### Can FreshLock stop an app from *launching*?

No — and no third-party app can, using public APIs. macOS has no pre-launch veto.
FreshLock detects the launch the instant macOS notifies it, immediately covers the
app with a top-most overlay, and requires authentication. See
[ARCHITECTURE.md](ARCHITECTURE.md) for the honest details.

### Is this as secure as iPhone app lock?

It's the same *practical* protection — a deterrent against someone casually
opening an app on your unlocked Mac — but it is a userland app, not an OS
feature. A determined admin user can bypass it. Use FileVault / separate accounts
for stronger guarantees.

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
