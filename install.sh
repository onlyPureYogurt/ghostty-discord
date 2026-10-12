#!/bin/bash
set -euo pipefail
VERSION=v0.1.0
REPO=onlyPureYogurt/ghostty-discord
[[ $(uname -s) == Darwin ]] || { echo 'macOS 13+ is required.'; exit 1; }
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
[[ "$MAJOR" -ge 13 ]] || { echo 'macOS 13+ is required.'; exit 1; }
case $(uname -m) in arm64) ARCH=arm64;; x86_64) ARCH=x86_64;; *) echo 'Unsupported architecture'; exit 1;; esac
TASK_TMP=$(mktemp -d)
trap 'rm -rf "$TASK_TMP"' EXIT
ASSET="ghostty-discord-${VERSION#v}-macos-$ARCH.tar.gz"
BASE="https://github.com/$REPO/releases/download/$VERSION"
curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 "$BASE/$ASSET" -o "$TASK_TMP/$ASSET"
curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 "$BASE/SHA256SUMS" -o "$TASK_TMP/SHA256SUMS"
EXPECTED=$(awk -v asset="$ASSET" '$2 == asset {print $1}' "$TASK_TMP/SHA256SUMS")
[[ "$EXPECTED" =~ ^[0-9a-f]{64}$ ]] || { echo 'Missing or invalid release checksum'; exit 1; }
ACTUAL=$(shasum -a 256 "$TASK_TMP/$ASSET" | awk '{print $1}')
[[ "$EXPECTED" == "$ACTUAL" ]] || { echo 'Checksum mismatch; installation aborted'; exit 1; }
tar -xzf "$TASK_TMP/$ASSET" -C "$TASK_TMP"
bash "$TASK_TMP/ghostty-discord/install-local.sh" "$@"
