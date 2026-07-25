# Contributing to AppLock

Thanks for your interest in improving AppLock! 🎉

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
   Scripts/build-app.sh && open dist/AppLock.app
   ```

## Development workflow

- Create a feature branch: `git checkout -b feat/my-feature`.
- Keep the project **compiling and green at every commit**.
- Add or update tests in `Tests/AppLockCoreTests` for any core-logic change.
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
- Keep `AppLockCore` free of AppKit/SwiftUI.
- Small, focused files. Comment the *why*, not the *what*.
- No new third-party dependencies without discussion.

## Pull requests

- Fill in the PR template.
- Link the issue you're addressing.
- CI (build, test, SwiftLint, SwiftFormat) must pass.

By contributing you agree your work is licensed under the project's
[MIT License](LICENSE).
