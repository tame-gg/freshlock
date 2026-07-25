# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres
to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- Locked, backgrounded protected apps are now **hidden** so their contents no
  longer appear in Mission Control, the Spaces switcher, App Exposé or Stage
  Manager. macOS has no public API to exclude another app's window from those
  previews, so hiding is the strongest available mitigation.
- Removed the **Accessibility** permission requirement entirely — AppLock only
  uses public APIs that don't need it. This also fixes false "not granted"
  reports (the grant is tied to a binary's code signature and doesn't survive
  ad-hoc rebuilds).
- Removed the **Minimal** overlay style; only the polished Blurred/Solid styles
  remain. Old configurations referencing it fall back to Blurred.

### Added
- Initial AppLock implementation.
- Testable `AppLockCore` library: models, discovery, authentication, settings
  persistence and the pure `UnlockStateStore`.
- Menu-bar app with `NavigationSplitView` catalogue, search, favourites and
  categories.
- Locking engine: `NSWorkspace`-driven launch detection, full-screen blur
  overlay, native LocalAuthentication, and configurable auto-relock.
- Shared `AppLockEngine` library and a dedicated background helper
  (`AppLockHelper`) registered via `SMAppService`, so protection runs
  independently of the settings GUI.
- Preferences window (General, Locking, Backup, Advanced).
- Shared `ConfigurationStore` as the single source of truth, fixing settings/
  protection-list save races.
- Per-app inspector: protection, favourite, category, per-app relock-policy
  override (with minutes), and terminate-after-failures.
- Configuration import/export as JSON via native save/open panels.
- Global keyboard shortcuts (Lock All / Unlock All) via Carbon hot keys, owned by
  the engine process, with a shortcut-recorder UI and live re-registration when
  edited (a `DispatchSource` config-file watcher, no polling).
- First-launch onboarding guide with Accessibility permission priming (live
  status), launch-at-login, honest limitation framing, and a "Replay Setup
  Guide" action in Preferences.
- Localization pipeline (`.lproj/Localizable.strings` copied into the app and
  helper bundles) with English, Spanish and French translations of the UI.
- Launch-at-login via `SMAppService`.
- Documentation suite, CI, SwiftLint/SwiftFormat, and Homebrew cask.

[Unreleased]: https://github.com/tame-gg/applock/commits/main
