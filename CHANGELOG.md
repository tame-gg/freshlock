# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres
to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
