#!/bin/bash
# Runs the window checks in UIChecks.swift in "RetroHub Dev Check", a debug build with its own
# bundle ID. Its settings are wiped before each run (except the relaunch run, which checks the
# appearance the full run saved), so runs start like a first launch, and RetroHub Dev's settings,
# favorites and window are never touched. The window comes to the front
# for about a minute and goes full screen once (couch mode); clicking elsewhere meanwhile makes
# the keyboard and menu checks fail. Pictures of each step go to build/dev/ui-check. Exits
# non-zero if a check fails.
#
#   RETROHUB_DEV_LIBRARY   games folder to use (default: .devdata/Games, as in dev-run.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="RetroHub Dev Check"
BUNDLE_ID=io.github.jbutler0831.retrohub.devcheck
APP="build/dev/$NAME.app"
LIBRARY="${RETROHUB_DEV_LIBRARY:-$(cd .. && pwd)/.devdata/Games}"
OUT=build/dev/ui-check

if pgrep -f "$APP/Contents/MacOS/RetroHub" >/dev/null; then
    echo "Quit $NAME first" >&2
    exit 1
fi
# The checks only exist in debug builds.
CONFIG=debug NAME="$NAME" BUNDLE_ID="$BUNDLE_ID" scripts/dev-build.sh
[ -d "$LIBRARY" ] || swift scripts/make-test-library.swift "$LIBRARY"
rm -rf "$OUT"

status=0
fresh() {
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    rm -rf ~/Library/"Saved Application State/$BUNDLE_ID.savedState"
    rm -f ~/Library/"Application Support/$NAME/library.json"
}
# -libraryRoot and the other arguments apply to this run only. Opened with `open` so macOS brings
# the window to the front: keyboard focus and menu commands only behave normally in the active
# window. Output goes to <name>.log, then to the terminal.
run() {
    local name=$1; shift
    local log="$PWD/$OUT/$name.log"
    mkdir -p "$OUT"
    : > "$log"
    open -W -n --stdout "$log" --stderr "$log" "$APP" --args -libraryRoot "${RUN_LIBRARY:-$LIBRARY}" "$@" &
    local opener=$!
    local waited=0
    while kill -0 "$opener" 2>/dev/null; do
        sleep 1
        waited=$((waited + 1))
        if [ "$waited" -ge 180 ]; then
            pkill -f "$APP/Contents/MacOS/RetroHub" || true
            echo "FAIL: timed out" >> "$log"
        fi
    done
    cat "$log"
    grep -q "^PASS:" "$log" || status=1
}

fresh
run checks --ui-check "$PWD/$OUT"
# With the settings the full run left: it ended on Dark.
echo "Relaunch:"
run relaunch --ui-check "$PWD/$OUT/relaunch" --relaunch
# The sidebar at the other icon sizes in System Settings › Appearance.
echo "Sidebar icon size Small:"
fresh
run small -NSTableViewDefaultSizeMode 1 --ui-check "$PWD/$OUT/small" --rows-only
echo "Sidebar icon size Large:"
fresh
run large -NSTableViewDefaultSizeMode 3 --ui-check "$PWD/$OUT/large" --rows-only
# The Smart Game Scanner changes files, so it gets a copy of the test library.
echo "Library Check:"
fresh
COPY="$(mktemp -d)"
cp -R "$LIBRARY" "$COPY/Games"
RUN_LIBRARY="$COPY/Games" run library --ui-check "$PWD/$OUT/library" --library-check
echo "Library Check after a relaunch:"
RUN_LIBRARY="$COPY/Games" run library-relaunch --ui-check "$PWD/$OUT/library-relaunch" --library-check-relaunch
rm -rf "$COPY"
# A real game: the test pattern in RetroArch for about 12 seconds (skipped without RetroArch and Mesen).
echo "Play time:"
fresh
run playtime --ui-check "$PWD/$OUT/playtime" --playtime-check
fresh

echo "Pictures of each step: mac/$OUT"
exit $status
