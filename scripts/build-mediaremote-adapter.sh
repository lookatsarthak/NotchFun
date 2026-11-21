#!/bin/bash
# Builds mediaremote-adapter (github.com/ungive/mediaremote-adapter) the way NotchFun bundles it:
# a universal, ad-hoc-signed MediaRemoteAdapter.framework, the test client and the Perl script.
# Needs only Xcode's clang, no CMake.
#
# Usage: scripts/build-mediaremote-adapter.sh <adapter source checkout> <output dir> <version>
# Then copy the three outputs over mediaremote-adapter/ and run the soak.
set -euo pipefail
M="$1"; O="$2"; VER="$3"
rm -rf "$O"; mkdir -p "$O"
F="$O/MediaRemoteAdapter.framework"; V="$F/Versions/A"; mkdir -p "$V/Resources"
SRC=()
while read -r s; do SRC+=("$M/$s"); done < <(sed -n '/set(ADAPTER_SOURCES/,/)/p' "$M/CMakeLists.txt" | grep -oE "src/[A-Za-z_/]+\.m")
FLAGS=(-arch x86_64 -arch arm64 -mmacosx-version-min=26.0 -O2 -fobjc-arc)
clang "${FLAGS[@]}" -fvisibility=default -dynamiclib -I"$M/include" -I"$M/src" "${SRC[@]}" \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter -o "$V/MediaRemoteAdapter"
clang "${FLAGS[@]}" -I"$M/src/test" "$M/src/test/main.m" "$M/src/test/NowPlayingTest.m" \
  -framework Foundation -framework MediaPlayer -o "$O/MediaRemoteAdapterTestClient"
cat > "$V/Resources/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>English</string>
<key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
<key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>MediaRemoteAdapter</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>$VER</string>
<key>CFBundleVersion</key><string>$VER</string>
</dict></plist>
PL
ln -s A "$F/Versions/Current"; ln -s Versions/Current/MediaRemoteAdapter "$F/MediaRemoteAdapter"; ln -s Versions/Current/Resources "$F/Resources"
cp "$M/bin/mediaremote-adapter.pl" "$O/"
codesign --force --deep --sign - "$F"; codesign --force --sign - "$O/MediaRemoteAdapterTestClient"
