#!/bin/bash
# Builds a universal (Apple silicon + Intel) RetroHub.app and copies it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

BINS=()
for ARCH in arm64 x86_64; do
    TRIPLE="$ARCH-apple-macosx14.0"
    swift build -c release --triple "$TRIPLE"
    BINS+=("$(swift build -c release --triple "$TRIPLE" --show-bin-path)/RetroHub")
done

APP=build/RetroHub.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/RetroHub"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

mkdir -p ~/Applications
rm -rf ~/Applications/RetroHub.app
cp -R "$APP" ~/Applications/
echo "Installed ~/Applications/RetroHub.app"
