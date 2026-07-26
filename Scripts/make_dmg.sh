#!/bin/bash
# Create a simple drag-to-Applications DMG for FolderLint.
# Prefers create-dmg when installed; otherwise uses hdiutil.
#
# Usage: Scripts/make_dmg.sh path/to/FolderLint.app path/to/out.dmg
set -euo pipefail

APP="${1:-}"
OUT="${2:-}"
if [[ -z "$APP" || -z "$OUT" || ! -d "$APP" ]]; then
  echo "usage: $0 <FolderLint.app> <output.dmg>" >&2
  exit 1
fi

APP_NAME="$(basename "$APP")"
VOLUME_NAME="FolderLint"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/folderlint-dmg.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

cp -R "$APP" "$STAGE/$APP_NAME"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT"
mkdir -p "$(dirname "$OUT")"

if command -v create-dmg >/dev/null 2>&1; then
  create-dmg \
    --volname "$VOLUME_NAME" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "$APP_NAME" 150 180 \
    --app-drop-link 450 180 \
    --hide-extension "$APP_NAME" \
    "$OUT" \
    "$STAGE"
else
  echo "note: create-dmg not found; using hdiutil (brew install create-dmg for a prettier layout)"
  RW="$STAGE/rw.dmg"
  hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGE" -ov -format UDRW "$RW"
  # Convert to compressed read-only
  hdiutil convert "$RW" -format ULMO -o "$OUT"
fi

echo "dmg OK: $OUT"
