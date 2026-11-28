#!/usr/bin/env bash
# Run P gdUnit slices side by side on one runner: slices I..I+P-1 of tools/shard_assign.py --shards N.
#   run_shard_group.sh --shards N --first I --procs P
#   run_shard_group.sh --suite-file FILE      one process (slice 0) over the suites listed in FILE (the LOOK short run)
# Each process gets its own user:// (XDG_DATA_HOME=$RUNNER_TEMP/ud<i>), seeded from the restored CDN
# caches by hard links (blobs are immutable and replaced by rename, never written in place), its own
# report dir (reports/slice<i>) and its own log (gdunit_output_<i>.log). Every PID is waited for
# one by one: the script exits 1 if ANY slice exits non-zero or dies by a signal.
set -u
N=""; FIRST=""; PROCS=""; SUITE_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --shards) N="$2"; shift 2 ;;
    --first) FIRST="$2"; shift 2 ;;
    --procs) PROCS="$2"; shift 2 ;;
    --suite-file) SUITE_FILE="$2"; N=1; FIRST=0; PROCS=1; shift 2 ;;
    *) echo "run_shard_group: unknown argument $1" >&2; exit 2 ;;
  esac
done
if [ -z "$N" ] || [ -z "$FIRST" ] || [ -z "$PROCS" ]; then
  echo "usage: run_shard_group.sh --shards N --first I --procs P | --suite-file FILE" >&2; exit 2
fi
SEED="$HOME/.local/share/godot/app_userdata/Niemandsland"
TMPROOT="${RUNNER_TEMP:-/tmp}"
mkdir -p "$SEED"
declare -a PIDS IDX
for ((i = FIRST; i < FIRST + PROCS; i++)); do
  if [ -n "$SUITE_FILE" ]; then [ -s "$SUITE_FILE" ] && cp "$SUITE_FILE" "slice_$i.txt" || { echo "::error::empty or unreadable suite file $SUITE_FILE" >&2; exit 1; }
  else python3 tools/shard_assign.py --shards "$N" --index "$i" > "slice_$i.txt" || exit 1; fi
  echo "slice $i: $(wc -l < "slice_$i.txt") suite(s)"
  UD="$TMPROOT/ud$i/godot/app_userdata/Niemandsland"
  mkdir -p "$UD"
  for d in "$SEED"/*_cache; do
    [ -d "$d" ] && cp -al "$d" "$UD/"
  done
  ARGS=()
  while IFS= read -r suite; do ARGS+=(-a "res://${suite}"); done < "slice_$i.txt"
  NML_LANDING_INVARIANT=1 XDG_DATA_HOME="$TMPROOT/ud$i" godot --headless --path . \
    -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
    --ignoreHeadlessMode -c -rd "reports/slice$i" "${ARGS[@]}" > "gdunit_output_$i.log" 2>&1 &
  PIDS+=("$!"); IDX+=("$i")
done
RC=0
for k in "${!PIDS[@]}"; do
  i="${IDX[$k]}"
  wait "${PIDS[$k]}"; st=$?
  echo "::group::slice $i (exit $st)"; cat "gdunit_output_$i.log"; echo "::endgroup::"
  if [ "$st" -ne 0 ]; then echo "::error::slice $i exited $st"; RC=1; fi
  # LANDING-INVARIANT: the core says "LANDING-GAP" when a step's landings do not explain its end state (the table would keep
  # a model the core removed); any such line fails the group.
  if grep -q "LANDING-GAP" "gdunit_output_$i.log"; then grep "LANDING-GAP" "gdunit_output_$i.log" | sed 's/^/::error::/'; RC=1; fi
  UD="$TMPROOT/ud$i/godot/app_userdata/Niemandsland"
  for d in "$UD"/*_cache; do
    [ -d "$d" ] && cp -rn "$d" "$SEED/"
  done
done
exit "$RC"
