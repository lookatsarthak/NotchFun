#!/bin/zsh
#
# Measures a NotchFun build the same way every time: launch time, idle cost, cost with
# the notch open on each tab, and idle cost again after repeated screen lock cycles,
# which is where uptime leaks show up (1.7.0 fixed one that only appeared after locks).
#
#   scripts/soak.sh [--cycles N] [--phase SECONDS] [--keep] [path/to/NotchFun.app]
#
# With no app path it builds a measurement copy first. The copy runs under its own
# bundle id (…notchfun.freshtest) with its own preferences, so it never touches the
# installed app's settings or permissions. Quit the installed NotchFun first, or both
# notches draw on top of each other (the numbers are still per process).
#
# The build must include SoakHooks (SWIFT_ACTIVE_COMPILATION_CONDITIONS=NOTCHFUN_SOAK),
# which only measurement builds do. Results print as a table and are saved next to the
# copy as soak-<timestamp>.txt.
#
# Pass: idle CPU at or below 0.2% before and after the cycles, memory after cycles within
# 15 MB of fresh, exactly one notch window, all of it with no window left visible-but-dead.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CYCLES=20; PHASE=30; KEEP=false; APP=""
while (( $# )); do
  case "$1" in
    --cycles) CYCLES=$2; shift 2 ;;
    --phase) PHASE=$2; shift 2 ;;
    --keep) KEEP=true; shift ;;
    *) APP=$1; shift ;;
  esac
done

TESTID=io.github.lookatsarthak.notchfun.freshtest
WORK="${${TMPDIR:-/tmp}%/}/notchfun-soak"
mkdir -p "$WORK"

if [[ -z "$APP" ]]; then
  echo "==> Building a measurement copy"
  xcodebuild -project "$ROOT/boringNotch.xcodeproj" -scheme boringNotch -configuration Release \
    -derivedDataPath "$WORK/dd" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS=NOTCHFUN_SOAK build -quiet
  APP="$WORK/dd/Build/Products/Release/NotchFun.app"
fi

