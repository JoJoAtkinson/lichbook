class Lichbook < Formula
  desc "Keep a MacBook awake with the lid closed - only while plugged in and logged in"
  homepage "https://github.com/JoJoAtkinson/lichbook"
  url "https://github.com/JoJoAtkinson/lichbook/archive/refs/tags/v0.3.3.tar.gz"
  sha256 "b956709d8e6debf2cd069d25574e754423fa700ddbb6a8cd7a41c69a48ea266c"
  license "MIT"

  # The formula ships the CLI and nothing else. The menu bar app (menubar/) and
  # the Control Center control (controlcenter/) are Swift app bundles that need
  # a full Xcode toolchain, code signing, and — for the login item and the
  # widget registration — to be launched by the user from /Applications. None of
  # that survives a `brew install`, so they stay build-from-source. See the repo.
  def install
    bin.install "lich"
    # Build the menu bar app HERE, on the user's machine — an ad-hoc signature
    # is only trusted where it was made, so a prebuilt download would be
    # refused by Gatekeeper, while this one is born trusted. Needs only the
    # Command Line Tools brew already requires; if swiftc is somehow absent,
    # skip — the CLI must install regardless (fail-open, per support policy).
    # `lich install` finds the app in this prefix and copies it to
    # /Applications (stable path — the app registers a login item).
    if quiet_system("/usr/bin/xcrun", "--find", "swiftc")
      system "make", "-C", "menubar"
      prefix.install "menubar/Lich.app"
    else
      opoo "swiftc not found — skipping the menu bar app build (CLI unaffected)"
    end
    # Keep the Control Center widget's sources (a few KB) so `lich widget`
    # can build it later for users who have full Xcode. Never built here —
    # appex targets need Xcode proper, which a formula must not require.
    prefix.install "controlcenter"
  end

  # Why caveats instead of doing the setup here: a formula's install runs
  # unprivileged and non-interactively. lich needs a root-owned sudoers rule
  # (one password prompt) and a per-user LaunchAgent bootstrapped into a live
  # GUI session — neither is something brew can or should do on the user's
  # behalf. So `lich install` asks for consent once, and this text points at it.
  # Keep it short: it prints on every install and upgrade.
  def caveats
    <<~EOS
      First-time setup, two steps — nothing works until you run them:

        1. \e[1;33mlich install\e[0m    # one-time; ONE sudo prompt. Adds a sudoers rule
                           # scoped to exactly two pmset commands, plus a
                           # per-user watcher process.
        2. \e[1;33mlich on\e[0m         # 💀 risen: lid-close no longer sleeps this Mac
                           # while it's plugged in and you're logged in

      Everyday use:
        lich               # status: risen/at rest, power, sleep, watcher health
        lich off           # ⚰️ back to normal sleep

      Unplugging, logging out, or `lich off` ALWAYS restores normal sleep.

      lich install also puts the menu bar app (💀 status + controls) in
      /Applications, built just now on this machine.

      Optional Control Center toggle (needs full Xcode):  lich widget
      To update everything later, one word:  lich upgrade

      Optional menu bar skull + Control Center toggle build from source:
        https://github.com/JoJoAtkinson/lichbook
    EOS
  end

  # `help` is the only command that touches no state, no sudo, and no launchd —
  # the only thing safe to run inside brew's test sandbox.
  test do
    assert_match "lich", shell_output("#{bin}/lich help")
  end
end
