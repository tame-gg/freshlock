# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres
to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- **Lock pipeline redesign.** Protected apps are secured with Accessibility-driven
  overlays and LocalAuthentication only. FreshLock no longer hides, minimizes, or
  reactivates apps *during* authentication — that previously cancelled Touch ID
  (`LAError.systemCancel`) because `LocalAuthentication.UIAgent` becoming
  frontmost made the protected app look "backgrounded" and eligible for hide.
- Accessibility permission is required again (onboarding + Preferences → Advanced).
- Launch no longer waits for the protected app to become frontmost (fixes the
  "click the Dock icon first" failure). Overlay is pinned through the
  launch→window→auth handoff.
- FreshLock no longer activates itself before Touch ID. Activating an accessory
  host was hiding the protected app; the sequence is now reveal app → show lock
  overlay → LocalAuthentication UIAgent sheet.

### Fixed
- Changing the overlay style (or any preference) no longer turns off unrelated
  settings such as "Launch at Login". `SettingsViewModel` kept a separate working
  copy that round-tripped through the store and read it back inside
  `objectWillChange` (which fires *before* the new value lands), reading a stale
  value and clobbering other fields. Each control now binds directly to a single
  store field, and launch-at-login reflects the real login-item state.
- Touch ID prompts interrupted by hide/activate churn; `systemCancel` no longer
  counts toward terminate-after-N.
- Helper bundle ID included in lock-flow frontmost allowlists so helper-hosted
  authentication keeps the overlay stable.
- Cancelling auth because the user switched away no longer force-quits the
  protected app.

### Added
- `AccessibilityService`: AXObserver window create/move/resize watching and AX
  frame queries, with CGWindowList fallback when untrusted.
- Testable `FreshLockCore` library: models, discovery, authentication, settings
  persistence and the pure `UnlockStateStore`.
- Menu-bar app with `NavigationSplitView` catalogue, search, favourites and
  categories.
- Locking engine: `NSWorkspace`-driven launch detection, full-screen blur
  overlay, native LocalAuthentication, and configurable auto-relock.
- Shared `FreshLockEngine` library and a dedicated background helper
  (`FreshLockHelper`) registered via `SMAppService`, so protection runs
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

[Unreleased]: https://github.com/tame-gg/freshlock/commits/main
