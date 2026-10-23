#!/bin/bash
# Prints what can play on this Mac: its hardware, the installed emulators and RetroArch cores,
# and a READY / SETUP_REQUIRED / UNKNOWN / UNSUPPORTED status for each system, with the evidence
# and limits behind it (Sources/RetroHub/Compatibility.swift). Read-only: it changes nothing,
# starts nothing and runs no benchmarks.
#
#   scripts/dev-inventory.sh                      text report
#   scripts/dev-inventory.sh --json               the same as JSON
#   scripts/dev-inventory.sh --include-documents  also reads RetroArch's firmware folder in
#                                                 ~/Documents (macOS may ask to allow it)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -q >&2
"$(swift build --show-bin-path)/RetroHub" --inventory "$@"
