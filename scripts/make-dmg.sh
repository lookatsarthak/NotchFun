#!/bin/bash
#
# Builds a Release .app and packages it into a distributable .dmg.
#
# The build is ad-hoc signed ("-"). Apple Silicon refuses to launch a completely
# unsigned binary, so this is the minimum that works without an Apple Developer
# Program membership. It is NOT notarised, so Gatekeeper will warn on first launch —
# see the install instructions in the README.
#
# Usage:  scripts/make-dmg.sh [output-directory]
#
set -euo pipefail

SCHEME="boringNotch"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT/dist}"

# Read the user-visible name and version straight from the project so this script
# needs no edits after a rebrand.
cd "$ROOT"
SETTINGS=$(xcodebuild -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null)
APP_NAME=$(echo "$SETTINGS" | awk -F' = ' '/ FULL_PRODUCT_NAME = /{print $2; exit}' | sed 's/\.app$//')
VERSION=$(echo "$SETTINGS" | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')
: "${APP_NAME:?could not determine product name}"
: "${VERSION:=0.0.0}"

DERIVED="$ROOT/.build/dmg"
APP_PATH="$DERIVED/Build/Products/Release/$APP_NAME.app"

echo "==> Building $APP_NAME $VERSION (Release)"
xcodebuild -scheme "$SCHEME" -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  build

[ -d "$APP_PATH" ] || { echo "error: $APP_PATH not found"; exit 1; }

echo "==> Staging disk image"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP_PATH" "$STAGING/"
# The Applications symlink is what makes the window a drag-to-install target.
ln -s /Applications "$STAGING/Applications"

mkdir -p "$OUT_DIR"
DMG="$OUT_DIR/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"

echo "==> Creating $DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG" >/dev/null

echo
echo "Built: $DMG"
echo "Size:  $(du -h "$DMG" | cut -f1)"
echo
echo "Note: this build is ad-hoc signed and not notarised. On first launch macOS will"
echo "say it cannot verify the developer. Users must right-click the app and choose"
echo "Open, or allow it under System Settings > Privacy & Security."
