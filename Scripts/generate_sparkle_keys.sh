#!/bin/bash
# Generate or print the FolderLint Sparkle EdDSA keypair.
#
# Private key lives in the login Keychain (account: folderlint) and is also
# exported to ~/.folderlint/sparkle_eddsa_private.key for backup.
# NEVER commit the private key. Losing it strands the installed base.
#
# Usage: Scripts/generate_sparkle_keys.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ACCOUNT="folderlint"
BACKUP_DIR="$HOME/.folderlint"
BACKUP_KEY="$BACKUP_DIR/sparkle_eddsa_private.key"

find_generate_keys() {
  if [[ -n "${SPARKLE_BIN:-}" && -x "$SPARKLE_BIN/generate_keys" ]]; then
    echo "$SPARKLE_BIN/generate_keys"; return
  fi
  if command -v generate_keys >/dev/null 2>&1; then
    command -v generate_keys; return
  fi
  for p in /tmp/Sparkle-bin/bin/generate_keys "$ROOT/Tools/Sparkle/bin/generate_keys"; do
    [[ -x "$p" ]] && { echo "$p"; return; }
  done
  return 1
}

GEN="$(find_generate_keys)" || {
  echo "error: generate_keys not found. Download Sparkle 2.8+ tools and set SPARKLE_BIN." >&2
  exit 1
}

echo "==> Ensuring Keychain key for account '$ACCOUNT'"
"$GEN" --account "$ACCOUNT"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
echo "==> Exporting private key backup to $BACKUP_KEY"
"$GEN" --account "$ACCOUNT" -x "$BACKUP_KEY"
chmod 600 "$BACKUP_KEY"

echo ""
echo "Public key (must match Info.plist SUPublicEDKey):"
"$GEN" --account "$ACCOUNT" -p
echo ""
echo "BACKUP NOW: copy $BACKUP_KEY into your password manager."
echo "If this file and the Keychain entry are lost, existing installs cannot update."
