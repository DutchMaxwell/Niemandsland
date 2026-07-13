#!/usr/bin/env bash
# Batch self-play runner: run N diverse AI-vs-AI games (seeds 1..N) through
# tools/solo_selfplay.gd headless, then AGGREGATE the per-game result JSONs into
# ~/selfplay_out/batch_summary.json and print a concise table. This is the
# prerequisite for an overnight fix-measure loop.
#
# Usage:   tools/selfplay_batch.sh [N] [DICE_SEED]   (default N=3; DICE_SEED optional)
# Env:     GODOT_APP=org.godotengine.Godot    flatpak app id
#          SELFPLAY_OUT=$HOME/selfplay_out    output directory
#          SKIP_IMPORT=1                       reuse an existing warm import cache
#          DICE_SEED=<n>                       same as the 2nd positional arg
#
# Each game varies terrain / deployment / AI section-pick by seed (fully
# deterministic per (seed, dice_seed) pair), writing game_NNN_* outputs.
# DICE_SEED holds ONE fixed dice-tray stream across all N boards (omitted =>
# dice seed derives from each game seed, the original behaviour).
set -euo pipefail

N="${1:-3}"
DICE_SEED="${2:-${DICE_SEED:-}}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${SELFPLAY_OUT:-$HOME/selfplay_out}"
GODOT_APP="${GODOT_APP:-org.godotengine.Godot}"
FLATPAK=(flatpak run --filesystem=home --share=network "$GODOT_APP")

mkdir -p "$OUT_DIR"
echo "[BATCH] repo=$REPO_DIR  games=$N  dice_seed=${DICE_SEED:-derived}  out=$OUT_DIR"

# 1) ONE import pass first (re-import-before-run gotcha): a headless editor pass
#    imports resources + compiles every script, so the N runs reuse a warm cache.
if [[ "${SKIP_IMPORT:-0}" == "1" ]]; then
	echo "[BATCH] import pass SKIPPED (SKIP_IMPORT=1)"
else
	echo "[BATCH] import pass (headless editor)…"
	"${FLATPAK[@]}" --headless --editor --quit --path "$REPO_DIR" \
		>"$OUT_DIR/batch_import.log" 2>&1 || true
	if grep -qiE "SCRIPT ERROR|Parse Error|Failed to load script" "$OUT_DIR/batch_import.log"; then
		echo "[BATCH] FATAL: script/parse errors during import — see $OUT_DIR/batch_import.log" >&2
		grep -iE "SCRIPT ERROR|Parse Error|Failed to load script" "$OUT_DIR/batch_import.log" | head >&2
		exit 1
	fi
fi

# 2) N games, seeds 1..N, reusing the warm import cache.
for ((s = 1; s <= N; s++)); do
	out=$(printf "game_%03d" "$s")
	game_args=(seed="$s" out="$out")
	if [[ -n "$DICE_SEED" ]]; then
		game_args+=(dice_seed="$DICE_SEED")
	fi
	echo "[BATCH] game seed=$s dice_seed=${DICE_SEED:-derived} -> $out"
	rm -f "$OUT_DIR/${out}_result.json"
	if ! "${FLATPAK[@]}" --headless --path "$REPO_DIR" \
		-s res://tools/solo_selfplay.gd -- "${game_args[@]}" \
		>"$OUT_DIR/${out}_run.log" 2>&1; then
		echo "[BATCH] WARN: seed $s exited non-zero (see ${out}_run.log)"
	fi
done

# 3) Aggregate every per-game result JSON -> batch_summary.json + a printed table.
python3 - "$N" "$OUT_DIR" <<'PY'
import json, sys, os

N = int(sys.argv[1]); out_dir = sys.argv[2]
games = []
for s in range(1, N + 1):
    p = os.path.join(out_dir, "game_%03d_result.json" % s)
    if not os.path.exists(p):
        games.append({"seed": s, "out": "game_%03d" % s, "missing": True})
        continue
    with open(p) as f:
        games.append(json.load(f))

agg_viol = {}
tot = {"viol": 0, "seizes": 0, "p1": 0, "p2": 0, "neutral": 0, "decisive": 0, "draw": 0}
present = [g for g in games if not g.get("missing")]
for g in present:
    v = g.get("violations", {})
    tot["viol"] += int(v.get("total", 0))
    for k, c in (v.get("by_kind") or {}).items():
        agg_viol[k] = agg_viol.get(k, 0) + int(c)
    o = g.get("objectives", {})
    tot["p1"] += int(o.get("p1", 0)); tot["p2"] += int(o.get("p2", 0)); tot["neutral"] += int(o.get("neutral", 0))
    tot["seizes"] += int(g.get("seize_events", 0))
    tot["draw" if str(g.get("verdict", "")).startswith("Draw") else "decisive"] += 1

summary = {
    "games_requested": N,
    "games_completed": len(present),
    "aggregate": {
        "violations_total": tot["viol"],
        "violations_by_kind": agg_viol,
        "seize_events_total": tot["seizes"],
        "objectives_held": {"p1": tot["p1"], "p2": tot["p2"], "neutral": tot["neutral"]},
        "decisive": tot["decisive"],
        "draws": tot["draw"],
    },
    "games": games,
}
sp = os.path.join(out_dir, "batch_summary.json")
with open(sp, "w") as f:
    json.dump(summary, f, indent=2)

print()
print("==== SELF-PLAY BATCH SUMMARY (%d/%d games completed) ====" % (len(present), N))
print("%-10s %5s %6s %7s %12s %12s %4s %4s %5s %7s %5s  %s" % (
    "game", "seed", "dseed", "terrain", "terrain_fp", "deploy_fp", "P1", "P2", "neut", "seizes", "viol", "verdict"))
for g in games:
    if g.get("missing"):
        print("%-10s %5s   MISSING result.json (run failed)" % (g["out"], g["seed"]))
        continue
    o = g.get("objectives", {})
    print("%-10s %5s %6s %7s %12s %12s %4s %4s %5s %7s %5s  %s" % (
        g.get("out"), g.get("seed"),
        str(g.get("dice_seed", "-"))[:6] if g.get("dice_seed_explicit") else "der",
        g.get("terrain_pieces"),
        str(g.get("terrain_fingerprint", "-"))[:12], str(g.get("deploy_fingerprint", "-"))[:12],
        o.get("p1"), o.get("p2"), o.get("neutral"),
        g.get("seize_events"), g.get("violations", {}).get("total"),
        str(g.get("verdict", "-"))[:34]))
# Diversity self-check: distinct terrain/deploy fingerprints across the completed games.
tfp = {g.get("terrain_fingerprint") for g in present}
dfp = {g.get("deploy_fingerprint") for g in present}
print("DIVERSITY: %d/%d distinct terrain boards, %d/%d distinct deployments" % (
    len(tfp), len(present), len(dfp), len(present)))
print("-" * 58)
print("AGGREGATE violations: %d total" % tot["viol"])
for k in sorted(agg_viol):
    print("  %-34s %d" % (k, agg_viol[k]))
if not agg_viol:
    print("  (none across all audited classes)")
print("AGGREGATE seizes: %d   objectives held  P1=%d  P2=%d  neutral=%d" % (
    tot["seizes"], tot["p1"], tot["p2"], tot["neutral"]))
print("VERDICTS: %d decisive / %d draw (of %d completed)" % (
    tot["decisive"], tot["draw"], len(present)))
print("batch_summary.json -> %s" % sp)
PY