echo "==> Preparing the test copy"
COPY="$WORK/NotchFun.app"
rm -rf "$COPY"; ditto "$APP" "$COPY"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $TESTID" "$COPY/Contents/Info.plist"
ENT="$WORK/app.entitlements"
cp "$ROOT/boringNotch/boringNotch.entitlements" "$ENT"
/usr/libexec/PlistBuddy -c "Add :com.apple.security.get-task-allow bool true" "$ENT" 2>/dev/null || true
for f in "$COPY"/Contents/Frameworks/*; do codesign -f -s - "$f" 2>/dev/null || true; done
for x in "$COPY"/Contents/XPCServices/*.xpc; do
  codesign -f -s - --entitlements "$ROOT/BoringNotchXPCHelper/BoringNotchXPCHelper.entitlements" "$x" 2>/dev/null
done
codesign -f -s - --entitlements "$ENT" "$COPY" 2>/dev/null
defaults write $TESTID onboardingCompletedVersion -int 1

LOG="$HOME/Library/Containers/$TESTID/Data/tmp/soak.log"
# A tiny compiled poster: `swift -e` takes seconds per call, too slow for launch timing.
POSTER="$WORK/post"
if [[ ! -x "$POSTER" ]]; then
  cat > "$WORK/post.swift" <<'SWIFT'
import Foundation
let args = CommandLine.arguments
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name(args[1]), object: args.count > 2 ? args[2] : nil, deliverImmediately: true)
SWIFT
  swiftc -O "$WORK/post.swift" -o "$POSTER"
fi
post() { "$POSTER" "$TESTID.soak.$1" ${2:+"$2"}; }
# ps prints [[hh:]mm:]ss.cc of CPU time; convert to milliseconds.
cputime() { ps -o time= -p $PID | awk '{ n = split($1, a, ":"); s = 0; for (i = 1; i <= n; i++) s = s * 60 + a[i]; printf "%d", s * 1000 }'; }
memmb() { top -l 1 -pid $PID -stats mem | tail -1 | tr -d ' +-' | awk '/K$/{printf "%.0f", $0/1024; next} /G$/{printf "%.0f", $0*1024; next} {sub(/M$/,""); print}'; }
RESULTS=()
typeset -A PCT MEM
measure() {  # name
  local a b
  a=$(cputime); sleep $PHASE; b=$(cputime)
  local pct=$(awk -v d=$((b - a)) -v s=$PHASE 'BEGIN { printf "%.2f", d / (s * 10) }')
  local mem=$(memmb)
  PCT[$1]=$pct; MEM[$1]=$mem
  RESULTS+=("$(printf '%-24s %6s%% %6s ms %6s MB' "$1" "$pct" $((b - a)) "$mem")")
  echo "    ${RESULTS[-1]}"
}

# Idle is the median of three windows. One stray burst (a Now Playing update, a battery
# tick, macOS doing something on NotchFun's behalf) turned up in single windows of both the
# 2.0 and the 1.7 builds and failed the gate at random; a steady cost still fails it.
measure_idle() {  # name
  local w=() a b i
  for i in 1 2 3; do a=$(cputime); sleep $PHASE; b=$(cputime); w+=($((b - a))); done
  local median=$(printf '%s\n' $w | sort -n | sed -n 2p)
  local pct=$(awk -v d=$median -v s=$PHASE 'BEGIN { printf "%.2f", d / (s * 10) }')
  local mem=$(memmb)
  PCT[$1]=$pct; MEM[$1]=$mem
  RESULTS+=("$(printf '%-24s %6s%% %6s ms %6s MB   (windows: %s ms)' "$1" "$pct" $median "$mem" "${(j:, :)w}")")
  echo "    ${RESULTS[-1]}"
}

caffeinate -d -u -t $(( PHASE * 12 + CYCLES * 2 + 130 )) &
rm -f "$LOG"
echo "==> Launching"
START=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
open -n "$COPY"
PID=""
for _ in {1..100}; do PID=$(pgrep -f "$COPY/Contents/MacOS/NotchFun" | head -1 || true); [[ -n "$PID" ]] && break; sleep 0.05; done
[[ -n "$PID" ]] || { echo "error: the test copy did not start"; exit 1; }
LAUNCH=""
for _ in {1..200}; do
  post report; sleep 0.05
  if [[ -f "$LOG" ]] && grep -q "notchWindows=[1-9]" "$LOG"; then
    LAUNCH=$(perl -MTime::HiRes=time -e "printf '%.2f', time - $START"); break
  fi
done
echo "    launch to notch window: ${LAUNCH:-unknown} s"
# Let launch work (caches, first Now Playing read, calendar load) finish before "idle".
sleep 20

echo "==> Measuring ($PHASE s per phase)"
measure_idle "idle, fresh"
post open home;      sleep 2; measure "open: home"
post open shelf;     sleep 2; measure "open: shelf"
post open clipboard; sleep 2; measure "open: clipboard"
post close; sleep 3
echo "==> $CYCLES lock cycles"
for _ in $(seq $CYCLES); do post lockcycle; sleep 1.5; done
sleep 8
measure_idle "idle, after $CYCLES locks"
: > "$LOG"; post report; sleep 1
WINDOWS=$(grep -o "notchWindows=[0-9]*" "$LOG" | tail -1 | cut -d= -f2)
# Whether the Now Playing helper delivered anything. Informational: with nothing playing
# anywhere there is nothing to deliver.
NOWPLAYING=$(grep -o "nowPlayingSource=[a-z]*" "$LOG" | tail -1 | cut -d= -f2)

# The bar every release has to clear.
FAILS=()
for phase in "idle, fresh" "idle, after $CYCLES locks"; do
  awk -v p="${PCT[$phase]}" 'BEGIN { exit !(p > 0.2) }' && FAILS+=("$phase CPU ${PCT[$phase]}% > 0.2%")
done
growth=$(( ${MEM["idle, after $CYCLES locks"]:-0} - ${MEM["idle, fresh"]:-0} ))
(( growth > 15 )) && FAILS+=("memory grew ${growth} MB over $CYCLES locks (> 15)")
[[ "${WINDOWS:-}" == 1 ]] || FAILS+=("${WINDOWS:-unknown} notch windows after $CYCLES locks (should be 1)")
if (( ${#FAILS} )); then VERDICT="FAIL: ${(j:; :)FAILS}"; else VERDICT="PASS"; fi

OUT="$WORK/soak-$(date +%Y%m%d-%H%M%S).txt"
{
  # The commit, marked "+changes" when the working tree differs: the release script only
  # accepts a pass for exactly the commit it is publishing.
  echo "NotchFun soak $(defaults read "$COPY/Contents/Info.plist" CFBundleShortVersionString) ($(git -C "$ROOT" rev-parse --short HEAD)$(git -C "$ROOT" diff --quiet HEAD -- boringNotch BoringNotchXPCHelper mediaremote-adapter || echo +changes)), $(sw_vers -productVersion), $(date)"
  echo "launch to notch window: ${LAUNCH:-unknown} s"
  printf '%s\n' "${RESULTS[@]}"
  echo "notch windows after $CYCLES locks: ${WINDOWS:-unknown}"
  echo "Now Playing after $CYCLES locks: ${NOWPLAYING:-unknown}"
  echo "$VERDICT"
} | tee "$OUT"

if ! $KEEP; then
  kill $PID 2>/dev/null || true; sleep 1
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  # Xcode registers what it builds; leave only the installed app registered.
  for a in "$COPY" "$APP" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"; do
    [[ "$a" == "$WORK"/* || "$a" == "$APP"* && "$APP" != /Applications/* ]] && "$LSREGISTER" -u "$a" 2>/dev/null || true
  done
  rm -rf "$COPY"
fi
echo "Saved $OUT"
[[ $VERDICT == PASS ]]
