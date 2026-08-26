#!/usr/bin/env bash
# M4 MOVE-CORPUS RECORDER — NML-1073 M4-0a: records planner_v0-vs-planner_v0 arena games (default
# seeds 27..42, 16 games) with NML_CORE=1 + NML_MOVE_DUMP + NML_MOVE_TRACE=1 into
# ~/selfplay_out/m4_corpus/s<seed>/moves_calls.jsonl — the per-plan_unit_step-call corpus M4-0b's
# Rust-port replay-parity gate reads. Runs PARALLEL games at a time (default 2); a seed whose
# s<seed>/moves_calls.jsonl already exists and is non-empty is SKIPPED, so an interrupted run just
# resumes on re-invocation. Every seed's outcome (OK line count / FAIL reason) goes into
# $OUT_DIR/m4_corpus.log.
#
# Usage:   farm/m4_corpus.sh [FIRST_SEED] [LAST_SEED] [PARALLEL]   (defaults: 27 42 2)
# Env:     GODOT_BIN=$HOME/bin/godot                  engine binary (the GDExtension must sit alongside it)
#          ARMY1=/path/to/army1.json                  NML_AI_ARMY1 (default: robot_legions_1000.json)
#          ARMY2=/path/to/army2.json                  NML_AI_ARMY2 (default: blessed_sisters_1000.json)
#          OUT_DIR=$HOME/selfplay_out/m4_corpus        output root (one s<seed>/ subdir per game)
#          SKIP_IMPORT=1                               reuse an existing warm import cache
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$HOME/bin/godot}"
OUT_DIR="${OUT_DIR:-$HOME/selfplay_out/m4_corpus}"
ARMY1="${ARMY1:-$HOME/ai_lists_gf/robot_legions_1000.json}"
ARMY2="${ARMY2:-$HOME/ai_lists_gf/blessed_sisters_1000.json}"
FIRST_SEED="${1:-27}"
LAST_SEED="${2:-42}"
PARALLEL="${3:-2}"

mkdir -p "$OUT_DIR"
LOG="$OUT_DIR/m4_corpus.log"
echo "[M4-CORPUS] repo=$REPO_DIR seeds=$FIRST_SEED..$LAST_SEED parallel=$PARALLEL out=$OUT_DIR" | tee -a "$LOG"

# 1) ONE import pass first (re-import-before-run gotcha) so every game reuses a warm cache.
if [[ "${SKIP_IMPORT:-0}" == "1" ]]; then
	echo "[M4-CORPUS] import pass SKIPPED (SKIP_IMPORT=1)" | tee -a "$LOG"
else
	echo "[M4-CORPUS] import pass (headless editor)…" | tee -a "$LOG"
	timeout 900 "$GODOT_BIN" --headless --editor --quit --path "$REPO_DIR" >"$OUT_DIR/import.log" 2>&1
	if grep -qiE "SCRIPT ERROR|Parse Error|Failed to load script" "$OUT_DIR/import.log"; then
		echo "[M4-CORPUS] FATAL: script/parse errors during import — see $OUT_DIR/import.log" | tee -a "$LOG"
		exit 1
	fi
fi

# 2) One game per seed, up to PARALLEL at a time. Each game's own dir doubles as its resume marker.
record_one() {
	local seed="$1" dir rc
	dir="$OUT_DIR/s${seed}"
	if [[ -s "$dir/moves_calls.jsonl" ]]; then
		echo "[M4-CORPUS] seed $seed SKIP (already recorded)" | tee -a "$LOG"
		return 0
	fi
	mkdir -p "$dir"
	NML_CORE=1 NML_AI_SEED="$seed" NML_AI_P1=planner_v0 NML_AI_P2=planner_v0 \
		NML_AI_ARMY1="$ARMY1" NML_AI_ARMY2="$ARMY2" \
		NML_AI_CAPTURE="$dir" NML_AI_OUT="$dir" NML_AI_BATCH=1 NML_CAPTURE_ACTS=1 \
		NML_MOVE_DUMP="$dir" NML_MOVE_TRACE=1 \
		timeout 600 "$GODOT_BIN" --headless --path "$REPO_DIR" -s res://tools/arena_match.gd \
		>"$dir/run.log" 2>&1
	rc=$?
	if [[ $rc -ne 0 ]]; then
		echo "[M4-CORPUS] seed $seed FAIL (exit $rc / timeout — see $dir/run.log)" | tee -a "$LOG"
	elif [[ -s "$dir/moves_calls.jsonl" ]]; then
		echo "[M4-CORPUS] seed $seed OK ($(wc -l <"$dir/moves_calls.jsonl") lines)" | tee -a "$LOG"
	else
		echo "[M4-CORPUS] seed $seed FAIL (exit 0 but no moves_calls.jsonl — see $dir/run.log)" | tee -a "$LOG"
	fi
}
export -f record_one
export GODOT_BIN REPO_DIR OUT_DIR ARMY1 ARMY2 LOG

seq "$FIRST_SEED" "$LAST_SEED" | xargs -P "$PARALLEL" -I{} bash -c 'record_one "$@"' _ {}

echo "[M4-CORPUS] done — per-seed results in $LOG, games in $OUT_DIR/s<seed>/"
