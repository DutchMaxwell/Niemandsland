#!/usr/bin/env bash
# Readability gate of the ruin town: captures the play camera of N boards with the army placeholders, scores every model's contrast against its surroundings
# (tools/boardgen/bg_capture_town.gd, `baseline=1`), REPEATS times, for every yaw and preset. Rows are summarised by tools/boardgen/gate_rows.py.
#
#   TAG=after PROJECT=/path/to/worktree tools/boardgen/gate_run.sh          # the town under test
#   TAG=base  PROJECT=/path/to/worktree EXTRA=board=none tools/boardgen/gate_run.sh   # the baseline: the same spots on the bare table (gate change 22.11.)
#   python3 tools/boardgen/gate_rows.py OUT after base                      # the rows; exit 1 when a row is under the bar
#
# Environment: PROJECT (default .), GODOT (the binary, default godot; needs a real display), OUT (default ./gate_out), SEEDS (default 11,13,17,19,23,29,31,37,41,43),
# YAWS (default "0 180": the default player's side and the opposite one), PRESETS (default medium), REPEATS (default 3), EXTRA (default empty: more capture arguments, e.g. sky=town). Anything else the capture needs (for example the
# staged texture libraries NML_RUINTOWN_LIB_DIR / NML_RUINTOWN_KIT_DIR) is inherited from the environment.
set -u
TAG=${TAG:?set TAG}
PROJECT=${PROJECT:-.}
GODOT=${GODOT:-godot}
OUT=${OUT:-./gate_out}
SEEDS=${SEEDS:-11,13,17,19,23,29,31,37,41,43}
YAWS=${YAWS:-"0 180"}
PRESETS=${PRESETS:-medium}
REPEATS=${REPEATS:-3}
EXTRA=${EXTRA:-}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
cd "$PROJECT" || exit 9
for yaw in $YAWS; do
  for r in $(seq 1 "$REPEATS"); do
    dir="$OUT/${TAG}_y${yaw}_r${r}"
    rm -rf "$dir"
    for attempt in 1 2 3 4 5; do   # a display that is busy or a Godot cap: try again
      "$GODOT" --path "$PROJECT" -s "$HERE/bg_capture_town.gd" -- "$dir" baseline=1 only=play $([ "$yaw" = "${YAWS%% *}" ] && echo views=4) "presets=$PRESETS" "seeds=$SEEDS" "yaw=$yaw" $EXTRA > "$OUT/${TAG}_y${yaw}_r${r}.log" 2>&1
      [ -f "$dir/manifest.json" ] && break
      sleep 10
    done
    [ -f "$dir/manifest.json" ] || { echo "capture failed: $dir (see its .log)" >&2; exit 1; }
  done
done
echo "GATE_RUN_DONE $TAG"
