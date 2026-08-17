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
# A stable signing identity keeps macOS from treating each build as a different app.
# With ad-hoc signing the designated requirement is a cdhash, so every release resets
# users' Accessibility permission; a certificate makes it "identifier + cert leaf",
# which survives rebuilds. Falls back to ad-hoc if the certificate is missing.
SIGN_IDENTITY="${NOTCHFUN_SIGN_IDENTITY:-NotchFun Developer}"
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
# `clean build`, not `build`. This script reuses a fixed derived-data directory, so an
# incremental build can link object files compiled against a previous version of a
# dependency. That is not hypothetical: after Lottie went to 4.6.1 -- which changed
# LottieAnimation.loadedFrom(url:session:closure:animationCache:) from returning Void to
# returning URLSessionDataTask?, and so changed its mangled symbol -- a stale LottieView.o
# failed to link with "Undefined symbols", while clean builds of the same source
# succeeded. A release is worth the extra few minutes to be sure of what is in it.
xcodebuild -scheme "$SCHEME" -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  clean build

[ -d "$APP_PATH" ] || { echo "error: $APP_PATH not found"; exit 1; }

# Re-sign every nested bundle with the same ad-hoc identity as the app.
#
# MediaRemoteAdapter.framework is vendored pre-signed by its original author, and
# xcodebuild leaves that signature alone. With hardened runtime enabled, macOS enforces
# library validation and refuses to load a library whose Team ID differs from the
# process loading it — so the app builds fine and then dies at launch with
# "Library not loaded ... different Team IDs". Re-signing everything with one identity
# makes the Team IDs consistent (all absent, for ad-hoc).
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  echo "==> Re-signing with \"$SIGN_IDENTITY\""
else
  echo "==> \"$SIGN_IDENTITY\" not found in the keychain; falling back to ad-hoc"
  echo "    (users will have to re-grant Accessibility on every release)"
  SIGN_IDENTITY="-"
fi
ENTITLEMENTS=$(mktemp -t notchfun-entitlements).plist
codesign -d --entitlements "$ENTITLEMENTS" --xml "$APP_PATH" 2>/dev/null || true

while IFS= read -r nested; do
  codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$nested"
done < <(find "$APP_PATH/Contents" \
           \( -name "*.framework" -o -name "*.xpc" -o -name "*.app" -o -name "*.dylib" \) \
           -not -path "$APP_PATH" | sort -r)

# Hardened runtime enforces library validation, which requires every loaded library to
# share the app's signing identity. Ad-hoc signatures have no identity to share, so an
# ad-hoc build embedding third-party frameworks cannot satisfy it however carefully
# everything is re-signed — the app builds, verifies, and then dies at launch. This
# entitlement exists for exactly that case. A build signed with a real Developer ID
# would not need it, because the frameworks would carry that Team ID.
if [ -s "$ENTITLEMENTS" ]; then
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$ENTITLEMENTS" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :com.apple.security.cs.disable-library-validation true" "$ENTITLEMENTS"

  # Strip get-task-allow. Xcode adds it so debuggers can attach, and because these
  # entitlements are copied off the built app it would otherwise be carried into the
  # shipped DMG — letting any process running as the user attach to NotchFun and read
  # its memory. This app holds clipboard history, so that is not a theoretical concern.
  /usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$ENTITLEMENTS" 2>/dev/null \
    && echo "    stripped get-task-allow" || true
  # The app itself is re-signed last, since its nested content just changed.
  # Entitlements are re-applied explicitly or the sandbox would be silently dropped.
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --entitlements "$ENTITLEMENTS" "$APP_PATH"
else
  echo "error: could not read entitlements from the built app" >&2
  exit 1
fi
rm -f "$ENTITLEMENTS"

codesign --verify --deep --strict "$APP_PATH" && echo "    signature verifies"

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
echo "Note: this build is not notarised. On first launch macOS will say it cannot verify"
echo "the developer. Tell users to open System Settings > Privacy & Security, scroll to"
echo "Security and click \"Open Anyway\". Do NOT tell them to right-click > Open: macOS 15"
echo "removed that bypass, and the dialog they get instead has \"Move to Bin\" as its"
echo "prominent button."
