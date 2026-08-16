#!/bin/bash
#
# Cuts a release: builds the DMG, signs it for Sparkle, and prints the appcast entry.
#
#   scripts/release.sh
#
# Publishing steps afterwards are manual on purpose — you should look at the DMG
# before it goes public.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGN_UPDATE="$HOME/Library/Developer/Xcode/DerivedData/boringNotch-felwyhxnvozvaxfnhnwjyhgqmvaa/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"

cd "$ROOT"
VERSION=$(xcodebuild -scheme boringNotch -configuration Release -showBuildSettings 2>/dev/null \
          | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')

"$ROOT/scripts/make-dmg.sh" "$ROOT/dist"
DMG="$ROOT/dist/NotchFun-$VERSION.dmg"

if [ ! -x "$SIGN_UPDATE" ]; then
  echo
  echo "sign_update not found at:"
  echo "  $SIGN_UPDATE"
  echo "Build once in Xcode so SwiftPM fetches Sparkle's tools, then re-run."
  exit 1
fi

echo
echo "==> Sparkle signature for $DMG"
SIG=$("$SIGN_UPDATE" "$DMG")
echo "$SIG"

cat <<TEMPLATE

Add this <item> to docs/appcast.xml, above the previous release:

    <item>
      <title>$VERSION</title>
      <pubDate>$(date -R)</pubDate>
      <sparkle:version>$(xcodebuild -scheme boringNotch -configuration Release -showBuildSettings 2>/dev/null | awk -F' = ' '/ CURRENT_PROJECT_VERSION = /{print $2; exit}')</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[ <ul><li>Describe the changes here.</li></ul> ]]></description>
      <enclosure
        url="https://github.com/lookatsarthak/NotchFun/releases/download/v$VERSION/NotchFun-$VERSION.dmg"
        $SIG
        type="application/octet-stream" />
    </item>

Then:
  1. gh release create v$VERSION "$DMG" --title "NotchFun $VERSION" --notes "..."
  2. Commit and push docs/appcast.xml
TEMPLATE
