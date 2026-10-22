#!/bin/bash
# Builds a development copy of RetroHub for this Mac only: build/dev/RetroHub Dev.app.
# It has its own bundle ID, so its settings and cover cache are kept apart from an installed
# RetroHub, and unlike build.sh it is never copied to ~/Applications.
#
#   CONFIG   debug (default; adds `--self-test`) or release
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-debug}"
BUNDLE_ID=io.github.jbutler0831.retrohub.dev
APP="build/dev/RetroHub Dev.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/RetroHub"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RetroHub"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string "RetroHub Dev" "$APP/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "RetroHub Dev" "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($CONFIG, $BUNDLE_ID)"
