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
      One-time privileged setup (scoped sudoers rule + LaunchAgent watcher):
        lich install
      Then raise it with:
        lich on
      After upgrading lichbook, restart the watcher onto the new code:
        lich reload
      The optional menu bar and Control Center toggles build from source:
        https://github.com/JoJoAtkinson/lichbook
    EOS
  end

  test do
    assert_match "lich", shell_output("#{bin}/lich help")
  end
end
