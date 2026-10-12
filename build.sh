#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p dist .build/cache
for ARCH in arm64 x86_64; do
    STAGE=".build/$ARCH/ghostty-discord"
    mkdir -p "$STAGE"
    swiftc -O -module-cache-path .build/cache -target "$ARCH-apple-macosx13.0" main.swift -o "$STAGE/ghostty-discord"
    codesign --force --sign - "$STAGE/ghostty-discord"
    cp ghostty-discord.plugin.zsh README.md LICENSE "$STAGE/"
    cp install-local.sh "$STAGE/install-local.sh"
    tar -czf "dist/ghostty-discord-0.1.0-macos-$ARCH.tar.gz" -C ".build/$ARCH" ghostty-discord
done
(cd dist && shasum -a 256 ghostty-discord-*.tar.gz > SHA256SUMS)
cp install.sh dist/install.sh
