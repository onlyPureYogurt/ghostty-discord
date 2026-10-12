class GhosttyDiscord < Formula
  desc "Discord Rich Presence for Ghostty on macOS"
  homepage "https://github.com/onlyPureYogurt/ghostty-discord"
  version "0.1.0"
  license "MIT"

  on_macos do
    depends_on macos: :ventura
    on_arm do
      url "https://github.com/onlyPureYogurt/ghostty-discord/releases/download/v0.1.0/ghostty-discord-0.1.0-macos-arm64.tar.gz"
      sha256 "572ab49fa72104a8ae6b8f97f26ebf8bfcc6f2d8f7141efa058b8aec04b8255e"
    end
    on_intel do
      url "https://github.com/onlyPureYogurt/ghostty-discord/releases/download/v0.1.0/ghostty-discord-0.1.0-macos-x86_64.tar.gz"
      sha256 "7ecd93a1b6ae39cb2a1b6a27bc6c6a3e40c22ab98271200dce1ab3e2a2e003c3"
    end
  end

  depends_on :macos

  def install
    bin.install "ghostty-discord"
    (share/"ghostty-discord").install "ghostty-discord.plugin.zsh"
  end

  def caveats
    <<~EOS
      Enable the shell integration and per-user background service:
        #{HOMEBREW_PREFIX}/bin/ghostty-discord setup
      Then open a new Ghostty tab. Discord desktop must be running.
      Before brew uninstall, run: ghostty-discord uninstall
    EOS
  end

  test do
    assert_match "0.1.0", shell_output("#{bin}/ghostty-discord --version")
  end
end
