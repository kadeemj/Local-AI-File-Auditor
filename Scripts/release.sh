#!/bin/bash
# Build, notarize, staple, package, and refresh the Sparkle appcast.
#
# Usage: VERSION=0.9.0 Scripts/release.sh
#    or: make release VERSION=0.9.0
#
# Hard rules:
#   - Always archive → -exportArchive (never ship a plain Release build)
#   - Never codesign --deep
#   - Staple the .app before zipping for Sparkle
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: VERSION=x.y.z $0" >&2
  exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.]+)?$ ]]; then
  echo "error: VERSION must look like 1.2.3 (got: $VERSION)" >&2
  exit 1
fi

DIST="$ROOT/dist/$VERSION"
ARCHIVE="$DIST/FolderLint.xcarchive"
EXPORT_DIR="$DIST/export"
APP="$EXPORT_DIR/FolderLint.app"
DMG="$DIST/FolderLint-$VERSION.dmg"
SPARKLE_ZIP="$DIST/FolderLint-$VERSION.zip"
EXPORT_OPTIONS="$ROOT/Config/ExportOptions.plist"
SCHEME="FolderLint"
PROJECT="FolderLint.xcodeproj"

echo "==> Regenerating Xcode project"
make generate

BUILD_NUMBER="$(date +%s)"
echo "==> Setting MARKETING_VERSION=$VERSION CURRENT_PROJECT_VERSION=$BUILD_NUMBER"
perl -i -pe "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $VERSION/" Config/Shared.xcconfig
perl -i -pe "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $BUILD_NUMBER/" Config/Shared.xcconfig

rm -rf "$DIST"
mkdir -p "$DIST"

echo "==> Archiving (Developer ID)"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -destination "generic/platform=macOS" \
  DEVELOPMENT_TEAM=JUQMKZZ7TJ \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application"

echo "==> Exporting archive (developer-id)"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

if [[ ! -d "$APP" ]]; then
  echo "error: expected $APP after export" >&2
  exit 1
fi

echo "==> Notarizing + stapling app"
"$ROOT/Scripts/notarize.sh" "$APP" --staple

echo "==> Building Sparkle zip (app must already be stapled)"
ditto -c -k --keepParent "$APP" "$SPARKLE_ZIP"

echo "==> Building DMG"
"$ROOT/Scripts/make_dmg.sh" "$APP" "$DMG"

echo "==> Notarizing + stapling DMG"
"$ROOT/Scripts/notarize.sh" "$DMG" --staple

echo "==> Updating appcast"
"$ROOT/Scripts/update_appcast.sh" "$DIST"

echo "==> Verifying artifacts"
"$ROOT/Scripts/verify.sh" "$APP" "$DMG"

echo ""
echo "Release $VERSION ready in $DIST"
echo "  App:  $APP"
echo "  Zip:  $SPARKLE_ZIP"
echo "  DMG:  $DMG"
echo "  Feed: $ROOT/appcast/appcast.xml"
echo ""
echo "Publish the DMG + Sparkle zip + appcast.xml to the feed host (folderlint.com)."
echo "Private EdDSA key stays in Keychain account 'folderlint' / ~/.folderlint/ — never commit it."
