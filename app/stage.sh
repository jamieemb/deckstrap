#!/usr/bin/env bash
# Copy the deckstrap tool into app/build-tool so electron-builder can bundle it
# as resources/deckstrap inside the AppImage.
set -euo pipefail
APP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$APP/.." && pwd)"
rm -rf "$APP/build-tool"
mkdir -p "$APP/build-tool"
cp "$REPO/deckstrap" "$REPO/profile.example.json" "$APP/build-tool/"
cp -r "$REPO/lib" "$REPO/modules" "$REPO/ui" "$APP/build-tool/"
chmod +x "$APP/build-tool/deckstrap"
find "$APP/build-tool" -name '__pycache__' -type d -prune -exec rm -rf {} +
echo "staged $(find "$APP/build-tool" -type f | wc -l) files into app/build-tool"
