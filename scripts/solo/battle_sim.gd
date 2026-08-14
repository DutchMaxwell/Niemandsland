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
	return rows


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
	var units := {}
	for key in state["units"]:
		var su: Dictionary = (state["units"][key] as Dictionary).duplicate()
		su["positions"] = (su["positions"] as Array).duplicate()
		su["wounds"] = (su["wounds"] as Array).duplicate()
		units[key] = su
	var objectives: Array = []
	for o in state["objectives"]:
		objectives.append((o as Dictionary).duplicate())
	var out := {"round": state["round"], "rounds_total": state["rounds_total"],
		"units": units, "objectives": objectives}
	if state.has("terrain_at"):
		out["terrain_at"] = state["terrain_at"]
	if state.has("los_blocked"):
		out["los_blocked"] = state["los_blocked"]
	return out


## Resolves one activation IN EXPECTATION on a cloned state and returns it.
## action: {"unit": key, "kind": AiDecision.Action, "dest": Vector3 (optional
## move goal for the unit centre)}. Movement v0 (plan D4): the whole unit
## translates toward dest, clamped by the official move band — no pathfinding.
static func resolve(state: Dictionary, action: Dictionary) -> Dictionary:
	var next := clone_state(state)
	var su: Dictionary = next["units"][action["unit"]]
	var was_shaken := bool(su.get("shaken", false))
	var kind: int = int(action.get("kind", AiDecision.Action.HOLD))
	var bands := SoloController.move_bands_for_unit(su["unit"], null)
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
		for i in range(positions.size()):
			positions[i] = (positions[i] as Vector3) + delta
		var terrain_at: Callable = next.get("terrain_at", Callable())
		if terrain_at.is_valid():   # T2b: the mover's cover follows it (unit-centre probe, v0)
			su["in_cover"] = TerrainRules.gives_cover(int(terrain_at.call(centre + delta)))
	var shoot_key := str(action.get("shoot", ""))
	if shoot_key != "" and next["units"].has(shoot_key) and sees(su, shoot_key) \
			and (kind == AiDecision.Action.HOLD or kind == AiDecision.Action.ADVANCE):
		var tu: Dictionary = next["units"][shoot_key]
		if _los_clear(next, su, tu):
			var d := dist_in(positions, tu["positions"])
			var alive_before := int(tu["alive"])
			var wounds_before := _wounds_left(tu)
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
			_expected_melee_morale(su, su_before, tu, tu_before)
	# Shaken recovery (p.10): the idle activation clears Shaken — the recovery
	# hold plan()/the rollout policy hand a shaken unit buys next round back.
	if was_shaken and kind == AiDecision.Action.HOLD and shoot_key == "":
		su["shaken"] = false
	su["activated"] = true
	return next


const CONTACT_IN := 1.0

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
	if melee and bool(su.get("fatigued", false)):
		ctx["quality"] = 6
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
	var out: Array = []
	for p in AiEv.stamp_sergeant(profiles, u):
		var q := (p as Dictionary).duplicate()
		q["attacks"] = SoloController.effective_attacks(int(q.get("attacks", 0)),
			int(su["alive"]), u.models.size())
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
		var hits := int(eff.get("hits", 0)) * maxi(int((entry.get("target", {}) as Dictionary).get("count", 1)), 1)
		var facets := AiSpell.spell_facets(eff.get("weapon_rules", []))
		var ev := AiSpell.cast_success_chance(0, 0) * AiSpell.spell_damage_ev(hits, def_ctx, facets)
		if ev > best_ev:
			best_ev = ev
			best_cost = threshold
	return {"ev": best_ev, "cost": best_cost}


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
## Fearless hold. Banner/Fear/spell mods are v0 gaps, noted for the parity wave.
static func _morale_fails_expected(su: Dictionary) -> bool:
	if bool(su.get("shaken", false)):
		return true
	var u: GameUnit = su["unit"]
	var fail_p := float(AiCombatMath.morale_target(u.get_quality(), 0) - 1) / 6.0
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
		for m in u.models:
			if m.is_alive and m.node != null:
				positions.append(m.node.global_position)
				wounds.append(m.wounds_current)
		units[uid] = {
			"unit": u,
			"player": int(u.unit_properties.get("player_id", 0)),
			"positions": positions,
			"alive": positions.size(),
			"wounds": wounds,
			"in_cover": bool(cover_of.call(u)) if cover_of.is_valid() else false,
			"shaken": u.is_shaken,
			"fatigued": u.is_fatigued,
			"activated": u.is_activated,
			"casts": u.casts_current,
		}
	if los_of.is_valid():
		for k in units:
			var su: Dictionary = units[k]
			var matrix := {}
			for ok in units:
				var other: Dictionary = units[ok]
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
	}
	if terrain_at.is_valid():   # absent key = pre-T2b snapshot, byte-identical
		state["terrain_at"] = terrain_at
	return state
