# tame-gg/homebrew-tap

Homebrew tap for [FreshLock](https://github.com/tame-gg/freshlock).

> **Note**: this directory is the *source* for the companion repository
> `tame-gg/homebrew-tap`. In production it lives in its own repo so that
> `brew tap tame-gg/tap` works. It is mirrored here for convenience and so the
> release automation can update the cask.

## Install

```bash
brew tap tame-gg/tap
brew install --cask freshlock
```

## Upgrade

```bash
brew upgrade --cask freshlock
```

## How releases update the cask

`Scripts/update-cask.sh` (run by the release workflow) rewrites `version` and
`sha256` in `Casks/freshlock.rb` for each tagged release and pushes to the tap
repository. See [../docs/RELEASING.md](../docs/RELEASING.md).
