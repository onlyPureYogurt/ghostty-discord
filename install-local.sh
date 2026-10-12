#!/bin/bash
set -euo pipefail
SOURCE=$(cd "$(dirname "$0")" && pwd)
TARGET="$HOME/Library/Application Support/ghostty-discord"
BIN="$HOME/.local/bin/ghostty-discord"
mkdir -p "$TARGET" "$(dirname "$BIN")"
chmod 700 "$TARGET"
# Move the executable atomically so a running daemon isn't overwritten in place.
cp "$SOURCE/ghostty-discord" "$BIN.new"
chmod 755 "$BIN.new"
mv -f "$BIN.new" "$BIN"
cp "$SOURCE/ghostty-discord.plugin.zsh" "$TARGET/ghostty-discord.plugin.zsh"
"$BIN" setup --client-id "${1:-1559258860634771566}"
