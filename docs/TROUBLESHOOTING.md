# Troubleshooting

### The overlay doesn't appear / doesn't stay on top

- Grant **Accessibility** permission: System Settings → Privacy & Security →
  Accessibility → enable AppLock. Preferences → Advanced shows the current status.
- Some full-screen apps and secure input contexts may briefly render before the
  overlay. This is a documented macOS limitation ([ARCHITECTURE.md](ARCHITECTURE.md)).

### "AppLock is damaged / can't be opened" (Gatekeeper)

Unsigned builds trigger Gatekeeper. Either install the signed Homebrew cask, or
for a self-built app run:

```bash
xattr -dr com.apple.quarantine dist/AppLock.app
```

### Touch ID prompt never appears

- Ensure Touch ID is enrolled (System Settings → Touch ID & Password).
- On Macs without Touch ID, AppLock falls back to Apple Watch or your password —
  the sheet still appears.
- If biometrics are locked out after too many failures, use the password
  fallback in the system sheet.

### Launch at Login won't enable

`SMAppService` requires the app to live in `/Applications`. Move `AppLock.app`
there, then toggle Launch at Login again.

### A protected app opened without prompting

- Confirm protection is enabled for it in the main window.
- If its relock policy grants a lasting unlock (e.g. "After 10 minutes"), it may
  still be within the unlocked window. Use **Lock All** from the menu bar to
  relock immediately.

### High CPU usage

AppLock is notification-driven and should idle near 0% CPU. If you see sustained
usage, enable **Developer Mode** (Preferences → Advanced) and check the unified
log:

```bash
log stream --predicate 'subsystem == "gg.tame.applock"' --level debug
```

Then open an issue with the relevant excerpt.
