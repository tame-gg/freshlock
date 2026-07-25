# Frequently Asked Questions

### Does AppLock see or store my password?

No. AppLock uses Apple's `LocalAuthentication` framework, which shows its own
system authentication sheet. AppLock only receives a success/failure result — it
never sees, handles, or stores your password.

### Can AppLock stop an app from *launching*?

No — and no third-party app can, using public APIs. macOS has no pre-launch veto.
AppLock detects the launch the instant macOS notifies it, immediately covers the
app with a top-most overlay, and requires authentication. See
[ARCHITECTURE.md](ARCHITECTURE.md) for the honest details.

### Is this as secure as iPhone app lock?

It's the same *practical* protection — a deterrent against someone casually
opening an app on your unlocked Mac — but it is a userland app, not an OS
feature. A determined admin user can bypass it. Use FileVault / separate accounts
for stronger guarantees.

### Why does it need Accessibility permission?

To position the lock overlay above other applications' windows. Without it, the
overlay may not reliably stay on top.

### Does it phone home?

No. AppLock makes no network requests, has no analytics, and no telemetry.

### Can I lock Finder / Terminal / System Settings?

Yes. Any installed app can be added, including system apps.

### Where is my configuration stored?

`~/Library/Application Support/AppLock/configuration.json`. You can export/import
it from Preferences.

### Does it support Intel Macs?

Yes — `Scripts/build-app.sh` produces a universal binary by default.

### Will there be iCloud sync?

The configuration is a single `Codable` document specifically so sync can be
added cleanly. It's on the [roadmap](ROADMAP.md).
