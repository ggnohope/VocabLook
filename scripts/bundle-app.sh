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
# Sign with a stable identity so the TCC (Accessibility / Input Monitoring) grant survives rebuilds.
# Falls back to ad-hoc if the "VocabLook Dev" self-signed identity is not installed.
SIGN_ID="VocabLook Dev"
if security find-certificate -c "$SIGN_ID" >/dev/null 2>&1; then
    codesign --force --deep --sign "$SIGN_ID" "$APP"
    echo "Bundled $APP ($CONFIG), signed with '$SIGN_ID'"
else
    codesign --force --deep --sign - "$APP"
    echo "Bundled $APP ($CONFIG), ad-hoc signed ('$SIGN_ID' not found — TCC grants won't persist across rebuilds)"
fi
