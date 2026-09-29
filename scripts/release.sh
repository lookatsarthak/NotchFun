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
# The Homebrew tap whose cask is bumped after publishing.
TAP_REPO="lookatsarthak/homebrew-tap"

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
# Read from the project rather than hardcoded. Sparkle uses this to decide who gets
# offered the update, so if it lags behind the deployment target, people on an older
# macOS are offered a build that cannot launch on their Mac.
MIN_OS=$(xcodebuild -scheme boringNotch -configuration Release -showBuildSettings 2>/dev/null \
          | awk -F' = ' '/ MACOSX_DEPLOYMENT_TARGET = /{print $2; exit}')
: "${MIN_OS:?could not read MACOSX_DEPLOYMENT_TARGET}"
: "${VERSION:?could not read MARKETING_VERSION}"

echo "==> Releasing NotchFun $VERSION (build $BUILD) to $REPO"

# Release notes are required, and written first: the same file is shown in Sparkle's
# update window inside the app and used as the GitHub release notes. See
# release-notes/README.md for the format. Checked before building so a missing file
# fails in seconds, not after a full build.
NOTES="$ROOT/release-notes/$VERSION.md"
[ -s "$NOTES" ] || { echo "error: write $NOTES first (see release-notes/README.md)"; exit 1; }

"$ROOT/scripts/make-dmg.sh" "$ROOT/dist"
DMG="$ROOT/dist/NotchFun-$VERSION.dmg"
[ -f "$DMG" ] || { echo "error: $DMG not found"; exit 1; }

# Verify the packaged app actually launches. A DMG whose signature verifies can still
# be dead on arrival — that has happened here before, so this check is not optional.
echo "==> Verifying the packaged app launches"
MNT=$(hdiutil attach "$DMG" -nobrowse -readonly | grep -o '/Volumes/.*$' | tail -1)
# mktemp -d, not /tmp: on macOS /tmp is a symlink to /private/tmp, and the kernel
# reports the process under the resolved path. A pattern built from "/tmp/..." therefore
# never matched, so the pkill below silently did nothing and every release left an
# orphaned NotchFun running from a bundle this script had already deleted - a second
# notch app fighting the installed one, with its own clipboard monitor and its own power
# assertions. mktemp -d hands back an already-resolved path, so the pattern matches.
#
# `pwd -P` because the path has to be the *physical* one to compare against what the
# kernel reports. Both of macOS's temp roots are symlinks - /tmp -> /private/tmp, and
# /var -> /private/var, so even mktemp -d hands back a /var/folders/... path while the
# process shows up under /private/var/folders/... Resolving it once here is what makes
# the comparison below reliable.
TEST_DIR=$(cd "$(mktemp -d)" && pwd -P)
TEST_APP="$TEST_DIR/NotchFun.app"
cp -R "$MNT/NotchFun.app" "$TEST_APP"
hdiutil detach "$MNT" >/dev/null 2>&1 || true

# Which running NotchFun processes belong to the test copy.
#
# Matches on the process's executable path (ps -o comm=), not on `pgrep -f` over the
# whole command line: a -f pattern also matches any shell whose command text happens to
# contain the path, including the one running this script, which made an earlier version
# of this check abort a release that was actually fine.
test_instances() {
  local pid image
  for pid in $(pgrep -x NotchFun 2>/dev/null || true); do
    image=$(ps -o comm= -p "$pid" 2>/dev/null || true)
    case "$image" in "$TEST_DIR"*) echo "$pid" ;; esac
  done
}

# Always clean up the test instance, however this script exits.
cleanup_test_app() {
  local pids
  pids=$(test_instances)
  [ -n "$pids" ] && kill $pids 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    [ -z "$(test_instances)" ] && break
    sleep 1
  done
  # SIGTERM is not guaranteed to stop an AppKit app; make sure.
  pids=$(test_instances)
  [ -n "$pids" ] && kill -9 $pids 2>/dev/null || true
  rm -rf "$TEST_DIR"
}
trap cleanup_test_app EXIT

open -a "$TEST_APP"
sleep 6
if [ -n "$(test_instances)" ]; then
  echo "    launches OK"
else
  echo "    ERROR: the packaged app failed to launch. Not releasing."
  echo "    Check: ls -t ~/Library/Logs/DiagnosticReports/NotchFun-*.ips | head -1"
  exit 1
fi

cleanup_test_app
trap - EXIT
if [ -n "$(test_instances)" ]; then
  echo "    ERROR: the launch-test instance is still running. Not releasing."
  exit 1
fi
echo "    launch-test instance cleaned up"

if [ ! -x "$SIGN_UPDATE" ]; then
  echo "error: sign_update not found at $SIGN_UPDATE"
  echo "Build once in Xcode so SwiftPM fetches Sparkle's tools, then re-run."
  exit 1
fi

