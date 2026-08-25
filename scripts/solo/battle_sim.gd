class_name BattleSim
extends RefCounted
## Planner substrate, phase 1: a read-only snapshot of the live game as plain
## data. Static facts (profiles, rules) stay on the referenced GameUnit and are
## never mutated; dynamic facts (positions, wounds, flags, objective owners)
## are copied so expectation rollouts can edit them without touching the scene.
## Positions are metres, world space. Callable seams mirror SoloController's:
## objectives_provider() -> Array[Vector3], objective_owner_of(i) -> int.


const IN2M := 0.0254

## CORE track S1: when set, expected wounds round STOCHASTICALLY (mean-
## preserving: the fraction becomes a probability) instead of carrying a
## fractional ledger — full games get outcome variance without per-die
## simulation (that is S4). Set only via resolve_stochastic().
static var stochastic_rng: RandomNumberGenerator = null

## NML-1068 A/B seam: NML_SIM_SPACING="1"/"on" makes resolve() honour the
## unit-spacing no-go rule (mirrors SoloController._spacing_zones_world) when
## it translates a mover's positions; unset/anything else leaves resolve
## byte-identical to today — the planner substrate keeps its shipped rollouts
## until a never-worse A/B promotes the rule.
static var _spacing_env := -1
static func spacing_enabled() -> bool:
	if _spacing_env < 0:
		var raw := OS.get_environment("NML_SIM_SPACING")
		_spacing_env = 1 if (raw == "1" or raw == "on") else 0
	return _spacing_env == 1

## NML-1069 A/B seam: NML_SIM_CAST="1"/"on" makes resolve() run the cast
## SUB-PHASE (before any attack, every activation); unset/anything else falls
## back to the legacy shoot-rider (spell_ev_of folded into the shoot volley,
## verbatim from dabd1da) — byte-identical to today, so the shipped rollouts
## keep their behaviour until a never-worse A/B promotes the sub-phase.
static var _cast_env := -1
static func cast_phase_enabled() -> bool:
	if _cast_env < 0:
		var raw := OS.get_environment("NML_SIM_CAST")
		_cast_env = 1 if (raw == "1" or raw == "on") else 0
	return _cast_env == 1

## NML-1072: wall-clock profile of the trainer path — env-gated NML_PROFILE=1
## (unset = byte-identical: the hot path pays exactly one cached bool check,
## no extra call). Buckets NEST (resolve/clone/spacing/cast all run INSIDE
## plan_with_rollout's search) — kept as their own totals anyway so a reader
## sees both "search total" and "how much of it is resolve". core_selfplay
## resets/reads this once per game.
static var _profile_env := -1
static func profile_enabled() -> bool:
	if _profile_env < 0:
		var raw := OS.get_environment("NML_PROFILE")
		_profile_env = 1 if (raw == "1" or raw == "on") else 0
	return _profile_env == 1

static var profile := {"plan": 0, "plan_n": 0, "resolve": 0, "resolve_n": 0,
	"clone": 0, "clone_n": 0, "snapshot": 0, "snapshot_n": 0,
	"spacing": 0, "spacing_n": 0, "cast": 0, "cast_n": 0}

static func profile_reset() -> void:
	for k in profile.keys():
		profile[k] = 0

# === Encoder board rows (v5 schema, NML-995) ==================================
# ONE canonical source for the position-net input, used by BOTH the factory
# (core_selfplay corpus) and the in-game encoder eval — a fork here would let
# training and play drift apart silently. Unit rows:
# [player, x_in, z_in, alive, wounds_left, shaken, fatigued, activated,
#  range_max_in, attacks_total, quality, defense, shoot_ev12, melee_ev,
#  6 flag rules, n_rule_pairs, (slot, value)*n] — objective rows are
# [3, x, z, owner, 0*17]. Rules reach the corpus via the committed append-only
# vocabulary (unit slots 0-199, weapon 200-299); unknown rules are collected
# LOUDLY in `unknown_rules` (slot assignment only ever happens centrally).

const EV_REF_DIST_IN := 12.0
const FLAG_RULES: Array[String] = ["Fearless", "Ambush", "Flying", "Stealth", "Furious", "Regeneration"]
const RULE_VOCAB_PATH := "res://data/encoder_rule_vocab_v1.json"
static var _vocab_unit: Dictionary = {}
static var _vocab_weapon: Dictionary = {}
static var _vocab_spell: Dictionary = {}   # v1c: spell book namespace, slots 300+
static var _vocab_loaded := false
static var unknown_rules: Dictionary = {}


static func _load_vocab() -> void:
	if _vocab_loaded:
		return
	_vocab_loaded = true
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULE_VOCAB_PATH))
	if data is Dictionary:
		var ul: Array = data.get("unit", [])
		for i in ul.size():
			_vocab_unit[str(ul[i])] = i
		var wl: Array = data.get("weapon", [])
		for i in wl.size():
			_vocab_weapon[str(wl[i])] = 200 + i
		var sl: Array = data.get("spell", [])
		for i in sl.size():
			_vocab_spell[str(sl[i])] = 300 + i
	else:
		push_warning("BattleSim: rule vocab unreadable at %s" % RULE_VOCAB_PATH)


## "Tough(3)" / {name:"Tough", rating:3} -> ["Tough", 3]
static func _parse_rule(r: Variant) -> Array:
	if r is Dictionary:
		return [str(r.get("name", "")).strip_edges(), int(r.get("rating", 0))]
	var s := str(r).strip_edges()
	var m := RegEx.create_from_string("^(.*?)\\s*\\((\\d+)\\)\\s*$").search(s)
	if m != null:
		return [m.get_string(1), int(m.get_string(2))]
	return [s, 0]


static func _rule_pairs(gu: Variant, od: OPRApiClient.OPRUnit) -> Array:
	_load_vocab()
	var vals := {}
	for r in gu.get_special_rules():
		var pr := _parse_rule(r)
		if pr[0] == "":
			continue
		if _vocab_unit.has(pr[0]):
			var slot: int = _vocab_unit[pr[0]]
			vals[slot] = maxi(int(vals.get(slot, 0)), int(pr[1]) if pr[1] > 0 else 1)
		elif not unknown_rules.has(pr[0]):
			unknown_rules[pr[0]] = true
			push_warning("BattleSim: UNKNOWN unit rule '%s' — not in vocab, stamped into result" % pr[0])
	for w in od.weapons:
		for r in w.special_rules:
			var pr := _parse_rule(r)
			if pr[0] == "":
				continue
			if _vocab_weapon.has(pr[0]):
				var slot: int = _vocab_weapon[pr[0]]
				vals[slot] = maxi(int(vals.get(slot, 0)), maxi(int(pr[1]), 1))
			elif not unknown_rules.has(pr[0]):
				unknown_rules[pr[0]] = true
				push_warning("BattleSim: UNKNOWN weapon rule '%s' — not in vocab, stamped into result" % pr[0])
	# v1c (v5.1): a caster's SPELL BOOK enters the row — (slot 300+, threshold)
	# per known spell; unknown spell names loud-collect exactly like rules.
	if gu.has_method("is_caster") and gu.is_caster():
		for sp in SpellsRegistry.spells_for_unit(gu):
			var spd := sp as Dictionary
			var sn := str(spd.get("name", "")).strip_edges()
			if sn == "":
				continue
			if _vocab_spell.has(sn):
				var slot: int = _vocab_spell[sn]
				vals[slot] = maxi(int(vals.get(slot, 0)), maxi(int(spd.get("threshold", 0)), 1))
			elif not unknown_rules.has("spell:" + sn):
				unknown_rules["spell:" + sn] = true
				push_warning("BattleSim: UNKNOWN spell '%s' — not in vocab, stamped into result" % sn)
	var out: Array = []
	var slots := vals.keys()
	slots.sort()
	for s in slots:
		out.append(int(s))
		out.append(int(vals[s]))
	return out


