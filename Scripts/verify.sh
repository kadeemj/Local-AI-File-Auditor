#!/bin/bash
# Verify release artifacts: Gatekeeper, codesign --strict, stapler, sandbox entitlement.
#
# Usage:
#   Scripts/verify.sh path/to/FolderLint.app [path/to.dmg]
#   make verify APP=dist/0.9.0/export/FolderLint.app DMG=dist/0.9.0/FolderLint-0.9.0.dmg
set -euo pipefail

APP="${1:-${APP:-}}"
DMG="${2:-${DMG:-}}"

if [[ -z "$APP" ]]; then
  echo "usage: $0 <FolderLint.app> [FolderLint.dmg]" >&2
  echo "  or: make verify APP=… [DMG=…]" >&2
  exit 1
fi
if [[ ! -d "$APP" ]]; then
  echo "error: app not found: $APP" >&2
  exit 1
fi

fail=0

echo "==> codesign --verify --strict --deep (deep verify only; we never sign with --deep)"
if ! codesign --verify --strict --deep --verbose=2 "$APP"; then
  echo "FAIL: codesign verify"
  fail=1
fi

echo "==> codesign entitlements include app-sandbox + Sparkle mach-lookup"
ENTS="$(codesign -d --entitlements - "$APP" 2>/dev/null || true)"
for needle in \
  "com.apple.security.app-sandbox" \
  "com.apple.security.network.client" \
  "com.folderlint.app-spks" \
  "com.folderlint.app-spki"
do
  if ! printf '%s' "$ENTS" | grep -q "$needle"; then
    echo "FAIL: missing entitlement/mach name: $needle"
    fail=1
  else
    echo "  ok: $needle"
  fi
done

echo "==> spctl assess (Developer ID Gatekeeper)"
if ! spctl -a -vv --type execute "$APP" 2>&1; then
  echo "FAIL: spctl"
  fail=1
fi

echo "==> stapler validate app"
if ! xcrun stapler validate "$APP"; then
  echo "FAIL: stapler (app not stapled?)"
  fail=1
fi

# Sparkle helpers must be present for sandboxed updates.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [[ ! -d "$SPARKLE" ]]; then
  echo "FAIL: Sparkle.framework missing from app bundle"
  fail=1
else
  echo "  ok: Sparkle.framework embedded"
  if [[ ! -d "$SPARKLE/Versions/B/XPCServices/Installer.xpc" ]] && [[ ! -d "$SPARKLE/XPCServices/Installer.xpc" ]]; then
    echo "WARN: Installer.xpc not found at expected path — confirm Sparkle version embeds XPC services"
  fi
fi

if [[ -n "$DMG" ]]; then
  if [[ ! -f "$DMG" ]]; then
    echo "FAIL: dmg not found: $DMG"
    fail=1
  else
    echo "==> stapler validate dmg"
    if ! xcrun stapler validate "$DMG"; then
      echo "FAIL: stapler (dmg)"
      fail=1
    fi
    echo "==> spctl assess dmg"
    if ! spctl -a -vv --type install "$DMG" 2>&1; then
      echo "FAIL: spctl dmg"
      fail=1
    fi
  fi
fi

if [[ "$fail" -ne 0 ]]; then
  echo "verify FAILED"
  exit 1
fi
echo "verify OK"
