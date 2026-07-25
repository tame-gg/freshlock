# Security Policy

## Reporting a vulnerability

Please **do not** open public issues for security vulnerabilities. Email
**security@tame.gg** with details and steps to reproduce. We aim to acknowledge
within 72 hours and to ship a fix or mitigation as quickly as is responsible.

## Security design principles

- **AppLock never stores or sees your password.** All authentication is
  delegated to Apple's `LocalAuthentication` framework, which presents its own
  system UI and returns only a success/failure result.
- **No custom password dialogs, ever.** We only use the native system sheet.
- **Keychain is used only if strictly necessary.** The current release stores no
  secrets; configuration contains no credentials.
- **Local-only by default.** No telemetry, no network calls, no analytics.

## Honest limitations (please read)

AppLock is a **userland deterrent**, not an OS-enforced security boundary:

- macOS provides **no public API to prevent or veto an app launch**. AppLock
  reacts to the post-launch notification and overlays the app; it cannot
  guarantee zero frames were rendered first.
- A local user with administrator privileges can bypass any third-party
  app-locker (force-quitting AppLock, booting to recovery, etc.).
- AppLock protects against **casual, opportunistic access** to an unlocked,
  logged-in Mac — comparable to iOS's app-lock feature — and nothing stronger.

If you need OS-enforced protection, use FileVault, separate macOS user accounts,
or a per-app password where the app itself supports one. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full threat model.

## Supported versions

The latest released minor version receives security fixes.
