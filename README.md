<div align="center">

# 🔒 AppLock

**Protect any macOS app behind Touch ID, Apple Watch, or your Mac password.**

iOS and iPadOS let you lock individual apps behind Face ID / Touch ID. macOS has
no native equivalent. **AppLock** is the closest, honest implementation built
entirely on **public Apple APIs** — no private frameworks, no kernel extensions,
no Electron.

[![CI](https://github.com/tame-gg/applock/actions/workflows/ci.yml/badge.svg)](https://github.com/tame-gg/applock/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-orange?logo=swift)

</div>

---

## Features

- 🔐 **Native authentication** — Apple's own LocalAuthentication sheet (Touch ID,
  Apple Watch, or macOS password). AppLock never draws a password field and never
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
- 🔍 **Searchable catalogue** with favourites and categories.
- 📤 **Import / export / backup** your configuration as JSON (iCloud-sync ready).
- ♿ **Accessible** — VoiceOver labels, keyboard navigation, reduced motion.
- 🪶 **Featherweight** — zero polling; everything is notification-driven.

## Installation

### Homebrew (recommended)

```bash
brew tap tame-gg/tap
brew install --cask applock
```

### From source

```bash
git clone https://github.com/tame-gg/applock.git
cd applock
Scripts/build-app.sh
open dist/AppLock.app
```

See [docs/BUILDING.md](docs/BUILDING.md) for details.

## Honest macOS limitations

AppLock is deliberate about what macOS **does and does not allow** a third-party
app to do with public APIs. In short:

> macOS provides **no public API to veto or freeze another app's launch**.
> AppLock reacts to the launch/activation notification as fast as the OS
> delivers it and immediately covers the app with a top-most overlay, then
> requires authentication. This is a strong deterrent, **not** a kernel-level
> guarantee.

The full threat model and every limitation are documented in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [SECURITY.md](SECURITY.md).
We will never pretend a limitation doesn't exist.

## Permissions

On first launch AppLock will ask for:

- **Accessibility** — to position overlays above other apps.
- **Notifications** *(optional)* — to alert you when a protected app launches.

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) and our
[Code of Conduct](CODE_OF_CONDUCT.md). Good first issues are labelled
`good first issue`.

## License

[MIT](LICENSE) © tame.gg
