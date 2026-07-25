# Security Policy

## Reporting a vulnerability

Please **do not** open public issues for security vulnerabilities. Email
**security@tame.gg** with details and steps to reproduce. We aim to acknowledge
within 72 hours and to ship a fix or mitigation as quickly as is responsible.

## Security design principles

- **FreshLock never stores or sees your password.** All authentication is
  delegated to Apple's `LocalAuthentication` framework, which presents its own
  system UI and returns only a success/failure result.
- **No custom password dialogs, ever.** We only use the native system sheet.
- **Keychain is used only if strictly necessary.** The current release stores no
  secrets; configuration contains no credentials.
- **Local-only by default.** No telemetry, no network calls, no analytics.
- **No private APIs / no malware techniques.** Any future stronger enforcement
  uses Apple's public Endpoint Security APIs only (defensive AUTH allow/deny).

## Honest limitations (please read)

FreshLock **today** is a **userland deterrent** (Phase 0), not an OS ownership
boundary:

- Shipping builds react to post-launch `NSWorkspace` notifications and overlay
  the app. They do **not** claim kernel enforcement.
- A local **administrator** can bypass any third-party app locker (force-quit /
  uninstall, revoke TCC permissions, Recovery Mode, disable SIP, etc.).
- There is **no** public-API path for "admins cannot bypass" on a personally
  owned Mac. That requires org-owned supervised MDM / ADE, not a consumer app.
- Endpoint Security `AUTH_EXEC` *can* provide kernel-held launch denial for
  entitled system extensions (Phase 1 scaffolding in-tree). Even then, an admin
  can uninstall or disable the product. See
  [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) and
  [docs/ENFORCEMENT.md](docs/ENFORCEMENT.md).

FreshLock protects against **casual, opportunistic access** to an unlocked,
logged-in Mac — comparable in *intent* to iOS app-lock features, not in
OS-enforcement strength.

If you need stronger separation: FileVault, separate macOS user accounts, or
(for fleets) supervised MDM. Architecture notes:
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Supported versions

The latest released minor version receives security fixes.
