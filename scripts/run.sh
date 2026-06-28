#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"
swift build $([ "$CONFIG" = "release" ] && echo "-c release")
./scripts/bundle-app.sh "$CONFIG"
# Quit any running instance, then launch fresh.
pkill -x VocabLook 2>/dev/null || true
open VocabLook.app
echo "Launched VocabLook.app"
