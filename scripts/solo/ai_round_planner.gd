class_name AiRoundPlanner
extends RefCounted
## NACHTMAHR round planner (NML-210) — the PURE global-assignment core that replaces the per-unit
## greedy objective pick for the ONE grade. Architecture decision 2026-07-22 (data-backed by the
## Schmiede baseline: 82% of marker approaches arrived short, 45% of moves congested): the tree
## decided each activation LOCALLY, so nobody promised arrivals and everybody stacked lanes.
##
## solve(p) assigns every own unit ONE task for the round:
##   {"kind": "seize", "marker": i, "arrive_round": r, "lane": k}   — go take marker i, arrival is
##                                                                    FEASIBLE within the rounds left
##   {"kind": "fight"}                                              — no worthwhile/feasible marker:
##                                                                    the decision tree fights on
## Deterministic (stable sorts, index tie-breaks), side-effect free, fully unit-testable. The log
## string is the battle-log line — the plan is EXPLAINABLE by construction (rules-must-log).
##
## p = {
##   "units":   [{"key": String, "centre": Vector3, "band_in": float, "ev_best": float}],
##   "markers": [{"index": int, "pos": Vector3, "ai_owned": bool, "enemy_near": int}],
##   "rounds_left": int,          # INCLUDING the current round
##   "current_round": int,
##   "max_per_marker": int = 1,   # anti-congestion: one committed runner per marker …
##   "contest_cap": int = 2,      # … except enemy-held markers, which may take a pair (majority win)
## }

const SEIZE_RING_IN := 3.0
const WORTH_FREE := 2.5        # expected-wounds currency: an unheld marker (mirrors OBJ_SEIZE_WORTH)
const WORTH_ENEMY := 3.5       # flipping an enemy-held marker is a two-point swing
const TIME_COST_PER_ROUND := 0.6
const FIGHT_OPPORTUNITY_W := 0.5    # per MARCH ROUND: a walking gun forfeits this share of its volley


static func solve(p: Dictionary) -> Dictionary:
	var units: Array = p.get("units", [])
	var markers: Array = p.get("markers", [])
	var rounds_left: int = maxi(int(p.get("rounds_left", 1)), 1)
	var max_per: int = maxi(int(p.get("max_per_marker", 1)), 1)
	var contest_cap: int = maxi(int(p.get("contest_cap", 2)), max_per)
	var tasks := {}
	if units.is_empty():
		return {"tasks": tasks, "log": ""}

	# Every feasible (unit, marker) pair with its NET value.
	var pairs: Array = []
	for ui in range(units.size()):
		var u: Dictionary = units[ui]
		var band: float = maxf(float(u.get("band_in", 12.0)), 0.5)
		for m in markers:
			var md: Dictionary = m
			if bool(md.get("ai_owned", false)):
				continue   # already ours — holding is the tree's business, not a trip
			var travel: float = maxf(MoveIntent.distance_inches(u.get("centre", Vector3.ZERO), md.get("pos", Vector3.ZERO)) - SEIZE_RING_IN, 0.0)
			var need: int = maxi(int(ceil(travel / band)), 0)
			# FEASIBILITY PROMISE (the baseline's 82%-short killer): `need` marches happen in rounds
			# current … current+need−1, so the unit stands on the marker at THAT round's end —
			# need ≤ rounds_left is feasible. The old gate (need ≤ rounds_left−1) was off by one:
			# in the FINAL round nothing was ever "feasible" (maintainer log R4: "everyone fights —
			# no feasible marker trip" with a marker one rush away) and the endgame died with it.
			if need > rounds_left:
				continue
			var enemy_near: int = int(md.get("enemy_near", 0))
			var worth: float = WORTH_ENEMY if enemy_near > 0 else WORTH_FREE
			# Every march round costs time AND the volley it forfeits — a live gun only walks when
			# the marker outbids the whole trip's firepower (commander-hold economics, test-pinned).
			# DENIAL ECONOMICS (maintainer 2026-07-23: "die KI findet sich damit ab, dass der Punkt
			# besetzt ist"): marching on an ENEMY-HELD marker walks INTO the fight, not away from
			# one — the trip forfeits no volleys (3.5 − need×0.6). LATE-GAME ONLY (wave5 A/B: the
			# blanket form churned mirror games into neutrals 18/24, the score-gated form was worse
			# 17/24 — both-tied sides deny from round 1; the last-two-rounds form measured best at
			# 20/24 with the baseline's diff): the endgame flip/deny is where the concession hurt.
			var value: float
			if enemy_near > 0 and rounds_left <= 2:
				value = worth - float(need) * TIME_COST_PER_ROUND
			else:
				value = worth - float(need) * (TIME_COST_PER_ROUND \
					+ float(u.get("ev_best", 0.0)) * FIGHT_OPPORTUNITY_W)
			if value <= 0.0:
				continue
			pairs.append({"ui": ui, "marker": int(md.get("index", 0)), "need": need,
				"value": value, "enemy_near": enemy_near})

	# Greedy global assignment: best net value first; stable tie-breaks (value ↓, need ↑, ui ↑, marker ↑).
	pairs.sort_custom(func(a, b) -> bool:
		var ad: Dictionary = a
		var bd: Dictionary = b
		if absf(float(ad["value"]) - float(bd["value"])) > 0.0001:
			return float(ad["value"]) > float(bd["value"])
		if int(ad["need"]) != int(bd["need"]):
			return int(ad["need"]) < int(bd["need"])
		if int(ad["ui"]) != int(bd["ui"]):
			return int(ad["ui"]) < int(bd["ui"])
		return int(ad["marker"]) < int(bd["marker"]))
	var per_marker := {}
	for pr in pairs:
		var pd: Dictionary = pr
		var ui: int = int(pd["ui"])
		var key := str((units[ui] as Dictionary).get("key", ui))
		if tasks.has(key):
			continue
		var mi: int = int(pd["marker"])
		var cap: int = contest_cap if int(pd["enemy_near"]) > 0 else max_per
		var taken: int = int(per_marker.get(mi, 0))
		if taken >= cap:
			continue
		per_marker[mi] = taken + 1
		tasks[key] = {"kind": "seize", "marker": mi,
			# Arrival = the round whose LAST march completes the trip (need 0 or 1 → this round).
			"arrive_round": int(p.get("current_round", 1)) + maxi(int(pd["need"]) - 1, 0),
			"lane": taken}
	for u in units:
		var key2 := str((u as Dictionary).get("key", ""))
		if not tasks.has(key2):
			tasks[key2] = {"kind": "fight"}

	# The explainable plan line (battle log): every seize promise with its arrival round. E1 (test
	# game 1): the line carries unit NAMES, not raw unit ids; E2: an all-fight round says so instead
	# of staying silent (a silent round read like a dead planner).
	var parts: PackedStringArray = []
	for u in units:
		var ud := u as Dictionary
		var key3 := str(ud.get("key", ""))
		var t: Dictionary = tasks.get(key3, {})
		if str(t.get("kind", "")) == "seize":
			parts.append("%s → marker %d (arrives R%d)" % [str(ud.get("name", key3)), int(t["marker"]), int(t["arrive_round"])])
	var log_line := ("NACHTMAHR plan R%d: everyone fights — no feasible marker trip" % int(p.get("current_round", 1))) \
		if parts.is_empty() else "NACHTMAHR plan R%d: %s — everyone else fights" % [
		int(p.get("current_round", 1)), ", ".join(parts)]
	return {"tasks": tasks, "log": log_line}
