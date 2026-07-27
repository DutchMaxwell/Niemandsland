#!/usr/bin/env bash
# AI RATING LADDER — round-robin the four difficulty grades (rekrut, veteran,
# kriegsherr, albtraum) through tools/arena_match.gd: 6 pairings, each played
# TWICE with sides swapped (a structural second-player advantage exists — the
# last activation of a round seizes markers unpunished — so single-sided games
# are biased). Fixed seed => same board/deployment/roll-off in both games of a
# pairing; fixed dice_seed => same dice stream. Afterwards AGGREGATE every
# arena result JSON in the out dir into a win-rate matrix + monotonicity check
# (albtraum >= kriegsherr >= veteran >= rekrut).
#
# Usage:   tools/arena_ladder.sh [SEED] [DICE_SEED]   (defaults: SEED=7, DICE_SEED=SEED)
# Env:     GODOT_APP=org.godotengine.Godot    flatpak app id
#          ARENA_OUT=$HOME/selfplay_out       output directory
#          SKIP_IMPORT=1                      reuse an existing warm import cache
#          PAIRINGS="rekrut:veteran ..."      run only these pairings (both orders each)
#          NML_AI_ARMY1 / NML_AI_ARMY2        army-list overrides (passed through)
#
# Run it again with a second DICE_SEED to thicken the sample — the aggregation
# step folds in every arena_*.json it finds.
set -euo pipefail

SEED="${1:-7}"
DICE_SEED="${2:-$SEED}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ARENA_OUT:-$HOME/selfplay_out}"
GODOT_APP="${GODOT_APP:-org.godotengine.Godot}"
FLATPAK=(flatpak run --filesystem=home --share=network "$GODOT_APP")
GRADES=(rekrut veteran kriegsherr albtraum)

mkdir -p "$OUT_DIR"
echo "[LADDER] repo=$REPO_DIR seed=$SEED dice_seed=$DICE_SEED out=$OUT_DIR"

# 1) ONE import pass first (re-import-before-run gotcha) so every game reuses a warm cache.
if [[ "${SKIP_IMPORT:-0}" == "1" ]]; then
	echo "[LADDER] import pass SKIPPED (SKIP_IMPORT=1)"
else
	echo "[LADDER] import pass (headless editor)…"
	"${FLATPAK[@]}" --headless --editor --quit --path "$REPO_DIR" \
		>"$OUT_DIR/ladder_import.log" 2>&1 || true
	if grep -qiE "SCRIPT ERROR|Parse Error|Failed to load script" "$OUT_DIR/ladder_import.log"; then
		echo "[LADDER] FATAL: script/parse errors during import — see $OUT_DIR/ladder_import.log" >&2
		exit 1
	fi
fi

# 2) The 6 round-robin pairings, each in BOTH side orders (12 games), sequential.
if [[ -n "${PAIRINGS:-}" ]]; then
	read -r -a pairs <<<"$PAIRINGS"
