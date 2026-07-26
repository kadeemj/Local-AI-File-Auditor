#!/bin/bash
# Sign Sparkle update archives in a directory and refresh appcast/appcast.xml.
#
# Usage: Scripts/update_appcast.sh dist/0.9.0
#
# Looks for generate_appcast on PATH, SPARKLE_BIN, or a local Sparkle checkout.
# Private key: Keychain account "folderlint", or SPARKLE_PRIVATE_KEY_FILE.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVES_DIR="${1:-}"
if [[ -z "$ARCHIVES_DIR" || ! -d "$ARCHIVES_DIR" ]]; then
  echo "usage: $0 <directory-containing-FolderLint-*.zip>" >&2
  exit 1
fi

find_generate_appcast() {
  if [[ -n "${SPARKLE_BIN:-}" && -x "$SPARKLE_BIN/generate_appcast" ]]; then
    echo "$SPARKLE_BIN/generate_appcast"
    return
  fi
  if command -v generate_appcast >/dev/null 2>&1; then
    command -v generate_appcast
    return
  fi
  local candidate
  candidate="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/SourcePackages/artifacts/sparkle/*/Sparkle.xcframework' -prune -o -name generate_appcast -type f -print 2>/dev/null | head -1 || true)"
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    echo "$candidate"
    return
  fi
  # Fallback: tools downloaded beside this script's cache
  for p in /tmp/Sparkle-bin/bin/generate_appcast "$ROOT/Tools/Sparkle/bin/generate_appcast"; do
    if [[ -x "$p" ]]; then
      echo "$p"
      return
    fi
  done
  return 1
}

GEN="$(find_generate_appcast)" || {
  echo "error: generate_appcast not found. Install Sparkle tools or set SPARKLE_BIN." >&2
  echo "  curl -L https://github.com/sparkle-project/Sparkle/releases/download/2.8.1/Sparkle-2.8.1.tar.xz | tar x" >&2
  exit 1
}

APPCAST_DIR="$ROOT/appcast"
mkdir -p "$APPCAST_DIR"

# Stage zips into appcast dir for generate_appcast (it writes appcast beside archives).
STAGE="$APPCAST_DIR/.staging"
rm -rf "$STAGE"
mkdir -p "$STAGE"
# Keep existing appcast so new entries merge.
if [[ -f "$APPCAST_DIR/appcast.xml" ]]; then
  cp "$APPCAST_DIR/appcast.xml" "$STAGE/appcast.xml"
fi
shopt -s nullglob
for z in "$ARCHIVES_DIR"/FolderLint-*.zip; do
  cp "$z" "$STAGE/"
done
shopt -u nullglob

KEY_ARGS=()
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  KEY_ARGS+=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
elif [[ -f "$HOME/.folderlint/sparkle_eddsa_private.key" ]]; then
  KEY_ARGS+=(--ed-key-file "$HOME/.folderlint/sparkle_eddsa_private.key")
else
  # generate_appcast reads the Keychain account used by generate_keys
  KEY_ARGS+=(--account folderlint)
fi

echo "==> Running generate_appcast on $STAGE"
"$GEN" "${KEY_ARGS[@]}" "$STAGE"

if [[ -f "$STAGE/appcast.xml" ]]; then
  cp "$STAGE/appcast.xml" "$APPCAST_DIR/appcast.xml"
fi
# Publish signed zips next to the feed for GitHub Pages / static hosting.
shopt -s nullglob
for z in "$STAGE"/FolderLint-*.zip; do
  cp "$z" "$APPCAST_DIR/"
done
shopt -u nullglob

# Rewrite enclosure URLs to the public feed host if still file-relative.
# generate_appcast uses filenames; publish path is https://folderlint.com/<zip>
python3 - <<'PY' "$APPCAST_DIR/appcast.xml" || true
import re, sys
path = sys.argv[1]
text = open(path).read()
# Ensure enclosure urls point at the production host when they are bare filenames.
def fix(m):
    url = m.group(1)
    if url.startswith("http"):
        return m.group(0)
    name = url.split("/")[-1]
    return f'url="https://folderlint.com/{name}"'
text2 = re.sub(r'url="([^"]+)"', fix, text)
open(path, "w").write(text2)
print("appcast enclosure URLs normalized to https://folderlint.com/…")
PY

rm -rf "$STAGE"
echo "appcast OK: $APPCAST_DIR/appcast.xml"
