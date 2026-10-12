# Ghostty Discord

Discord Rich Presence for Ghostty on macOS. A native Swift executable plus a zsh plugin. No Python, Node.js, Discord account token, or administrator access required. Community integration, unaffiliated with Ghostty or Discord.

**Requires:** macOS 13+, zsh, Ghostty, and the Discord desktop app under the same user.

## Install

### Release installer

```sh
curl -fsSL https://github.com/onlyPureYogurt/ghostty-discord/releases/download/v0.1.0/install.sh -o /tmp/ghostty-discord-install.sh
bash /tmp/ghostty-discord-install.sh
```

The installer selects Apple Silicon or Intel, downloads the pinned release, verifies its SHA-256 checksum, and installs the integration. You can inspect the downloaded script before running it. Alternatively download the matching release archive, extract it, and run `bash ghostty-discord/install-local.sh`.

### Homebrew

```sh
brew tap onlyPureYogurt/ghostty-discord https://github.com/onlyPureYogurt/ghostty-discord
brew install onlyPureYogurt/ghostty-discord/ghostty-discord
"$(brew --prefix)/bin/ghostty-discord" setup
```

Homebrew installs the executable and plugin; `setup` explicitly enables the shell hook and per-user background service.

Open a new Ghostty tab after setup. Enable activity sharing in Discord's activity privacy settings. The card title comes from Discord Application ID `1559258860634771566`; its owner manages the application name and artwork. Override it with `ghostty-discord configure YOUR_APPLICATION_ID`.

## Use

```sh
ghostty-discord status
ghostty-discord pause
ghostty-discord resume
ghostty-discord configure 1559258860634771566 --image-key ghostty
ghostty-discord uninstall
```

The image command requires an asset named `ghostty` uploaded to the application's Rich Presence assets. No icon is requested by default.

Homebrew users should run `ghostty-discord uninstall` before `brew uninstall ghostty-discord`. Keep zsh configuration backups if you want to restore earlier settings.

## What is shared

- Project: nearest ancestor containing `.git`, otherwise current directory's final component. Supports ordinary repositories and Git worktrees without invoking git.
- Command: executable name only; arguments, full paths, filenames, and file contents are not retained or published.
- Editors: Neovim, Vim, Vi, Nano, Emacs, and Helix launched from the shell.
- Idle shell and elapsed daemon time.

Project names are public to people who can view your Discord activity. Local session files contain only project name, executable name, PID, and timestamp. Pause clears the card while hooks still record local session events. There is no server or telemetry; communication is through local Discord IPC.

## Limitations

The latest shell event wins across windows; this does not detect focused windows. Short commands can finish between updates. Editor-internal file switches, GUI editors, commands within an already-running tmux or SSH session, and complex pipelines are not tracked precisely. Wrappers with options may show a generic command label. Closing registered shells clears activity; disconnected Discord is retried every ten seconds. Updates are limited to one every five seconds.

These early release binaries are ad-hoc signed, not Apple notarized. If macOS blocks an archive-downloaded executable, review the source and use Apple's normal Privacy & Security approval flow. Do not disable Gatekeeper globally.

## Installed files

Manual install: `~/.local/bin/ghostty-discord`.

Both methods: `~/Library/Application Support/ghostty-discord`, `~/Library/LaunchAgents/local.ghostty-discord.plist`, and a marked block in `${ZDOTDIR:-$HOME}/.zshrc`. Setup makes a backup before changing an existing zsh configuration. Homebrew setup stores the stable Homebrew executable path so upgrades don't point the service to an old versioned directory.

`ghostty-discord status` reports whether Discord acknowledged activity. `stale: true` means the daemon has not reported for over 45 seconds. Unexpected daemon errors go to `~/Library/Application Support/ghostty-discord/daemon.log`.

## Build and test

Only developers need Xcode Command Line Tools and Python 3 for the IPC test server:

```sh
bash build.sh
python3 test_native.py .build/arm64/ghostty-discord/ghostty-discord
```

Release assets include both architectures and `SHA256SUMS`. Intel binaries are cross-compiled on Apple Silicon; execution tests on Intel remain necessary. Live Discord UI validation also remains necessary.
