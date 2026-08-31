#!/usr/bin/env bash
# NML-1152 step 1 — the pregame fixture runner (deployment-parity design §4.1, §6 step 1).
# Plays NO games: it drives tools/arena_match.gd's `dump=pregame` mode over the PINNED D7 pairing
# table — one faction pair per seed at 1000/1500/2000 pts, extracted from the gen4_ab_fleet corpus
# results — for 50 seeds x BOTH seat orders. Seat order = the army lists swapped between P1/P2;
# the grade seats stay fixed because grades never touch the pregame streams. The D7 corpus pins
# 45 seeds (21-65); seeds 66-70 reuse the table's first five rows to round the runner to 50.
# Per run it prints "PREGAME_DUMP <seed> <order> OK|FAIL"; at the end a final count plus a JSON
# integrity check (every dump parses, every field non-null, probe_hits present). Exit != 0 on any gap.
#
# Env overrides (all optional, private-safe: no secrets, $HOME-relative defaults):
#   NML_PREGAME_GODOT   godot binary                (default $HOME/bin/godot)
#   NML_PREGAME_REPO    project dir w/ this branch  (default $HOME/openTTS)
#   NML_AI_LISTS_DIR    army-list dir               (default $HOME/nml-mission/farm/ai_lists)
#   NML_PREGAME_OUT     output dir                  (default $HOME/selfplay_out/pregame_fixture)
#   NML_PREGAME_WORKERS parallel dump runs          (default 1)
set -uo pipefail
GODOT="${NML_PREGAME_GODOT:-$HOME/bin/godot}"
REPO="${NML_PREGAME_REPO:-$HOME/openTTS}"
LISTS="${NML_AI_LISTS_DIR:-$HOME/nml-mission/farm/ai_lists}"
OUT="${NML_PREGAME_OUT:-$HOME/selfplay_out/pregame_fixture}"
WORKERS="${NML_PREGAME_WORKERS:-1}"
mkdir -p "$OUT"

TABLE='21 robot_legions battle_brothers 2000
22 change_disciples blessed_sisters 1000
23 blood_brothers robot_legions 1500
24 alien_hives blood_brothers 2000
25 battle_brothers alien_hives 1000
26 blessed_sisters battle_brothers 1500
27 robot_legions blessed_sisters 2000
28 change_disciples robot_legions 1000
29 blood_brothers change_disciples 1500
30 alien_hives robot_legions 2000
31 battle_brothers change_disciples 1000
32 blessed_sisters blood_brothers 1500
33 robot_legions alien_hives 2000
34 change_disciples battle_brothers 1000
35 blood_brothers blessed_sisters 1500
36 alien_hives battle_brothers 2000
37 battle_brothers blessed_sisters 1000
38 blessed_sisters robot_legions 1500
39 robot_legions change_disciples 2000
40 change_disciples blood_brothers 1000
41 blood_brothers alien_hives 1500
42 alien_hives blessed_sisters 2000
43 battle_brothers robot_legions 1000
44 blessed_sisters change_disciples 1500
45 robot_legions blood_brothers 2000
46 change_disciples alien_hives 1000
47 blood_brothers battle_brothers 1500
48 alien_hives robot_legions 2000
49 battle_brothers change_disciples 1000
50 blessed_sisters blood_brothers 1500
51 robot_legions alien_hives 2000
52 change_disciples battle_brothers 1000
53 blood_brothers blessed_sisters 1500
54 alien_hives change_disciples 2000
55 battle_brothers blood_brothers 1000
56 blessed_sisters alien_hives 1500
57 robot_legions battle_brothers 2000
58 change_disciples blessed_sisters 1000
59 blood_brothers robot_legions 1500
60 alien_hives blood_brothers 2000
61 battle_brothers alien_hives 1000
62 blessed_sisters battle_brothers 1500
63 robot_legions blessed_sisters 2000
64 change_disciples robot_legions 1000
65 blood_brothers change_disciples 1500
66 robot_legions battle_brothers 2000
67 change_disciples blessed_sisters 1000
68 blood_brothers robot_legions 1500
69 alien_hives blood_brothers 2000
70 battle_brothers alien_hives 1000'

run_one() {
	local seed="$1" fa="$2" fb="$3" pts="$4" order="$5"
	local a1="$LISTS/${fa}_${pts}.json" a2="$LISTS/${fb}_${pts}.json"
	if [[ ! -f "$a1" || ! -f "$a2" ]]; then
		echo "PREGAME_DUMP $seed $order FAIL (list missing: $a1 / $a2)"
		return 1
	fi
	[[ "$order" == "b" ]] && { local t="$a1"; a1="$a2"; a2="$t"; }
	# Resume-safe: a dump already on disk (earlier interrupted run, same code) is not re-run.
	local fexpect="$OUT/pregame_$(basename "$a1" .json)_vs_$(basename "$a2" .json)_s${seed}.json"
	if [[ -f "$fexpect" ]]; then
		echo "PREGAME_DUMP $seed $order SKIP (exists)"
		return 0
	fi
	local log="$OUT/log_s${seed}_${order}.log"
	NML_OBJECTIVES=rulebook timeout 900 "$GODOT" --headless --path "$REPO" \
		-s res://tools/arena_match.gd -- p1=planner_v0 p2=planner_v1 \
		seed="$seed" dice_seed="$seed" out="$OUT" army1="$a1" army2="$a2" \
		symmetric=1 "layout_seed=$((500000 + seed))" "dump=$OUT" > "$log" 2>&1
	if grep -q "^PREGAME_DUMP $seed .* OK$" "$log"; then
		echo "PREGAME_DUMP $seed $order OK"
		return 0
	fi
	echo "PREGAME_DUMP $seed $order FAIL (log: $log)"
	return 1
}

while read -r seed fa fb pts; do
	[[ -z "$seed" ]] && continue
	for order in a b; do
		while [[ "$(jobs -rp | wc -l)" -ge "$WORKERS" ]]; do wait -n; done
		run_one "$seed" "$fa" "$fb" "$pts" "$order" &
	done
done <<< "$TABLE"
wait

N=$(ls "$OUT"/pregame_*.json 2>/dev/null | wc -l)
BAD=$(python3 - "$OUT" <<'PY'
import json, glob, sys
bad = 0
for f in sorted(glob.glob(sys.argv[1] + "/pregame_*.json")):
	try:
		d = json.load(open(f))
		keys = ["schema", "tool", "seed", "dice_seed", "layout_seed", "git_head", "armies",
			"symmetric", "roll_off_attempts", "opener", "deploy_order", "sides"]
		ok = all(k in d and d[k] is not None for k in keys) and all(
			s.get("probe_hits") is not None and isinstance(s.get("units"), list)
			for s in (d.get("sides") or {}).values())
		if not ok:
			bad += 1
			print("BAD:", f)
	except Exception:
		bad += 1
		print("BAD:", f)
print(bad)
PY
)
echo "PREGAME_FIXTURE_DONE dumps=$N want=100 invalid=$BAD"
[[ "$N" -eq 100 && "$BAD" -eq 0 ]]
