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

# The window layout - background, icon positions, hidden toolbar - lives in the image's
# .DS_Store. dmgbuild writes that file directly rather than scripting Finder, so this
# works headless and gives the same window every time. It is a build-time tool only,
# kept in a virtualenv under .build; nothing about it ends up in the app.
DMGBUILD_VENV="$ROOT/.build/dmgvenv"
if [ ! -x "$DMGBUILD_VENV/bin/dmgbuild" ]; then
  echo "    installing dmgbuild into $DMGBUILD_VENV"
  python3 -m venv "$DMGBUILD_VENV"
  "$DMGBUILD_VENV/bin/pip" install -q --disable-pip-version-check "dmgbuild==1.6.5"
fi

# One TIFF holding the 1x and 2x images; see scripts/dmg/render-background.swift. It is
# committed LZW-compressed (114KB) but goes into the image uncompressed: the image's own
# lzfse pass does far better on flat gradient rows than LZW does, so the download grows
# by ~51KB this way against ~111KB for the LZW file as-is.
BACKGROUND="$STAGING/background.tiff"
tiffutil -none "$ROOT/scripts/dmg/background.tiff" -out "$BACKGROUND" >/dev/null

mkdir -p "$OUT_DIR"
DMG="$OUT_DIR/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"

# Built in two steps, deliberately.
#
# `hdiutil create` (which dmgbuild runs underneath) can leave large unreferenced
# regions inside the image: the 1.4.1
# release shipped 1,088,360 bytes of slack - 98.8% zeroes - between two compressed
# chunks, making the download 23% bigger than 1.4.0 despite the app itself having
# shrunk. It mounted and ran fine, which is exactly why nobody noticed. It was not
# reproducible either; it happened once, on the first build after a macOS update.
#
# `hdiutil convert` always rewrites the chunk table compactly, so a create-then-convert
# pass cannot carry slack through. The assertion below is the part that matters: it
# means a bloated image fails the build instead of reaching a release.
#
# ULFO (lzfse) rather than UDZO (zlib): ~12% smaller and faster to mount. Needs macOS
# 10.11 to open, far below this app's own floor.
RAW_DMG="$STAGING.raw.dmg"
echo "==> Creating $DMG"
"$DMGBUILD_VENV/bin/dmgbuild" -s "$ROOT/scripts/dmg/settings.py" \
  -D app="$APP_PATH" -D background="$BACKGROUND" \
  "$APP_NAME" "$RAW_DMG" >/dev/null

hdiutil convert "$RAW_DMG" -format ULFO -o "$DMG" -quiet
rm -f "$RAW_DMG"

# Fail loudly on a bloated image rather than shipping it.
python3 - "$DMG" <<'PYEOF'
import plistlib, struct, sys, os

path = sys.argv[1]
with open(path, "rb") as f:
    f.seek(-512, os.SEEK_END)
    trailer = f.read(512)
    if trailer[:4] != b"koly":
        sys.exit("error: no koly trailer; not a UDIF image")
    xml_off, xml_len = struct.unpack(">QQ", trailer[216:232])
    f.seek(xml_off)
    plist = plistlib.loads(f.read(xml_len))

# Sum the bytes every block actually stores, and compare with where the data fork ends.
stored = 0
for blk in plist["resource-fork"]["blkx"]:
    data = blk["Data"]
    for i in range(struct.unpack(">I", data[200:204])[0]):
        stored += struct.unpack(">IIQQQQ", data[204 + 40 * i:244 + 40 * i])[5]

slack = xml_off - stored
size = os.path.getsize(path)
print(f"    {size:,} bytes, {slack:,} unreferenced")
if slack > 65536:
    sys.exit(f"error: {slack:,} bytes of slack in the disk image (limit 65,536)")
PYEOF

echo
echo "Built: $DMG"
echo "Size:  $(du -h "$DMG" | cut -f1)"
echo
echo "Note: this build is not notarised. On first launch macOS will say it cannot verify"
echo "the developer. Tell users to open System Settings > Privacy & Security, scroll to"
echo "Security and click \"Open Anyway\". Do NOT tell them to right-click > Open: macOS 15"
echo "removed that bypass, and the dialog they get instead has \"Move to Bin\" as its"
echo "prominent button."
