<div align="center">

# 🔒 FreshLock, a tame.gg project

**Protect any macOS app behind Touch ID, Apple Watch, or your Mac password.**
**MacOS App Locker | App Authenticator**

iOS and iPadOS let you lock individual apps behind Face ID / Touch ID. macOS has
no native equivalent. **FreshLock** is the closest, honest implementation built
entirely on **public Apple APIs** — no private frameworks, no kernel extensions,
no Electron.

[![CI](https://github.com/tame-gg/freshlock/actions/workflows/ci.yml/badge.svg)](https://github.com/tame-gg/freshlock/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-orange?logo=swift)

</div>

---

## Features

- 🔐 **Native authentication** — Apple's own LocalAuthentication sheet (Touch ID,
  Apple Watch, or macOS password). FreshLock never draws a password field and never
  sees your password.
- 🖥️ **Lock any app** — Finder, Terminal, Safari, System Settings, or anything in
  `/Applications`.
- 🎨 **Beautiful overlay** — blurred, material-based lock screen with light/dark
  support and reduced-motion friendliness.
- ⏱️ **Flexible auto-relock** — every launch, after N minutes, on sleep, on screen
  lock, on inactivity, on switching away, or manual only.
- 🧭 **Menu-bar first** — Lock All, Unlock Until Sleep, preferences, and more from
  the menu bar. No Dock clutter (`LSUIElement`).
- 🚀 **Launch at login** via `SMAppService`.
- 🔍 **Searchable catalogue** with favorites and categories.
- 📤 **Import / export / backup** your configuration as JSON (iCloud-sync ready).
- ♿ **Accessible** — VoiceOver labels, keyboard navigation, reduced motion.
- 🌍 **Localized** — English, Spanish and French (easy to add more).
- 🪶 **Featherweight** — Accessibility-driven window covering; no hide/activate
  churn during Touch ID.

## Installation

### Homebrew (recommended)

```bash
brew tap tame-gg/tap
brew install --cask freshlock
```

### From source

```bash
git clone https://github.com/tame-gg/freshlock.git
cd freshlock
Scripts/build-app.sh
open dist/FreshLock.app
```

See [docs/BUILDING.md](docs/BUILDING.md) for details.

## Honest macOS limitations

FreshLock is deliberate about what macOS **does and does not allow**. In short:

> **Today:** FreshLock is a **userland deterrent** (overlay + Touch ID after
> launch). That is **not** kernel enforcement.
>
> **Ceiling:** Endpoint Security can deny launches before exec (`AUTH_EXEC`) with
> Apple's managed entitlement and a system extension. Even then, a local
> **admin can still uninstall or disable** the product. "Admins cannot bypass"
> is **not** achievable for a third-party app on a personally owned Mac.

Full write-up: [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md),
[docs/ENFORCEMENT.md](docs/ENFORCEMENT.md), [SECURITY.md](SECURITY.md).
We will never pretend a limitation doesn't exist.

## Permissions

On first launch FreshLock will ask for:

- **Accessibility** *(required)* — to detect protected windows and cover them
  without hiding or reactivating apps (which would interrupt Touch ID).
- **Notifications** *(optional)* — to alert you when a protected app launches.

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) and our
[Code of Conduct](CODE_OF_CONDUCT.md). Good first issues are labelled
`good first issue`.

## License

[MIT](LICENSE) © tame.gg
