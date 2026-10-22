#!/bin/bash
# Builds build/dev/RetroHub Dev.app from the current source and opens it with its games folder set
# to a test library, so ~/Games and an installed RetroHub's settings are never touched.
#
#   RETROHUB_DEV_LIBRARY   games folder to use (default: .devdata/Games at the repository root,
#                          filled with sample files by scripts/make-test-library.swift on first run)
#
# The games folder is only set when the dev app has none yet, or when RETROHUB_DEV_LIBRARY is
# given, so changing it in Setup sticks between runs. Output goes to build/dev/logs.
#
# Arguments are passed to the app:
#   scripts/dev-run.sh --controller-diagnostics   also opens Controller Diagnostics, which shows
#                                                 and logs what each controller press did
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID=io.github.jbutler0831.retrohub.dev
APP="build/dev/RetroHub Dev.app"
LIBRARY="${RETROHUB_DEV_LIBRARY:-$(cd .. && pwd)/.devdata/Games}"
LOG="build/dev/logs/RetroHub-Dev-$(date +%Y%m%d-%H%M%S).log"

# Never a second copy: both would save favorites and recents to one settings file, each
# overwriting the other. Checked before building, which replaces the app.
if pgrep -f "$APP/Contents/MacOS/RetroHub" >/dev/null; then
    open "$APP"
    echo "$APP is already running; brought it to the front (quit it first to run the latest build)"
    exit 0
fi

scripts/dev-build.sh
[ -d "$LIBRARY" ] || swift scripts/make-test-library.swift "$LIBRARY"

if [ -n "${RETROHUB_DEV_LIBRARY:-}" ] || ! defaults read "$BUNDLE_ID" libraryRoot >/dev/null 2>&1; then
    defaults write "$BUNDLE_ID" libraryRoot -string "$LIBRARY"
fi

mkdir -p "$(dirname "$LOG")"
if [ $# -gt 0 ]; then
    open --stdout "$PWD/$LOG" --stderr "$PWD/$LOG" "$APP" --args "$@"
else
    open --stdout "$PWD/$LOG" --stderr "$PWD/$LOG" "$APP"
fi
echo "Opened $APP"
echo "  games folder: $(defaults read "$BUNDLE_ID" libraryRoot)"
echo "  log:          mac/$LOG"
