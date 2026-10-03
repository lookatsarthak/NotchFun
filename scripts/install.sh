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

# Anonymous install counts: whether an install starts, finishes, or the step it stopped
# at, with the NotchFun version, chip type and macOS major version. Nothing that
# identifies you or this Mac. Off with NOTCHFUN_NO_ANALYTICS=1 or DO_NOT_TRACK=1, and it
# runs in the background with a 3-second limit, so it never slows or breaks the install.
ping() {
  if [ "${NOTCHFUN_NO_ANALYTICS:-}" = 1 ] || [ "${DO_NOT_TRACK:-}" = 1 ]; then return 0; fi
  curl -fsS -m 3 -o /dev/null "https://notchfun.lookatsarthak.workers.dev/i?$1&a=$(uname -m)&m=$MAJOR" >/dev/null 2>&1 &
}
ping "s=start"

if [ "$MAJOR" -lt 26 ]; then
  ping "s=fail&r=old_macos"
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
if ! curl -fL --progress-bar "$URL" -o "$TMP/NotchFun.dmg"; then
  ping "s=fail&r=download"
  echo "error: the download failed. Check your connection and run the line again." >&2
  exit 1
fi

# Our own mount point, so a NotchFun volume that is already mounted from an earlier
# download cannot shadow this one at /Volumes/NotchFun.
mkdir "$MNT"
if ! hdiutil attach -nobrowse -readonly -quiet -mountpoint "$MNT" "$TMP/NotchFun.dmg"; then
  ping "s=fail&r=mount"
  echo "error: the download could not be opened. Run the line again." >&2
  exit 1
fi

if [ ! -d "$MNT/NotchFun.app" ]; then
  ping "s=fail&r=other"
  echo "error: the download did not contain NotchFun.app" >&2
  exit 1
fi
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MNT/NotchFun.app/Contents/Info.plist" 2>/dev/null || true)

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
if ! { rm -rf "$APP" && ditto "$MNT/NotchFun.app" "$APP"; }; then
  ping "s=fail&r=copy&v=$VERSION"
  echo "error: couldn't copy NotchFun into $DEST." >&2
  exit 1
fi
# curl does not quarantine what it downloads, but some security tools add the flag to
# everything; clear it so the first launch never stops at Gatekeeper.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

if ! open "$APP"; then
  ping "s=fail&r=open&v=$VERSION"
  echo "NotchFun is installed in $DEST but didn't open. Open it from there." >&2
  exit 1
fi
ping "s=ok&v=$VERSION"
echo "Done. NotchFun is in your menu bar and your notch."
