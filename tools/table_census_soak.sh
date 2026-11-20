#!/usr/bin/env bash
# P4.D-4: soak the runtime table census (CoreActivation.note_legacy, P4.D-3).
# Plays N headless both-AI games (tools/arena_match.gd) over two AI-list directories, each game writing
# NML_TABLE_CENSUS=<OUT>/game_<i>.json, then sums them into <OUT>/census.json: per door and reason the table volley
# count, plus the share of ALL AI volleys (table + core). It ORDERS the allowlist widenings (plan section C).
#
#   tools/table_census_soak.sh [N]       play N games (default 24), then merge
#   tools/table_census_soak.sh merge DIR sum DIR/game_*.json into DIR/census.json, print the top 15 reasons
# Env: LISTS_GF, LISTS_AOF (dirs of <faction>_<points>.json lists; required), SIZES (default "1000 2000"),
#      OUT (default ./census_soak), GODOT (default godot), DRY_RUN=1 (print the commands, play nothing),
#      ARMY_BOOKS_DIR (a snapshot dir of army books, handed to every game as NML_ARMY_BOOKS_DIR: without it the spell and rule texts
#      come from the live API per game, and a flaky answer makes two runs of the SAME games differ in their "takes effect" lines).
set -euo pipefail
cd "$(dirname "$0")/.."

merge() {
	python3 - "$1" <<'PY'
import glob, json, sys
out = sys.argv[1]
legacy, sets, runs, games, shadow = {}, {}, 0, 0, []
for path in sorted(glob.glob(out + "/game_*.json")):
    data = json.load(open(path))
    games += 1
    runs += int(data.get("core_ai_runs", 0))
    shadow += data.get("shadow", [])   # C-5: NML_CORE_SHADOW=1 volley records, concatenated
    for door, reasons in data.get("legacy", {}).items():
        for reason, n in reasons.items():
            legacy.setdefault(door, {})[reason] = legacy.get(door, {}).get(reason, 0) + int(n)
    for door, by_set in data.get("legacy_sets", {}).items():
        for key, n in by_set.items():
            sets.setdefault(door, {})[key] = sets.get(door, {}).get(key, 0) + int(n)
table = legacy.get("ai_volley", {}).get("_all", 0)
total = table + runs
share = {r: round(100.0 * n / total, 1) for r, n in legacy.get("ai_volley", {}).items() if total}
json.dump({"games": games, "core_ai_runs": runs, "ai_volleys": total, "legacy": legacy, "legacy_sets": sets,
           "ai_volley_share_pct": share, **({"shadow": shadow} if shadow else {})}, open(out + "/census.json", "w"), indent=1, sort_keys=True)
print("games %d  ai_volleys %d  on the table %d" % (games, total, table))
for r, n in sorted(legacy.get("ai_volley", {}).items(), key=lambda kv: (-kv[1], kv[0]))[:16]:
    if r != "_all":
        print("%6d  %5.1f %%  %s" % (n, share.get(r, 0.0), r))
PY
}

if [[ "${1:-}" == "merge" ]]; then
	merge "${2:?usage: table_census_soak.sh merge DIR}"
	exit 0
fi

N="${1:-24}"
OUT="${OUT:-census_soak}"
GODOT="${GODOT:-godot}"
read -r -a SIZES <<<"${SIZES:-1000 2000}"
mkdir -p "$OUT"
[[ -n "${ARMY_BOOKS_DIR:-}" ]] || echo "[soak] note: ARMY_BOOKS_DIR is not set - army-book texts come from the live API (a flaky answer shows as a text difference between runs)" >&2
for ((i = 0; i < N; i++)); do
	sys=gf dir="${LISTS_GF:-}"
	if ((i % 2 == 1)); then sys=aof dir="${LISTS_AOF:-}"; fi
	size="${SIZES[$(((i / 2) % ${#SIZES[@]}))]}"
	mapfile -t files < <(ls "$dir"/*_"$size".json 2>/dev/null | sort)
	if ((${#files[@]} < 2)); then
		[[ "${DRY_RUN:-0}" == "1" ]] || { echo "need >= 2 lists named *_$size.json in LISTS_${sys^^} ('$dir')" >&2; exit 2; }
		files=("$dir/first_$size.json" "$dir/second_$size.json")
	fi
	a="${files[$((i % ${#files[@]}))]}" b="${files[$(((i + 1) % ${#files[@]}))]}"
	cmd=(env NML_AI_SEED=$((i + 1)) NML_AI_ARMY1="$a" NML_AI_ARMY2="$b" NML_AI_OUT="$OUT/arena"
		NML_TABLE_CENSUS="$OUT/game_$i.json" ${ARMY_BOOKS_DIR:+NML_ARMY_BOOKS_DIR="$ARMY_BOOKS_DIR"} systemd-run --user --scope -q -p MemoryMax=12G
		"$GODOT" --headless --path . -s res://tools/arena_match.gd)
	echo "[soak] game $i ($sys $size pts): ${cmd[*]}"
	[[ "${DRY_RUN:-0}" == "1" ]] || "${cmd[@]}" >"$OUT/game_$i.log" 2>&1
done
[[ "${DRY_RUN:-0}" == "1" ]] || merge "$OUT"
