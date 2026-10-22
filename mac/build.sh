#!/bin/bash
# Builds a universal (Apple silicon + Intel) RetroHub.app, zips it to build/RetroHub.zip
# and copies it to ~/Applications.
#
# Signing (optional, for builds you share):
#   SIGN_IDENTITY   "Developer ID Application: Your Name (TEAMID)". Without it the app is
#                   signed ad hoc, which runs on this Mac but is rejected by Gatekeeper elsewhere.
#   NOTARY_PROFILE  a notarytool keychain profile, created once with
#                   xcrun notarytool store-credentials <profile> --apple-id <you> --team-id <TEAMID>
#                   When set (with SIGN_IDENTITY), the app is notarized and the ticket stapled.
#   INSTALL         0 to leave ~/Applications alone and only build. Development copies:
#                   scripts/dev-build.sh and scripts/dev-run.sh instead.
set -euo pipefail
cd "$(dirname "$0")"

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

BINS=()
for ARCH in arm64 x86_64; do
    TRIPLE="$ARCH-apple-macosx14.0"
    swift build -c release --triple "$TRIPLE"
    BINS+=("$(swift build -c release --triple "$TRIPLE" --show-bin-path)/RetroHub")
done

APP=build/RetroHub.app
ZIP=build/RetroHub.zip
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/RetroHub"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"

if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --options runtime --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
if [ -n "$NOTARY_PROFILE" ]; then
    if [ "$SIGN_IDENTITY" = "-" ]; then
        echo "NOTARY_PROFILE needs SIGN_IDENTITY (a Developer ID certificate)" >&2
        exit 1
    fi
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    spctl --assess --type execute -vv "$APP"
fi

if [ "${INSTALL:-1}" = 0 ]; then
    echo "Built $APP (release zip: $ZIP); not installed"
    exit 0
fi
mkdir -p ~/Applications
rm -rf ~/Applications/RetroHub.app
cp -R "$APP" ~/Applications/
echo "Installed ~/Applications/RetroHub.app (release zip: $ZIP)"
