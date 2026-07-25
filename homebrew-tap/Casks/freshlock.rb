cask "freshlock" do
  version "1.67"
  sha256 "c04bee3a6b6de582623c6cdef8d519f1c1a5a1cb8d5be93fb7458869532eed57"

  url "https://github.com/tame-gg/freshlock/releases/download/v#{version}/FreshLock.zip"
  name "FreshLock"
  desc "Protect any macOS app with Touch ID, Apple Watch, or your Mac password"
  homepage "https://github.com/tame-gg/freshlock"

  depends_on macos: :sequoia

  app "FreshLock.app"

  # Unsigned / non–Developer ID builds: clear Gatekeeper quarantine so macOS
  # does not report the app as "damaged" and refuse to open it.
  postflight do
    app_path = "#{appdir}/FreshLock.app"
    system_command "/usr/bin/xattr", args: ["-cr", app_path]
    system_command "/usr/bin/codesign",
                   args: ["--force", "--deep", "--sign", "-", app_path],
                   sudo: false
  end

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

    Release builds may be unsigned (no Apple Developer ID / notarization). After
    install, this cask clears Gatekeeper quarantine and applies an ad-hoc
    signature. If macOS still says the app is "damaged", run:

      xattr -cr "#{appdir}/FreshLock.app"

    FreshLock is a userland deterrent, not an OS-enforced security boundary. See
    the project's SECURITY.md for the honest threat model.
  EOS
end
