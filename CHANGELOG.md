# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres
to [Semantic Versioning](https://semver.org/).

## [1.70]

### Fixed
- **First-run setup no longer vanishes when you open System Settings.** The
  onboarding window was created with `hidesOnDeactivate`, so activating System
  Settings to grant Accessibility ordered the setup window off screen and the
  guide appeared to close. The window now stays put across app deactivation, and
  when you return with permission granted the Accessibility step advances
  automatically.

### Changed
- **Accessibility permission is now retained across updates.** Releases are
  signed with a stable "tame.gg" certificate instead of an ad-hoc signature.
  macOS pins a TCC grant to the app's designated requirement; a cert-signed build
  anchors that requirement to the certificate rather than the code hash, so the
  grant is no longer dropped every time the app is updated. (Not Apple-notarized;
  the cask still clears Gatekeeper quarantine on install.)

## [1.69]

### Fixed
- **The lock overlay no longer floats over unrelated apps.** A cover is a
  `.floating` panel sized to the protected app's windows, and being "pinned"
  used to force it on screen no matter who was frontmost - so a locked Discord
  left a Discord-shaped blur sitting on top of whatever you switched to. Pinning
  now only decides what to do when there is no frontmost app to consult; a cover
  is raised when the protected app owns the screen, or when FreshLock's own
  Touch ID sheet is up for it, and is ordered out otherwise. Covers also no
  longer join every Space.
- Covers appear and disappear with the app switch itself. `OverlayService` now
  watches `didActivateApplicationNotification` instead of waiting up to a second
  for its backstop timer.
- **Touch ID prompt storms.** Any outcome that was neither success nor an
  explicit user cancel left the app frontmost, locked, and covered - exactly the
  condition the 1.5s liveness poll re-secures - so FreshLock raised a new sheet
  every poll and stole focus each time, which is what made the protected app,
  FreshLock, and the sheet itself all unclickable. Automatic prompts now run on
  a budget (`AuthPromptBudget`): at most three per app in a 12s window, after
  which the overlay simply waits for its Unlock button. `systemCancel` is
  handled explicitly rather than falling through to a retry.
- A freshly raised sheet is protected from switch-away teardown for a moment.
  Raising it activates FreshLock, and the protected app often bounces focus once
  in response; that bounce used to cancel the sheet the user was reaching for.
- The login-item helper now stands down for *any* running FreshLock-family GUI,
  not just the exact release bundle id. Two engines enforcing at once cancelled
  each other's prompts in a loop.

### Changed
- Settings adopt the main window's card language: soft tonal icon wells, bold
  section titles, grouped rounded islands, and switches instead of checkboxes.
  Settings pages now carry the same header treatment as the Library pages.
- Overlay style is chosen from preview tiles that render the effect rather than
  from a pop-up menu of the words "Blurred" and "Solid".
- `LockCoordinator` split into `AppVisibilityKeeper`, `AuthPromptBudget`, and
  command/outcome extensions.

## [1.68]

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
- Menu-bar app with `NavigationSplitView` catalogue, search, favorites and
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
