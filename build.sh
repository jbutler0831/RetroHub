#!/bin/bash
# Builds RetroHub.app and copies it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/RetroHub"

APP=build/RetroHub.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/RetroHub"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

mkdir -p ~/Applications
rm -rf ~/Applications/RetroHub.app
cp -R "$APP" ~/Applications/
echo "Installed ~/Applications/RetroHub.app"
