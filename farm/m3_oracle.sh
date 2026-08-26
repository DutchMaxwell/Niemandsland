#!/usr/bin/env bash
# NML-1073 M3-0 ORACLE — records the corpus tools/core_selfplay.gd's activation
# recorder wrap (act_recorder.gd) feeds the Python/Rust rebuild: 4 army-list
# pairings x 5 seeds (27..31) = 20 games, each with NML_ACT_DUMP + NML_NODE_DUMP
# (cap 2000) + the result JSON, into its own
# ~/selfplay_out/m3_oracle/<a>_vs_<b>_s<seed>/ directory.
#
# Resumable: a game whose acts.jsonl AND core_s<seed>.json both already exist
# is skipped (SIZE-checked, not just present — a truncated file from a killed
# run re-runs). Games are launched in batches of PARALLEL at once (default 4);
# M3_MAX_BATCHES caps how many batches THIS invocation runs before it stops
# (default 0 = every batch) — re-run the script (its own resumability picks up
# where the last invocation left off) to continue under a watcher.
#
# Usage:  farm/m3_oracle.sh
# Env:    ARMY_DIR=$HOME/ai_lists_gf         army-list source
#         OUT_ROOT=$HOME/selfplay_out/m3_oracle
#         GODOT=$HOME/bin/godot
#         SEEDS="27 28 29 30 31"
#         PARALLEL=4                         games launched at once per batch
#         M3_MAX_BATCHES=0                   0 = every batch; N = stop after N
#         SKIP_IMPORT=1                      reuse an existing warm import cache
#         GAME_TIMEOUT=600                   per-game timeout (seconds)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARMY_DIR="${ARMY_DIR:-$HOME/ai_lists_gf}"
OUT_ROOT="${OUT_ROOT:-$HOME/selfplay_out/m3_oracle}"
GODOT="${GODOT:-$HOME/bin/godot}"
read -r -a SEEDS <<<"${SEEDS:-27 28 29 30 31}"
PARALLEL="${PARALLEL:-4}"
M3_MAX_BATCHES="${M3_MAX_BATCHES:-0}"
GAME_TIMEOUT="${GAME_TIMEOUT:-600}"

# 4 hero-joined 1000pt pairings (robot_legions/blessed_sisters is the M3-0
# byte-identity pair; the other three round out the oracle's faction spread).
PAIRINGS=(
	"robot_legions_1000:blessed_sisters_1000"
	"alien_hives_1000:blood_brothers_1000"
	"change_disciples_1000:wormhole_daemons_of_change_1000"
	"custodian_brothers_1000:dao_union_1000"
)

mkdir -p "$OUT_ROOT"
echo "[M3-ORACLE] repo=$REPO_DIR out=$OUT_ROOT parallel=$PARALLEL max_batches=$M3_MAX_BATCHES"

# 1) ONE import pass first (re-import-before-run gotcha) so every game reuses a warm cache.
if [[ "${SKIP_IMPORT:-0}" == "1" ]]; then
	echo "[M3-ORACLE] import pass SKIPPED (SKIP_IMPORT=1)"
else
	echo "[M3-ORACLE] import pass (headless editor)…"
	timeout 900 "$GODOT" --headless --editor --quit --path "$REPO_DIR" \
		>"$OUT_ROOT/import.log" 2>&1 || true
	if grep -qiE "SCRIPT ERROR|Parse Error|Failed to load script" "$OUT_ROOT/import.log"; then
		echo "[M3-ORACLE] FATAL: script/parse errors during import — see $OUT_ROOT/import.log" >&2
		exit 1
	fi
fi

# 2) Build the job queue: pairing x seed, skipping whatever is already recorded.
jobs=()
for pairing in "${PAIRINGS[@]}"; do
	a="${pairing%%:*}"
	b="${pairing##*:}"
	for seed in "${SEEDS[@]}"; do
		gdir="$OUT_ROOT/${a}_vs_${b}_s${seed}"
		if [[ -s "$gdir/acts.jsonl" && -s "$gdir/core_s${seed}.json" ]]; then
			echo "[M3-ORACLE] SKIP $a vs $b seed=$seed (already recorded)"
			continue
		fi
		jobs+=("$a:$b:$seed")
	done
done
echo "[M3-ORACLE] ${#jobs[@]} game(s) queued"

# 3) One game: its own output dir, its own env, its own log — OK/FAIL on stdout.
run_one() {
	local a="$1" b="$2" seed="$3"
	local gdir="$OUT_ROOT/${a}_vs_${b}_s${seed}"
	mkdir -p "$gdir"
	if NML_ACT_DUMP="$gdir" NML_NODE_DUMP="$gdir" NML_NODE_DUMP_MAX=2000 \
			timeout "$GAME_TIMEOUT" "$GODOT" --headless --path "$REPO_DIR" \
			-s res://tools/core_selfplay.gd -- \
			"army1=$ARMY_DIR/${a}.json" "army2=$ARMY_DIR/${b}.json" \
			"seed=$seed" "games=1" "out=$gdir" \
			>"$gdir/run.log" 2>&1; then
		echo "[M3-ORACLE] OK   $a vs $b seed=$seed"
	else
		echo "[M3-ORACLE] FAIL $a vs $b seed=$seed (see $gdir/run.log)"
	fi
}

# 4) Batches of PARALLEL games at once, M3_MAX_BATCHES of them per invocation.
batch_no=0
i=0
while ((i < ${#jobs[@]})); do
	batch_no=$((batch_no + 1))
	if ((M3_MAX_BATCHES > 0 && batch_no > M3_MAX_BATCHES)); then
		echo "[M3-ORACLE] stopping after $M3_MAX_BATCHES batch(es) (M3_MAX_BATCHES);" \
			"$((${#jobs[@]} - i)) game(s) remain — re-run to continue"
		break
	fi
	pids=()
	batch_jobs=()
	for ((k = 0; k < PARALLEL && i < ${#jobs[@]}; k++, i++)); do
		IFS=: read -r a b seed <<<"${jobs[$i]}"
		batch_jobs+=("$a vs $b s=$seed")
		run_one "$a" "$b" "$seed" &
		pids+=($!)
	done
	echo "[M3-ORACLE] batch $batch_no: ${batch_jobs[*]}"
	for pid in "${pids[@]}"; do
		wait "$pid"
	done
done
echo "[M3-ORACLE] done"
