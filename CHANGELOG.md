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
- Preferences window (General, Locking, Advanced) with import/export.
- Launch-at-login via `SMAppService`.
- Documentation suite, CI, SwiftLint/SwiftFormat, and Homebrew cask.

[Unreleased]: https://github.com/tame-gg/applock/commits/main
