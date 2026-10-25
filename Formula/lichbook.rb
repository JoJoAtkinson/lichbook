class Lichbook < Formula
  desc "Keep a MacBook awake with the lid closed - only while plugged in and logged in"
  homepage "https://github.com/JoJoAtkinson/lichbook"
  url "https://github.com/JoJoAtkinson/lichbook/archive/refs/tags/v0.4.2.tar.gz"
  sha256 "df270c04de5e2edf3f158cf282b1f0b094be385009e38da8f9cff2b97e46847b"
  license "MIT"

  # The formula ships the CLI and builds the menu bar app (Command Line Tools
  # suffice). The Control Center control (controlcenter/) needs full Xcode, so
  # only its sources ship here, for `lich widget` to build on request.
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
  # Keep it short: it prints on every install and upgrade. And keep every
  # command copy-safe: no inline `# comments` — zsh's interactive default
  # passes them to the command as arguments.
  def caveats
    <<~EOS
      First-time setup, two steps — nothing works until you run them:

        \e[1;33mlich install && lich on\e[0m

      lich install is one-time and asks for your password ONCE: it adds a
      sudoers rule scoped to exactly two pmset commands, plus a per-user
      watcher process, and puts the menu bar app (💀 status + controls),
      built just now on this machine, in /Applications. lich on raises it:
      lid-close no longer sleeps this Mac while it's plugged in and you're
      logged in. Unplugging, logging out, or lich off ALWAYS restores
      normal sleep.

      Everyday use: lich (status), lich on, lich off.
      Update everything later: lich upgrade
      Optional Control Center toggle (needs full Xcode): lich widget
      Claude Code skill: /plugin marketplace add JoJoAtkinson/lichbook
    EOS
  end

  # `help` is the only command that touches no state, no sudo, and no launchd —
  # the only thing safe to run inside brew's test sandbox.
  test do
    assert_match "lich", shell_output("#{bin}/lich help")
  end
end
