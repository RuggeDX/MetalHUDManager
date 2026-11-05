#!/bin/bash
# Packages "build/Metal HUD Manager.app" into a drag-to-install disk image
# containing the app and a shortcut to /Applications.
#
# Usage:
#   scripts/build-app.sh && scripts/make-dmg.sh            -> build/MetalHUDManager.dmg
#   scripts/make-dmg.sh path/to/output.dmg           -> custom output path

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Metal HUD Manager"
APP="build/$APP_NAME.app"
OUT="${1:-build/MetalHUDManager.dmg}"

[[ -d "$APP" ]] || { echo "$APP not found. Run scripts/build-app.sh first."; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Staging"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating disk image"
rm -f "$OUT"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT" >/dev/null

echo "Done: $OUT"
