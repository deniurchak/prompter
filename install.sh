#!/bin/bash
# Downloads the latest Prompter release and installs it into /Applications.
set -euo pipefail

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Prompter…"
curl -fsSL https://github.com/deniurchak/prompter/releases/latest/download/Prompter.zip -o "$TMP/Prompter.zip"
ditto -x -k "$TMP/Prompter.zip" "$TMP"

pkill -x Prompter 2>/dev/null || true
rm -rf /Applications/Prompter.app
ditto "$TMP/Prompter.app" /Applications/Prompter.app

echo "Installed /Applications/Prompter.app"
open /Applications/Prompter.app
