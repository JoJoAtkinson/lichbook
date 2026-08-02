class Lichbook < Formula
  desc "Keep a MacBook awake with the lid closed - only while plugged in and logged in"
  homepage "https://github.com/JoJoAtkinson/lichbook"
  url "https://github.com/JoJoAtkinson/lichbook/archive/refs/tags/v0.1.3.tar.gz"
  sha256 "46b0d5b2110532f6acd3718d38559d16f20832786a3f47f78ed0122cdfdf0f26"
  license "MIT"

  # The formula ships the CLI and nothing else. The menu bar app (menubar/) and
  # the Control Center control (controlcenter/) are Swift app bundles that need
  # a full Xcode toolchain, code signing, and — for the login item and the
  # widget registration — to be launched by the user from /Applications. None of
  # that survives a `brew install`, so they stay build-from-source. See the repo.
  def install
    bin.install "lich"
  end

  # Why caveats instead of doing the setup here: a formula's install runs
  # unprivileged and non-interactively. lich needs a root-owned sudoers rule
  # (one password prompt) and a per-user LaunchAgent bootstrapped into a live
  # GUI session — neither is something brew can or should do on the user's
  # behalf. So `lich install` asks for consent once, and this text points at it.
  # Keep it short: it prints on every install and upgrade.
  def caveats
    <<~EOS
      First-time setup, two steps:

        1. lich install    # one-time; ONE sudo prompt. Adds a sudoers rule
                           # scoped to exactly two pmset commands, plus a
                           # per-user watcher agent.
        2. lich on         # 💀 risen: lid-close no longer sleeps this Mac
                           # while it's plugged in and you're logged in

      Everyday use:
        lich               # status: risen/at rest, power, sleep, watcher health
        lich off           # ⚰️ back to normal sleep

      Unplugging, logging out, or `lich off` ALWAYS restores normal sleep.

      After `brew upgrade lichbook`, run:  lich reload

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