echo "==> Signing for Sparkle"
# Reads the private key from your login Keychain, where macOS may stop to ask for the
# keychain password - which leaves an unattended release waiting on a dialog. Set
# SPARKLE_ED_KEY_FILE to an exported copy of the key to sign without the Keychain.
if [ -n "${SPARKLE_ED_KEY_FILE:-}" ]; then
  SIG_LINE=$("$SIGN_UPDATE" --ed-key-file "$SPARKLE_ED_KEY_FILE" "$DMG")
else
  SIG_LINE=$("$SIGN_UPDATE" "$DMG")
fi
SIGNATURE=$(echo "$SIG_LINE" | sed -n 's/.*edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(echo "$SIG_LINE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
[ -n "$SIGNATURE" ] || { echo "error: could not parse a signature from: $SIG_LINE"; exit 1; }
echo "    $SIG_LINE"

echo "==> Rendering release notes"
# GitHub's own Markdown renderer, so the in-app notes match the release page exactly
# and nothing new has to be installed; gh is already required to publish.
NOTES_HTML=$(mktemp)
gh api markdown -f text="$(cat "$NOTES")" -f mode=gfm > "$NOTES_HTML"
[ -s "$NOTES_HTML" ] || { echo "error: could not render $NOTES"; exit 1; }

echo "==> Writing docs/appcast.xml"
python3 - "$VERSION" "$BUILD" "$SIGNATURE" "$LENGTH" "$MIN_OS" "$NOTES_HTML" <<'PY'
import sys, pathlib, re, subprocess
version, build, signature, length, min_os, notes_path = sys.argv[1:7]
notes = pathlib.Path(notes_path).read_text().strip()
assert "]]>" not in notes, "release notes cannot contain ]]>"
# Sparkle shows this in a small web view that follows the system appearance only if told to.
style = ("<style>:root{color-scheme:light dark}body{font:13px -apple-system,sans-serif;"
         "margin:0 2px}h3{font-size:13px;margin:10px 0 4px}ul{margin:0;padding-left:18px}"
         "li{margin:3px 0}</style>")
p = pathlib.Path("docs/appcast.xml")
s = p.read_text()
pubdate = subprocess.check_output(["date", "-R"], text=True).strip()
item = f'''    <item>
      <title>{version}</title>
      <pubDate>{pubdate}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{min_os}</sparkle:minimumSystemVersion>
      <description><![CDATA[{style}{notes}]]></description>
      <sparkle:fullReleaseNotesLink>https://github.com/lookatsarthak/NotchFun/releases</sparkle:fullReleaseNotesLink>
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
  # A fixed-name copy alongside the versioned one, so
  # .../releases/latest/download/NotchFun.dmg always resolves to the newest release.
  # scripts/install.sh, and the one-line install in the README, depend on it.
  LATEST_DMG="$ROOT/dist/NotchFun.dmg"
  cp "$DMG" "$LATEST_DMG"
  gh release create "v$VERSION" "$DMG" "$LATEST_DMG" -R "$REPO" \
    --title "NotchFun $VERSION" --notes-file "$NOTES"
  echo "Published: https://github.com/$REPO/releases/tag/v$VERSION"

  # The Homebrew cask pins a version and a checksum, and Homebrew never looks for a
  # newer release by itself, so the cask has to be bumped with every release. It sat on
  # 1.3.3 through four releases before this step existed, so `brew install` handed new
  # users a build months old until Sparkle caught them up.
  #
  # The checksum is taken from the published download rather than the local file, so
  # the cask is guaranteed to describe what Homebrew will actually fetch. Failure here
  # does not undo the release, which is already out; it says what to do by hand.
  echo "==> Updating the Homebrew cask"
  bump_cask() {
    local sha tap
    sha=$(curl -fsSL "https://github.com/$REPO/releases/download/v$VERSION/$(basename "$DMG")" \
          | shasum -a 256 | cut -d' ' -f1)
    [ "$sha" = "$(shasum -a 256 "$DMG" | cut -d' ' -f1)" ] || { echo "    published DMG does not match the local one"; return 1; }
    tap=$(mktemp -d)
    git clone -q "https://github.com/$TAP_REPO.git" "$tap" || return 1
    sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" \
              -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$tap/Casks/notchfun.rb"
    if git -C "$tap" diff --quiet; then
      # Re-running a release that was already bumped: nothing to do, not a failure.
      rm -rf "$tap"
      echo "    cask already at $VERSION"
      return 0
    fi
    git -C "$tap" commit -q -am "notchfun $VERSION" || return 1
    # Credentials from gh explicitly: a global keychain helper may hold another account.
    git -C "$tap" -c credential.helper= -c "credential.helper=!gh auth git-credential" \
      push -q origin HEAD || return 1
    rm -rf "$tap"
    echo "    cask now at $VERSION"
  }
  bump_cask || echo "    WARNING: cask not updated. Set version and sha256 in $TAP_REPO/Casks/notchfun.rb by hand."
else
  echo
  echo "Dry run complete. Review docs/appcast.xml, then re-run with --publish."
fi
