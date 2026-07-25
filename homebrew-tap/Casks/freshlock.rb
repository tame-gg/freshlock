cask "freshlock" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/tame-gg/freshlock/releases/download/v#{version}/FreshLock.zip"
  name "FreshLock"
  desc "Protect any macOS app with Touch ID, Apple Watch, or your Mac password"
  homepage "https://github.com/tame-gg/freshlock"

  depends_on macos: ">= :sequoia"

  app "FreshLock.app"

  # FreshLock stores its configuration under Application Support and registers a
  # login item; clean both up on uninstall.
  uninstall login_item: "FreshLock",
            quit:       "gg.tame.freshlock"

  zap trash: [
    "~/Library/Application Support/FreshLock",
    "~/Library/Preferences/gg.tame.freshlock.plist",
  ]

  caveats <<~EOS
    FreshLock needs Accessibility permission to place its lock overlay above other
    apps. Grant it in System Settings → Privacy & Security → Accessibility.

    FreshLock is a userland deterrent, not an OS-enforced security boundary. See
    the project's SECURITY.md for the honest threat model.
  EOS
end
