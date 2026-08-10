class_name BattleSim
extends RefCounted
## Planner substrate, phase 1: a read-only snapshot of the live game as plain
## data. Static facts (profiles, rules) stay on the referenced GameUnit and are
## never mutated; dynamic facts (positions, wounds, flags, objective owners)
## are copied so expectation rollouts can edit them without touching the scene.
## Positions are metres, world space. Callable seams mirror SoloController's:
## objectives_provider() -> Array[Vector3], objective_owner_of(i) -> int.


const IN2M := 0.0254


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
		var d := dist_in(positions, tu["positions"])
		var alive_before := int(tu["alive"])
		var wounds_before := _wounds_left(tu)
		_apply_expected_wounds(tu, AiEv.shoot_ev(_profiles_of(su, false, d),
			_ctx_of(su), _ctx_of(tu), d))
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
			if int(mu["player"]) != player or int(mu["alive"]) <= 0 or not sees(eu, str(mk)):
				continue
			var d := dist_in(eu["positions"], mu["positions"])
			var ev := AiEv.shoot_ev(_profiles_of(eu, false, d), _ctx_of(eu), _ctx_of(mu), d)
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
