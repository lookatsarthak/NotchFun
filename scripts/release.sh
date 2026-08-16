#!/bin/bash
#
# Cuts a release: builds and signs the DMG, signs it for Sparkle, updates the
# appcast, and publishes a GitHub release with the DMG attached.
#
#   scripts/release.sh            # build, sign, print the appcast entry
#   scripts/release.sh --publish  # ...and create the GitHub release
#
set -euo pipefail

# Always target this repository explicitly. `gh` picks a repo from the git remotes
# heuristically, and this checkout has an `upstream` remote pointing at the project
# this was forked from — without -R it will happily aim a release at TheBoredTeam.
REPO="lookatsarthak/NotchFun"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_BIN="$HOME/Library/Developer/Xcode/DerivedData/boringNotch-felwyhxnvozvaxfnhnwjyhgqmvaa/SourcePackages/artifacts/sparkle/Sparkle/bin"
SIGN_UPDATE="$SPARKLE_BIN/sign_update"
PUBLISH=false
[ "${1:-}" = "--publish" ] && PUBLISH=true

cd "$ROOT"
VERSION=$(xcodebuild -scheme boringNotch -configuration Release -showBuildSettings 2>/dev/null \
          | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')
BUILD=$(xcodebuild -scheme boringNotch -configuration Release -showBuildSettings 2>/dev/null \
          | awk -F' = ' '/ CURRENT_PROJECT_VERSION = /{print $2; exit}')
: "${VERSION:?could not read MARKETING_VERSION}"

echo "==> Releasing NotchFun $VERSION (build $BUILD) to $REPO"

"$ROOT/scripts/make-dmg.sh" "$ROOT/dist"
DMG="$ROOT/dist/NotchFun-$VERSION.dmg"
[ -f "$DMG" ] || { echo "error: $DMG not found"; exit 1; }

# Verify the packaged app actually launches. A DMG whose signature verifies can still
# be dead on arrival — that has happened here before, so this check is not optional.
echo "==> Verifying the packaged app launches"
MNT=$(hdiutil attach "$DMG" -nobrowse -readonly | grep -o '/Volumes/.*$' | tail -1)
TEST_APP="/tmp/NotchFun-launch-test.app"
rm -rf "$TEST_APP"
cp -R "$MNT/NotchFun.app" "$TEST_APP"
hdiutil detach "$MNT" >/dev/null 2>&1 || true
pkill -f "$TEST_APP" 2>/dev/null || true
open -a "$TEST_APP"
sleep 6
if pgrep -f "$TEST_APP/Contents/MacOS/NotchFun" >/dev/null; then
  echo "    launches OK"
  pkill -f "$TEST_APP" 2>/dev/null || true
else
  echo "    ERROR: the packaged app failed to launch. Not releasing."
  echo "    Check: ls -t ~/Library/Logs/DiagnosticReports/NotchFun-*.ips | head -1"
  rm -rf "$TEST_APP"
  exit 1
fi
rm -rf "$TEST_APP"

if [ ! -x "$SIGN_UPDATE" ]; then
  echo "error: sign_update not found at $SIGN_UPDATE"
  echo "Build once in Xcode so SwiftPM fetches Sparkle's tools, then re-run."
  exit 1
fi

echo "==> Signing for Sparkle"
# Reads the private key from your login Keychain; macOS may prompt for approval.
SIG_LINE=$("$SIGN_UPDATE" "$DMG")
SIGNATURE=$(echo "$SIG_LINE" | sed -n 's/.*edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(echo "$SIG_LINE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
[ -n "$SIGNATURE" ] || { echo "error: could not parse a signature from: $SIG_LINE"; exit 1; }
echo "    $SIG_LINE"

echo "==> Writing docs/appcast.xml"
python3 - "$VERSION" "$BUILD" "$SIGNATURE" "$LENGTH" <<'PY'
import sys, pathlib, re, subprocess
version, build, signature, length = sys.argv[1:5]
p = pathlib.Path("docs/appcast.xml")
s = p.read_text()
pubdate = subprocess.check_output(["date", "-R"], text=True).strip()
item = f'''    <item>
      <title>{version}</title>
      <pubDate>{pubdate}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[ See the release notes on GitHub. ]]></description>
      <enclosure
        url="https://github.com/lookatsarthak/NotchFun/releases/download/v{version}/NotchFun-{version}.dmg"
        sparkle:edSignature="{signature}"
        length="{length}"
        type="application/octet-stream" />
    </item>
'''
if f"<sparkle:shortVersionString>{version}</sparkle:shortVersionString>" in s:
    # Replace the existing entry for this version rather than duplicating it.
    s = re.sub(r'    <item>(?:(?!</item>).)*?<sparkle:shortVersionString>'
               + re.escape(version) + r'</sparkle:shortVersionString>.*?</item>\n',
               item, s, flags=re.S)
else:
    s = s.replace("    <item>", item + "\n    <item>", 1) if "<item>" in s \
        else s.replace("  </channel>", item + "\n  </channel>")
p.write_text(s)
import xml.dom.minidom; xml.dom.minidom.parse(str(p))
print("    appcast valid")
PY

if [ "$PUBLISH" = true ]; then
  echo "==> Publishing release v$VERSION to $REPO"
  git add docs/appcast.xml
  git commit -q -m "Sign appcast for $VERSION" || true
  git push origin main
  gh release create "v$VERSION" "$DMG" -R "$REPO" \
    --title "NotchFun $VERSION" --generate-notes
  echo "Published: https://github.com/$REPO/releases/tag/v$VERSION"
else
  echo
  echo "Dry run complete. Review docs/appcast.xml, then re-run with --publish."
fi