## Judge-bench sidecar: for each LIVING unit — same filter and order as
## board_rows — its index in the units-dict key order (the game's roster
## order). Logged NEXT TO the rows, never inside them: the v5 number format
## stays untouched, tooling maps rows back to roster names via these ints.
static func board_row_indices(state: Dictionary) -> Array:
	var out: Array = []
	var i := 0
	for k in state["units"]:
		if int((state["units"][k] as Dictionary)["alive"]) > 0:
			out.append(i)
		i += 1
	return out


static func board_rows(state: Dictionary) -> Array:
	var rows: Array = []
	for k in state["units"]:
		var su: Dictionary = state["units"][k]
		if int(su["alive"]) <= 0:
			continue
		var c := Vector3.ZERO
		for p in su["positions"]:
			c += p as Vector3
		c /= float((su["positions"] as Array).size())
		var wl := 0
		for w in su["wounds"]:
			wl += int(w)
		var rmax := 0
		var atk := 0
		var q := 0
		var d := 0
		var sev := 0.0
		var mev := 0.0
		var flags := [0, 0, 0, 0, 0, 0]
		var pairs: Array = []
		var gu: Variant = su.get("unit")
		if gu != null and gu.get("source_data") is OPRApiClient.OPRUnit:
			var od: OPRApiClient.OPRUnit = gu.source_data
			q = od.quality
			d = od.defense
			for w in od.weapons:
				rmax = maxi(rmax, w.range_value)
				atk += w.attacks * maxi(w.count, 1)
			var att: Dictionary = AiEv.ctx_for(gu)
			sev = snappedf(AiEv.shoot_ev(AiShooting.profiles_in_range(od.weapons, EV_REF_DIST_IN),
				att, AiEv.NEUTRAL_DEFENDER.duplicate(), EV_REF_DIST_IN), 0.01)
			mev = snappedf(AiEv.melee_ev(AiShooting.melee_profiles(od.weapons),
				att, AiEv.NEUTRAL_DEFENDER.duplicate(), true), 0.01)
			for i in FLAG_RULES.size():
				if gu.has_special_rule(FLAG_RULES[i]):
					flags[i] = 1
			pairs = _rule_pairs(gu, od)
		var row: Array = [int(su["player"]), snappedf(c.x / IN2M, 0.1),
			snappedf(c.z / IN2M, 0.1), int(su["alive"]), wl,
			1 if bool(su.get("shaken", false)) else 0,
			1 if bool(su.get("fatigued", false)) else 0,
			1 if bool(su.get("activated", false)) else 0,
			rmax, atk, q, d, sev, mev,
			flags[0], flags[1], flags[2], flags[3], flags[4], flags[5],
			pairs.size() / 2]
		row.append_array(pairs)
		rows.append(row)
	for o in state.get("objectives", []):
		var op: Vector3 = (o as Dictionary)["pos"]
		rows.append([3, snappedf(op.x / IN2M, 0.1), snappedf(op.z / IN2M, 0.1),
			int((o as Dictionary).get("owner", 0)),
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	# NML-1012 input v1 — the GAME-STATE row (type 4): round, rounds left,
	# the VP standing and the scoring semantics. The unit stats were already
	# rich; THIS was the net's real blindfold — no endgame sense, no idea
	# whether it is ahead, no clue which currency the mission pays.
	var fl: Dictionary = state.get("vp_flavour", {})
	var sc := str(state.get("scoring", "end"))
	var sc_code := 0
	if sc == "round_vp":
		sc_code = 1
	elif sc == "sabotage":
		sc_code = 2
	var mj := str(fl.get("majority", "end"))
	var mj_code := 0 if mj == "none" else (1 if mj == "end" else 2)
	var vp_live: Array = state.get("vp", [0, 0])
	rows.append([4, int(state.get("round", 1)), int(state.get("rounds_total", 4)),
		int(vp_live[0]) if vp_live.size() == 2 else 0,
		int(vp_live[1]) if vp_live.size() == 2 else 0,
		sc_code, mj_code, 1 if bool(fl.get("first_seize", false)) else 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	return rows


## Round-end marker seize on a SIM STATE — THE BOOK'S RULE, identical to
## SoloController.seize_objectives: one side inside the 3" ring seizes it,
## BOTH sides near makes it NEUTRAL, nobody near leaves the owner alone.
## Shaken units neither seize nor contest.
## Corrected 16.08. It used to award the marker to the MAJORITY of units,
## which is not a rule this game has, and the old docstring said "both sides
## near = neutral" when the code only did that on an exact TIE. Anything
## scored with the old rule — including the factory's fork labels — was
## scored against a game that does not exist.
## Measured the book's way since 16.08.: from the BASE EDGE and HORIZONTALLY
## (MoveIntent.distance_inches ignores height), excluding AIRCRAFT and units
## that arrived from AMBUSH in the current round. capture() carries the base
## radii, the aircraft flag and the ambush arrival ROUND for it — the round
## rather than a precomputed boolean, because a playout advances rounds and
## the lock has to expire with them.
## Mutates `owners` AND writes ownership back into the state's objective
## dicts (eval/features read them).
static func playout_seize(state: Dictionary, owners: Array) -> void:
	var objs: Array = state.get("objectives", [])
	for i in range(objs.size()):
		var op: Vector3 = (objs[i] as Dictionary)["pos"]
		# SIDES PRESENT, NOT BODIES PRESENT. Until 16.08. this counted units and
		# gave the marker to the majority — a rule the game does not have. The
		# book (and SoloController.seize_objectives) says: one side near seizes
		# it, BOTH sides near makes it NEUTRAL, nobody near leaves the owner as
		# it was. The old version paid for crowding a contested marker, which
		# scores exactly nothing on the table, so a policy trained in here would
		# have learned to do the worthless thing well. The simulator follows the
		# rulebook; deviations are not permitted (maintainer, 16.08.).
		var sides := {}
		for k in state["units"]:
			var su: Dictionary = state["units"][k]
			if not can_hold_marker(su, int(state.get("round", 1))):
				continue
			var pid := int(su["player"])
			if sides.has(pid):
				continue
			if control_gap_in(su, op) <= SoloController.OBJECTIVE_CONTROL_IN + CONTROL_EPS:
				sides[pid] = true
		if sides.size() == 1:
			owners[i] = int(sides.keys()[0])
		elif sides.size() > 1:
			owners[i] = 0
		(objs[i] as Dictionary)["owner"] = int(owners[i])


## HEAD_QUEUE #12/#13 (rebuilt 23.08.): ONE marker measure for referee AND
## planner. The nearest BASE EDGE gap in inches, measured HORIZONTALLY — the
## same way MoveIntent.distance_inches measures for the real check. A 3D
## centre-to-centre measure is a tighter ring than the book's, and on elevated
## terrain it is a different ring altogether: a model 2" out on a 5" roof read
## 5.4" and silently stopped counting as a holder.
static func control_gap_in(su: Dictionary, obj_pos: Vector3) -> float:
	var ps: Array = su.get("positions", [])
	if ps.is_empty():
		return INF
	var radii: Array = su.get("radii", [])
	var best := INF
	for pi in range(ps.size()):
		var dp: Vector3 = (ps[pi] as Vector3) - obj_pos
		var d_in := Vector3(dp.x, 0.0, dp.z).length() / IN2M
		var r_in: float = (float(radii[pi]) / IN2M) if pi < radii.size() else 0.0
		best = minf(best, d_in - r_in)
	return best


## The referee's eligibility set — who may hold a marker at a round end at all:
## alive, not Shaken, not an Aircraft, and not a unit that arrived from Ambush
## THIS round (GF/AoF v3.5.1 p.13: it may act, it may not seize).
static func can_hold_marker(su: Dictionary, round_no: int) -> bool:
	if int(su.get("alive", 0)) <= 0 or bool(su.get("shaken", false)):
		return false
	if bool(su.get("aircraft", false)):
		return false
	return int(su.get("ambush_arrived_round", -1)) != round_no


## NML-1008 (GF Advanced v3.5.1): cumulative VICTORY POINTS — at the end of
## each round 1 VP per controlled marker; at game end +1 VP for controlling
## more markers. The maintainer's D2 curve ("markers gain value steadily")
## is this rule; every scoring consumer switches to this currency.
static func vp_round_add(owners: Array, vp: Array) -> void:
	for o in owners:
		if int(o) == 1:
			vp[0] += 1
		elif int(o) == 2:
			vp[1] += 1


static func vp_end_bonus(owners: Array, vp: Array) -> void:
	var m1 := 0
	var m2 := 0
	for o in owners:
		if int(o) == 1:
			m1 += 1
		elif int(o) == 2:
			m2 += 1
	if m1 > m2:
		vp[0] += 1
	elif m2 > m1:
		vp[1] += 1


## NML-1010 W2 — one entry point for every round_vp mission flavour, so the
## live game, the arena and the planner playout all speak the same book:
## flavour.majority = "end" (default; Pitched Battle/Capture&Hold/HQ pay the
## majority bonus once at game end), "round" (Domination pays it EVERY
## round), or "none" (Mosh Pit). flavour.first_seize pays 1 VP the FIRST
## time either side controls a marker (Mosh Pit); memo carries that flag
## across rounds (memo.first_seizer = 0 until claimed).
static func vp_score_round(owners: Array, vp: Array, flavour: Dictionary, memo: Dictionary, markers: Array = []) -> void:
	if str(flavour.get("mode", "")) == "demolition":
		# Demolition (book + maintainer 17.08.): 1 VP per round while the OWN
		# marker stands; once BOTH are gone, the side whose marker fell FIRST
		# collects the revenge VP from the event round onward — destroying
		# first and losing later earns nothing.
		for side in [1, 2]:
			var own_alive := false
			var own_seq := 0
			var enemy_destroyed := false
			var enemy_seq := 0
			for mk in markers:
				var mo: Dictionary = mk
				var ob := int(mo.get("owned_by", 0))
				if ob == side:
					own_alive = not bool(mo.get("destroyed", false))
					own_seq = int(mo.get("destroyed_seq", 0))
				elif ob == 3 - side:
					enemy_destroyed = bool(mo.get("destroyed", false))
					enemy_seq = int(mo.get("destroyed_seq", 0))
			if own_alive:
				vp[side - 1] += 1
			elif enemy_destroyed and own_seq < enemy_seq:
				vp[side - 1] += 1
		return
	vp_round_add(owners, vp)
	if str(flavour.get("majority", "end")) == "round":
		vp_end_bonus(owners, vp)
	if bool(flavour.get("first_seize", false)) and int(memo.get("first_seizer", 0)) == 0:
		for o in owners:
			if int(o) == 1 or int(o) == 2:
				memo["first_seizer"] = int(o)
				vp[int(o) - 1] += 1
				break


static func vp_score_end(owners: Array, vp: Array, flavour: Dictionary) -> void:
	if str(flavour.get("majority", "end")) == "end":
		vp_end_bonus(owners, vp)


## NML-1010 W3 — destructible OWNED markers (Sabotage, Demolition). An owned
## marker that the ENEMY alone holds at round end is destroyed on the spot
## and never scores again; the sequence counter orders same-round losses
## (the maintainer's Demolition tiebreak). markers entries: {owned_by:int,
## destructible:bool, destroyed:bool, destroyed_seq:int}. owners[i] is
## zeroed for a destroyed marker so no later scorer counts a ghost.
static func apply_destroy_step(markers: Array, owners: Array, seq: Array) -> Array:
	var events: Array = []
	for i in range(markers.size()):
		var mk: Dictionary = markers[i]
		if not bool(mk.get("destructible", false)) or bool(mk.get("destroyed", false)):
			continue
		var owner_side := int(mk.get("owned_by", 0))
		if owner_side <= 0 or i >= owners.size():
			continue
		if int(owners[i]) == 3 - owner_side:
			mk["destroyed"] = true
			seq[0] = int(seq[0]) + 1
			mk["destroyed_seq"] = int(seq[0])
			owners[i] = 0
			events.append({"index": i, "destroyed_by": 3 - owner_side})
	return events


## Sabotage end verdict (book): you win by destroying the enemy's marker
## WHILST keeping your own intact — anything else is a draw.
static func sabotage_winner(markers: Array) -> String:
	var alive := {1: false, 2: false}
	for mk in markers:
		var mo: Dictionary = mk
		var side := int(mo.get("owned_by", 0))
		if side == 1 or side == 2:
			alive[side] = not bool(mo.get("destroyed", false))
	if alive[1] and not alive[2]:
		return "p1"
	if alive[2] and not alive[1]:
		return "p2"
	return "draw"


## NML-1048 — THE end-of-game referee, so the verdict the player reads in the
## summary can never disagree with the one the arena writes into its result:
## a progressive mission is decided by the round_vp ledger (booked every round
## by main._solo_book_mission_vp), sabotage by its own destroy verdict, every
## other mission by the markers held at the end, and a board with no markers
## at all by surviving models. Returns "p1" / "p2" / "draw". Lifted from
## tools/arena_match.gd with the branch order intact — re-deciding the 633
## measured self-play games through it reproduces all 633 recorded winners.
static func mission_winner(scoring: String, owners: Array, vp: Array,
		markers: Array, alive1: int, alive2: int) -> String:
	if scoring == "sabotage":
		return sabotage_winner(markers)
	if scoring == "round_vp":
		var v1: int = int(vp[0]) if vp.size() > 0 else 0
		var v2: int = int(vp[1]) if vp.size() > 1 else 0
		return ("p1" if v1 > v2 else "p2") if v1 != v2 else "draw"
	var p1 := 0
	var p2 := 0
	for o in owners:
		if int(o) == 1:
			p1 += 1
		elif int(o) == 2:
			p2 += 1
	if p1 != p2:
		return "p1" if p1 > p2 else "p2"
	if owners.is_empty() and alive1 != alive2:
		return "p1" if alive1 > alive2 else "p2"
	return "draw"


## One activation with stochastic rounding (core self-play games).
static func resolve_stochastic(state: Dictionary, action: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	stochastic_rng = rng
	var out := resolve(state, action)
	stochastic_rng = null
	return out



## Deep-copies the DYNAMIC layers (positions/wounds/flags/objective owners);
## GameUnit refs stay shared — they are read-only by contract.
static func clone_state(state: Dictionary) -> Dictionary:
	var _prof_t0 := Time.get_ticks_usec() if profile_enabled() else 0
	var units := {}
	for key in state["units"]:
		var su: Dictionary = (state["units"][key] as Dictionary).duplicate()
		su["positions"] = (su["positions"] as Array).duplicate()
		su["wounds"] = (su["wounds"] as Array).duplicate()
		# radii are mutated alongside positions when a model dies, so they must
		# be copied like them — a shared array would let one rollout edit another
		su["radii"] = (su.get("radii", []) as Array).duplicate()
		# A1b-1: "mods" is a snapshot dict, not shared state — a clone owns its own copy.
		# ("mods_base" is the capture-time reading and is NEVER written after capture,
		# so the shallow ref the duplicate above carries over is safe to share.)
		su["mods"] = (su.get("mods", {}) as Dictionary).duplicate()
		units[key] = su
	var objectives: Array = []
	for o in state["objectives"]:
		objectives.append((o as Dictionary).duplicate())
	# W3: marker mission state must be COPIED per rollout — shared dicts would
	# let one playout's destructions leak into its siblings and the live game.
	var markers_meta: Array = []
	for mk in state.get("markers_meta", []):
		markers_meta.append((mk as Dictionary).duplicate())
	var out := {"round": state["round"], "rounds_total": state["rounds_total"],
		"units": units, "objectives": objectives}
	# NML-1069: the round's cast log rides the state and must be COPIED, not shared —
	# a rollout that casts would otherwise stamp its imagined spells into the real game.
	if state.has("cast_events"):
		out["cast_events"] = (state["cast_events"] as Array).duplicate()
	if state.has("terrain_at"):
		out["terrain_at"] = state["terrain_at"]
	if state.has("charge_illegal"):   # head wave 1: legality rides every imagined step
		out["charge_illegal"] = state["charge_illegal"]
	if state.has("los_at"):   # sight feature for net-guided playout tuples
		out["los_at"] = state["los_at"]
	if state.has("los_blocked"):
		out["los_blocked"] = state["los_blocked"]
	if state.has("markers_meta"):
		out["markers_meta"] = markers_meta
		out["destroy_seq"] = [int((state.get("destroy_seq", [0]) as Array)[0])]
	for kf in ["scoring", "vp", "vp_flavour", "vp_memo"]:
		if state.has(kf):
			out[kf] = state[kf]
	if profile_enabled():
		profile["clone"] += Time.get_ticks_usec() - _prof_t0
		profile["clone_n"] += 1
	return out


## NML-1068: the largest fraction t in [0,1] of `delta` that leaves every mover
## model clear of every OTHER alive unit's alive models (no-go disc radius =
## other model radius + UNIT_SPACING_IN + mover model radius, horizontal
## distance only — the control_gap_in convention). The engine forbids ENDING
## inside a no-go disc, never merely leaving one — deployment in the trainer
## has no spacing rule, so a captured state may legally start with units
## overlapping. (1) t=1 legal -> 1.0, regardless of the start. (2) else, start
## (t=0) legal -> an 8-step binary search (monotone: legality can only lapse
## as t grows away from a clear start). (3) else (start AND full move both
## illegal, no monotone guarantee — the path may cross clear ground) -> a
## descending 8-point sample t=1.0,0.875,...,0.125, largest legal wins, 0.0 if
## none are. Radii come from the snapshot, falling back to the shared default
## base radius when absent.
static func _spacing_fraction(next: Dictionary, mover_key: String, positions: Array,
		mover_radii: Array, delta: Vector3) -> float:
	if delta.length_squared() <= 0.0:
		return 1.0
	var buffer_m := SoloController.UNIT_SPACING_IN * IN2M
	var obstacles: Array = []   # {"c": Vector3, "r": float} per other alive model
	for key in next["units"]:
		if key == mover_key:
			continue
		var ou: Dictionary = next["units"][key]
		var o_positions: Array = ou.get("positions", [])
		var o_radii: Array = ou.get("radii", [])
		for oi in range(o_positions.size()):
			var o_r: float = float(o_radii[oi]) if oi < o_radii.size() else SeparationChecker.DEFAULT_BASE_RADIUS_M
			obstacles.append({"c": o_positions[oi], "r": o_r + buffer_m})
	if obstacles.is_empty():
		return 1.0
	var legal := func(t: float) -> bool:
		for i in range(positions.size()):
			var own_r: float = float(mover_radii[i]) if i < mover_radii.size() else SeparationChecker.DEFAULT_BASE_RADIUS_M
			var p: Vector3 = (positions[i] as Vector3) + delta * t
			for ob in obstacles:
				var oc: Vector3 = ob["c"]
				if Vector3(p.x - oc.x, 0.0, p.z - oc.z).length() < float(ob["r"]) + own_r:
					return false
		return true
	if legal.call(1.0):
		return 1.0
	if legal.call(0.0):
		var lo := 0.0
		var hi := 1.0
		for _i in range(8):
			var mid := (lo + hi) * 0.5
			if legal.call(mid):
				lo = mid
			else:
				hi = mid
		return lo
	for i in range(8):
		var t: float = 1.0 - float(i) * 0.125
		if legal.call(t):
			return t
	return 0.0


## Resolves one activation IN EXPECTATION on a cloned state and returns it.
## action: {"unit": key, "kind": AiDecision.Action, "dest": Vector3 (optional
## move goal for the unit centre)}. Movement v0 (plan D4): the whole unit
## translates toward dest, clamped by the official move band — no pathfinding.
static func resolve(state: Dictionary, action: Dictionary) -> Dictionary:
	var _prof_t0 := Time.get_ticks_usec() if profile_enabled() else 0
	var next := clone_state(state)
	var su: Dictionary = next["units"][action["unit"]]
	var was_shaken := bool(su.get("shaken", false))
	var kind: int = int(action.get("kind", AiDecision.Action.HOLD))
	var bands := SoloController.sim_move_bands(su["unit"])
	var band_in := 0.0
	if kind == AiDecision.Action.ADVANCE:
		band_in = float(bands.get("advance", 6))
	elif kind == AiDecision.Action.RUSH or kind == AiDecision.Action.CHARGE:
		band_in = float(bands.get("rush", 12))
	var positions: Array = su["positions"]
	if band_in > 0.0 and action.has("dest") and not positions.is_empty():
		var centre := Vector3.ZERO
		for p in positions:
			centre += p as Vector3
		centre /= positions.size()
		var delta: Vector3 = (action["dest"] as Vector3) - centre
		var reach_m := band_in * IN2M
		if delta.length() > reach_m:
			delta = delta.normalized() * reach_m
		# NML-1068: RUSH and CHARGE share this same translation — one clamp covers both.
		if spacing_enabled():
			var _prof_sp_t0 := Time.get_ticks_usec() if profile_enabled() else 0
			delta *= _spacing_fraction(next, action["unit"], positions, su.get("radii", []), delta)
			if profile_enabled():
				profile["spacing"] += Time.get_ticks_usec() - _prof_sp_t0
				profile["spacing_n"] += 1
		for i in range(positions.size()):
			positions[i] = (positions[i] as Vector3) + delta
		var terrain_at: Callable = next.get("terrain_at", Callable())
		if terrain_at.is_valid():   # T2b: the mover's cover follows it (unit-centre probe, v0)
			su["in_cover"] = TerrainRules.gives_cover(int(terrain_at.call(centre + delta)))
	# NML-1069 — the CAST SUB-PHASE: after the move, before ANY attack, for every
	# activation (the old cast site was a rider inside the shoot branch below, so a
	# melee caster never cast at all). stochastic_rng null = expectation path.
	# A/B seam (cast_phase_enabled): OFF restores the legacy shoot-rider below
	# instead, so shipped rollouts stay byte-identical until the never-worse A/B.
	if cast_phase_enabled():
		var _prof_c_t0 := Time.get_ticks_usec() if profile_enabled() else 0
		var cast_event := _cast_phase(next, str(action["unit"]), stochastic_rng)
		if profile_enabled():
			profile["cast"] += Time.get_ticks_usec() - _prof_c_t0
			profile["cast_n"] += 1
		if not cast_event.is_empty():
			if not next.has("cast_events"):
				next["cast_events"] = []
			(next["cast_events"] as Array).append(cast_event)
	var shoot_key := str(action.get("shoot", ""))
	if shoot_key != "" and next["units"].has(shoot_key) and sees(su, shoot_key) \
			and (kind == AiDecision.Action.HOLD or kind == AiDecision.Action.ADVANCE):
		var tu: Dictionary = next["units"][shoot_key]
		if _los_clear(next, su, tu):
			var d := dist_in(positions, tu["positions"])
			var alive_before := int(tu["alive"])
			var wounds_before := _wounds_left(tu)
			if cast_phase_enabled():
				_apply_expected_wounds(tu,
					AiEv.shoot_ev(_profiles_of(su, false, d), _ctx_of(su), _ctx_of(tu), d))
			else:
				# Seam OFF: the legacy spell rider, verbatim from dabd1da — the
				# sub-phase above never ran, so casting only happens inside a shoot pick.
				var volley := AiEv.shoot_ev(_profiles_of(su, false, d), _ctx_of(su), _ctx_of(tu), d)
				var sp := spell_ev_of(su, tu, d)
				if float(sp["ev"]) > 0.0:
					volley += float(sp["ev"])
					su["casts"] = int(su.get("casts", 0)) - int(sp["cost"])
				_apply_expected_wounds(tu, volley)
			_expected_shooting_morale(tu, alive_before, wounds_before)
	var charge_key := str(action.get("charge", ""))
	if kind == AiDecision.Action.CHARGE and charge_key != "" and next["units"].has(charge_key):
		var tu: Dictionary = next["units"][charge_key]
		if dist_in(positions, tu["positions"]) <= CONTACT_IN:
			var tu_before := _wounds_left(tu)
			var su_before := _wounds_left(su)
			_apply_expected_wounds(tu, AiEv.melee_ev(_profiles_of(su, true),
				_ctx_of(su, true), _ctx_of(tu), true))
			su["fatigued"] = true
			if int(tu["alive"]) > 0:   # survivors strike back, already survivor-scaled
				_apply_expected_wounds(su, AiEv.melee_ev(_profiles_of(tu, true),
					_ctx_of(tu, true), _ctx_of(su), false))
				# W-P1 parity (p.9): striking back fatigues the DEFENDER too — the
				# game stamps both sides, the sim only ever stamped the charger.
				tu["fatigued"] = true
			_expected_melee_morale(su, su_before, tu, tu_before)
	# Shaken recovery (p.10): the idle activation clears Shaken — the recovery
	# hold plan()/the rollout policy hand a shaken unit buys next round back.
	if was_shaken and kind == AiDecision.Action.HOLD and shoot_key == "":
		su["shaken"] = false
	su["activated"] = true
	if profile_enabled():
		profile["resolve"] += Time.get_ticks_usec() - _prof_t0
		profile["resolve_n"] += 1
	return next


const CONTACT_IN := 1.0
const CONTROL_EPS := 0.001   # float guard on the inclusive 3" ring

## Snapshot LOS: no matrix (no los_of wired at capture) = everyone sees
## everyone, byte-identical to pre-T2. V0 approximation, documented: the
## matrix is CAPTURE-TIME — a unit moved during a rollout keeps its captured
## sight lines (exact for hold+shoot, approximate after moves).
## Dynamic LOS: a state-level `los_blocked` callable probes CURRENT unit
## centres — needed by the core runner, where resolve moves units across whole
## games and a capture-time matrix would go stale. Engine snapshots do not
## carry the callable, so their behaviour is unchanged.
static func _los_clear(state: Dictionary, su: Dictionary, tu: Dictionary) -> bool:
	var lb: Callable = state.get("los_blocked", Callable())
	if not lb.is_valid():
		return true
	return not bool(lb.call(_centre_of(su), _centre_of(tu)))


static func _centre_of(su: Dictionary) -> Vector3:
	var c := Vector3.ZERO
	var ps: Array = su["positions"]
	if ps.is_empty():
		return c
	for p in ps:
		c += p as Vector3
	return c / ps.size()


static func sees(su: Dictionary, other_key: String) -> bool:
	if not su.has("los"):
		return true
	return bool((su["los"] as Dictionary).get(other_key, true))

## Nearest-model gap between two snapshot position arrays, inches.
static func dist_in(a: Array, b: Array) -> float:
	var best := INF
	for pa in a:
		for pb in b:
			best = minf(best, ((pa as Vector3) - (pb as Vector3)).length())
	return best / IN2M


## AiEv context sourced from the SNAPSHOT's dynamic layer, not the live models.
## `melee`: a FATIGUED unit hits only on unmodified 6s in melee (GF v3.5.1
## p.9) — approximated as Quality 6 for the EV; shooting is unaffected. The
## EV layer itself is fatigue-blind, so the snapshot flag must be priced here.
static func _ctx_of(su: Dictionary, melee := false) -> Dictionary:
	var ctx := AiEv.ctx_for(su["unit"], bool(su.get("in_cover", false)))
	ctx["models"] = int(su["alive"])
	# W-P1 parity: the flag rides the ctx — profile_ev hard-sets the natural-6
	# target itself (the old quality=6 approximation still let modifiers move it).
	if melee and bool(su.get("fatigued", false)):
		ctx["fatigued"] = true
	return ctx


## Weapon profiles with attacks scaled to the snapshot's survivors (dead models
## stop attacking — mirrors effective_attacks in the real path). Limited-weapon
## usage tracking is NOT modelled yet (v0; noted for the parity wave).
static func _profiles_of(su: Dictionary, melee: bool, d := 0.0) -> Array:
	var u: GameUnit = su["unit"]
	var weapons: Array = []
	if u.source_type == "opr" and u.source_data is OPRApiClient.OPRUnit:
		weapons = (u.source_data as OPRApiClient.OPRUnit).weapons
	var profiles: Array = AiShooting.melee_profiles(weapons) if melee \
		else AiShooting.profiles_in_range(weapons, d)
	# W-P1 parity: UNIT-level striker rules reach the dice in the game
	# (main.gd:6396/6852/6880 weapon-OR-unit fallback) but the profile flags
	# only ever read the weapon. Same DOOR as the game: prefix scan of the
	# unit's special_rules (the registry gate would demand faction data the
	# game's own fallback never asks for).
	var u_bane := false
	var u_rending := false
	var u_unstop := false
	for r in u.get_special_rules():
		var rs := str(r).strip_edges()
		if rs.begins_with("Bane") or rs.begins_with("Lacerate"):
			u_bane = true
		elif rs.begins_with("Rending"):
			u_rending = true
		elif rs.begins_with("Unstoppable") and not rs.contains(" in ") and not rs.contains(" when "):
			u_unstop = true
	var out: Array = []
	for p in AiEv.stamp_sergeant(profiles, u):
		var q := (p as Dictionary).duplicate()
		q["attacks"] = SoloController.effective_attacks(int(q.get("attacks", 0)),
			int(su["alive"]), u.models.size())
		if u_bane:
			q["bane"] = true
		if u_rending:
			q["rending"] = true
		if u_unstop:
			q["unstoppable"] = true
		out.append(q)
	return out


## Expected melee damage `tu` would take from `su` charging RIGHT NOW —
## survivor-scaled profiles, fatigue/cover contexts. The feature wave's
## magnitude signal: a grot mob and an ogre block threaten very differently,
## which the binary charge-exposure count cannot see.
static func melee_threat(su: Dictionary, tu: Dictionary) -> float:
	return AiEv.melee_ev(_profiles_of(su, true), _ctx_of(su, true), _ctx_of(tu), true)


## Spell EV (parity wave; ladder-v3 evidence: the caster faction scored
## 19-27%): the best affordable DAMAGE spell of `su` against `tu` at
## distance d — cast-success chance x damage EV. v0 scope, documented:
## damage spells only (buffs/debuffs later), unit-level tokens (attached-
## hero tokens not yet visible to the snapshot), no boost/interference.
## Returns {"ev": float, "cost": int}; zeros when nothing castable.
static func spell_ev_of(su: Dictionary, tu: Dictionary, d: float) -> Dictionary:
	var tokens := int(su.get("casts", 0))
	if tokens <= 0:
		return {"ev": 0.0, "cost": 0}
	var u: GameUnit = su["unit"]
	if u == null or not u.has_method("is_caster") or not u.is_caster():
		return {"ev": 0.0, "cost": 0}
	return _spell_ev_from(SpellsRegistry.spells_for_unit(u), tokens, _ctx_of(tu), d)


## Pure core (unit-independent, testable): best damage-spell EV from a spell
## list given tokens, defender context and distance in inches.
static func _spell_ev_from(spells: Array, tokens: int, def_ctx: Dictionary, d: float) -> Dictionary:
	var best_ev := 0.0
	var best_cost := 0
	for e in spells:
		var entry := e as Dictionary
		if str(entry.get("status", "unmodeled")) == "unmodeled":
			continue
		var eff: Dictionary = entry.get("effect", {})
		if str(eff.get("kind", "")) != "damage":
			continue
		var threshold := int(entry.get("threshold", 1))
		if threshold > tokens or d > float(entry.get("range_in", 0)) + 0.001:
			continue
		var ev := AiSpell.cast_success_chance(0, 0) * _spell_damage_ev_of(entry, def_ctx)
		if ev > best_ev:
			best_ev = ev
			best_cost = threshold
	return {"ev": best_ev, "cost": best_cost}


## Expected wounds ONE spell entry's damage effect puts on a defender context —
## hits x target count through AiSpell's facet math, no cast chance folded in.
## The single home of that arithmetic: the EV pricing (_spell_ev_from) and the
## cast sub-phase both call it, so the two can never drift apart.
static func _spell_damage_ev_of(entry: Dictionary, def_ctx: Dictionary) -> float:
	var eff: Dictionary = entry.get("effect", {})
	if str(eff.get("kind", "")) != "damage":
		return 0.0
	var hits := int(eff.get("hits", 0)) \
		* maxi(int((entry.get("target", {}) as Dictionary).get("count", 1)), 1)
	return AiSpell.spell_damage_ev(hits, def_ctx, AiSpell.spell_facets(eff.get("weapon_rules", [])))


# ===== NML-1069 — the cast sub-phase =========================================

## ONE cast attempt for `actor_key`, resolved on `next` after the move and
## BEFORE any attack (GF v3.5.1 Caster(X): "at any point before attacking,
## spend as many tokens as the spell's value to try casting one or more spells
## ... roll one die, on 4+ resolve the effect on a target in line of sight").
## Mirrors the engine's official Solo & Co-Op procedure through the SAME helper
## (solo_controller.gd:3664-3666 -> AiSpell.official_pick_order): D3 + X indexes
## the faction's BOOK-ORDERED list (start = (D3 + X - 1) % size), then the cycle
## walks on to the first VALID spell; the tokens are spent ON THE ATTEMPT, the
## 4+ die decides the effect. The engine's DIFFICULTY LADDER on top of that cycle
## (Veteran skips 0-EV spells, Kriegsherr/Albtraum replace the die with the
## EV-best spell) is NOT modelled here — the sim plays the base procedure, the
## same one the default/Rekrut difficulty plays.
##
## `rng` null = the EXPECTATION path (planner rollouts through resolve());
## non-null = the stochastic path (resolve_stochastic, core self-play).
##
## APPROXIMATIONS — all deliberate, all v0, all named here:
##   * D3 EXPECTATION. With no rng every D3 face is played at weight 1/3 and
##     its effect applied scaled by that weight (x the 4+ chance). The three
##     faces may pick three DIFFERENT spells; then all three land, each at a
##     third of its strength. With an rng exactly the rolled face is played.
##   * INTEGER TOKEN LEDGER. The trainer counts token DELTAS, so a fractional
##     spend is not representable. The attempt therefore costs the threshold of
##     the D3=1 face (the first of three equally likely faces), and the stamped
##     event names that same spell. With an rng the rolled face pays, exactly.
##   * BOOST / INTERFERENCE OUT OF SCOPE. cast_success_chance(0, 0) always —
##     the same 4+ spell_ev_of prices with. The engine's token economy (helper
##     tokens in 18" LoS) is a later step.
##   * EFFECT COVERAGE. Damage lands as expected wounds; buff/debuff land as
##     the six modifier fields the snapshot's "mods" dict carries (hit, def,
##     morale, range_in, advance, rush — the mapping of main.gd:3652
##     _solo_record_spell_mod -> SoloController.active_mod_net_of). A spell's
##     casting_mod and grants_rule have NO snapshot slot: those spells are cast
##     and paid for, but nothing in the sim feels them yet.
##   * TARGETS. Damage/debuff pick the living enemy in range with line of sight
##     whose damage EV is highest (nearest on a tie); a buff always lands on the
##     CASTER ITSELF — the friendly-unit choice the procedure leaves open, and
##     multi-target spells (target.count > 1) still resolve on one unit.
##   * The attempt is not gated on the ACTION KIND — the engine plans a cast for
##     every activation it runs, Advance/Rush/Charge alike. Shaken IS gated (see
##     the p.10 check below); that is the one activation the engine skips.
## Returns the cast event {spell, kind, cost, target, p_success}, or {} on a HOLD
## (Shaken, no tokens, no caster, no book, no valid spell) — a hold spends nothing.
static func _cast_phase(next: Dictionary, actor_key: String,
		rng: RandomNumberGenerator) -> Dictionary:
	var units: Dictionary = next["units"]
	if not units.has(actor_key):
		return {}
	var su: Dictionary = units[actor_key]
	# GF v3.5.1 p.10: a Shaken unit spends its activation IDLE and never casts. Same gate the
	# engine puts at the activation entry (solo_controller.gd:505, which builds the idle report
	# without ever reaching _plan_casts; the aircraft variant returns at :2311 for the same reason).
	if bool(su.get("shaken", false)):
		return {}
	var tokens := int(su.get("casts", 0))
	if tokens <= 0 or int(su.get("alive", 0)) <= 0:
		return {}
	var u: GameUnit = su["unit"]
	if u == null or not u.has_method("is_caster") or not u.is_caster():
		return {}
	var spells := SpellsRegistry.spells_for_unit(u)
	if spells.is_empty():
		return {}
	var faces: Array = [1, 2, 3] if rng == null else [rng.randi_range(1, 3)]
	var weight := 1.0 / float(faces.size())
	var p_success := AiSpell.cast_success_chance(0, 0)
	var event := {}
	for d3 in faces:
		var pick := _pick_cast(next, su, actor_key, spells, tokens, int(d3), u.get_caster_value())
		if pick.is_empty():
			continue
		var entry: Dictionary = pick["entry"]
		_apply_cast_effect(next, str(pick["target"]), entry, weight * p_success, rng)
		if event.is_empty():   # the FIRST face pays and names the attempt (see above)
			event = {"spell": str(entry.get("name", "?")),
				"kind": str((entry.get("effect", {}) as Dictionary).get("kind", "")),
				"cost": int(entry.get("threshold", 0)), "target": str(pick["target"]),
				"p_success": p_success}
	if event.is_empty():
		return {}
	su["casts"] = maxi(tokens - int(event["cost"]), 0)
	return event


## The official cycle for ONE D3 face: walk official_pick_order and return the
## first VALID spell as {entry, target}, or {} when the caster must hold.
## Valid = status not "unmodeled", threshold affordable, and a legal target —
## a buff takes the caster itself, damage/debuff need a living enemy in range
## with line of sight (the same sees()/_los_clear seam the shoot branch uses).
static func _pick_cast(state: Dictionary, su: Dictionary, actor_key: String, spells: Array,
		tokens: int, d3: int, caster_x: int) -> Dictionary:
	for idx in AiSpell.official_pick_order(spells.size(), d3, caster_x):
		var entry := spells[int(idx)] as Dictionary
		if str(entry.get("status", "unmodeled")) == "unmodeled":
			continue
		if int(entry.get("threshold", 0)) > tokens:
			continue
		var kind := str((entry.get("effect", {}) as Dictionary).get("kind", ""))
		if kind == "buff":
			return {"entry": entry, "target": actor_key}
		if kind != "damage" and kind != "debuff":
			continue   # an effect kind the sim has no arithmetic for is not castable here
		var target_key := _best_spell_target(state, su, entry)
		if target_key != "":
			return {"entry": entry, "target": target_key}
	return {}


## The enemy unit a damage/debuff spell should land on: living, on the other
## side, within range_in of the caster with line of sight, best damage EV first
## and nearest on a tie (a debuff prices at 0, so it simply takes the nearest).
static func _best_spell_target(state: Dictionary, su: Dictionary, entry: Dictionary) -> String:
	var range_in := float(entry.get("range_in", 0))
	var player := int(su.get("player", 0))
	var best_key := ""
	var best_ev := -1.0
	var best_d := INF
	for k in state["units"]:
		var tu: Dictionary = state["units"][k]
		if int(tu.get("player", 0)) == player or int(tu.get("alive", 0)) <= 0:
			continue
		if not sees(su, str(k)) or not _los_clear(state, su, tu):
			continue
		var d := dist_in(su["positions"], tu["positions"])
		if d > range_in + CONTROL_EPS:
			continue
		var ev := _spell_damage_ev_of(entry, _ctx_of(tu))
		if ev > best_ev + CONTROL_EPS or (absf(ev - best_ev) <= CONTROL_EPS and d < best_d):
			best_ev = ev
			best_d = d
			best_key = str(k)
	return best_key


## Land one spell's effect. `scale` is the D3 weight x the 4+ cast chance:
## damage is applied as that scaled expectation either way (mean-preserving,
## exactly what _apply_expected_wounds is for), while a modifier is a discrete
## stamp — the rng path ROLLS it (`scale` is the probability it lands whole),
## the expectation path adds it scaled. A modifier-less buff/debuff (the
## grants_rule-only "castable" spells) is cast but leaves no snapshot trace.
static func _apply_cast_effect(state: Dictionary, target_key: String, entry: Dictionary,
		scale: float, rng: RandomNumberGenerator) -> void:
	var tu: Dictionary = (state["units"] as Dictionary).get(target_key, {})
	if tu.is_empty():
		return
	var eff: Dictionary = entry.get("effect", {})
	if str(eff.get("kind", "")) == "damage":
		_apply_expected_wounds(tu, scale * _spell_damage_ev_of(entry, _ctx_of(tu)))
		return
	var modifier: Dictionary = eff.get("modifier", {})
	if modifier.is_empty():
		return
	var landed := scale
	if rng != null:
		landed = 1.0 if rng.randf() < scale else 0.0
	if landed <= 0.0:
		return
	var mods: Dictionary = tu.get("mods", {})
	if mods.is_empty():
		mods = {"hit": 0, "def": 0, "morale": 0, "range_in": 0.0, "advance": 0.0, "rush": 0.0}
		tu["mods"] = mods
	# Mirrors main.gd:3652 _solo_record_spell_mod as active_mod_net_of reads it back:
	# a "beneficiary: attackers" record is the ATTACKER's hit/def modifier against this
	# unit (role "vs_target"), never part of the bearer's own net — the other four
	# fields carry no beneficiary split there and none here.
	if str(eff.get("beneficiary", "")) != "attackers":
		mods["hit"] = float(mods.get("hit", 0)) + landed * float(modifier.get("hit_mod", 0))
		mods["def"] = float(mods.get("def", 0)) + landed * float(modifier.get("def_mod", 0))
	mods["morale"] = float(mods.get("morale", 0)) + landed * float(modifier.get("morale_mod", 0))
	mods["range_in"] = float(mods.get("range_in", 0.0)) + landed * float(modifier.get("range_in", 0))
	mods["advance"] = float(mods.get("advance", 0.0)) + landed * float(modifier.get("advance_in", 0))
	mods["rush"] = float(mods.get("rush", 0.0)) + landed * float(modifier.get("rush_in", 0))


## Spell modifiers are ROUND-SCOPED ("until the end of the round" — the arena
## clears them with the tokens in main.gd). Puts every unit back on its
## CAPTURE-TIME reading, so a new round never inherits the last one's buffs.
## Called by the trainer's round loop (tools/core_selfplay.gd:_play_one) where
## `activated`/`fatigued` are cleared.
static func reset_round_mods(state: Dictionary) -> void:
	for k in state["units"]:
		var su: Dictionary = state["units"][k]
		su["mods"] = (su.get("mods_base", {}) as Dictionary).duplicate()


## Expected wounds the enemy's shooting REPLY takes off `player`'s units:
## every living enemy activates once and shoots its best-EV visible target.
## Returns my_unit_key -> expected incoming wounds. V0 simplifications,
## documented: shooting only (no charge reply), capture-time sight lines,
## already-activated enemies still count (they reply next round).
static func reply_threat(state: Dictionary, player: int) -> Dictionary:
	var incoming := {}
	for ek in state["units"]:
		var eu: Dictionary = state["units"][ek]
		if int(eu["player"]) == player or int(eu["alive"]) <= 0:
			continue
		var best_key := ""
		var best_ev := 0.0
		for mk in state["units"]:
			var mu: Dictionary = state["units"][mk]
			if int(mu["player"]) != player or int(mu["alive"]) <= 0 or not sees(eu, str(mk)) \
					or not _los_clear(state, eu, mu):
				continue
			var d := dist_in(eu["positions"], mu["positions"])
			var ev := AiEv.shoot_ev(_profiles_of(eu, false, d), _ctx_of(eu), _ctx_of(mu), d) \
				+ float(spell_ev_of(eu, mu, d)["ev"])   # magic is part of the reply
			if ev > best_ev:
				best_ev = ev
				best_key = str(mk)
		if best_key != "":
			incoming[best_key] = float(incoming.get(best_key, 0.0)) + best_ev
	return incoming


## Expected unsaved wounds land on the snapshot, filled model by model in array
## order (v0 — casualty_order parity is a later step). Fractional carry (parity
## wave step 4): the sub-wound remainder stays on the TARGET and joins the next
## volley instead of being floored away per hit — a rollout's aggregate damage
## now matches the sum of expectations, not the sum of floors (the sim killed
## systematically less than reality; calib meter step 3 ranked this suspect #1).
static func _apply_expected_wounds(tu: Dictionary, ev: float) -> void:
	var pool := float(tu.get("wound_frac", 0.0)) + ev
	var left := int(floor(pool))
	if stochastic_rng != null:
		if stochastic_rng.randf() < pool - left:
			left += 1
		tu["wound_frac"] = 0.0
	else:
		tu["wound_frac"] = pool - left
	var wounds: Array = tu["wounds"]
	var positions: Array = tu["positions"]
	while left > 0 and not wounds.is_empty():
		var take: int = mini(left, int(wounds[0]))
		wounds[0] = int(wounds[0]) - take
		left -= take
		if int(wounds[0]) <= 0:
			wounds.remove_at(0)
			positions.remove_at(0)
			var rr: Array = tu.get("radii", [])
			if not rr.is_empty():
				rr.remove_at(0)   # stays aligned with positions or the base-edge measure lies
	tu["alive"] = positions.size()


## Wounds left across the snapshot's alive models (the p.10 tough-wounds scale).
static func _wounds_left(su: Dictionary) -> int:
	var total := 0
	for w in su["wounds"]:
		total += int(w)
	return total


## At-or-below-half ON THE SNAPSHOT (GF v3.5.1 p.10): single-model units measure
## tough WOUNDS against the model's max, multi-model units measure alive models
## against starting size. Joined-hero chains are separate snapshot units (v0 gap).
static func _below_half(su: Dictionary) -> bool:
	var u: GameUnit = su["unit"]
	if u.models.size() == 1:
		return AiCombatMath.at_or_below_half(_wounds_left(su),
			(u.models[0] as ModelInstance).wounds_max)
	return AiCombatMath.at_or_below_half(int(su["alive"]), u.models.size())


## The EXPECTED morale outcome, deterministically: Shaken always fails (p.10);
## otherwise the quality target's fail chance, halved by the Fearless re-roll
## (advanced p.13), fails when it reaches 50% — Q4+ crowds break, Q3 elites and
## Fearless hold. Gap 18a: the Banner/attached-hero bonus rides in on the snapshot
## (capture stamps it) — the default 0 keeps hand-built states byte-identical. Fear
## and spell mods are still v0 gaps, noted for the parity wave.
static func _morale_fails_expected(su: Dictionary) -> bool:
	if bool(su.get("shaken", false)):
		return true
	var u: GameUnit = su["unit"]
	var fail_p := float(AiCombatMath.morale_target(u.get_quality(),
		int(su.get("morale_bonus", 0))) - 1) / 6.0
	if u.has_special_rule("Fearless"):
		fail_p *= 0.5
	return fail_p >= 0.5


## Post-volley morale (parity wave step 2, mirrors main.gd's PDF-verified flow):
## casualties this volley AND now at/below half => test; a shooting fail is
## SHAKEN, never a Rout (Rout exists only in melee — playtest bug 9).
static func _expected_shooting_morale(tu: Dictionary, alive_before: int, wounds_before: int) -> void:
	var u: GameUnit = tu["unit"]
	if u.models.size() == 1:
		if int(tu["alive"]) > 0 and _wounds_left(tu) < wounds_before and _below_half(tu) \
				and _morale_fails_expected(tu):
			tu["shaken"] = true
		return
	if AiCombatMath.should_test_shooting_morale(alive_before, int(tu["alive"]), u.models.size()) \
			and _morale_fails_expected(tu):
		tu["shaken"] = true


## Melee morale (p.10 via main.gd's flow): the side that dealt FEWER wounds
## tests (tie = nobody); an expected fail at/below half is a ROUT — the loser
## leaves the board. Fear's comparison bonus is a v0 gap, noted.
static func _expected_melee_morale(su: Dictionary, su_before: int, tu: Dictionary, tu_before: int) -> void:
	var dealt_by_su := tu_before - _wounds_left(tu)
	var dealt_by_tu := su_before - _wounds_left(su)
	if dealt_by_su == dealt_by_tu:
		return
	var loser: Dictionary = tu if dealt_by_su > dealt_by_tu else su
	if int(loser["alive"]) <= 0 or not _morale_fails_expected(loser):
		return
	if _below_half(loser):
		(loser["wounds"] as Array).clear()
		(loser["positions"] as Array).clear()
		(loser.get("radii", []) as Array).clear()
		loser["alive"] = 0
	else:
		loser["shaken"] = true


static func capture(army: OPRArmyManager, objectives_provider: Callable = Callable(),
		objective_owner_of: Callable = Callable(), round_no: int = 1,
		rounds_total: int = 4, cover_of: Callable = Callable(),
		los_of: Callable = Callable(), terrain_at: Callable = Callable()) -> Dictionary:
	var units := {}
	for uid in army.game_units:
		var u: GameUnit = army.game_units[uid]
		var positions: Array = []
		var wounds: Array = []
		var radii: Array = []
		# Arrivals S1: a unit still on the tray (Ambush reserve) enters the
		# snapshot DORMANT — zero table presence (alive=0, so every existing
		# dead-unit guard already excludes it from eligibility, targeting and
		# scoring) while its strength survives in dormant_* for the arrival
		# step. A tray node's position must never leak into the board picture.
		var dormant := SoloController.unit_in_reserve(u)
		var dormant_wounds: Array = []
		for m in u.models:
			if dormant:
				if m.is_alive:
					dormant_wounds.append(m.wounds_current)
				continue
			if m.is_alive and m.node != null:
				positions.append(m.node.global_position)
				wounds.append(m.wounds_current)
				# BASE RADIUS per living model, aligned with positions: the book
				# measures a marker from the closest point of the BASE, not from
				# the model's centre (a 25mm model whose centre is at 3.4" still
				# holds the marker). Without this the sim's ring is a base
				# radius too tight and it scores a rule the game does not have.
				radii.append(SoloController.model_base_radius_m(m as ModelInstance))
		units[uid] = {
			"unit": u,
			"radii": radii,
			# Neither can seize or contest: an Aircraft ever, a unit that
			# arrived from Ambush in the CURRENT round (GF/AoF v3.5.1 p.13).
			# The arrival ROUND is captured, not a precomputed boolean, because
			# a playout advances rounds and the lock has to expire with them.
			"aircraft": SoloController.is_aircraft(u),
			"ambush_arrived_round": int(u.unit_properties.get("ambush_arrived_round", -1)),
			"player": int(u.unit_properties.get("player_id", 0)),
			"positions": positions,
			"alive": positions.size(),
			"wounds": wounds,
			"in_cover": bool(cover_of.call(u)) if cover_of.is_valid() else false,
			# Gap 18a: Banner/attached-hero morale bonus, stamped ONCE — the rollout
			# must never walk the rules registry per activation.
			"morale_bonus": SoloController.morale_bonus_of(u),
			# A1b-1: the NET active spell/token hit/def/morale/range/speed deltas, stamped once —
			# the planner substrate carries the numbers the dice path already applies (not wired
			# to a consumer yet; that reads the "mods" dict in a later diff).
			"mods": SoloController.active_mod_net_of(u),
			# NML-1069: the same reading kept UNTOUCHED as the round-scope floor —
			# reset_round_mods restores "mods" to it when a new round starts.
			"mods_base": SoloController.active_mod_net_of(u),
			"shaken": u.is_shaken,
			"fatigued": u.is_fatigued,
			"activated": u.is_activated,
			"casts": u.casts_current,
		}
		if dormant:
			var du: Dictionary = units[uid]
			du["dormant"] = true
			du["dormant_models"] = dormant_wounds.size()
			du["dormant_wounds"] = dormant_wounds
			du["earliest_arrival_round"] = SoloController.ambush_earliest_round(u)
	if los_of.is_valid():
		for k in units:
			var su: Dictionary = units[k]
			var matrix := {}
			if su.get("dormant", false):
				su["los"] = matrix   # a sleeper neither sees nor is probed
				continue
			for ok in units:
				var other: Dictionary = units[ok]
				if other.get("dormant", false):
					continue
				if int(other["player"]) != int(su["player"]):
					matrix[ok] = bool(los_of.call(su["unit"], other["unit"]))
			su["los"] = matrix
	var objectives: Array = []
	if objectives_provider.is_valid():
		var objs: Variant = objectives_provider.call()
		for i in range(objs.size()):
			objectives.append({
				"pos": objs[i],
				"owner": int(objective_owner_of.call(i)) if objective_owner_of.is_valid() else 0,
			})
	var state := {
		"round": round_no,
		"rounds_total": rounds_total,
		"units": units,
		"objectives": objectives,
		# NML-1010 W2: the planner's playout must speak the mission's currency
		# AND start from the LIVE ledger — a playout that counts only the
		# remaining rounds' VP can call a game "lost" that is already won.
		"scoring": SoloController.mission_scoring,
	}
	if SoloController.mission_scoring == "round_vp":
		state["vp"] = [int(SoloController.mission_vp[0]), int(SoloController.mission_vp[1])]
		state["vp_flavour"] = SoloController.mission_vp_flavour
		state["vp_memo"] = SoloController.mission_vp_memo.duplicate()
	if not SoloController.mission_markers.is_empty():
		# W3: playouts must know owned/destructible markers AND the live
		# destruction state, or they optimise a mission that no longer exists.
		var mm: Array = []
		for mk in SoloController.mission_markers:
			mm.append((mk as Dictionary).duplicate())
		state["markers_meta"] = mm
		state["destroy_seq"] = [int(SoloController.mission_destroy_seq[0])]
	if terrain_at.is_valid():   # absent key = pre-T2b snapshot, byte-identical
		state["terrain_at"] = terrain_at
	return state
