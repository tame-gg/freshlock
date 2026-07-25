cask "freshlock" do
  version "1.70"
  sha256 "4a15c3d4dd4a65969f041a3c8db614d399aa40b3863d43fd3614a4eada808060"

  url "https://github.com/tame-gg/freshlock/releases/download/v#{version}/FreshLock.zip"
  name "FreshLock"
  desc "Protect any macOS app with Touch ID, Apple Watch, or your Mac password"
  homepage "https://github.com/tame-gg/freshlock"

  depends_on macos: :sequoia

  app "FreshLock.app"

  # Clear Gatekeeper quarantine so macOS does not report the non-notarized app as
  # "damaged" and refuse to open it.
  #
  # Releases are signed with a stable "tame.gg" certificate. macOS binds the
  # Accessibility (TCC) grant to the app's designated requirement, which for a
  # cert-signed build is anchored to that certificate rather than the code hash -
  # so the grant survives updates. Re-signing ad-hoc here would strip that stable
  # signature and revert the requirement to a per-build cdhash pin, dropping the
  # grant on every update. So preserve a valid signature; only fall back to an
  # ad-hoc signature if the shipped bundle does not verify (e.g. an old
  # unsigned build), which at least lets it launch.
  postflight do
    app_path = "#{appdir}/FreshLock.app"
    system_command "/usr/bin/xattr", args: ["-cr", app_path]
    verified = system_command("/usr/bin/codesign",
                              args: ["--verify", "--strict", app_path],
                              must_succeed: false)
    unless verified.success?
      system_command "/usr/bin/codesign",
                     args: ["--force", "--deep", "--sign", "-", app_path],
                     sudo: false
    end
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

    Release builds are signed with a stable "tame.gg" certificate but are not
    Apple-notarized. After install, this cask clears Gatekeeper quarantine so the
    app opens. If macOS still says the app is "damaged", run:

      xattr -cr "#{appdir}/FreshLock.app"

    Because the signing certificate is stable across releases, the Accessibility
    permission you grant is retained across app updates.

    FreshLock is a userland deterrent, not an OS-enforced security boundary. See
    the project's SECURITY.md for the honest threat model.
  EOS
end