else
	pairs=()
	for ((i = 0; i < ${#GRADES[@]}; i++)); do
		for ((j = i + 1; j < ${#GRADES[@]}; j++)); do
			pairs+=("${GRADES[$i]}:${GRADES[$j]}")
		done
	done
fi
game_no=0
total=$((${#pairs[@]} * 2))
for pair in "${pairs[@]}"; do
	a="${pair%%:*}"
	b="${pair##*:}"
	for order in "$a:$b" "$b:$a"; do
		p1="${order%%:*}"
		p2="${order##*:}"
		game_no=$((game_no + 1))
		log="$OUT_DIR/arena_${p1}_vs_${p2}_s${SEED}_d${DICE_SEED}.log"
		echo "[LADDER] game $game_no/$total: $p1 (P1) vs $p2 (P2) seed=$SEED dice=$DICE_SEED"
		rm -f "$OUT_DIR/arena_${p1}_vs_${p2}_s${SEED}_d${DICE_SEED}.json"
		if ! NML_AI_TRACE=1 timeout "${GAME_TIMEOUT:-1500}" "${FLATPAK[@]}" --headless --path "$REPO_DIR" \
			-s res://tools/arena_match.gd -- \
			"p1=$p1" "p2=$p2" "seed=$SEED" "dice_seed=$DICE_SEED" "out=$OUT_DIR" \
			>"$log" 2>&1; then
			echo "[LADDER] WARN: game exited non-zero/timed out (see $(basename "$log"))"
		fi
	done
done

# 3) Aggregate EVERY arena_*.json in the out dir → win-rate matrix + monotonicity verdict.
python3 - "$OUT_DIR" <<'PY'
import glob, json, os, sys

out_dir = sys.argv[1]
ladder = ["rekrut", "veteran", "kriegsherr", "albtraum"]
games = []
for p in sorted(glob.glob(os.path.join(out_dir, "arena_*.json"))):
    with open(p) as f:
        g = json.load(f)
    if g.get("tool") == "arena_match":
        g["_file"] = os.path.basename(p)
        games.append(g)
if not games:
    print("[LADDER] no arena result JSONs found in", out_dir)
    sys.exit(0)

# points[a][b] = points grade a scored against grade b (win 1 / draw 0.5); n[a][b] = games played.
points = {a: {b: 0.0 for b in ladder} for a in ladder}
n = {a: {b: 0 for b in ladder} for a in ladder}
side_wins = {"p1": 0, "p2": 0, "draw": 0}
for g in games:
    a, b = g["grades"]["p1"], g["grades"]["p2"]
    if a == b or a not in ladder or b not in ladder:
        continue
    w = g.get("winner", "draw")
    side_wins[w if w in side_wins else "draw"] += 1
    n[a][b] += 1
    n[b][a] += 1
    if w == "p1":
        points[a][b] += 1.0
    elif w == "p2":
        points[b][a] += 1.0
    else:
        points[a][b] += 0.5
        points[b][a] += 0.5

print()
print("==== RATING LADDER — win-rate matrix (row grade's points vs column, of games played) ====")
hdr = "%-12s" % "" + "".join("%-16s" % c for c in ladder) + "%8s" % "total"
print(hdr)
totals = {}
for a in ladder:
    row = "%-12s" % a
    tp = tn = 0
    for b in ladder:
        if a == b:
            row += "%-16s" % "-"
        else:
            row += "%-16s" % ("%.1f / %d" % (points[a][b], n[a][b]))
            tp += points[a][b]
            tn += n[a][b]
    totals[a] = (tp, tn)
    row += "%8s" % ("%.1f/%d" % (tp, tn))
    print(row)

dec = side_wins["p1"] + side_wins["p2"]
print()
print("Side advantage (all %d graded games): P1-side wins %d, P2-side wins %d, draws %d"
      % (len(games), side_wins["p1"], side_wins["p2"], side_wins["draw"]))

# Monotonicity: (a) every pairing — the higher grade scores >= the lower; (b) total score ordering.
violations = []
for i, lo in enumerate(ladder):
    for hi in ladder[i + 1:]:
        if n[hi][lo] and points[hi][lo] < points[lo][hi]:
            violations.append("%s scored %.1f < %s %.1f over %d games"
                              % (hi, points[hi][lo], lo, points[lo][hi], n[hi][lo]))
# Compare normalized WIN RATES (points per game), not raw points — pairings can carry extra
# dice-seed samples, so raw totals across unequal game counts would flag spurious "violations".
rate = {g: (totals[g][0] / totals[g][1] if totals[g][1] else None) for g in ladder}
order_ok = all(rate[ladder[i]] <= rate[ladder[i + 1]] + 1e-9
               for i in range(len(ladder) - 1)
               if rate[ladder[i]] is not None and rate[ladder[i + 1]] is not None)
print("MONOTONICITY:", "OK — every higher grade >= lower per pairing" if not violations
      else "VIOLATED: " + "; ".join(violations))
print("WIN-RATE ORDER (rekrut <= veteran <= kriegsherr <= albtraum):",
      "OK" if order_ok else "VIOLATED",
      " ".join("%s=%.2f" % (g, rate[g]) for g in ladder if rate[g] is not None))

with open(os.path.join(out_dir, "ladder_summary.json"), "w") as f:
    json.dump({"games": len(games), "points": points, "games_played": n,
               "totals": {k: {"points": v[0], "games": v[1]} for k, v in totals.items()},
               "side_wins": side_wins, "pairwise_violations": violations,
               "win_rate_order_ok": order_ok, "win_rates": rate,
               "files": [g["_file"] for g in games]}, f, indent=2)
print("ladder_summary.json ->", os.path.join(out_dir, "ladder_summary.json"))
PY
