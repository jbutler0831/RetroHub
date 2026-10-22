#!/bin/bash
# Runs the window checks in UIChecks.swift: builds RetroHub Dev, opens it on the test library for a
# few seconds and saves a picture of the window after each step to build/dev/ui-check. Exits
# non-zero if a check fails.
#
#   RETROHUB_DEV_LIBRARY   games folder to use (default: .devdata/Games, as in dev-run.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/dev/RetroHub Dev.app"
LIBRARY="${RETROHUB_DEV_LIBRARY:-$(cd .. && pwd)/.devdata/Games}"
OUT=build/dev/ui-check

if pgrep -f "$APP/Contents/MacOS/RetroHub" >/dev/null; then
    echo "Quit RetroHub Dev first: the checks open their own window" >&2
    exit 1
fi
# The checks only exist in debug builds.
CONFIG=debug scripts/dev-build.sh
[ -d "$LIBRARY" ] || swift scripts/make-test-library.swift "$LIBRARY"

rm -rf "$OUT"
status=0
# -libraryRoot on the command line applies to this run only; it isn't saved.
"$APP/Contents/MacOS/RetroHub" -libraryRoot "$LIBRARY" --ui-check "$PWD/$OUT" || status=$?
echo "Pictures of each step: mac/$OUT"
exit $status
