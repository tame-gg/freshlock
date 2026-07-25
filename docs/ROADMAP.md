# Roadmap

This is a living document; priorities may shift with community feedback.

## v0.1 — Foundations (current)

- [x] Testable core (models, services, unlock state machine)
- [x] Menu-bar app, catalogue, search, favourites, categories
- [x] Launch detection + overlay + native authentication
- [x] Auto-relock policies
- [x] Preferences, import/export, launch-at-login
- [x] Docs, CI, Homebrew cask

## v0.2 — Polish

- [x] Dedicated background helper (`SMAppService` agent) so protection survives
      the GUI quitting
- [x] Per-app relock policy editor UI
- [x] Global keyboard shortcuts (Lock All / Unlock)
- [x] Onboarding flow with permission priming
- [x] Localised strings (en, es, fr)

## v0.3 — Sync & backup

- [ ] iCloud sync of `Configuration`
- [ ] Scheduled configuration backups
- [ ] Configuration diff / merge on conflict

## Later

- [ ] Menu-bar quick-lock for the frontmost app
- [ ] Optional per-app grace-window customisation
- [ ] Accessibility audit pass + VoiceOver rotor support

Have an idea? Open a [discussion](https://github.com/tame-gg/applock/discussions).
