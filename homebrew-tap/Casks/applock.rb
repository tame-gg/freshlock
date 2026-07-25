cask "applock" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/tame-gg/applock/releases/download/v#{version}/AppLock.zip"
  name "AppLock"
  desc "Protect any macOS app with Touch ID, Apple Watch, or your Mac password"
  homepage "https://github.com/tame-gg/applock"

  depends_on macos: ">= :sequoia"

  app "AppLock.app"

  # AppLock stores its configuration under Application Support and registers a
  # login item; clean both up on uninstall.
  uninstall login_item: "AppLock",
            quit:       "gg.tame.applock"

  zap trash: [
    "~/Library/Application Support/AppLock",
    "~/Library/Preferences/gg.tame.applock.plist",
  ]

  caveats <<~EOS
    AppLock needs Accessibility permission to place its lock overlay above other
    apps. Grant it in System Settings → Privacy & Security → Accessibility.

    AppLock is a userland deterrent, not an OS-enforced security boundary. See
    the project's SECURITY.md for the honest threat model.
  EOS
end
