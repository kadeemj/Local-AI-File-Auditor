#!/bin/bash
# Build gate for the auditable network policy (docs/NETWORK_POLICY.md):
# the ONLY file in the app target allowed to use networking APIs is
# FolderLint/Services/Network/NetworkClient.swift. Sparkle's networking lives
# inside the Sparkle framework and is disclosed in the policy document.
set -euo pipefail

ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
APP_SOURCES="$ROOT/FolderLint"

violations=$(grep -rn \
    -e "URLSession" \
    -e "NSURLConnection" \
    -e "CFNetwork" \
    -e "import Network" \
    "$APP_SOURCES" \
    --include="*.swift" \
    | grep -v "Services/Network/" \
    || true)

if [ -n "$violations" ]; then
    echo "error: networking API used outside FolderLint/Services/Network/ — this violates the network policy (docs/NETWORK_POLICY.md):"
    echo "$violations"
    exit 1
fi

echo "network policy check passed"
