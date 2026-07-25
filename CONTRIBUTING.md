# Contributing to FreshLock

Thanks for your interest in improving FreshLock! 🎉

## Getting started

1. Fork and clone the repo.
2. Ensure you have **Xcode 17+** (macOS 15 SDK) and Swift 6.
3. Build and test:
   ```bash
   swift build
   swift test
   ```
4. Package a runnable app:
   ```bash
   Scripts/build-app.sh && open dist/FreshLock.app
   ```

## Development workflow

- Create a feature branch: `git checkout -b feat/my-feature`.
- Keep the project **compiling and green at every commit**.
- Add or update tests in `Tests/FreshLockCoreTests` for any core-logic change.
- Run the linters before pushing:
  ```bash
  swiftlint
  swiftformat --lint .
  ```

## Commit style — Conventional Commits

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(app): add unlock-until-logout menu item
fix(core): correct duration-grant expiry off-by-one
docs: expand troubleshooting for Accessibility
```

Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`, `perf`.

## Code style

- Idiomatic Swift 6, `async/await`, dependency injection — no singletons except
  the single `AppEnvironment.shared` container.
- Keep `FreshLockCore` free of AppKit/SwiftUI.
- Small, focused files. Comment the *why*, not the *what*.
- No new third-party dependencies without discussion.

## Localization

User-facing strings live in `Localization/<lang>.lproj/Localizable.strings`. The
**key is the base English string** (matching SwiftUI's `LocalizedStringKey`), so
adding a new UI string requires no code change beyond using a normal `Text("…")`
/ `Button("…")` literal — just add the key to `en.lproj` and any translations.

Interpolations map to printf placeholders: `Text("Step \(i) of \(n)")` →
key `"Step %lld of %lld"`; a `String` interpolation → `%@`.

The packaging script copies every `*.lproj` into the app (and helper) bundle's
`Contents/Resources`, where the runtime resolves them against the main bundle.
A bare `swift build` run has no bundle resources and shows the English literals.

To add a language:

1. Copy `Localization/en.lproj/Localizable.strings` to `Localization/<code>.lproj/`.
2. Translate the values (leave placeholders intact). Untranslated keys fall back
   to English automatically.
3. Add `<code>` to `CFBundleLocalizations` in `Packaging/Info.plist` and
   `Packaging/Helper-Info.plist`.
4. `plutil -lint Localization/<code>.lproj/Localizable.strings` must pass.

## Pull requests

- Fill in the PR template.
- Link the issue you're addressing.
- CI (build, test, SwiftLint, SwiftFormat) must pass.

By contributing you agree your work is licensed under the project's
[MIT License](LICENSE).
