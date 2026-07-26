#!/bin/bash
# Submit a .app or .dmg to Apple notary service and optionally staple.
#
# Usage:
#   Scripts/notarize.sh path/to/FolderLint.app [--staple]
#   Scripts/notarize.sh path/to/FolderLint-1.0.0.dmg [--staple]
#
# Requires: xcrun notarytool store-credentials "notary-profile"
set -euo pipefail

STAPLE=false
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --staple) STAPLE=true ;;
    *) TARGET="$arg" ;;
  esac
done

if [[ -z "$TARGET" || ! -e "$TARGET" ]]; then
  echo "usage: $0 <path-to-.app-or-.dmg> [--staple]" >&2
  exit 1
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-notary-profile}"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/folderlint-notary.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

SUBMIT="$TARGET"
if [[ "$TARGET" == *.app ]]; then
  ZIP="$WORKDIR/$(basename "$TARGET" .app).zip"
  ditto -c -k --keepParent "$TARGET" "$ZIP"
  SUBMIT="$ZIP"
fi

echo "==> Submitting $(basename "$TARGET") via profile '$NOTARY_PROFILE'"
xcrun notarytool submit "$SUBMIT" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

if $STAPLE; then
  echo "==> Stapling $(basename "$TARGET")"
  xcrun stapler staple "$TARGET"
  xcrun stapler validate "$TARGET"
fi

echo "notarize OK: $TARGET"
