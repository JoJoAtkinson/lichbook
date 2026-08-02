class Lichbook < Formula
  desc "Keep a MacBook awake with the lid closed - only while plugged in and logged in"
  homepage "https://github.com/JoJoAtkinson/lichbook"
  url "https://github.com/JoJoAtkinson/lichbook/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "a8d9b73281958d1c4ba0c3bde61aba02b6c44c20f629c42707bbd1cd2de6bf57"
  license "MIT"

  def install
    bin.install "lich"
  end

  def caveats
    <<~EOS
      First-time setup, two steps:

        1. lich install    # one-time; asks for sudo ONCE to add a sudoers rule
                           # scoped to exactly two pmset commands, plus a
                           # per-user watcher agent
        2. lich on         # 💀 risen: from now on, closing the lid does NOT
                           # sleep the Mac while it's plugged in and you're
                           # logged in

      Everyday use:
        lich               # status: risen or at rest, power, watcher health
        lich off           # ⚰️ back to normal sleep
      Unplugging or logging out ALWAYS restores normal sleep on its own.

      After `brew upgrade lichbook`, run:  lich reload

      Optional menu bar skull + Control Center toggle build from source:
        https://github.com/JoJoAtkinson/lichbook
    EOS
  end

  test do
    assert_match "lich", shell_output("#{bin}/lich help")
  end
end
