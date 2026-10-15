#!/usr/bin/env bash
# Runs the GUT unit tests headless (no window).
#   tools/run_tests.sh          fast suite (AC-89, under 2 minutes)
#   tools/run_tests.sh --long   long suite: full iteration counts (decision D-20)
# GODOT can point at the pinned 4.7.2-stable binary; default: godot on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
if [[ "${1:-}" == "--long" ]]; then export RTS_LONG=1; fi
# Build the class cache first so class_name scripts resolve in a fresh checkout.
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gexit
