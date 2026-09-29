#!/bin/bash
#
# Installs the latest NotchFun release into /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/lookatsarthak/NotchFun/main/scripts/install.sh | bash
#
# Why this exists: NotchFun is not notarised, so an app dragged out of a downloaded disk
# image is stopped by Gatekeeper on first launch ("Open Anyway" in System Settings).
# curl does not mark what it downloads as quarantined, so an app installed this way
# opens straight away. That is the whole trick - there is nothing else here.
#
# Plain bash 3.2, which is what macOS ships.
set -euo pipefail

URL="https://github.com/lookatsarthak/NotchFun/releases/latest/download/NotchFun.dmg"

# NotchFun needs macOS 26 Tahoe. Stop before touching anything on an older Mac, so a
# working copy of an older release is not replaced by one that cannot launch.
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MAJOR" -lt 26 ]; then
  echo "NotchFun needs macOS 26 Tahoe or later; this Mac has macOS $(sw_vers -productVersion)." >&2
  echo "NotchFun 1.2.1 still works on macOS 15: https://github.com/lookatsarthak/NotchFun/releases/tag/v1.2.1" >&2
  exit 1
fi

# /Applications, unless this account cannot write there (a standard, non-admin user),
# or NotchFun already lives in ~/Applications - then that is where it goes.
if [ -d "$HOME/Applications/NotchFun.app" ] || ! [ -w /Applications ]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
else
  DEST="/Applications"
fi
APP="$DEST/NotchFun.app"

TMP=$(mktemp -d)
MNT="$TMP/mnt"
cleanup() {
  hdiutil detach -quiet "$MNT" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "Downloading NotchFun..."
curl -fL --progress-bar "$URL" -o "$TMP/NotchFun.dmg"

# Our own mount point, so a NotchFun volume that is already mounted from an earlier
# download cannot shadow this one at /Volumes/NotchFun.
mkdir "$MNT"
hdiutil attach -nobrowse -readonly -quiet -mountpoint "$MNT" "$TMP/NotchFun.dmg"

if [ ! -d "$MNT/NotchFun.app" ]; then
  echo "error: the download did not contain NotchFun.app" >&2
  exit 1
fi

# Quit a running copy, or `open` below would just bring the old version forward.
# Releases before 1.4.2 ignored SIGTERM, hence the fallback.
if pgrep -x NotchFun >/dev/null; then
  echo "Quitting the running NotchFun..."
  pkill -x NotchFun || true
  for _ in 1 2 3 4 5; do
    pgrep -x NotchFun >/dev/null || break
    sleep 1
  done
  pkill -9 -x NotchFun 2>/dev/null || true
  # Its Now Playing helper is a separate perl process that outlives a signalled app.
  pkill -f "NotchFun.app/Contents/Resources/mediaremote-adapter.pl" 2>/dev/null || true
fi

echo "Installing to $DEST..."
# Replace rather than copy over the top, so files a newer version dropped do not linger.
rm -rf "$APP"
ditto "$MNT/NotchFun.app" "$APP"
# curl does not quarantine what it downloads, but some security tools add the flag to
# everything; clear it so the first launch never stops at Gatekeeper.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

open "$APP"
echo "Done. NotchFun is in your menu bar and your notch."
