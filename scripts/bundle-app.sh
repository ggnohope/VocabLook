#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"
APP="VocabLook.app"
BIN=".build/${CONFIG}/VocabLook"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/VocabLook"
# Ad-hoc sign so TCC has an identity to track.
codesign --force --deep --sign - "$APP"
echo "Bundled $APP ($CONFIG)"
