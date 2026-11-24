#!/usr/bin/env bash
# Acceptance sheets of the ruin town against a look target: captures the six acceptance cameras of the town under test on a REAL display
# (tools/boardgen/bg_capture_town.gd, `baseline=1 presets=medium`, yaw 0: seed 41 overview / top / play / street / fountain_eye, seed 25 wall), then composes them beside the
# target images with tools/boardgen/target_sheet.py. The target images live OUTSIDE the repo; their folder is an argument.
#
#   OUT=/tmp/sheet TARGETS=/path/to/targets PROJECT=/path/to/worktree tools/boardgen/target_run.sh
#
# Environment: OUT (required), TARGETS (required), PROJECT (default .), GODOT (default godot; needs a real display), EXTRA (default empty: more capture arguments, e.g. sky=town).
# Result artefact: OUT/sheet_all.jpg (written last). Stills: OUT/cap_s41, OUT/cap_s25 (each with its manifest.json); OUT/sha.txt = the commit captured.
set -u
OUT=${OUT:?set OUT}
TARGETS=${TARGETS:?set TARGETS}
PROJECT=${PROJECT:-.}
GODOT=${GODOT:-godot}
EXTRA=${EXTRA:-}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
rm -f "$OUT/sheet_all.jpg"
sha=$(git -C "$PROJECT" rev-parse --short HEAD)
git -C "$PROJECT" diff --quiet HEAD -- || sha="$sha+dirty"
echo "$sha" > "$OUT/sha.txt"
cd "$PROJECT" || exit 9
capture() {   # capture <dir> <seeds> <cameras>
  rm -rf "$1"
  for attempt in 1 2 3; do   # a display that is busy: try again
    # shellcheck disable=SC2086
    "$GODOT" --path "$PROJECT" -s "$HERE/bg_capture_town.gd" -- "$1" baseline=1 presets=medium yaw=0 "seeds=$2" "only=$3" $EXTRA > "$1.log" 2>&1
    [ -f "$1/manifest.json" ] && return 0
    sleep 10
  done
  echo "capture failed: $1 (see $1.log)" >&2
  exit 1
}
capture "$OUT/cap_s41" 41 overview,top,play,street,fountain   # (fountain also writes fountain_eye)
capture "$OUT/cap_s25" 25 wall
python3 "$HERE/target_sheet.py" "$OUT" "$TARGETS" || exit 1
echo "TARGET_RUN_DONE $sha"
